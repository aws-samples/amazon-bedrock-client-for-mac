#!/usr/bin/env python3
"""Run the same complete macOS validation pipeline locally and on GitHub."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def run_bounded(command, *, cwd, env, stdout, timeout, heartbeat=30, progress=None):
    """Bound the stage and clean up its process group on timeout or interruption."""
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=stdout,
                               stderr=subprocess.STDOUT, start_new_session=True)
    started = time.monotonic()

    def stop():
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        # Include descendants that kept the stage's output or work alive.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)

    try:
        while True:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                stop()
                return 124
            try:
                return process.wait(timeout=min(heartbeat, remaining))
            except subprocess.TimeoutExpired:
                if progress:
                    progress(time.monotonic() - started)
    except BaseException:
        stop()
        raise


def input_hashes(root):
    """Hash source and automation, including new files but excluding ignored local evidence."""
    folders = {"Sources", "Tests", "Configuration", "scripts", "docs"}
    files = {
        "Package.swift", "README.md", "CONTRIBUTING.md",
        "Bedrock.xcodeproj/project.pbxproj",
        "Bedrock.xcodeproj/xcshareddata/xcschemes/Bedrock.xcscheme",
        "Bedrock.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    }
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root
    ).decode().split("\0")
    inputs = sorted({
        name for name in names if name
        and (Path(name).parts[0] in folders or name.startswith(".github/workflows/") or name in files)
        and "__pycache__" not in Path(name).parts and Path(name).suffix not in (".pyc", ".log")
    })
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in inputs}


def input_executables(root, paths):
    return {name: bool((root / name).stat().st_mode & 0o111) for name in paths}


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, default=root / "artifacts")
    parser.add_argument("--derived-data", type=Path, default=root / ".build/ci-derived")
    parser.add_argument("--packages", type=Path, default=root / ".build/ci-packages")
    parser.add_argument("--developer-dir", type=Path)
    args = parser.parse_args()
    output = args.artifacts.resolve()
    output.mkdir(parents=True, exist_ok=True)
    result_bundle = output / "Bedrock.xcresult"
    if result_bundle.exists() or (output / "ci-result.json").exists():
        parser.error("Use a fresh --artifacts directory to preserve the previous test evidence.")

    selected = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
    developer = args.developer_dir or Path(os.environ.get("DEVELOPER_DIR", selected))
    if developer.name == "CommandLineTools":
        developer = Path("/Applications/Xcode.app/Contents/Developer")
    xcodebuild = developer / "usr/bin/xcodebuild"
    if not xcodebuild.is_file():
        parser.error("Full Xcode is required for the app and UI suites. Pass --developer-dir.")

    environment = {key: value for key, value in os.environ.items() if not key.startswith("AWS_")}
    environment.update(
        DEVELOPER_DIR=str(developer),
        BEDROCK_TEST_OFFLINE="1",
        BEDROCK_TEST_FIXTURES=str(root / "Tests/Fixtures"),
        BEDROCK_WORKBENCH_DATA_DIR=str(output / "test-data"),
        LLVM_PROFILE_FILE=str(output / "bedrock-%p.profraw"),
        PYTHONUNBUFFERED="1",
        AWS_EC2_METADATA_DISABLED="true",
    )
    environment.pop("BEDROCK_LIVE_NETWORK_TESTS", None)

    hashes = input_hashes(root)
    executables = input_executables(root, hashes)
    report = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root)),
        "developerDirectory": str(developer),
        "configuration": "Release",
        "optimization": "-O",
        "complete": False,
        "steps": [],
        "inputSHA256": hashes,
        "inputExecutable": executables,
    }
    receipt = output / "ci-result.json"

    def save():
        receipt.write_text(json.dumps(report, indent=2) + "\n")

    def run(name, command, logfile, timeout=120):
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::group::{name}", flush=True)
        print(f"Running {name}…", flush=True)
        start = time.monotonic()
        def progress(elapsed):
            print(f"{name}: {elapsed:.0f}s / {timeout}s; log: {logfile}", flush=True)
            live_log = output / ("core/tests.log" if name == "local core" else logfile)
            if live_log.is_file():
                with live_log.open("rb") as source:
                    source.seek(max(0, live_log.stat().st_size - 8_192))
                    lines = source.read().decode(errors="replace").splitlines()
                cases = [line for line in lines if line.startswith("Test Case ")]
                if cases:
                    print(cases[-1][:250], flush=True)
        with (output / logfile).open("w") as log:
            return_code = run_bounded([str(value) for value in command], cwd=root, env=environment,
                                      stdout=log, timeout=timeout, progress=progress)
        report["steps"].append({
            "name": name, "exitCode": return_code,
            "seconds": round(time.monotonic() - start, 3), "log": logfile,
        })
        save()
        if os.environ.get("GITHUB_ACTIONS"):
            print("::endgroup::", flush=True)
        if return_code:
            lines = (output / logfile).read_text(errors="replace").splitlines()
            important = [line for line in lines if "error:" in line or "failed" in line.lower()]
            print("\n".join((important or lines[-25:])[-25:]), file=sys.stderr)
            reason = f"exceeded its {timeout}s limit" if return_code == 124 else "failed"
            raise RuntimeError(f"{name} {reason}; see {output / logfile}")
        print(f"Passed {name} ({report['steps'][-1]['seconds']:.1f}s)", flush=True)

    common = [
        "-project", root / "Bedrock.xcodeproj", "-scheme", "Bedrock",
        "-derivedDataPath", args.derived_data.resolve(),
        "-clonedSourcePackagesDirPath", args.packages.resolve(),
    ]
    python = sys.executable
    Path("/private/tmp/bedrock-ui-fixtures").mkdir(parents=True, exist_ok=True)
    save()
    exit_code = 0
    try:
        run("Xcode readiness", [xcodebuild, "-checkFirstLaunchStatus"], "xcode.log")
        run("project membership and compatibility", [python, "scripts/check-project.py"], "project.log")
        run("release metadata", [python, "scripts/verify-release.py"], "release-metadata.log")
        run("validation script syntax",
            [python, "-m", "py_compile", *sorted((root / "scripts").glob("*.py")),
             *sorted((root / "Tests/Fixtures").glob("*.py"))], "scripts.log")
        run("documentation and media", [python, "scripts/validate-documentation.py"], "documentation.log")
        run("pipeline automation",
            [python, "-m", "unittest", "discover", "-s", "Tests/Pipeline", "-v"], "pipeline.log")
        run("real AppKit shutdown and update relaunch",
            [python, "scripts/validate-app-termination.py", "--output", output / "lifecycle"],
            "lifecycle.log", timeout=180)
        run("Bedrock protocol fixtures",
            [python, "-m", "unittest", "discover", "-s", "Tests/Fixtures", "-p", "test_*.py", "-v"], "fixtures.log")
        run("local core", [python, "scripts/validate-local-core.py", "--output", output / "core"],
            "core-suite.log", timeout=600)
        run("pinned dependencies", [xcodebuild, "-resolvePackageDependencies", *common,
                                    "-onlyUsePackageVersionsFromResolvedFile"], "dependencies.log", timeout=300)
        run("UI automation readiness",
            [python, "scripts/check-ui-test-environment.py"], "ui-environment.log")
        run("optimized app integration and UI",
            [xcodebuild, "test", *common, "-configuration", "Release",
             "-destination", "platform=macOS", "-resultBundlePath", result_bundle,
             "-disableAutomaticPackageResolution", "-parallel-testing-enabled", "NO",
             "-test-timeouts-enabled", "YES",
             "-default-test-execution-time-allowance", "180",
             "-maximum-test-execution-time-allowance", "300",
             "-skipMacroValidation", "-skipPackagePluginValidation",
             "ENABLE_TESTABILITY=YES", "SWIFT_OPTIMIZATION_LEVEL=-O",
             "ONLY_ACTIVE_ARCH=YES", "COMPILER_INDEX_STORE_ENABLE=NO",
             "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) WORKBENCH_TESTING",
             "BEDROCK_APP_BUNDLE_IDENTIFIER=AWS.Amazon-Bedrock-Client-for-Mac.UITestHost",
             f"BEDROCK_TEST_PYTHON={python}",
             "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-",
             "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM="], "app-tests.log", timeout=2100)
        run("Xcode execution receipt",
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", result_bundle, "--compact"],
            "xcode-summary.json")
        run("Xcode suite inventory",
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", result_bundle, "--compact"],
            "xcode-tests.json")
        # These same rendering cases are compiled into and executed by the app suite.
        # Verify every source-declared case instead of building and running them twice.
        run("native Markdown and clipboard",
            [python, "scripts/verify-rendering-results.py", "--inventory", output / "xcode-tests.json"],
            "rendering-suite.log")
        execution = json.loads((output / "xcode-summary.json").read_text())
        inventory = json.loads((output / "xcode-tests.json").read_text())

        def test_cases(nodes):
            for node in nodes:
                if node.get("nodeType") == "Test Case":
                    yield node
                yield from test_cases(node.get("children", []))

        cases = list(test_cases(inventory.get("testNodes", [])))
        if execution.get("result") != "Passed" or execution.get("failedTests", 1) != 0:
            raise RuntimeError("Xcode did not record a completely passing execution.")
        optional_network_cases = {
            f"MCPServerTests/{name}()" for name in (
                "testOAuthServerConnectivity", "testOpenServerConnectivity",
                "testAPIKeyServerConnectivity", "testOAuthMetadataDiscovery"
            )
        }
        skipped = [case.get("nodeIdentifier", "") for case in cases if case.get("result") == "Skipped"]
        if any(name not in optional_network_cases for name in skipped):
            raise RuntimeError("A required test was skipped. Only the four opt-in public MCP diagnostics may skip.")
        for suite in ("BedrockUITests", "MCPConfigurationTests", "MCPIntegrationTests", "WindowLifecycleTests",
                      "UpdateInstallerTests", "ConversationViewportTests", "NativeTranscriptTests"):
            actual = [case for case in cases if case.get("nodeIdentifier", "").startswith(suite + "/")]
            if not actual or any(case.get("result") != "Passed" for case in actual):
                raise RuntimeError(f"{suite} did not execute and pass every required case.")
        if input_hashes(root) != hashes or input_executables(root, hashes) != executables:
            raise RuntimeError("Source files changed during validation; rerun the complete pipeline.")
        report["complete"] = True
        print(f"Complete local CI passed. Evidence: {receipt}", flush=True)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
        print(str(error), file=sys.stderr)
        exit_code = 1
    finally:
        report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        save()
        subprocess.run([python, str(root / "scripts/summarize-validation.py"), str(output)], cwd=root, env=environment)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
