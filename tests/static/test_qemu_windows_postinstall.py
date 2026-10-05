from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "vps" / "Configure-KatarinaQemuWindows.ps1"


class QemuWindowsPostInstallStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT.read_text(encoding="utf-8")
        cls.lower = cls.text.lower()

    def test_rdp_is_enabled_without_disabling_firewall(self):
        self.assertIn("fDenyTSConnections", self.text)
        self.assertIn('Enable-NetFirewallRule -DisplayGroup "Remote Desktop"', self.text)
        self.assertNotIn("Set-NetFirewallProfile -Enabled False", self.text)

    def test_winrm_and_awake_mode_are_configured(self):
        self.assertIn("Enable-PSRemoting", self.text)
        self.assertIn("standby-timeout-ac 0", self.text)

    def test_tools_bootstrap_is_discovered_by_media_content(self):
        self.assertIn("bootstrap-katarina.ps1", self.text)
        self.assertIn("Get-Volume", self.text)

    def test_postinstall_never_claims_live_readiness(self):
        self.assertIn("live_risk_ready = $false", self.text)
        self.assertIn("live_execution_enabled = $false", self.text)

    def test_no_embedded_password_or_security_disable(self):
        forbidden = (
            "katarina@2026",
            "set-mppreference -disablerealtimemonitoring",
            "enablelua",
            "password =",
        )
        for marker in forbidden:
            with self.subTest(marker=marker):
                self.assertNotIn(marker, self.lower)


if __name__ == "__main__":
    unittest.main()
