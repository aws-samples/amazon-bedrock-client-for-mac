"""The release may reuse CI only when its source and complete execution match."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_gate", ROOT / "scripts/verify-main-ci.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Sources/App.swift"
        self.source.parent.mkdir()
        self.source.write_text("let version = 2\n")
        self.source.chmod(0o644)
        self.revision = "a" * 40
        self.run = {"id": 12, "html_url": "https://github.com/example/app/actions/runs/12",
                    "head_sha": self.revision, "head_branch": "main", "event": "push",
                    "path": ".github/workflows/ci.yml", "status": "completed", "conclusion": "success"}
        self.receipt = {
            "revision": self.revision, "complete": True, "dirty": False,
            "configuration": "Release", "optimization": "-O",
            "steps": [{"name": name, "exitCode": 0} for name in sorted(gate.REQUIRED_STEPS)],
            "inputSHA256": {"Sources/App.swift": hashlib.sha256(self.source.read_bytes()).hexdigest()},
            "inputExecutable": {"Sources/App.swift": False},
        }
        self.inventory = {"testNodes": [{"nodeType": "Test Suite", "children": [
            {"nodeType": "Test Case", "nodeIdentifier": f"{suite}/testRegression()", "result": "Passed"}
            for suite in sorted(gate.REQUIRED_SUITES)
        ]}]}
        self.summary = {"result": "Passed", "failedTests": 0, "totalTestCount": len(gate.REQUIRED_SUITES)}
        self.inputs = {"Sources/App.swift"}

    def verify(self):
        return gate.verify_receipt(self.root, self.revision, self.run, self.receipt,
                                   self.summary, self.inventory, self.inputs)

    def test_complete_matching_execution_is_reusable(self):
        self.assertTrue(self.verify()["verified"])

    def test_wrong_revision_branch_workflow_or_event_is_rejected(self):
        for key, value in (("head_sha", "b" * 40), ("head_branch", "release/v2.0.1"),
                           ("path", ".github/workflows/other.yml"), ("event", "pull_request"),
                           ("status", "in_progress"), ("conclusion", "failure")):
            with self.subTest(key=key):
                original = self.run[key]
                self.run[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
                self.run[key] = original

    def test_partial_dirty_debug_or_other_revision_receipt_is_rejected(self):
        for key, value in (("revision", "b" * 40), ("complete", False), ("dirty", True),
                           ("configuration", "Debug"), ("optimization", "-Onone")):
            with self.subTest(key=key):
                original = self.receipt[key]
                self.receipt[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
                self.receipt[key] = original

    def test_missing_or_failed_stage_is_rejected(self):
        original = copy.deepcopy(self.receipt["steps"])
        self.receipt["steps"].pop()
        with self.assertRaises(ValueError):
            self.verify()
        self.receipt["steps"] = original
        self.receipt["steps"][0]["exitCode"] = 1
        with self.assertRaises(ValueError):
            self.verify()

    def test_source_change_is_rejected(self):
        self.source.write_text("let version = 3\n")
        with self.assertRaisesRegex(ValueError, "Source changed"):
            self.verify()

    def test_executable_mode_change_is_rejected(self):
        self.source.chmod(0o755)
        with self.assertRaisesRegex(ValueError, "Executable mode"):
            self.verify()

    def test_added_deleted_or_missing_inventory_is_rejected(self):
        for inputs in (set(), {"Sources/New.swift"}, self.inputs | {"Sources/New.swift"}):
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                gate.verify_receipt(self.root, self.revision, self.run, self.receipt,
                                    self.summary, self.inventory, inputs)
        self.source.unlink()
        with self.assertRaisesRegex(ValueError, "Invalid tested input"):
            self.verify()

    def test_symlink_outside_checkout_is_rejected(self):
        external = self.root.parent / (self.root.name + "-external.swift")
        external.write_bytes(self.source.read_bytes())
        self.addCleanup(external.unlink)
        self.source.unlink()
        self.source.symlink_to(external)
        with self.assertRaisesRegex(ValueError, "Invalid tested input"):
            self.verify()

    def test_required_suite_cannot_be_missing_failed_or_skipped(self):
        cases = self.inventory["testNodes"][0]["children"]
        for status in ("Failed", "Skipped"):
            cases[0]["result"] = status
            with self.assertRaises(ValueError):
                self.verify()
        cases.pop(0)
        self.summary["totalTestCount"] -= 1
        with self.assertRaises(ValueError):
            self.verify()

    def test_only_documented_optional_network_cases_may_skip(self):
        cases = self.inventory["testNodes"][0]["children"]
        for name in gate.OPTIONAL_TESTS:
            cases.append({"nodeType": "Test Case", "nodeIdentifier": name, "result": "Skipped"})
        self.summary["totalTestCount"] = len(cases)
        self.assertTrue(self.verify()["verified"])
        cases[-1]["nodeIdentifier"] = "OtherTests/testUnexpectedSkip()"
        with self.assertRaises(ValueError):
            self.verify()

    def test_xcode_summary_must_match_execution(self):
        self.summary["totalTestCount"] += 1
        with self.assertRaises(ValueError):
            self.verify()
        self.summary["totalTestCount"] -= 1
        self.summary["failedTests"] = 1
        with self.assertRaises(ValueError):
            self.verify()

    def test_inventory_includes_new_source_but_excludes_ignored_private_reports(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / ".gitignore").write_text("/docs/quality/\n__pycache__/\n")
        private = self.root / "docs/quality/private.md"
        private.parent.mkdir(parents=True)
        private.write_text("local-only")
        subprocess.run(["git", "add", "Sources", ".gitignore"], cwd=self.root, check=True)
        script = self.root / "scripts/new.py"
        script.parent.mkdir()
        script.write_text("print('new')")
        self.assertEqual(gate.source_inputs(self.root), {"Sources/App.swift", "scripts/new.py"})
        ci_spec = importlib.util.spec_from_file_location("ci", ROOT / "scripts/ci.py")
        ci = importlib.util.module_from_spec(ci_spec)
        ci_spec.loader.exec_module(ci)
        self.assertEqual(set(ci.input_hashes(self.root)), gate.source_inputs(self.root))

    def test_pipeline_tests_are_required_when_present_in_release_source(self):
        self.inputs.add("Tests/Pipeline/test_release_gate.py")
        with self.assertRaisesRegex(ValueError, "required CI stage"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
