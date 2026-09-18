#!/usr/bin/env python3
"""Build and execute local storage/tool/parser XCTest tests with the installed CLT."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from validation_support import developer_directory, toolchain, assert_tests_executed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--developer-dir", type=Path)
    parser.add_argument("--xcode", type=Path)
    parser.add_argument("--filter", help="XCTest class or class/method to run locally; omit for the complete core suite.")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output or Path(tempfile.mkdtemp(prefix="bedrock-local-tests-"))
    output.mkdir(parents=True, exist_ok=True)
    developer = developer_directory(args.developer_dir)
    swift, platform, runner, _ = toolchain(developer, args.xcode)
    frameworks, libraries = platform / "Library/Frameworks", platform / "usr/lib"
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = str(developer)
    environment["LLVM_PROFILE_FILE"] = str(output / "core-%p.profraw")
    command = [str(swift), "build", "--build-tests", "--package-path", str(repo),
               "--scratch-path", str(output / ".build"), "-j", "4"]
    for flag, value in [("-I", libraries), ("-F", frameworks)]:
        command += ["-Xswiftc", flag, "-Xswiftc", str(value)]
    for flag, value in [("-F", frameworks), ("-L", libraries), ("-rpath", frameworks), ("-rpath", libraries)]:
        command += ["-Xlinker", flag, "-Xlinker", str(value)]
    with (output / "build.log").open("w") as log:
        result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=360)
    if result.returncode:
        raise SystemExit(f"Core test build failed: {output / 'build.log'}")
    bundles = list((output / ".build").glob("**/BedrockCoreTests.xctest"))
    if not bundles:
        bundles = list((output / ".build").glob("**/*PackageTests.xctest"))
    if not bundles:
        raise SystemExit("No XCTest bundle found; no tests were executed.")
    with (output / "tests.log").open("w") as log:
        selection = ["-XCTest", args.filter] if args.filter else []
        result = subprocess.run([str(runner), *selection, str(bundles[0])],
                                env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    text = (output / "tests.log").read_text()
    print(text)
    assert_tests_executed(text)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
