#!/usr/bin/env python3
"""Local, side-effect-free MCP fixture for native tool-flow validation.

Run with an optional label to distinguish two servers exposing the same tool.
Only protocol JSON goes to stdout; no filesystem or network access is performed.
"""
import json
import sys

LABEL = sys.argv[1] if len(sys.argv) > 1 else "fixture"
if "--stderr" in sys.argv:
    sys.stderr.write("Fixture diagnostic output.\n" * 12000)
    sys.stderr.flush()
TOOL = {
    "name": "echo_payload",
    "description": "Validate a nested payload and return it unchanged with the fixture server label.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "mode": {"type": "string", "enum": ["echo", "error", "wait", "multimodal"]},
            "payload": {
                "type": "object",
                "properties": {
                    "enabled": {"type": "boolean"},
                    "count": {"type": "integer"},
                    "labels": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["enabled", "count", "labels"],
                "additionalProperties": False,
            },
        },
        "required": ["mode", "payload"],
        "additionalProperties": False,
    },
}


def handle(request):
    method = request.get("method")
    if method == "initialize":
        return {
            "protocolVersion": request.get("params", {}).get("protocolVersion", "2025-03-26"),
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "Bedrock validation", "version": "1.0"},
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [TOOL]}
    if method == "tools/call":
        params = request.get("params", {})
        arguments = params.get("arguments", {})
        payload = arguments.get("payload", {})
        valid = (
            params.get("name") == TOOL["name"]
            and arguments.get("mode") in ("echo", "error", "wait", "multimodal")
            and type(payload.get("enabled")) is bool
            and type(payload.get("count")) is int
            and isinstance(payload.get("labels"), list)
            and all(isinstance(label, str) for label in payload["labels"])
        )
        if not valid:
            return {"isError": True, "content": [{"type": "text", "text": "INVALID_PAYLOAD"}]}
        result = {"server": LABEL, "marker": "MCP_OK", "received": arguments}
        if arguments["mode"] == "multimodal":
            return {
                "isError": False,
                "structuredContent": {"marker": "STRUCTURED_OK", "count": 42},
                "content": [
                    {"type": "text", "text": "TEXT_OK", "annotations": {"audience": ["user"]}, "_meta": {"fixture": True}},
                    {"type": "image", "mimeType": "image/png", "data": "aW1hZ2U="},
                    {"type": "audio", "mimeType": "audio/wav", "data": "YXVkaW8="},
                    {"type": "resource", "resource": {"uri": "file:///tmp/mcp-fixture.txt", "mimeType": "text/plain", "text": "RESOURCE_OK"}},
                    {"type": "resource_link", "uri": "file:///tmp/mcp-fixture.txt", "name": "fixture"},
                ],
            }
        return {
            "isError": arguments["mode"] == "error",
            "content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}],
        }
    raise ValueError("Method not found")


for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" not in request:
            continue
        if request.get("method") == "initialize" and "--hang-initialize" in sys.argv:
            continue
        if request.get("method") == "tools/call" and request.get("params", {}).get("arguments", {}).get("mode") == "wait":
            continue
        try:
            response = {"jsonrpc": "2.0", "id": request["id"], "result": handle(request)}
        except ValueError:
            response = {"jsonrpc": "2.0", "id": request["id"], "error": {"code": -32601, "message": "Method not found"}}
        print(json.dumps(response, ensure_ascii=False), flush=True)
    except (ValueError, TypeError, KeyError):
        print("Invalid fixture request", file=sys.stderr, flush=True)
