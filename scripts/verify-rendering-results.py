#!/usr/bin/env python3
"""Require every renderer/clipboard regression to have passed in the real app suite."""
import argparse
import json
from pathlib import Path
import re


def test_cases(nodes):
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            yield node
        yield from test_cases(node.get("children", []))


def verify(root, inventory):
    actual = {case["nodeIdentifier"]: case.get("result")
              for case in test_cases(inventory.get("testNodes", []))}
    totals = {}
    for suite in ("MarkdownRenderingTests", "ClipboardRenderingTests"):
        source = root / "Tests/BedrockTests" / f"{suite}.swift"
        names = set(re.findall(r"\bfunc\s+(test\w+)\s*\(", source.read_text()))
        if not names:
            raise ValueError(f"No source-declared cases found for {suite}.")
        missing = [name for name in sorted(names) if actual.get(f"{suite}/{name}()") != "Passed"]
        if missing:
            raise ValueError(f"{suite} did not execute and pass: {', '.join(missing)}")
        totals[suite] = len(names)
    return totals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(Path(__file__).resolve().parents[1],
                            json.loads(args.inventory.read_text())), indent=2))


if __name__ == "__main__":
    main()
