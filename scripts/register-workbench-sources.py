#!/usr/bin/env python3
"""Register native workbench Swift sources in the existing Xcode project."""
from hashlib import sha1
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
project = root / "Amazon Bedrock Client for Mac.xcodeproj/project.pbxproj"
text = project.read_text()
app = root / "Sources/Bedrock"
sources = sorted(app.rglob("*.swift"))

def identifier(value: str) -> str:
    return sha1(value.encode()).hexdigest()[:24].upper()

group_id = identifier("Bedrock Local Workbench group")
if f"{group_id} /* Local Workbench */ = " not in text:
    text = text.replace("/* Begin PBXGroup section */", f"""/* Begin PBXGroup section */
\t\t{group_id} /* Local Workbench */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tname = "Local Workbench";
\t\t\tsourceTree = "<group>";
\t\t}};""", 1)
    pattern = r"(79610DBA2AD22A2F00993D09 /\* Amazon Bedrock Client for Mac \*/ = \{\s*isa = PBXGroup;\s*children = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{group_id} /* Local Workbench */,", text, count=1)
    assert count == 1

added = 0
for source in sources:
    relative = source.relative_to(root).as_posix()
    file_id, build_id = identifier("file:" + relative), identifier("build:" + relative)
    if f"/* {source.name} */ = " in text:
        continue
    text = text.replace("/* Begin PBXFileReference section */", f"""/* Begin PBXFileReference section */
\t\t{file_id} /* {source.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {source.name}; path = "{relative}"; sourceTree = SOURCE_ROOT; }};""", 1)
    text = text.replace("/* Begin PBXBuildFile section */", f"""/* Begin PBXBuildFile section */
\t\t{build_id} /* {source.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {source.name} */; }};""", 1)
    pattern = rf"({group_id} /\* Local Workbench \*/ = \{{\s*isa = PBXGroup;\s*children = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{file_id} /* {source.name} */,", text, count=1)
    assert count == 1
    pattern = r"(7907BE902ACD87A000C4D500 /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{build_id} /* {source.name} in Sources */,", text, count=1)
    assert count == 1
    added += 1
resource_count = 0
for resource in sorted((app / "Resources" / "Highlight").glob("*")):
    if not resource.is_file() or resource.name == "README.md":
        continue
    relative = resource.relative_to(root).as_posix()
    file_id, build_id = identifier("file:" + relative), identifier("resource:" + relative)
    if f"/* {resource.name} */ = " in text:
        continue
    file_type = {".js": "sourcecode.javascript", ".css": "text.css"}.get(resource.suffix, "text")
    text = text.replace("/* Begin PBXFileReference section */", f"""/* Begin PBXFileReference section */
\t\t{file_id} /* {resource.name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; name = "{resource.name}"; path = "{relative}"; sourceTree = SOURCE_ROOT; }};""", 1)
    text = text.replace("/* Begin PBXBuildFile section */", f"""/* Begin PBXBuildFile section */
\t\t{build_id} /* {resource.name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {resource.name} */; }};""", 1)
    pattern = rf"({group_id} /\* Local Workbench \*/ = \{{\s*isa = PBXGroup;\s*children = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{file_id} /* {resource.name} */,", text, count=1)
    assert count == 1
    pattern = r"(7907BE922ACD87A000C4D500 /\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{build_id} /* {resource.name} in Resources */,", text, count=1)
    assert count == 1
    resource_count += 1

test_count = 0
test_sources = sorted((root / "Tests/Integration").glob("*.swift")) + sorted((root / "Tests/UITests").glob("*.swift"))
for source in test_sources:
    if f"/* {source.name} */ = " in text:
        continue
    relative = source.relative_to(root).as_posix()
    file_id, build_id = identifier("file:" + relative), identifier("test:" + relative)
    text = text.replace("/* Begin PBXFileReference section */", f"""/* Begin PBXFileReference section */
\t\t{file_id} /* {source.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {source.name}; path = "{relative}"; sourceTree = SOURCE_ROOT; }};""", 1)
    text = text.replace("/* Begin PBXBuildFile section */", f"""/* Begin PBXBuildFile section */
\t\t{build_id} /* {source.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {source.name} */; }};""", 1)
    pattern = r"(13A132032F10000300A13200 /\* Tests \*/ = \{\s*isa = PBXGroup;\s*children = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{file_id} /* {source.name} */,", text, count=1)
    assert count == 1
    phase = "7907BEAB2ACD87A200C4D500" if source.parent.name == "UITests" else "7907BEA12ACD87A200C4D500"
    pattern = rf"({phase} /\* Sources \*/ = \{{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \()"
    text, count = re.subn(pattern, lambda m: m.group(1) + f"\n\t\t\t\t{build_id} /* {source.name} in Sources */,", text, count=1)
    assert count == 1
    test_count += 1

project.write_text(text)
print(f"Registered {added} new sources ({len(sources)} app sources total), {resource_count} resources, {test_count} tests.")
