#!/usr/bin/env python3
"""Exercise actual AppKit quit, save failure/retry, and installer-driven relaunch."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binary = output / "TerminationProbe"
    sources = [
        "Tests/Lifecycle/TerminationProbe.swift",
        "Sources/Bedrock/App/ApplicationTerminationCoordinator.swift",
        "Sources/Bedrock/Core/Models/SoftwareUpdate.swift",
        "Sources/Bedrock/Core/Tools/LocalProcessRunner.swift",
        "Sources/Bedrock/Core/Support/LocalOperationError.swift",
        "Sources/Bedrock/Services/System/UpdateInstaller.swift",
    ]
    with (output / "build.log").open("w") as log:
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-O",
                        *[str(root / path) for path in sources], "-o", str(binary)],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    report = {"complete": False, "scenarios": [], "sourceSHA256": {
        path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources
    }}

    def require(value, message):
        if not value:
            raise RuntimeError(message)

    def launch(command, folder, timeout=8):
        started = time.monotonic()
        with (folder / "process.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                require(process.wait(timeout=timeout) == 0, f"Application failed: {folder.name}")
            except BaseException:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)
                raise
        return time.monotonic() - started

    def bundle(path, scenario, folder):
        contents = path / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copy2(binary, contents / "MacOS/TerminationProbe")
        info = {
            "CFBundleIdentifier": f"org.example.BedrockTermination.{scenario}",
            "CFBundleExecutable": "TerminationProbe", "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "2.0.2" if scenario == "installed" else "2.0.1",
            "LSUIElement": True, "LifecycleScenario": scenario, "LifecycleRoot": str(folder),
        }
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(path)],
                       check=True, capture_output=True, timeout=20)

    try:
        for scenario in ("quit", "duplicate", "retry"):
            folder = output / scenario
            folder.mkdir()
            elapsed = launch([str(binary), scenario, str(folder)], folder)
            events = (folder / "events.log").read_text().splitlines()
            expected = 2 if scenario == "retry" else 1
            require(sum(event.startswith("saving ") for event in events) == expected,
                    f"Unexpected save count: {scenario}")
            require(events.index(f"saved {expected}") < events.index(f"will-terminate {scenario}"),
                    "App quit before saving")
            require((folder / "draft.txt").read_text() == "Unsent draft preserved.\n", "Draft changed")
            if scenario == "retry":
                require("cancelled" in events and "retry-requested" in events,
                        "Failed save must leave the event loop running and permit retry")
            report["scenarios"].append({"name": scenario, "passed": True, "seconds": round(elapsed, 3)})

        folder = output / "install"
        folder.mkdir()
        destination = folder / "Installed/Bedrock Fixture.app"
        staged = destination.parent / ".staging/New.app"
        bundle(destination, "install", folder)
        bundle(staged, "installed", folder)
        elapsed = launch([str(destination / "Contents/MacOS/TerminationProbe")], folder)
        backup = destination.parent / ".staging/Previous.app"
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            # Relaunch and successful replacement can precede the helper's
            # final backup removal. Wait for all three observable outcomes.
            if (folder / "reopened").exists() and (folder / "result").exists() and not backup.exists():
                break
            time.sleep(0.05)
        require((folder / "reopened").read_text() == "2.0.2\n", "Installed application did not reopen")
        require((folder / "result").read_text() == "installed\n", "Installer did not finish")
        info = plistlib.loads((destination / "Contents/Info.plist").read_bytes())
        require(info["CFBundleShortVersionString"] == "2.0.2", "Wrong installed version")
        require(not backup.exists(), "Backup was not cleaned up")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(destination)],
                       check=True, capture_output=True, timeout=20)
        report["scenarios"].append({"name": "install-and-relaunch", "passed": True,
                                    "quitSeconds": round(elapsed, 3)})
        report["complete"] = True
    finally:
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
