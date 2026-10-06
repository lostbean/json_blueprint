"""The native warning gate rejects a compiler warning without rejecting valid code."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class NativeWarningTests(unittest.TestCase):
    def test_warning_rejected_with_positive_control(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "warning_probe.erl"
            for argument, accepted in (("_Value", True), ("Unused", False)):
                source.write_text(
                    "-module(warning_probe).\n-export([value/1]).\n"
                    f"value({argument}) -> ok.\n"
                )
                result = subprocess.run(
                    ["sh", str(ROOT / "scripts/check-native.sh"), str(source)],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(
                    result.returncode == 0, accepted, result.stdout + result.stderr
                )
                if not accepted:
                    self.assertIn("unused", result.stdout + result.stderr)
