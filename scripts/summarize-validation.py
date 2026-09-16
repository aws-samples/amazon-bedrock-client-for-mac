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
for path in [directory / relative for relative in ("core/tests.log", "rendering/tests.log", "app-tests.log")]:
    if not path.is_file():
        continue
    text = path.read_text(errors="replace")
    if path.name == "app-tests.log":
        cases = dict(re.findall(r"Test Case '([^'\n]+)' (passed|failed|skipped) \(", text))
        for suite, is_ui in (("App integration", False), ("Native UI", True)):
            actual = [status for name, status in cases.items() if ("BedrockUITests." in name) == is_ui]
            if actual:
                results.append({"log": suite, "executed": len(actual), "skipped": actual.count("skipped"),
                                "failures": actual.count("failed")})
        continue
    counts = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures", text)
    if not counts:
        counts = [(total, "0", failed) for total, failed in re.findall(r"Executed (\d+) tests?, with (\d+) failures", text)]
    if counts:
        total, skipped, failures = map(int, counts[-1])
        results.append({"log": str(path.relative_to(directory)), "executed": total, "skipped": skipped, "failures": failures})
(directory / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
receipt = directory / "ci-result.json"
complete = receipt.is_file() and json.loads(receipt.read_text()).get("complete", False)
lines = ["## Native regression validation", "",
         "**Complete CI passed.**" if complete else "**Complete CI has not passed. Counts below show only cases that executed.**",
         "",
         "The app tests run with Release optimization. Bedrock protocol responses come from a loopback fixture; actual SDK serialization, streaming, tools and local persistence remain in use.",
         "", "| Suite log | Executed | Skipped | Failures |", "| --- | ---: | ---: | ---: |"]
lines += [f"| {item['log']} | {item['executed']} | {item['skipped']} | {item['failures']} |" for item in results]
if (directory / "Bedrock.xcresult").is_dir():
    lines += ["", "Executed UI cases attach screenshots, measured interactions, fixture requests and failure diagnostics to `Bedrock.xcresult`."]
else:
    lines += ["", "The pipeline stopped before producing `Bedrock.xcresult`; no app/UI execution is claimed for this run."]
lines += ["", "Renderer cases also run in the app suite; counts are not a unique coverage total. `ci-result.json` records whether every stage passed against unchanged source files and executable permissions.", ""]
text = "\n".join(lines)
(directory / "summary.md").write_text(text)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
        output.write(text)
print(text)
