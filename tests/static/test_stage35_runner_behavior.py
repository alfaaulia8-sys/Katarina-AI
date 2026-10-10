"""Exercise the real PowerShell runner with a simulated terminal, never MT5."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')


@unittest.skipUnless(POWERSHELL, 'PowerShell required; Windows CI executes these cases')
class TesterRunnerBehaviorTests(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            result = subprocess.run([
                POWERSHELL, '-NoProfile', '-File',
                str(ROOT / 'tests/fixtures/stage35/mock_terminal.ps1'),
                '-Runner', str(ROOT / 'scripts/stage35/Run-KatarinaStage35Tester.ps1'),
                '-Work', temp, '-Mode', mode,
            ], capture_output=True, text=True, timeout=30)
            files = list(work.glob('evidence with spaces/*/evidence/stage35-tester-evidence.json'))
            evidence = json.loads(files[0].read_text(encoding='utf-8-sig')) if files else None
            return result, evidence

    def test_success_preserves_bound_report_and_disables_live(self):
        result, evidence = self.run_case('valid')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(evidence['result'], 'PASS_STAGE35_TESTER_INFRASTRUCTURE')
        self.assertFalse(evidence['live_execution_enabled'])
        self.assertFalse(evidence['strategy_validated'])
        for key in ('expert_sha256', 'runner_sha256', 'config_sha256', 'report_sha256'):
            self.assertRegex(evidence[key], r'^[0-9A-Fa-f]{64}$')

    def test_invalid_results_never_pass(self):
        for mode in ('missing', 'unrelated', 'empty', 'stale', 'nonzero', 'timeout'):
            with self.subTest(mode=mode):
                result, evidence = self.run_case(mode)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(evidence['result'], 'FAIL_STAGE35_TESTER_INFRASTRUCTURE')
                self.assertFalse(evidence['live_risk_ready'])

    def test_existing_installation_uses_bound_data_directory(self):
        result, evidence = self.run_case('existing')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(evidence['result'], 'PASS_STAGE35_TESTER_INFRASTRUCTURE')
        self.assertFalse(evidence['portable'])
        self.assertTrue(evidence['terminal_data_path'].endswith('existing data'))
        self.assertRegex(evidence['parameters_sha256'], r'^[0-9A-Fa-f]{64}$')

    def test_unsafe_launch_rejected_before_evidence(self):
        for mode in ('running', 'injection', 'dates', 'traversal', 'nonportable', 'wrong_origin', 'both_modes'):
            with self.subTest(mode=mode):
                result, evidence = self.run_case(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(evidence)
