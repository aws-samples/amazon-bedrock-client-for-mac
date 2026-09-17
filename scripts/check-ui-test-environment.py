#!/usr/bin/env python3
"""Report macOS automation status; XCTest performs its own authorization."""
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
        # Persistent Automation Mode is not the same as an authorized XCTest
        # session. Xcode can successfully drive the app while this tool still
        # reports disabled; rejecting that state prevented actual UI execution.
        print("XCTest will perform its normal UI-testing authorization if needed. "
              "CI still requires every UI scenario to execute and pass; "
              "this status check neither enables Automation Mode nor grants access.")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
