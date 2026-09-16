"""Validate the transport fixture before using it to diagnose app failures."""
import json
import struct
import tempfile
import threading
import unittest
import urllib.request
import zlib
from pathlib import Path

from bedrock_runtime import FixtureServer, event_frame


class BedrockFixtureTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
