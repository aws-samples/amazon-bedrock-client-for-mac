#!/usr/bin/env python3
"""Reuse complete main CI only for the exact release source and executable modes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


REQUIRED_STEPS = {
    "Xcode readiness", "project membership and compatibility", "release metadata",
    "validation script syntax", "documentation and media", "local core",
    "Bedrock protocol fixtures", "pinned dependencies", "native Markdown and clipboard",
    "UI automation readiness", "optimized app integration and UI",
    "Xcode execution receipt", "Xcode suite inventory",
}
OPTIONAL_TESTS = {
    f"MCPServerTests/{name}()" for name in (
        "testOAuthServerConnectivity", "testOpenServerConnectivity",
        "testAPIKeyServerConnectivity", "testOAuthMetadataDiscovery",
    )
}
REQUIRED_SUITES = {
    "BedrockUITests", "MCPConfigurationTests", "MCPIntegrationTests", "WindowLifecycleTests",
    "UpdateInstallerTests", "ConversationViewportTests", "NativeTranscriptTests",
    "MarkdownRenderingTests", "ClipboardRenderingTests",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_inputs(root):
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
    return {
        name for name in names if name
        and (Path(name).parts[0] in folders or name.startswith(".github/workflows/") or name in files)
        and "__pycache__" not in Path(name).parts and Path(name).suffix not in (".pyc", ".log")
    }


def test_cases(nodes):
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            yield node
        yield from test_cases(node.get("children", []))


def verify_receipt(root, revision, run, receipt, summary, inventory, inputs):
    require(run.get("head_sha") == revision and run.get("head_branch") == "main"
            and run.get("event") == "push" and run.get("path") == ".github/workflows/ci.yml"
            and run.get("status") == "completed" and run.get("conclusion") == "success",
            "Release requires a successful main push CI run for this exact commit.")
    require(receipt.get("revision") == revision and receipt.get("complete") is True
            and receipt.get("dirty") is False and receipt.get("configuration") == "Release"
            and receipt.get("optimization") == "-O",
            "CI receipt must describe a complete, clean, optimized run of the release commit.")
    steps = receipt.get("steps", [])
    required = REQUIRED_STEPS | ({"pipeline automation"} if any(
        name.startswith("Tests/Pipeline/") for name in inputs) else set())
    require(required <= {step.get("name") for step in steps}
            and all(step.get("exitCode") == 0 for step in steps), "A required CI stage did not pass.")
    hashes, modes = receipt.get("inputSHA256", {}), receipt.get("inputExecutable", {})
    require(set(hashes) == inputs and set(modes) == inputs and inputs,
            "The release input inventory differs from the tested source.")
    for name, expected in hashes.items():
        path = root / name
        require(path.resolve().is_relative_to(root.resolve()) and path.is_file(),
                f"Invalid tested input: {name}")
        require(hashlib.sha256(path.read_bytes()).hexdigest() == expected,
                f"Source changed after CI: {name}")
        require(bool(path.stat().st_mode & 0o111) == modes[name], f"Executable mode changed: {name}")
    require(summary.get("result") == "Passed" and summary.get("failedTests") == 0,
            "Xcode did not record a passing execution.")
    cases = list(test_cases(inventory.get("testNodes", [])))
    require(cases and all(case.get("result") == "Passed"
                         or (case.get("result") == "Skipped"
                             and case.get("nodeIdentifier") in OPTIONAL_TESTS) for case in cases),
            "Required Xcode cases failed or were skipped.")
    for suite in REQUIRED_SUITES:
        actual = [case for case in cases if case.get("nodeIdentifier", "").startswith(suite + "/")]
        require(actual and all(case.get("result") == "Passed" for case in actual),
                f"The main run did not execute and pass {suite}.")
    require(summary.get("totalTestCount") == len(cases),
            "The Xcode summary and case inventory disagree.")
    return {"revision": revision, "runID": run["id"], "runURL": run["html_url"],
            "sourceFiles": len(inputs), "testCases": len(cases), "verified": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(re.fullmatch(r"v\d+\.\d+\.\d+", args.tag), "Use an existing vx.y.z release tag.")
    root = args.root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def command(*values, timeout=120):
        return subprocess.check_output(values, cwd=root, text=True, timeout=timeout)

    revision = command("git", "rev-parse", "HEAD").strip()
    require(command("git", "rev-parse", f"refs/tags/{args.tag}^{{commit}}").strip() == revision,
            "Checkout must be the exact release tag.")
    subprocess.run(["git", "merge-base", "--is-ancestor", revision, "origin/main"], cwd=root, check=True)
    repository = os.environ["GITHUB_REPOSITORY"]
    runs = json.loads(command("gh", "run", "list", "--repo", repository, "--workflow", "ci.yml",
                             "--branch", "main", "--commit", revision, "--event", "push",
                             "--limit", "20", "--json", "databaseId,headSha,status,conclusion"))
    require(runs, "No main push CI run exists for this tag. Run main CI before releasing.")
    latest = max(runs, key=lambda run: run["databaseId"])
    run_id = str(latest["databaseId"])
    if latest["status"] != "completed":
        subprocess.run(["gh", "run", "watch", run_id, "--repo", repository,
                        "--interval", "15", "--exit-status"], cwd=root, check=True, timeout=2700)
    run = json.loads(command("gh", "api", f"repos/{repository}/actions/runs/{run_id}"))
    require(run.get("conclusion") == "success", "The latest main CI attempt did not pass.")
    artifacts = json.loads(command("gh", "api", f"repos/{repository}/actions/runs/{run_id}/artifacts"))
    names = {item["name"] for item in artifacts["artifacts"] if not item.get("expired")}
    compact = f"native-receipt-{run_id}"
    artifact = compact if compact in names else f"native-validation-{run_id}"
    require(artifact in names, "The main CI evidence is missing or expired; rerun main CI.")
    evidence = output / "main-ci"
    subprocess.run(["gh", "run", "download", run_id, "--repo", repository,
                    "--name", artifact, "--dir", str(evidence)],
                   cwd=root, check=True, timeout=300)
    read = lambda name: json.loads((evidence / name).read_text())
    receipt = read("ci-result.json")
    result = verify_receipt(root, revision, run, receipt, read("xcode-summary.json"),
                            read("xcode-tests.json"), source_inputs(root))
    (output / "main-ci-result.json").write_text(json.dumps(result, indent=2) + "\n")
    # Pin distribution to the same installed Xcode release as the tested app.
    version = re.search(r"/Xcode_([0-9.]+)\.app/", receipt["developerDirectory"])
    require(version, "CI receipt must identify the Xcode release used for validation.")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as target:
            target.write(f"revision={revision}\nrun_id={run_id}\nxcode={version[1]}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as target:
            target.write(f"### Main CI reused\n\nValidated [{revision[:7]}]({run['html_url']}): "
                         f"{result['sourceFiles']} source files and executable modes match; "
                         f"{result['testCases']} Xcode cases verified. The full suite is not repeated.\n\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
