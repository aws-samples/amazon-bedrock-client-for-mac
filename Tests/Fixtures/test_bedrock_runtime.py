"""Validate the transport fixture before using it to diagnose app failures."""
import json
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import urllib.request
from urllib.error import HTTPError
import zlib
from pathlib import Path

from bedrock_runtime import FixtureServer, event_frame


class BedrockFixtureTests(unittest.TestCase):
    def test_ready_file_is_complete_as_soon_as_the_child_publishes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            for attempt in range(10):
                ready = Path(directory) / f"ready-{attempt}.json"
                child = subprocess.Popen([
                    sys.executable, str(Path(__file__).with_name("bedrock_runtime.py")),
                    "--ready", str(ready), "--requests", str(Path(directory) / "requests.jsonl")
                ], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                try:
                    deadline = time.monotonic() + 5
                    while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.0005)
                    self.assertTrue(ready.exists(), "Fixture must publish readiness before requests.")
                    port = json.loads(ready.read_bytes())["port"]
                    self.assertGreater(port, 0)
                    self.assertLessEqual(port, 65535)
                finally:
                    child.terminate()
                    child.communicate(timeout=5)

    def test_loopback_startup_never_resolves_or_discovers_network_hosts(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("socket.getfqdn", side_effect=AssertionError("Unexpected hostname discovery")):
                server = FixtureServer(Path(directory) / "requests.jsonl")
                try:
                    self.assertEqual(server.server_name, "127.0.0.1")
                    self.assertGreater(server.server_port, 0)
                finally:
                    server.server_close()

    def test_event_framing_lengths_checksums_headers_and_unicode(self):
        payload = {"contentBlockIndex": 0, "delta": {"text": "한글 👋"}}
        frame = event_frame("contentBlockDelta", payload)
        size, header_size, prelude_crc = struct.unpack(">III", frame[:12])
        self.assertEqual(size, len(frame))
        self.assertEqual(prelude_crc, zlib.crc32(frame[:8]))
        self.assertEqual(struct.unpack(">I", frame[-4:])[0], zlib.crc32(frame[:-4]))
        headers, offset = {}, 12
        while offset < 12 + header_size:
            length = frame[offset]
            key = frame[offset + 1:offset + 1 + length].decode()
            offset += 1 + length
            self.assertEqual(frame[offset], 7)
            length = struct.unpack(">H", frame[offset + 1:offset + 3])[0]
            offset += 3
            headers[key] = frame[offset:offset + length].decode()
            offset += length
        self.assertEqual(headers[":event-type"], "contentBlockDelta")
        self.assertEqual(headers[":message-type"], "event")
        self.assertEqual(json.loads(frame[offset:-4]), payload)

    def test_http_converse_and_stream_use_the_same_body_and_record_actual_requests(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "requests.jsonl"
            server = FixtureServer(log)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                body = {"messages": [{"role": "user", "content": [{"text": "[remember] BRIDGE_CI"}]}]}
                for suffix in ("converse", "converse-stream"):
                    request = urllib.request.Request(
                        f"http://127.0.0.1:{server.server_port}/model/us.amazon.nova-2-lite-v1:0/{suffix}",
                        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
                    with urllib.request.urlopen(request, timeout=5) as response:
                        value = response.read()
                        if suffix == "converse":
                            self.assertEqual(json.loads(value)["stopReason"], "end_turn")
                        else:
                            event_count = 0
                            while value:
                                length = struct.unpack(">I", value[:4])[0]
                                self.assertLessEqual(length, len(value))
                                self.assertEqual(struct.unpack(">I", value[length-4:length])[0], zlib.crc32(value[:length-4]))
                                value = value[length:]
                                event_count += 1
                            self.assertGreater(event_count, 5)
                records = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(len(records), 2)
                self.assertTrue(all(record["body"] == body for record in records))
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)

    def test_failure_does_not_reject_a_followup_with_consecutive_user_context(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "requests.jsonl"
            server = FixtureServer(log)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                endpoint = f"http://127.0.0.1:{server.server_port}/model/us.amazon.nova-2-lite-v1:0/converse"
                content = [{"text": "[failure] Reject this request."}]

                def send():
                    return urllib.request.urlopen(urllib.request.Request(
                        endpoint, data=json.dumps({"messages": [{"role": "user", "content": content}]}).encode(),
                        headers={"Content-Type": "application/json"}), timeout=5)

                with self.assertRaises(HTTPError) as failure:
                    send()
                self.assertEqual(failure.exception.code, 400)
                failure.exception.close()
                content.append({"text": "Continue after the failure."})
                with send() as response:
                    value = json.loads(response.read())
                self.assertIn("RESPONSE_COMPLETE", value["output"]["message"]["content"][0]["text"])
                self.assertEqual(len(log.read_text().splitlines()), 2)
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)

    def test_responses_preserves_documents_and_stateless_tool_continuation(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "requests.jsonl"
            server = FixtureServer(log)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                endpoint = f"http://127.0.0.1:{server.server_port}/openai/v1/responses"
                parts = [
                    {"type": "input_file", "filename": "Earlier report.txt",
                     "file_data": "data:text/plain;base64,U1lOVEhFVElDX0RPQ1VNRU5U"},
                    {"type": "input_text", "text": "[responses-document-tool] /tmp/synthetic.txt"},
                ]
                body = {"model": "us.openai.gpt-5.6-luna", "store": False, "stream": True,
                        "input": [{"role": "user", "content": parts}],
                        "tools": [{"type": "function", "name": "local_read_file"}]}

                def send():
                    with urllib.request.urlopen(urllib.request.Request(
                        endpoint, data=json.dumps(body).encode(),
                        headers={"Content-Type": "application/json"}), timeout=5) as response:
                        self.assertEqual(response.headers["Content-Type"], "text/event-stream")
                        return [json.loads(line.removeprefix("data: "))
                                for line in response.read().decode().splitlines() if line.startswith("data: ")]

                first = send()
                output = first[-1]["response"]["output"]
                self.assertEqual(output[-1]["name"], "local_read_file")
                self.assertEqual(json.loads(output[-1]["arguments"])["path"], "/tmp/synthetic.txt")
                body["input"] += output + [{"type": "function_call_output", "call_id": "responses-file-read",
                                           "output": "RESPONSES_FILE_MARKER"}]
                second = send()
                self.assertEqual(second[0]["delta"], "RESPONSES_DOCUMENT_TOOL_COMPLETE")
                body["input"].append({"role": "user", "content": [
                    {"type": "input_text", "text": "Continue with the earlier document."}]})
                self.assertEqual(send()[0]["delta"], "RESPONSES_DOCUMENT_FOLLOWUP_COMPLETE")
                records = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(len(records), 3)
                self.assertTrue(all(record["path"] == "/openai/v1/responses" for record in records))
                self.assertTrue(all(record["body"]["input"][0]["content"][0] == parts[0] for record in records))
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)

    def test_kimi_responses_fixture_requires_omitted_sampling_and_explicit_thinking_off(self):
        with tempfile.TemporaryDirectory() as directory:
            server = FixtureServer(Path(directory) / "requests.jsonl")
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                endpoint = f"http://127.0.0.1:{server.server_port}/openai/v1/responses"
                body = {"model": "us.moonshotai.kimi-k3", "store": False, "stream": True,
                        "reasoning": {"effort": "none"},
                        "input": [{"role": "user", "content": [
                            {"type": "input_text", "text": "Continue without a document."}]}]}

                def send():
                    return urllib.request.urlopen(urllib.request.Request(
                        endpoint, data=json.dumps(body).encode(),
                        headers={"Content-Type": "application/json"}), timeout=5)

                for field in ("temperature", "top_p"):
                    body[field] = 0.7
                    with self.assertRaises(HTTPError) as failure:
                        send()
                    self.assertEqual(failure.exception.code, 400)
                    failure.exception.close()
                    del body[field]
                del body["reasoning"]
                with self.assertRaises(HTTPError) as failure:
                    send()
                self.assertEqual(failure.exception.code, 400)
                failure.exception.close()
                body["reasoning"] = {"effort": "none"}
                with send() as response:
                    self.assertIn(b"RESPONSES_DOCUMENT_FOLLOWUP_COMPLETE", response.read())
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)

    def test_layout_stream_waits_for_measurement_before_growth_and_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            server = FixtureServer(Path(directory) / "requests.jsonl")
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                request = urllib.request.Request(
                    base + "/model/us.amazon.nova-2-lite-v1:0/converse-stream",
                    data=json.dumps({"messages": [
                        {"role": "user", "content": [{"text": "[layout-stream]"}]}
                    ]}).encode(), headers={"Content-Type": "application/json"})
                with urllib.request.urlopen(request, timeout=5) as response:
                    def event():
                        prelude = response.read(12)
                        length, header_size, _ = struct.unpack(">III", prelude)
                        remainder = response.read(length - 12)
                        self.assertEqual(len(remainder), length - 12)
                        return json.loads(remainder[header_size:-4])

                    self.assertEqual(event()["role"], "assistant")
                    text = event()["delta"]["text"]
                    self.assertIn("LAYOUT_STREAM_BEGIN", text)
                    self.assertEqual(event()["delta"]["text"], "",
                                     "The short native response must remain measurable before growth.")
                    with urllib.request.urlopen(base + "/grow", timeout=5):
                        pass
                    while "LAYOUT_STREAM_GROWN" not in text:
                        text += event().get("delta", {}).get("text", "")
                    self.assertGreater(len(text.encode()), 4_000)
                    self.assertEqual(event()["delta"]["text"], "",
                                     "The WebKit response must remain streaming until the UI releases it.")
                    with urllib.request.urlopen(base + "/release", timeout=5):
                        pass
                    payload = {}
                    while "stopReason" not in payload:
                        payload = event()
                        text += payload.get("delta", {}).get("text", "")
                    self.assertEqual(payload["stopReason"], "end_turn")
                    self.assertTrue(text.endswith("LAYOUT_STREAM_COMPLETE"))
                    self.assertIn("Streaming section 23", text)
            finally:
                server.grow_stream.set()
                server.release_stream.set()
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
