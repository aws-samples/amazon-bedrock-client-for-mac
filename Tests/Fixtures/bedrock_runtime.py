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
        self.grow_stream = threading.Event()

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
        elif self.path == "/grow":
            self.server.grow_stream.set()
        elif self.path == "/reset":
            self.server.release_stream.clear()
            self.server.grow_stream.clear()
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
            request = json.loads(self.body())
            if self.path == "/openai/v1/responses":
                self.handle_responses(request)
            else:
                self.converse(request)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # Stop response deliberately closes a stream before its last frame.
            self.close_connection = True
        except (ValueError, KeyError) as error:
            self.json_response(400, {"message": f"Invalid fixture request: {error}"})

    def handle_responses(self, request):
        model = request.get("model", "")
        if model != "us.openai.gpt-5.6-luna" or request.get("store") is not False:
            raise ValueError("Expected stateless Luna on its selected US profile")
        items = request.get("input", [])
        user_parts = [
            part for item in items if item.get("role") == "user"
            for part in item.get("content", []) if isinstance(part, dict)
        ]
        documents = [part for part in user_parts if part.get("type") == "input_file"]
        if not documents or any(not part.get("filename", "").endswith(".txt") for part in documents):
            raise ValueError("Expected the document and its required filename extension")
        self.server.record({"model": model, "path": self.path, "body": request})
        prompts = [part.get("text", "") for part in user_parts if part.get("type") == "input_text"]
        latest_prompt = prompts[-1] if prompts else ""
        tool_prompt = latest_prompt if "[responses-document-tool]" in latest_prompt else None
        results = [item for item in items if item.get("type") == "function_call_output"]
        output = []
        text = ""
        if tool_prompt and not results:
            names = [tool.get("name") for tool in request.get("tools", [])]
            if "local_read_file" not in names:
                raise ValueError("The document route must retain the actual local tools")
            path = tool_prompt.partition("[responses-document-tool]")[2].strip()
            output = [
                {"type": "reasoning", "id": "reasoning-fixture", "summary": [],
                 "encrypted_content": "FIXTURE_REASONING"},
                {"type": "function_call", "call_id": "responses-file-read", "name": "local_read_file",
                 "arguments": json.dumps({"path": path}), "status": "completed"},
            ]
        else:
            if tool_prompt:
                if not any(item.get("encrypted_content") == "FIXTURE_REASONING" for item in items):
                    raise ValueError("The stateless tool continuation lost its reasoning item")
                if not any("RESPONSES_FILE_MARKER" in str(item.get("output", "")) for item in results):
                    raise ValueError("The real local file read did not return its contents")
            text = "RESPONSES_DOCUMENT_TOOL_COMPLETE" if tool_prompt else "RESPONSES_DOCUMENT_FOLLOWUP_COMPLETE"
            output = [{"type": "message", "role": "assistant",
                       "content": [{"type": "output_text", "text": text, "annotations": []}],
                       "status": "completed"}]
        events = []
        if text:
            events.append({"type": "response.output_text.delta", "delta": text})
        events.append({"type": "response.completed", "response": {
            "output": output, "usage": {"input_tokens": 128, "output_tokens": 32}}})
        body = "".join("data: " + json.dumps(event) + "\n\n" for event in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

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
        elif "[local-tools]" in prompt:
            sequence = [
                ("local-image", "local_view_image", {"path": prompt.partition("[local-tools]")[2].strip()}),
                ("local-search", "local_search_conversations", {"query": "CONTEXT_SAVED: BRIDGE_CI"}),
                ("local-save", "local_save_automation", {
                    "name": "Local workflow automation", "prompt": "Summarize a fictional day.",
                    "cadence": "daily", "time_zone": "Asia/Seoul", "weekdays": [2, 6], "enabled": False}),
                ("local-list", "local_list_automations", {}),
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
                actual_image = any("image" in item for result in tool_results for item in result.get("content", []))
                if not actual_image or any(result.get("status") != "success" for result in tool_results):
                    self.json_response(400, {"message": "Local tools did not return their actual successful results"})
                    return
                content = {"text": "LOCAL_TOOLS_COMPLETE: image · saved conversation · paused automation"}
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
            if "[layout-stream]" in prompt:
                # Deterministic native → WebKit transition. Keep both the short
                # response and the long live response available until the UI
                # test has measured and scrolled them; no race against a timer.
                def wait_for(signal):
                    deadline = time.monotonic() + 120
                    while not signal.wait(0.25) and time.monotonic() < deadline:
                        emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": ""}})

                emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": "LAYOUT_STREAM_BEGIN\n\n"}})
                wait_for(self.server.grow_stream)
                for index in range(24):
                    section = (
                        f"## Streaming section {index}\n\n"
                        "A response grows independently of the conversation's message array. "
                        "The whole conversation must scroll together while this paragraph wraps. "
                        "한국어와 English, **bold text**, and `inline code` remain readable.\n\n"
                        "- First list item with a complete sentence.\n"
                        "- Second item must stay inside this response.\n\n"
                    )
                    emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": section}})
                    time.sleep(0.04)
                emit("contentBlockDelta", {"contentBlockIndex": 0, "delta": {"text": "LAYOUT_STREAM_GROWN\n\n"}})
                wait_for(self.server.release_stream)
                content = {"text": "LAYOUT_STREAM_COMPLETE"}
            elif "[stream]" in prompt:
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
    # The UI runner starts reading as soon as this path exists. Publish the
    # complete payload atomically so it never observes a newly created empty file.
    pending = args.ready.with_name(args.ready.name + ".tmp")
    pending.write_text(json.dumps({"port": server.server_port}))
    pending.replace(args.ready)
    server.serve_forever(poll_interval=0.05)


if __name__ == "__main__":
    main()
