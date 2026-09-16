#!/usr/bin/env python3
"""Loopback Bedrock Converse fixture for the real app/SDK integration tests.

Uses AWS event-stream framing, including both CRCs, over chunked HTTP. It never
contacts AWS. Requests contain only synthetic test data and are saved so tests
can assert the actual wire payload, model switches, attachment bytes and tools.
"""
import argparse
import json
import struct
import threading
import time
import urllib.parse
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer


def event_frame(event_type, payload):
    headers = bytearray()
    for key, value in {
        ":message-type": "event",
        ":event-type": event_type,
        ":content-type": "application/json",
    }.items():
        key, value = key.encode(), value.encode()
        headers.extend(bytes([len(key)]) + key + b"\x07" + struct.pack(">H", len(value)) + value)
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
    prelude = struct.pack(">II", 16 + len(headers) + len(body), len(headers))
    message = prelude + struct.pack(">I", zlib.crc32(prelude)) + headers + body
    return message + struct.pack(">I", zlib.crc32(message))


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer resolves its host with getfqdn(), which can trigger macOS
        # local-network discovery. This fixture only needs a literal loopback
        # socket and never discovers or contacts another device.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]

    def __init__(self, requests_path):
        super().__init__(("127.0.0.1", 0), FixtureHandler)
        self.requests_path = Path(requests_path)
        self.request_lock = threading.Lock()
        self.release_stream = threading.Event()

    def record(self, value):
        with self.request_lock, self.requests_path.open("a") as output:
            output.write(json.dumps(value, ensure_ascii=False) + "\n")


class FixtureHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def json_response(self, code, value):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        if code >= 400:
            self.send_header("x-amzn-errortype", "ValidationException")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/release":
            self.server.release_stream.set()
        elif self.path == "/reset":
            self.server.release_stream.clear()
        elif self.path != "/health":
            self.json_response(404, {"message": "Unknown fixture endpoint"})
            return
        self.json_response(200, {"status": "ready"})

    def body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            chunks = []
            while True:
                length = int(self.rfile.readline().strip().split(b";", 1)[0], 16)
                if not length:
                    self.rfile.readline()
                    break
                chunks.append(self.rfile.read(length))
                self.rfile.read(2)
            return b"".join(chunks)
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def do_POST(self):
        try:
            self.converse(json.loads(self.body()))
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Stop response deliberately closes a stream before its last frame.
            self.close_connection = True
        except (ValueError, KeyError) as error:
            self.json_response(400, {"message": f"Invalid fixture request: {error}"})

    def converse(self, request):
        path = urllib.parse.unquote(self.path)
        if not path.startswith("/model/") or not path.endswith(("/converse-stream", "/converse")):
            self.json_response(404, {"message": "Expected a Converse request"})
            return
        model = path.removeprefix("/model/").rsplit("/", 1)[0]
        messages = request.get("messages", [])
        user_messages = [
            message for message in messages
            if message.get("role") == "user" and
            any("text" in content for content in message.get("content", []))
        ]
        if not user_messages:
            raise ValueError("Expected a user message containing text")
        prompt_parts = [content["text"] for content in user_messages[-1].get("content", []) if "text" in content]
        prompt = "\n".join(prompt_parts)
        self.server.record({"model": model, "path": path, "body": request})
        # Converse merges consecutive user messages after a failed request.
        # Only reject the new failure prompt, not a later message that retains
        # that failed prompt in its context.
        if "[failure]" in prompt_parts[-1]:
            self.json_response(400, {"message": "The fixture rejected this request. Your draft is safe."})
            return

        tool_results = [
            content["toolResult"]
            for message in messages for content in message.get("content", [])
            if "toolResult" in content
        ]
        content = None
        if "[background]" in prompt:
            results = {result.get("toolUseId"): result for result in tool_results}
            if "background-start" not in results:
                content = {"toolUse": {"toolUseId": "background-start", "name": "local_start_process",
                                       "input": {"command": "printf BACKGROUND_READY; sleep 20", "directory": "/tmp"}}}
            else:
                def process_result(name):
                    parts = results[name].get("content", [])
                    return json.loads(next(part["text"] for part in parts if "text" in part))

                process_id = process_result("background-start")["id"]
                if "background-poll" not in results:
                    content = {"toolUse": {"toolUseId": "background-poll", "name": "local_poll_process",
                                           "input": {"id": process_id, "wait_seconds": 5}}}
                elif "BACKGROUND_READY" not in process_result("background-poll")["output"]:
                    self.json_response(400, {"message": "The background process did not return its real output"})
                    return
                elif "background-stop" not in results:
                    content = {"toolUse": {"toolUseId": "background-stop", "name": "local_stop_process",
                                           "input": {"id": process_id}}}
                elif process_result("background-stop")["status"] != "stopped":
                    self.json_response(400, {"message": "The background process did not stop"})
                    return
                else:
                    content = {"text": "BACKGROUND_TOOLS_COMPLETE: BACKGROUND_READY · stopped"}
        elif "[tools]" in prompt:
            sequence = [
                ("fixture-list", "local_list_skills", {}),
                ("fixture-read", "local_read_skill", {"id": "code-review"}),
                ("fixture-exec", "local_run_command",
                 {"command": "/usr/bin/printf 'EXEC_FROM_REAL_TOOL\\n'", "directory": "/tmp"}),
            ]
            completed = {result.get("toolUseId") for result in tool_results}
            pending = next((item for item in sequence if item[0] not in completed), None)
            if pending:
                tool_id, name, arguments = pending
                advertised = {tool.get("toolSpec", {}).get("name") for tool in request.get("toolConfig", {}).get("tools", [])}
                if name not in advertised:
                    self.json_response(400, {"message": f"Required tool was not advertised: {name}"})
                    return
                content = {"toolUse": {"toolUseId": tool_id, "name": name, "input": arguments}}
            else:
                results = json.dumps(tool_results)
                if "EXEC_FROM_REAL_TOOL" not in results or "code-review" not in results:
                    self.json_response(400, {"message": "Tools did not return their real output"})
                    return
                content = {"text": "TOOLS_COMPLETE: code-review · EXEC_FROM_REAL_TOOL"}
        elif "[attachments]" in prompt:
            entries = user_messages[-1].get("content", [])
            documents = [entry["document"] for entry in entries if "document" in entry]
            images = [entry["image"] for entry in entries if "image" in entry]
            content = {"text": f"ATTACHMENTS_RECEIVED: {len(documents)} documents, {len(images)} images"}
        elif "[remember]" in prompt:
            content = {"text": "CONTEXT_SAVED: BRIDGE_CI"}
        elif "[recall]" in prompt:
            history = json.dumps(messages[:-1])
            content = {"text": "CONTEXT_RECALLED: BRIDGE_CI" if "BRIDGE_CI" in history else "CONTEXT_MISSING"}
        elif "[queue-one]" in prompt:
            content = {"text": "QUEUE_ONE_COMPLETE"}
        elif "[queue-two]" in prompt:
            content = {"text": "QUEUE_TWO_COMPLETE"}
        elif "[quick]" in prompt:
            content = {"text": "QUICK_ACCESS_COMPLETE"}
        elif "[truncated]" in prompt:
            content = {"text": "PARTIAL_RESPONSE"}
        else:
            content = {"text": "RESPONSE_COMPLETE\n\n- First **item**.\n- Second item with `inline code`.\n\n```swift\nlet value = 42\n```"}
        usage = {"inputTokens": 32, "outputTokens": 16, "totalTokens": 48}
        reason = "tool_use" if "toolUse" in content else "end_turn"
        if "[truncated]" in prompt:
            reason = "max_tokens"
        if path.endswith("/converse"):
            self.json_response(200, {"output": {"message": {"role": "assistant", "content": [content]}},
                                     "stopReason": reason, "usage": usage, "metrics": {"latencyMs": 25}})
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.amazon.eventstream")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("x-amzn-requestid", "local-fixture")
        self.end_headers()

        def emit(kind, payload):
            data = event_frame(kind, payload)
            self.wfile.write(f"{len(data):X}\r\n".encode() + data + b"\r\n")
            self.wfile.flush()

        emit("messageStart", {"role": "assistant"})
        if "toolUse" in content:
            tool = content["toolUse"]
            emit("contentBlockStart", {"contentBlockIndex": 0,
                                      "start": {"toolUse": {"toolUseId": tool["toolUseId"], "name": tool["name"]}}})
            arguments = json.dumps(tool["input"])
            # Split JSON inside a string to exercise incremental tool parsing.
            for chunk in (arguments[:len(arguments)//2], arguments[len(arguments)//2:]):
                emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"toolUse": {"input": chunk}}})
        else:
            if "[stream]" in prompt:
                emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": "STREAM_BEGIN\n"}})
                deadline = time.monotonic() + 120
                while not self.server.release_stream.wait(0.25) and time.monotonic() < deadline:
                    # Empty deltas keep cancellation observable without changing text.
                    emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": ""}})
                content = {"text": "STREAM_COMPLETE"}
            text = content["text"]
            for offset in range(0, len(text), 9):
                emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": text[offset:offset + 9]}})
                time.sleep(0.005)
        emit("contentBlockStop", {"contentBlockIndex": 0})
        emit("messageStop", {"stopReason": reason})
        emit("metadata", {"usage": usage, "metrics": {"latencyMs": 25}})
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready", required=True, type=Path)
    parser.add_argument("--requests", required=True, type=Path)
    args = parser.parse_args()
    server = FixtureServer(args.requests)
    args.ready.write_text(json.dumps({"port": server.server_port}))
    server.serve_forever(poll_interval=0.05)


if __name__ == "__main__":
    main()
