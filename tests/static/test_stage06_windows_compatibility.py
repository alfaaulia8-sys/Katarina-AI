import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "config" / "windows_compatibility_stage06.json"
COMPILE = ROOT / "scripts" / "mt5" / "compile_stage06.ps1"
HOST_CHECK = ROOT / "scripts" / "mt5" / "check_stage06_host.ps1"
VERIFY = ROOT / "scripts" / "mt5" / "verify_stage06_modern_windows.ps1"


class Stage06WindowsCompatibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(CONFIG.read_text(encoding="utf-8"))
        cls.compile_script = COMPILE.read_text(encoding="utf-8")
        cls.host_script = HOST_CHECK.read_text(encoding="utf-8")
        cls.verify_script = VERIFY.read_text(encoding="utf-8")

    def test_modern_preferred_hosts_are_x64(self):
        self.assertEqual(self.config["architecture"], "x64")
        self.assertIn(
            "WINDOWS_SERVER_2022_X64",
            self.config["policy"]["preferred"],
        )
        self.assertIn(
            "WINDOWS_11_X64",
            self.config["policy"]["preferred"],
        )

    def test_server_2012_r2_is_explicitly_deferred(self):
        deferred = {
            item["platform"]
            for item in self.config["policy"]["deferred"]
        }
        self.assertIn("WINDOWS_SERVER_2012_R2_X64", deferred)
        self.assertFalse(
            self.config["stage06_freeze_policy"][
                "windows_server_2012_r2_required"
            ]
        )

    def test_32_bit_windows_is_not_stage06_target(self):
        self.assertIn(
            "WINDOWS_X86_32_BIT",
            self.config["policy"]["unsupported_for_stage06_validation"],
        )

    def test_compile_proof_is_strict(self):
        policy = self.config["stage06_freeze_policy"]
        self.assertTrue(policy["zero_errors_required"])
        self.assertTrue(policy["zero_warnings_required"])
        self.assertTrue(policy["ex5_artifact_required"])

    def test_compile_script_parses_utf16le_metaeditor_log(self):
        self.assertIn(
            "[System.Text.Encoding]::Unicode",
            self.compile_script,
        )
        self.assertIn(
            "errors?\\s*,\\s*(?<warnings>",
            self.compile_script,
        )

    def test_compile_script_removes_stale_ex5_and_hashes_artifacts(self):
        self.assertIn(
            "Remove-Item $path -ErrorAction SilentlyContinue",
            self.compile_script,
        )
        self.assertIn("Get-FileHash", self.compile_script)
        self.assertIn("artifact_sha256", self.compile_script)

    def test_compile_script_uses_explicit_mql_include_root(self):
        self.assertIn('/inc:', self.compile_script)

    def test_compile_script_writes_machine_readable_evidence(self):
        self.assertIn(
            "stage06_compile_evidence.json",
            self.compile_script,
        )
        self.assertIn(
            "PASS_COMPILE_PROOF",
            self.compile_script,
        )

    def test_host_check_classifies_modern_and_deferred_windows(self):
        for token in (
            "Windows Server 2022",
            "Windows Server 2019",
            "Windows Server 2016",
            "Windows 11",
            "Windows 10",
            "Windows Server 2012 R2",
            "PREFERRED",
            "COMPATIBILITY",
            "DEFERRED",
        ):
            self.assertIn(token, self.host_script)

    def test_one_command_verifier_chains_host_static_and_compile_proof(self):
        self.assertIn("check_stage06_host.ps1", self.verify_script)
        self.assertIn(
            "tests.static.test_stage06_mt5_bridge",
            self.verify_script,
        )
        self.assertIn(
            "tests.static.test_stage06_windows_compatibility",
            self.verify_script,
        )
        self.assertIn("compile_stage06.ps1", self.verify_script)


if __name__ == "__main__":
    unittest.main()
