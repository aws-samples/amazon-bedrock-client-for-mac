import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ci", ROOT / "scripts/ci.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class StageLimitTests(unittest.TestCase):
    def run_stage(self, code, timeout=3, progress=None):
        with tempfile.TemporaryFile() as log:
            status = ci.run_bounded([sys.executable, "-c", code], cwd=ROOT, env=os.environ.copy(),
                                    stdout=log, timeout=timeout, heartbeat=0.05, progress=progress)
            log.seek(0)
            return status, log.read().decode()

    def test_real_exit_status_and_output_are_preserved(self):
        self.assertEqual(self.run_stage("print('stage result'); raise SystemExit(7)"),
                         (7, "stage result\n"))

    def test_stalled_command_is_bounded_and_reports_progress(self):
        progress = []
        start = time.monotonic()
        status, _ = self.run_stage("import time; time.sleep(60)", timeout=0.2, progress=progress.append)
        self.assertEqual(status, 124)
        self.assertLess(time.monotonic() - start, 3)
        self.assertTrue(progress)

    def test_a_timeout_does_not_leave_a_working_descendant(self):
        with tempfile.TemporaryDirectory() as temporary:
            marker = Path(temporary) / "unexpected"
            child = f"import time,pathlib; time.sleep(0.5); pathlib.Path({str(marker)!r}).touch()"
            parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(60)"
            self.assertEqual(self.run_stage(parent, timeout=0.2)[0], 124)
            time.sleep(0.6)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
