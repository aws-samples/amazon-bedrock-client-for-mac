#!/usr/bin/env python3
"""Report XCTest's normal macOS authentication requirement without changing it."""
from pathlib import Path
import subprocess


def main():
    tool = Path("/usr/bin/automationmodetool")
    if not tool.exists():
        print("Automation Mode status is unavailable; XCTest will validate the environment.")
        return 0
    result = subprocess.run([str(tool)], text=True, capture_output=True, timeout=10)
    status = result.stdout + result.stderr
    print(status.strip())
    if "disabled" in status.lower() and "requires user authentication" in status.lower():
        print("Local CI cannot run its required UI scenarios yet. Complete the normal "
              "UI-testing authentication in Xcode, then rerun scripts/ci.py. "
              "No release is permitted from this incomplete run.")
        return 1
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
