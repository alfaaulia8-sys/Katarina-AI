"""Private provenance tests: no synthetic source may become live trading proof."""
from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.research.audit_private_alpha_holdout import run

REPO = Path(__file__).resolve().parents[3]
UTC = timezone.utc
START = "2026-10-13T00:00:00+00:00"
END = "2027-04-30T23:59:59+00:00"
FROZEN = "2026-10-12T00:00:00+00:00"


def fixture(root: Path):
    src = root / "private_tick_data_mock.bin"
    src.write_bytes(b"NOT_REAL_MARKET_DATA")
    h = sha256(src.read_bytes()).hexdigest()
    manifest = {
        "schema_version": 1,
        "symbol": "XAUUSD.vx",
        "market_state": "TREND_UP", "side": "BUY",
        "playbook": "TREND_PULLBACK",
        "origin": "REAL_BROKER_BID_ASK_WITH_DOCUMENTED_COSTS",
        "frozen_at_utc": FROZEN,
        "holdout_start_utc": START,
        "holdout_end_utc": END,
        "raw_source_sha256": h,
        "attestation": {
            "holdout_independence_verified": False,
            "native_broker_costs_verified": False,
            "broker_contract_verified": False,
            "source_is_synthetic": True,
        },
    }
    m = root / "private_manifest.json"
    m.write_text(json.dumps(manifest), encoding="utf-8")
    outcomes = root / "outcomes.jsonl"
    outcomes.write_text("", encoding="utf-8")
    return src, m, outcomes, manifest


class PrivateHoldoutAuditTests(unittest.TestCase):
    def audit(self, src, manifest, outcomes, **kwargs):
        return run(REPO, manifest_path=manifest, raw_source_path=src,
                   outcomes_path=outcomes, **kwargs)

    def test_no_inputs_fail_closed(self):
        out = run(REPO, manifest_path=None, raw_source_path=None, outcomes_path=None)
        self.assertEqual(out["result"], "BLOCKED_PRIVATE_INPUT_FILES_NOT_PROVIDED")
        self.assertFalse(out["live_execution_authorized"])

    def test_hash_modified_source_rejected(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            src.write_bytes(b"CHANGED_AFTER_HASH")
            out = self.audit(src, m, o)
            self.assertEqual(out["result"], "BLOCKED_SOURCE_FILE_HASH_MISMATCH")

    def test_unverified_market_costs_rejected(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            out = self.audit(src, m, o)
            self.assertEqual(out["result"], "BLOCKED_ATTESTATIONS_MISSING_OR_UNVERIFIED")

    def test_synthetic_source_cannot_be_attested_as_real(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            for key in ("holdout_independence_verified",
                        "native_broker_costs_verified",
                        "broker_contract_verified"):
                manifest["attestation"][key] = True
            m.write_text(json.dumps(manifest), "utf-8")
            self.assertEqual(self.audit(src, m, o)["result"],
                             "BLOCKED_SYNTHETIC_EVIDENCE_DISALLOWED")

    def test_new_future_period_cannot_pass_early(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            manifest["attestation"] = {
                "holdout_independence_verified": True,
                "native_broker_costs_verified": True,
                "broker_contract_verified": True,
                "source_is_synthetic": False,  # Fixture tests chronology ONLY.
            }
            m.write_text(json.dumps(manifest), "utf-8")
            result = self.audit(src, m, o,
                                audit_at=datetime(2026, 10, 11, tzinfo=UTC))
            self.assertEqual(result["result"], "BLOCKED_HOLDOUT_NOT_FINISHED")
            self.assertFalse(result["external_attestation_independently_audited"])
            self.assertFalse(result["live_execution_authorized"])

    def test_unknown_pair_and_wrong_side_blocked(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            manifest["symbol"] = "UNLISTED_CFD"
            m.write_text(json.dumps(manifest), "utf-8")
            self.assertEqual(self.audit(src, m, o)["result"], "BLOCKED_UNREGISTERED_MARKET")
            manifest["symbol"] = "XAUUSD.vx"
            manifest["side"] = "SELL"
            m.write_text(json.dumps(manifest), "utf-8")
            self.assertEqual(self.audit(src, m, o)["result"],
                             "BLOCKED_UNREGISTERED_DIRECTION_OR_PLAYBOOK")

    def test_wrong_freeze_boundary_rejected(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            manifest["holdout_start_utc"] = "2026-10-12T00:00:00+00:00"
            m.write_text(json.dumps(manifest), "utf-8")
            self.assertEqual(self.audit(src, m, o)["result"],
                             "BLOCKED_FROZEN_BOUNDARY_MISMATCH")

    def test_raw_account_paths_not_exposed(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            out = self.audit(src, m, o)
            rendered = json.dumps(out)
            self.assertNotIn(str(src), rendered)
            self.assertNotIn(str(m), rendered)
            self.assertNotIn(str(o), rendered)
            self.assertNotIn("private_tick_data_mock", rendered)

    def test_malformed_json_does_not_crash(self):
        with TemporaryDirectory() as tmp:
            src, m, o, manifest = fixture(Path(tmp))
            m.write_text("{invalid", encoding="utf-8")
            out = self.audit(src, m, o)
            self.assertEqual(out["result"], "BLOCKED_MALFORMED_PRIVATE_EVIDENCE")


if __name__ == "__main__":
    unittest.main()
