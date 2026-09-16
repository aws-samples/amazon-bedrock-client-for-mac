#!/usr/bin/env python3
"""Submit with stored runner credentials; reject every non-Accepted result."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("artifact", type=Path)
parser.add_argument("--report", type=Path, required=True)
parser.add_argument("--profile", default="bedrock-release")
args = parser.parse_args()
args.report.parent.mkdir(parents=True, exist_ok=True)
result = subprocess.run(
    ["xcrun", "notarytool", "submit", str(args.artifact), "--keychain-profile", args.profile,
     "--wait", "--timeout", "20m", "--output-format", "json"],
    capture_output=True, text=True, timeout=1300)
args.report.write_text(result.stdout)
if result.stderr:
    print(result.stderr)
try:
    report = json.loads(result.stdout)
except json.JSONDecodeError:
    raise SystemExit("Notarization did not return valid JSON. Inspect the saved report.")
if report.get("id"):
    subprocess.run(
        ["xcrun", "notarytool", "log", report["id"], "--keychain-profile", args.profile,
         str(args.report.with_name(args.report.stem + "-log.json"))], check=False)
if result.returncode or report.get("status") != "Accepted":
    raise SystemExit(f"Notarization failed: {report.get('status', 'unknown status')}.")
print(f"Notarization accepted: {args.artifact.name} ({report['id']})")
