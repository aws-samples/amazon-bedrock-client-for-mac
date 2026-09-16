#!/usr/bin/env python3
"""Fail a release if the tag, source version, packaged identity or notes disagree."""
import argparse
import json
import os
import plistlib
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--tag", default="")
parser.add_argument("--app", type=Path)
args = parser.parse_args()
project = root / "Amazon Bedrock Client for Mac.xcodeproj/project.pbxproj"
graph = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = graph["objects"]
target = next(item for item in objects.values()
              if item.get("isa") == "PBXNativeTarget" and item.get("name") == "Amazon Bedrock Client for Mac")
configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
versions = {objects[item]["buildSettings"]["MARKETING_VERSION"] for item in configurations}
if len(versions) != 1:
    raise SystemExit(f"Debug and Release versions disagree: {versions}")
version = versions.pop()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("Use a semantic MARKETING_VERSION.")
if args.tag and args.tag != f"v{version}":
    raise SystemExit(f"Tag {args.tag} does not match source version v{version}.")
notes = root / "docs/releases" / f"{version}.md"
if not notes.is_file() or len(notes.read_text().strip()) < 100:
    raise SystemExit(f"Release notes are missing: {notes.relative_to(root)}")
if args.app:
    with (args.app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    expected = {"CFBundleShortVersionString": version,
                "CFBundleIdentifier": "AWS.Amazon-Bedrock-Client-for-Mac",
                "CFBundleExecutable": "Amazon Bedrock"}
    for key, value in expected.items():
        if info.get(key) != value:
            raise SystemExit(f"Packaged {key} is {info.get(key)!r}; expected {value!r}.")
    if not str(info.get("CFBundleVersion", "")).isdigit():
        raise SystemExit("The distribution must use a numeric build number.")
    binary = args.app / "Contents/MacOS/Amazon Bedrock"
    if not binary.is_file():
        raise SystemExit("The app executable is missing.")
if os.environ.get("GITHUB_ENV"):
    with open(os.environ["GITHUB_ENV"], "a") as environment:
        environment.write(f"RELEASE_VERSION={version}\n")
print(f"Release v{version}: source version, tag and notes verified" + ("; packaged identity verified." if args.app else "."))
