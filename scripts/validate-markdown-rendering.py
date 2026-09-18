#!/usr/bin/env python3
"""Run the production native Markdown renderer's tests without AWS or app data.

Example with an existing MarkdownKit checkout:
  python3 scripts/validate-markdown-rendering.py \
    --markdown-package /path/to/swift-markdownkit \
    --developer-dir /Library/Developer/CommandLineTools
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from validation_support import developer_directory, toolchain, assert_tests_executed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--markdown-package", type=Path, required=True)
    parser.add_argument("--developer-dir", type=Path)
    parser.add_argument("--xcode", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not (args.markdown_package / "Package.swift").is_file():
        parser.error("--markdown-package must be a MarkdownKit checkout")

    repo = Path(__file__).resolve().parents[1]
    app = repo / "Sources/Bedrock"
    output = args.output or Path(tempfile.mkdtemp(prefix="bedrock-markdown-"))
    sources = output / "Sources/Rendering"
    tests = output / "Tests/RenderingTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)
    for relative in ("UI/Markdown/MarkdownRenderer.swift", "UI/Markdown/MarkdownMathScript.swift", "UI/Markdown/MarkdownClipboard.swift", "UI/Markdown/SelectableMarkdown.swift", "UI/Components/TextContextMenu.swift", "UI/Markdown/MarkdownColors.swift",
                     "Features/Chat/ConversationFind.swift", "Services/Attachments/AttachmentProcessor.swift", "Services/Attachments/ImagePreviewLoader.swift",
                     "Services/Attachments/AttachmentStore.swift", "Features/Composer/EditorFocusState.swift"):
        shutil.copy2(app / relative, sources / Path(relative).name)
    for source in (app / "Core").rglob("*.swift"):
        shutil.copy2(source, sources / source.name)
    resources = sources / "Resources"
    resources.mkdir(exist_ok=True)
    shutil.copy2(app / "Resources/Math/katex.min.js", resources / "katex.min.js")
    # Exercise the actual NSTextView paste implementation in isolation from
    # the SwiftUI wrapper's AWS/application state.
    editor = (app / "Features/Composer/ComposerTextView.swift").read_text()
    editor = editor.split("/// Extension to validate NSImage")[0]
    (sources / "ClipboardTextView.swift").write_text(editor)
    # Use the actual palette and font sizes, without pulling in AWS managers.
    components = (app / "UI/DesignSystem/DesignTokens.swift").read_text()
    style = re.search(r"enum DesignTokens \{.*?\n\}", components, re.S)
    if not style:
        raise SystemExit("DesignTokens moved; update the harness source list.")
    (sources / "DesignTokens.swift").write_text("import AppKit\nimport SwiftUI\n\n" + style.group(0) + "\n")
    shutil.copy2(repo / "Tests/BedrockTests/MarkdownRenderingTests.swift", tests / "MarkdownRenderingTests.swift")
    shutil.copy2(repo / "Tests/BedrockTests/ClipboardRenderingTests.swift", tests / "ClipboardRenderingTests.swift")

    developer = developer_directory(args.developer_dir)
    swift, platform, runner, plugin_flags = toolchain(developer, args.xcode)
    (output / "Package.swift").write_text(f"""// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BedrockMarkdownValidation", platforms: [.macOS(.v14)],
    dependencies: [.package(path: {json.dumps(str(args.markdown_package.resolve()))})],
    targets: [
        .target(name: "Amazon_Bedrock_Client_for_Mac",
                dependencies: [.product(name: "MarkdownKit", package: "swift-markdownkit")],
                path: "Sources/Rendering", resources: [.process("Resources")]),
        .testTarget(name: "MarkdownRenderingTests", dependencies: ["Amazon_Bedrock_Client_for_Mac"],
                    path: "Tests/RenderingTests")
    ], swiftLanguageModes: [.v6])
""")
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = str(developer)
    environment["LLVM_PROFILE_FILE"] = str(output / "rendering-%p.profraw")
    frameworks, libraries = platform / "Library/Frameworks", platform / "usr/lib"
    command = [str(swift), "build", "--build-tests",
               "--package-path", str(output), "-j", "6"]
    # CLT's SDK can reference SwiftUI macros supplied by Xcode. Pass this to
    # dependencies as well: MarkdownKit 1.4 includes its own SwiftUI views.
    for flag in plugin_flags:
        command += ["-Xswiftc", flag]
    for flag, value in [("-I", libraries), ("-F", frameworks)]:
        command += ["-Xswiftc", flag, "-Xswiftc", str(value)]
    for flag, value in [("-F", frameworks), ("-L", libraries), ("-rpath", frameworks), ("-rpath", libraries)]:
        command += ["-Xlinker", flag, "-Xlinker", str(value)]
    build_log = output / "build.log"
    with build_log.open("w") as log:
        result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(build_log.read_text().splitlines()[-80:]))
        raise SystemExit(f"Native renderer test build failed. See {build_log}")

    bundles = list((output / ".build").glob("**/MarkdownRenderingTests.xctest"))
    if not bundles:
        bundles = list((output / ".build").glob("**/*PackageTests.xctest"))
    if not bundles:
        raise SystemExit(f"No XCTest bundle was built. See {build_log}")
    run_log = output / "tests.log"
    with run_log.open("w") as log:
        result = subprocess.run([str(runner), str(bundles[0])], env=environment, stdout=log, stderr=subprocess.STDOUT)
    text = run_log.read_text()
    print(text)
    assert_tests_executed(text)
    print(f"Build and test evidence: {output}")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
