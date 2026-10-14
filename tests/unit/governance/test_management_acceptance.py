"""Serial Management acceptance with real regression evidence and fail-closed tests."""
import subprocess
import unittest
from unittest.mock import patch

from scripts.ai.management_acceptance import run_acceptance, run_required_regressions


class ManagementAcceptanceTests(unittest.TestCase):
    def test_serial_handoff_all_11_specialists_no_trading(self):
        result = run_acceptance("9" * 40)
        self.assertEqual(result["status"], "MANAGEMENT_ENGINEERING_ACCEPTANCE_PASS")
        self.assertEqual(result["specialists_verified"], 11)
        self.assertEqual(result["work_items_verified"], 11)
        self.assertTrue(result["regression_evidence"]["passed"])
        self.assertEqual(result["regression_evidence"]["process_exit_code"], 0)
        self.assertFalse(result["checkout_verified"])
        self.assertTrue(result["qa_passed"])
        self.assertEqual(result["release_status"], "BLOCKED")
        self.assertFalse(result["autonomous_code_writes_verified"])
        self.assertFalse(result["external_ai_workers_verified"])
        self.assertEqual(result["orders_sent"], 0)

    def test_invalid_identity_rejected_before_any_work(self):
        with self.assertRaises(ValueError):
            run_acceptance("main")

    def test_regression_failure_denies_acceptance(self):
        fake = subprocess.CompletedProcess(["python"], 1, "", "TEST FAILED")
        with patch(
            "scripts.ai.management_acceptance.subprocess.run", return_value=fake,
        ):
            with self.assertRaisesRegex(RuntimeError, "management_regression_failed"):
                run_acceptance("9" * 40)

    def test_pinned_checkout_required_in_cli(self):
        fake = subprocess.CompletedProcess(["git"], 0, "0" * 40 + "\n", "")
        with patch(
            "scripts.ai.management_acceptance.subprocess.run", return_value=fake,
        ):
            with self.assertRaisesRegex(ValueError, "checkout_not_pinned_or_clean"):
                run_acceptance("9" * 40, verify_checkout=True)


if __name__ == "__main__":
    unittest.main()
