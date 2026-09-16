#!/usr/bin/env python3
"""Run a clearly named, isolated UI test app against the local Bedrock fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="The WORKBENCH_TESTING app built by scripts/ci.py")
    parser.add_argument("--output", required=True, type=Path, help="A new folder for test data and evidence")
    args = parser.parse_args()
    source = args.app.resolve()
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    if not info.get("CFBundleIdentifier", "").endswith(".UITestHost"):
        parser.error("Use the isolated UITestHost build, not the normal Bedrock app.")
    output = args.output.resolve()
    if output.exists():
        parser.error("Use a fresh --output directory; existing test data will not be replaced.")
    output.mkdir(parents=True)
    data = output / "app-data"
    data.mkdir()
    app = output / "Bedrock UI Tests.app"
    subprocess.run(["ditto", str(source), str(app)], check=True)
    info.update(CFBundleIdentifier="AWS.Amazon-Bedrock-Client-for-Mac.ManualUITests",
                CFBundleName="Bedrock UI Tests", CFBundleDisplayName="Bedrock UI Tests")
    # Reopening this test copy from Finder must stay offline after the fixture
    # has stopped, rather than falling back to the user's AWS credentials.
    info["LSEnvironment"] = {
        "BEDROCK_WORKBENCH_DATA_DIR": str(data), "BEDROCK_TEST_OFFLINE": "1"
    }
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    with (output / "sign.log").open("w") as log:
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)

    root = Path(__file__).resolve().parents[1]
    ready = output / "runtime-ready.json"
    requests = output / "runtime-requests.jsonl"
    server = None
    application = None
    def stop(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        with (output / "fixture.log").open("w") as log:
            server = subprocess.Popen([
                sys.executable, str(root / "Tests/Fixtures/bedrock_runtime.py"),
                "--ready", str(ready), "--requests", str(requests)
            ], stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 8
        while not ready.is_file() and server.poll() is None and time.monotonic() < deadline:
            time.sleep(.02)
        if not ready.is_file():
            raise RuntimeError("The fixture failed to start; see fixture.log.")
        port = json.loads(ready.read_text())["port"]
        environment = {key: value for key, value in os.environ.items() if not key.startswith("AWS_")}
        environment.update(info["LSEnvironment"])
        environment.update(
            BEDROCK_TEST_RUNTIME_PORT=str(port), AWS_EC2_METADATA_DISABLED="true",
            LLVM_PROFILE_FILE=str(output / "bedrock-%p.profraw")
        )
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        with (output / "app.log").open("w") as log:
            application = subprocess.Popen([
                str(executable), "-checkForUpdates", "NO", "-enableQuickAccess", "NO",
                "-mcpEnabled", "NO", "-enableDebugLog", "NO", "-appearance", "light",
                "-selectedRegion", "us-west-2", "-selectedProfile", "default",
                "-defaultModelId", "us.amazon.nova-2-lite-v1:0"
            ], env=environment, stdout=log, stderr=subprocess.STDOUT)
        (output / "session.json").write_text(json.dumps({
            "appPID": application.pid, "serverPID": server.pid, "port": port,
            "app": str(app), "data": str(data), "offline": True,
            "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest()
        }, indent=2) + "\n")
        print(f"Bedrock UI Tests is running offline (PID {application.pid}). Evidence: {output}", flush=True)
        return application.wait()
    except KeyboardInterrupt:
        return 130
    finally:
        for process in (application, server):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
