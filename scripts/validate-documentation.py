#!/usr/bin/env python3
"""Check repository documentation links and the shipped README media offline."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


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

    signatures = {
        "assets/preview.png": lambda data: data.startswith(b"\x89PNG\r\n\x1a\n"),
        "assets/preview.gif": lambda data: data[:6] in (b"GIF87a", b"GIF89a"),
        "assets/readme/main-light.webp": lambda data: data[:4] == b"RIFF" and data[8:12] == b"WEBP",
        "assets/readme/main-dark.webp": lambda data: data[:4] == b"RIFF" and data[8:12] == b"WEBP",
        "assets/readme/demo.mp4": lambda data: data[4:8] == b"ftyp",
    }
    for relative, valid in signatures.items():
        path = root / relative
        if not path.is_file():
            failures.append(f"Missing README media: {relative}")
            continue
        with path.open("rb") as source:
            if not valid(source.read(32)):
                failures.append(f"Invalid README media format: {relative}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Documentation: {len(documents)} files, {checked} local links and {len(signatures)} media formats verified.")


if __name__ == "__main__":
    main()
