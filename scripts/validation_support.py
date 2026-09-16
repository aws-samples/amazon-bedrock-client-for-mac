"""Shared macOS toolchain discovery for local and CI validation."""
import os
from pathlib import Path
import subprocess


def developer_directory(value=None):
    return value or Path(os.environ.get("DEVELOPER_DIR") or
                         subprocess.check_output(["xcode-select", "-p"], text=True).strip())


def toolchain(developer, xcode=None):
    developer = Path(developer)
    if xcode is None:
        xcode = developer.parent.parent if developer.name == "Developer" else Path("/Applications/Xcode.app")
    platform = Path(xcode) / "Contents/Developer/Platforms/MacOSX.platform/Developer"
    swift = developer / "usr/bin/swift"
    if not swift.exists():
        swift = developer / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    runner = platform / "Library/Xcode/Agents/xctest"
    if not swift.exists() or not runner.exists():
        raise SystemExit("Swift and XCTest are required. Select an installed Xcode or pass --developer-dir and --xcode.")
    plugins = platform / "usr/lib/swift/host/plugins"
    server = developer / "usr/bin/swift-plugin-server"
    flags = ["-external-plugin-path", f"{plugins}#{server}"] if (
        developer.name == "CommandLineTools" and plugins.exists() and server.exists()) else []
    return swift, platform, runner, flags


def assert_tests_executed(text):
    if "Executed " not in text or "Executed 0 tests" in text:
        raise SystemExit("The XCTest runner did not execute the test suite.")
