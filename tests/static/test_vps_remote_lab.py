from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "config" / "vps_remote_lab_policy.json"
RUNNER = ROOT / "scripts" / "vps" / "Invoke-KatarinaRemoteTask.ps1"
AGENT = ROOT / "scripts" / "vps" / "legacy" / "KatarinaVpsAgent.ps1"
INSTALLER = ROOT / "scripts" / "vps" / "legacy" / "Install-KatarinaVpsAgent.ps1"
WORKFLOW = ROOT / ".github" / "workflows" / "katarina-vps-lab.yml"


class VpsRemoteLabPolicyTests(unittest.TestCase):
    def test_policy_is_fail_closed_and_no_inbound_port(self) -> None:
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        security = policy["security_model"]
        self.assertFalse(security["inbound_ports_required"])
        self.assertTrue(security["outbound_https_only"])
        self.assertFalse(security["arbitrary_shell_from_request_allowed"])
        self.assertTrue(security["allowed_tasks_only"])
        self.assertFalse(security["production_broker_mutation_allowed"])

    def test_legacy_and_actions_queues_are_separate(self) -> None:
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        dirs = policy["request"]["directories"]
        self.assertEqual(dirs["legacy"], "ops/vps/requests/legacy")
        self.assertEqual(dirs["github_actions"], "ops/vps/requests/actions")
        self.assertNotEqual(dirs["legacy"], dirs["github_actions"])

    def test_windows_2012_does_not_claim_actions_runner_support(self) -> None:
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        legacy = policy["windows_server_2012_r2"]
        self.assertFalse(legacy["github_actions_self_hosted_runner_supported"])
        self.assertEqual(legacy["bridge"], "KATARINA_LEGACY_VPS_AGENT")

    def test_task_runner_has_fixed_allowlist(self) -> None:
        text = RUNNER.read_text(encoding="utf-8")
        for task in (
            "HOST_INVENTORY",
            "REPO_STATIC_TESTS",
            "STAGE06_HOST_CHECK",
            "STAGE06_COMPILE_PROOF",
            "STAGE06_CLEARANCE",
            "STAGE07_PYTHON_TESTS",
            "COLLECT_MT5_LOGS",
        ):
            self.assertIn(f'"{task}"', text)
        self.assertIn("Task is not allowlisted", text)

    def test_task_runner_rejects_wrong_target_and_expiry(self) -> None:
        text = RUNNER.read_text(encoding="utf-8")
        self.assertIn("target_agent", text)
        self.assertIn("does not match", text)
        self.assertIn("Request expired", text)

    def test_request_cannot_supply_arbitrary_shell(self) -> None:
        text = RUNNER.read_text(encoding="utf-8").lower()
        self.assertNotIn("invoke-expression", text)
        self.assertNotIn("iex ", text)
        self.assertNotIn("request.command", text)
        self.assertNotIn("request.shell", text)

    def test_legacy_agent_uses_outbound_github_api_and_legacy_queue(self) -> None:
        text = AGENT.read_text(encoding="utf-8")
        self.assertIn("https://api.github.com", text)
        self.assertIn('ops/vps/requests/legacy', text)
        self.assertIn("Start-Sleep", text)
        self.assertNotIn("New-PSSession", text)
        self.assertNotIn("Enter-PSSession", text)

    def test_legacy_token_is_dpapi_protected(self) -> None:
        agent = AGENT.read_text(encoding="utf-8")
        installer = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("ProtectedData", agent)
        self.assertIn("DataProtectionScope]::LocalMachine", agent)
        self.assertIn("ProtectedData", installer)
        self.assertIn("DataProtectionScope]::LocalMachine", installer)
        self.assertIn("Read-Host", installer)
        self.assertIn("-AsSecureString", installer)

    def test_modern_workflow_targets_self_hosted_windows_and_actions_queue(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("runs-on: [self-hosted, windows, x64, katarina-vps]", text)
        self.assertIn("ops/vps/requests/actions/*.json", text)
        self.assertNotIn('"ops/vps/requests/legacy/*.json"', text)
        self.assertIn("actions/upload-artifact@v4", text)

    def test_results_are_text_only_by_policy(self) -> None:
        policy = json.loads(POLICY.read_text(encoding="utf-8"))
        result = policy["result"]
        self.assertFalse(result["binary_upload_to_repo"])
        self.assertEqual(
            set(result["allowed_extensions"]),
            {".json", ".txt", ".log", ".csv", ".md"},
        )


if __name__ == "__main__":
    unittest.main()
