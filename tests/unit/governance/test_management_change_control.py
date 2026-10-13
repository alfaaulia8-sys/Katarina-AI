"""Management proposals cannot silently edit trading code or bypass Owner."""
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ai.management_change_control import evaluate


def make_proposal(root: Path) -> dict:
    path = "scripts/ai/management_resources.py"
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("ANSWER = 1\n", encoding="utf-8")
    return {
        "schema_version": 1,
        "proposal_id": "MGT-P-001",
        "target_path": path,
        "base_sha256": sha256(target.read_bytes()).hexdigest(),
        "proposed_source": "ANSWER = 2\n",
        "reason": "Test the approval-only change review workflow",
    }


class ManagementChangeReviewTests(unittest.TestCase):
    def test_review_generates_diff_without_modifying_source(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            record = make_proposal(root)
            output = evaluate(root, record)
            self.assertIn("+ANSWER = 2", output["diff_preview"])
            self.assertIn("PENDING_", output["status"])
            self.assertFalse(output["file_modified"])
            self.assertFalse(output["auto_merge"])
            self.assertFalse(output["live_trading_authorized"])
            self.assertEqual((root / record["target_path"]).read_text(), "ANSWER = 1\n")

    def test_trading_or_traversal_target_is_rejected(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp)
            proposal=make_proposal(root)
            for unsafe in ("src/katarina/engines/capital.py", "../secret.py", "C:/trade.py"):
                proposal["target_path"]=unsafe
                with self.assertRaises(ValueError):
                    evaluate(root, proposal)

    def test_stale_proposal_does_not_modify_file(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp)
            proposal=make_proposal(root)
            proposal["base_sha256"]="0"*64
            with self.assertRaisesRegex(ValueError,"stale"):
                evaluate(root, proposal)

    def test_invalid_or_unchanged_source_fails_closed(self):
        with TemporaryDirectory() as tmp:
            root=Path(tmp)
            proposal=make_proposal(root)
            proposal["proposed_source"]="invalid python :("
            with self.assertRaises(SyntaxError):
                evaluate(root, proposal)
            proposal["proposed_source"]="ANSWER = 1\n"
            with self.assertRaises(ValueError):
                evaluate(root, proposal)


if __name__ == "__main__":
    unittest.main()
