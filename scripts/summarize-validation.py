#!/usr/bin/env python3
"""Keep executed test counts and failure summaries next to the xcresult."""
import json
import os
import re
import sys
from pathlib import Path

directory = Path(sys.argv[1])
directory.mkdir(parents=True, exist_ok=True)
results = []
for path in sorted(directory.rglob("*.log")):
    text = path.read_text(errors="replace")
    counts = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures", text)
    if not counts:
        counts = [(total, "0", failed) for total, failed in re.findall(r"Executed (\d+) tests?, with (\d+) failures", text)]
    if counts:
        total, skipped, failures = map(int, counts[-1])
        results.append({"log": str(path.relative_to(directory)), "executed": total, "skipped": skipped, "failures": failures})
(directory / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
lines = ["## Native regression validation", "",
         "The app tests run with Release optimization. Bedrock protocol responses come from a loopback fixture; actual SDK serialization, streaming, tools and local persistence remain in use.",
         "", "| Suite log | Executed | Skipped | Failures |", "| --- | ---: | ---: | ---: |"]
lines += [f"| {item['log']} | {item['executed']} | {item['skipped']} | {item['failures']} |" for item in results]
lines += ["", "UI screenshots, measured interactions, exact fixture requests and failure diagnostics are attached to `Workbench.xcresult`. Test groups can overlap; counts are not a unique coverage total.", ""]
text = "\n".join(lines)
(directory / "summary.md").write_text(text)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
        output.write(text)
print(text)
