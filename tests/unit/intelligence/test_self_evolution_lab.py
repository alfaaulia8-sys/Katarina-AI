"""Deterministic, no-LLM/MT5, retrospective held-out shadow evolution tests."""
from datetime import datetime, timedelta, timezone
import sqlite3
import unittest

from katarina.intelligence.self_evolution_lab import (
    evaluate_shadow_self_evolution, VERSION,
)

START = datetime(2026, 7, 1, tzinfo=timezone.utc)
AT = START + timedelta(days=40)


def mkdb():
    db = sqlite3.connect(":memory:")
    db.execute("""CREATE TABLE prospective_shadow(
        id INTEGER PRIMARY KEY, symbol TEXT, method TEXT, side TEXT,
        regime TEXT, observed_at REAL, exit_at REAL, state TEXT,
        virtual_net_r REAL, evidence_score REAL, official_news_verified INTEGER)""")
    return db


def sample(db, days=30, high=2.0, low=-1.0, pending=0):
    identity=0
    for day in range(days):
        for j in range(8):
            identity+=1
            when=(START + timedelta(days=day,hours=j+1)).timestamp()
            high_score=j%2==0
            value=high if high_score else low
            db.execute("""INSERT INTO prospective_shadow VALUES
                    (?,?,?,?,?,?,?,?,?,?,?)""",(
                identity,"XAUUSD.vx","SWEEP","SELL","TREND_DOWN",
                when,when+3600,"VIRTUAL_QUOTED",
                value,.85 if high_score else .64,1))
    for j in range(pending):
        identity+=1
        when=(START+timedelta(days=days,hours=j)).timestamp()
        db.execute("INSERT INTO prospective_shadow VALUES(?,?,?,?,?,?,?,?,?,?,?)",(
            identity,"XAUUSD.vx","SWEEP","SELL","TREND_DOWN",
            when,None,"OPEN",None,.85,0))
    db.commit()


class SelfEvolutionLabTests(unittest.TestCase):
    def test_no_table_no_signal(self):
        x=evaluate_shadow_self_evolution(sqlite3.connect(":memory:"),as_of_utc=AT)
        self.assertEqual(x["data_integrity"],"INVALID")
        self.assertEqual(x["decision"],"WAIT_FOR_VERIFIED_EVIDENCE")
        self.assertFalse(x["promotion_allowed"])

    def test_negative_series_no_promotion(self):
        db=mkdb()
        sample(db,high=-.3,low=-.9)
        r=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(r["cohorts"][0]["status"],"UNSTABLE_OR_NEGATIVE_QUOTE_EDGE")
        self.assertEqual(r["decision"],"WAIT_FOR_VERIFIED_EVIDENCE")

    def test_witnesses_real_train_holdout_learning_not_llm(self):
        db=mkdb();sample(db)
        r=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(r["data_integrity"],"VALID")
        self.assertEqual(r["cohorts"][0]["proposed_min_evidence_score"],.70)
        self.assertEqual(r["cohorts"][0]["status"],"RESEARCH_CANDIDATE_REVIEW_REQUIRED")
        self.assertEqual(r["cohorts"][0]["holdout"]["observations"],36)
        self.assertGreater(r["cohorts"][0]["holdout"]["daily_cluster_lower_r"],0)
        self.assertEqual(r["decision"],"RESEARCH_PROPOSAL_ONLY")
        self.assertEqual(r["external_models_invoked"],0)
        self.assertFalse(r["promotion_allowed"])
        self.assertFalse(r["order_submission_authorized"])
        self.assertFalse(r["self_code_mutation_authorized"])
        self.assertEqual(r["live_risk_authorized_fraction"],0)
        self.assertEqual([v["pass"] for v in r["reviewers"]],
                         [True,True,False,False])
        self.assertEqual(r["version"],VERSION)

    def test_determinism_and_freshness_fingerprint(self):
        db=mkdb();sample(db)
        a=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        b=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(a,b)
        when=(START + timedelta(days=31)).timestamp()
        db.execute("INSERT INTO prospective_shadow VALUES(?,?,?,?,?,?,?,?,?,?,?)",(
            777,"XAUUSD.vx","SWEEP","SELL","TREND_DOWN",when,
            when+3600,"VIRTUAL_QUOTED",-.5,.9,1))
        c=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertNotEqual(a["source_digest_sha256"],c["source_digest_sha256"])
        self.assertNotEqual(a["review_receipt_sha256"],c["review_receipt_sha256"])

    def test_time_leak_blocks(self):
        db=mkdb();sample(db)
        db.execute("UPDATE prospective_shadow SET exit_at=? WHERE id=1",
                   ((AT+timedelta(hours=1)).timestamp(),))
        x=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(x["data_integrity"],"INVALID")
        self.assertFalse(x["promotion_allowed"])

    def test_gap_coverage_blocks_cherrypicking(self):
        db=mkdb();sample(db)
        # Mark 70% quote paths as uncertain without claiming loss or victory
        db.execute("""UPDATE prospective_shadow SET state='UNCERTAIN_GAP',
                   virtual_net_r=NULL WHERE id % 4 != 0""")
        x=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(x["cohorts"][0]["status"],"INSUFFICIENT_EVIDENCE")
        self.assertLess(x["cohorts"][0]["coverage"],.8)

    def test_unknown_or_corrupt_record_fails_closed(self):
        db=mkdb();sample(db)
        db.execute("UPDATE prospective_shadow SET evidence_score=2.0 WHERE id=1")
        self.assertEqual(evaluate_shadow_self_evolution(
            db,as_of_utc=AT)["data_integrity"],"INVALID")

    def test_pending_never_treated_as_loss_or_win(self):
        db=mkdb();sample(db,days=5,pending=2)
        x=evaluate_shadow_self_evolution(db,as_of_utc=AT)
        self.assertEqual(x["cohorts"][0]["pending"],2)
        self.assertEqual(x["cohorts"][0]["status"],"INSUFFICIENT_EVIDENCE")

    def test_asof_must_be_aware(self):
        with self.assertRaises(ValueError):
            evaluate_shadow_self_evolution(mkdb(),as_of_utc=datetime(2026,10,13))

if __name__=="__main__":
    unittest.main()

[executed on device: WIN-4TTT19K3CL8 (06bb71fa-caee-4271-a9ca-1e9cb7db4c2a)]
