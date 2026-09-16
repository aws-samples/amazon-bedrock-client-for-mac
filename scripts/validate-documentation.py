#!/usr/bin/env python3
"""Check repository documentation links and the shipped README media offline."""
from pathlib import Path
import hashlib
import json
import re
import struct
from urllib.parse import unquote, urlsplit


def webp_chunks(data):
    offset = 12
    while offset + 8 <= len(data):
        name, length = data[offset:offset + 4], int.from_bytes(data[offset + 4:offset + 8], "little")
        end = offset + 8 + length
        if end > len(data):
            raise ValueError("Truncated WebP chunk")
        yield name, data[offset + 8:end]
        offset = end + length % 2


def image_dimensions(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return struct.unpack(">II", data[16:24])
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", data[6:10])
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        for name, payload in webp_chunks(data):
            if name == b"VP8X":
                return 1 + int.from_bytes(payload[4:7], "little"), 1 + int.from_bytes(payload[7:10], "little")
            if name == b"VP8L":
                bits = int.from_bytes(payload[1:5], "little")
                return 1 + (bits & 0x3fff), 1 + ((bits >> 14) & 0x3fff)
            if name == b"VP8 " and payload[3:6] == b"\x9d\x01\x2a":
                width, height = struct.unpack("<HH", payload[6:10])
                return width & 0x3fff, height & 0x3fff
    raise ValueError("Unrecognized image dimensions")


def movie_dimensions(data):
    def boxes(start, end):
        while start + 8 <= end:
            length, name = struct.unpack(">I4s", data[start:start + 8])
            header = 8
            if length == 1:
                length = int.from_bytes(data[start + 8:start + 16], "big")
                header = 16
            elif length == 0:
                length = end - start
            if length < header or start + length > end:
                raise ValueError("Invalid MP4 box length")
            if name in (b"moov", b"trak"):
                yield from boxes(start + header, start + length)
            elif name == b"tkhd":
                width, height = struct.unpack(">II", data[start + length - 8:start + length])
                if width and height:
                    yield width >> 16, height >> 16
            start += length
    return max(boxes(0, len(data)))


def validate_media(root):
    folder = root / "docs/assets"
    manifest = json.loads((folder / "media.json").read_text())
    expected = {"hero.png", "demo.webp", "demo.gif", "demo.mp4", "chat-light.webp",
                "chat-dark.webp", "settings-light.webp", "settings-dark.webp", "tool-details.webp"}
    if set(manifest["files"]) != expected:
        raise ValueError("README media inventory is incomplete")
    native, padding = manifest["nativeWindow"], manifest["padding"]
    if native["width"] < 2240 or padding < 32:
        raise ValueError("README media needs a Retina capture and room around the window")
    framed = native["width"] + 2 * padding, native["height"] + 2 * padding
    for name, record in manifest["files"].items():
        data = (folder / name).read_bytes()
        if len(data) != record["bytes"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
            raise ValueError(f"{name}: media changed without regenerating its capture manifest")
        size = movie_dimensions(data) if name.endswith(".mp4") else image_dimensions(data)
        if size != (record["width"], record["height"]):
            raise ValueError(f"{name}: actual resolution disagrees with the media manifest")
        if name in {"hero.png", "demo.webp", "demo.mp4", "chat-light.webp", "chat-dark.webp", "tool-details.webp"}:
            if size != framed:
                raise ValueError(f"{name}: preserve native pixels and consistent window framing")
        if name == "demo.gif" and size[0] < 1440:
            raise ValueError("The legacy GIF fallback is too small")
        if name == "demo.webp":
            durations = [int.from_bytes(payload[12:15], "little")
                         for kind, payload in webp_chunks(data) if kind == b"ANMF"]
            if len(durations) < 2 or abs(sum(durations) / 1000 - manifest["sourceDuration"]) > .1:
                raise ValueError("The main animation is missing frames or changes the recorded timing")
    return len(expected)


def local_targets(text):
    text = re.sub(r"(?ms)^```.*?^```[^\n]*", "", text)
    text = re.sub(r"`[^`\n]+`", "", text)
    links = re.findall(r"!?\[[^\]\n]*\]\(([^)\n]+)\)", text)
    links += re.findall(r'(?i)\b(?:src|href|srcset)=["\']([^"\']+)["\']', text)
    links += re.findall(r"(?m)^\[[^\]\n]+\]:\s*(\S+)", text)
    for value in links:
        value = value.strip()
        target = value[1:value.index(">")] if value.startswith("<") and ">" in value else value.split()[0]
        parsed = urlsplit(target)
        if parsed.scheme or parsed.netloc or not parsed.path:
            continue
        yield unquote(parsed.path)


def main():
    root = Path(__file__).resolve().parents[1]
    documents = sorted([*root.glob("*.md"), *(root / "docs").rglob("*.md")])
    failures = []
    checked = 0
    for document in documents:
        for target in local_targets(document.read_text()):
            destination = (document.parent / target).resolve()
            if not destination.is_relative_to(root) or not destination.exists():
                failures.append(f"{document.relative_to(root)}: missing local target {target}")
            checked += 1

    media_count = 0
    try:
        media_count = validate_media(root)
    except (OSError, ValueError, KeyError, struct.error) as error:
        failures.append(f"README media: {error}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Documentation: {len(documents)} files, {checked} local links and {media_count} media files verified "
          "(actual resolution, hashes, framing and animation timing).")


if __name__ == "__main__":
    main()
