"""Serial Management acceptance: verified engineering, no broker/trading authority."""
import unittest

from scripts.ai.management_acceptance import run_acceptance


class ManagementAcceptanceTests(unittest.TestCase):
    def test_serial_handoff_all_11_specialists_no_trading(self):
        result = run_acceptance("9" * 40)
        self.assertEqual(result["status"], "MANAGEMENT_ENGINEERING_ACCEPTANCE_PASS")
        self.assertEqual(result["specialists_verified"], 11)
        self.assertEqual(result["work_items_verified"], 11)
        self.assertTrue(result["qa_passed"])
        self.assertEqual(result["release_status"], "BLOCKED")
        self.assertFalse(result["autonomous_code_writes_verified"])
        self.assertFalse(result["external_ai_workers_verified"])
        self.assertEqual(result["orders_sent"], 0)

    def test_invalid_identity_rejected_before_any_work(self):
        with self.assertRaises(ValueError):
            run_acceptance("main")


if __name__ == "__main__":
    unittest.main()
