from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'vps2012' / 'Katarina-Vps2012.ps1'
LAUNCHER = ROOT / 'VPS_KATARINA_SETUP.bat'
CONTROL = ROOT / 'vps_bridge' / 'control.json'

class Vps2012BridgeStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = SCRIPT.read_text(encoding='utf-8')
        cls.launcher = LAUNCHER.read_text(encoding='utf-8')
        cls.control = CONTROL.read_text(encoding='utf-8')

    def test_launcher_targets_setup_mode(self):
        self.assertIn('Katarina-Vps2012.ps1', self.launcher)
        self.assertIn('-Mode Setup', self.launcher)

    def test_bridge_uses_control_and_report_branches(self):
        self.assertIn('vps-control', self.script)
        self.assertIn('vps-reports', self.script)
        self.assertIn('refs/remotes/origin/', self.script)

    def test_bridge_never_pushes_main(self):
        lowered = self.script.lower()
        self.assertNotIn('head:main', lowered)
        self.assertNotIn('head:refs/heads/main', lowered)

    def test_reports_are_sparse(self):
        self.assertIn('FAIL_OR_FINAL', self.script)
        self.assertNotIn('heartbeat', self.script.lower())

    def test_local_diff_is_reported(self):
        self.assertIn('latest.diff', self.script)
        self.assertIn('origin/main', self.script)

    def test_patch_is_checked_before_apply(self):
        self.assertIn('git apply --check failed', self.script)
        self.assertIn('APPLY_PATCH_AND_BUILD', self.script)

    def test_live_authority_is_never_granted(self):
        lowered = self.script.lower()
        self.assertIn('live_risk_ready', lowered)
        self.assertIn('live_execution_enabled', lowered)
        self.assertNotIn('live_risk_ready=$true', lowered)
        self.assertNotIn('live_execution_enabled=$true', lowered)

    def test_handshake_does_not_shadow_powershell_args(self):
        handshake = (ROOT / 'scripts' / 'vps2012' / 'Test-KatarinaVpsBridge.ps1').read_text(encoding='utf-8')
        self.assertNotIn('[string[]]$Args', handshake)
        self.assertNotIn('@Args 2>&1', handshake)
        self.assertIn('[string[]]$GitArgs', handshake)
        self.assertIn('@GitArgs 2>&1', handshake)



    def test_managed_python_bootstrap_is_clean(self):
        self.assertEqual(self.script.count('function Bootstrap-KatarinaPython2012'), 1)
        self.assertEqual(self.script.count('function Sanitize-Text {'), 1)
        self.assertEqual(self.script.count('function Ensure-LocalConfig {'), 1)
        self.assertEqual(self.script.count('function Setup-Katarina {'), 1)
        self.assertEqual(self.script.count('switch($Mode){'), 1)
        self.assertIn('python-3.8.10-embed-amd64.zip', self.script)
        self.assertIn('bootstrap.pypa.io/pip/3.8/get-pip.py', self.script)
        self.assertIn('python38._pth', self.script)
        self.assertIn('requirements-vps2012.txt', self.script)
        self.assertNotIn('python-3.12.10-amd64.exe', self.script)

    def test_bridge_starts_before_python_bootstrap(self):
        setup = self.script.split('function Setup-Katarina {', 1)[1].split('function Stop-Bridge {', 1)[0]
        self.assertLess(setup.index('Start-BridgeBackground'), setup.index('Bootstrap-KatarinaPython2012'))

    def test_initial_control_is_idle(self):
        self.assertIn('"sequence": 0', self.control)
        self.assertIn('"action": "IDLE"', self.control)

if __name__ == '__main__':
    unittest.main()
