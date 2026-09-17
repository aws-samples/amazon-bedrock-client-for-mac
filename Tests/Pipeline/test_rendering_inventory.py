import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("rendering_inventory", ROOT / "scripts/verify-rendering-results.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class RenderingInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.tests = self.root / "Tests/BedrockTests"
        self.tests.mkdir(parents=True)
        self.inventory = {"testNodes": [{"nodeType": "Test Suite", "children": []}]}
        for suite in ("MarkdownRenderingTests", "ClipboardRenderingTests"):
            (self.tests / f"{suite}.swift").write_text(
                f"final class {suite}: XCTestCase {{\n func testRegression() {{}}\n}}\n")
            self.inventory["testNodes"][0]["children"].append(
                {"nodeType": "Test Case", "nodeIdentifier": f"{suite}/testRegression()", "result": "Passed"})

    def test_both_suites_must_execute(self):
        self.assertEqual(sum(renderer.verify(self.root, self.inventory).values()), 2)
        self.inventory["testNodes"][0]["children"].pop()
        with self.assertRaises(ValueError):
            renderer.verify(self.root, self.inventory)

    def test_a_new_test_cannot_be_silently_omitted(self):
        with (self.tests / "MarkdownRenderingTests.swift").open("a") as source:
            source.write("func testNewRegression() {}")
        with self.assertRaisesRegex(ValueError, "testNewRegression"):
            renderer.verify(self.root, self.inventory)

    def test_failure_or_skip_blocks_the_rendering_stage(self):
        for status in ("Failed", "Skipped"):
            with self.subTest(status=status):
                self.inventory["testNodes"][0]["children"][0]["result"] = status
                with self.assertRaises(ValueError):
                    renderer.verify(self.root, self.inventory)


if __name__ == "__main__":
    unittest.main()
