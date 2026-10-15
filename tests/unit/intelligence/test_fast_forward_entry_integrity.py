import sqlite3
import unittest
from datetime import datetime, timezone

from scripts.ai.audit_forward_shadow_entry_integrity import assess_entry, scorecard

NOW = datetime(2026, 10, 15, 4, 0, tzinfo=timezone.utc)


def frozen(i=1, bid=100.0, ask=100.2):
    return dict(id=i, symbol="XAUUSD.vx", side="BUY",
                tick_at=NOW.timestamp() - 120, bid=bid, ask=ask,
                state="VIRTUAL_QUOTED")


def tick(time_msc, bid, ask):
    return dict(time_msc=time_msc, bid=bid, ask=ask)


class ForwardEntryIntegrityTests(unittest.TestCase):
    def test_matching_pre_entry_quote(self):
        t = frozen()["tick_at"]
        result = assess_entry(frozen(), [tick(int((t-1)*1000), 100., 100.2)],
                              tick_size=.01)
        self.assertEqual(result["status"], "MATCHED_ARCHIVED_ENTRY")

    def test_reject_mismatched_archive(self):
        t = frozen()["tick_at"]
        result = assess_entry(frozen(), [tick(int((t-.5)*1000), 102., 102.2)],
                              tick_size=.01)
        self.assertEqual(result["status"], "MISMATCHED_ARCHIVED_ENTRY")

    def test_future_history_cannot_revalidate_frozen_entry(self):
        t = frozen()["tick_at"]
        result = assess_entry(frozen(), [tick(int((t+1)*1000), 100., 100.2)])
        self.assertEqual(result["status"], "UNVERIFIED_MISSING_ENTRY_TICK")

    def test_stale_quotes_and_bad_ask_rejected(self):
        t = frozen()["tick_at"]
        quotes = [tick(int((t-10)*1000), 100., 100.2),
                  tick(int((t-1)*1000), 101., 100.)]
        self.assertEqual(assess_entry(frozen(), quotes)["status"],
                         "UNVERIFIED_MISSING_ENTRY_TICK")

    def test_legacy_samples_are_never_promoted(self):
        db = sqlite3.connect(":memory:")
        try:
            db.execute("""CREATE TABLE prospective_shadow(
                       id INTEGER,symbol TEXT,side TEXT,tick_at REAL,bid REAL,
                       ask REAL,state TEXT,virtual_net_r REAL,
                       official_news_verified INTEGER,observed_at REAL)""")
            for id, bid, state, net in [
                (1, 100., "VIRTUAL_QUOTED", -.8),
                (2, 110., "VIRTUAL_QUOTED", 2.),
                (3, 100., "UNCERTAIN_GAP", None),
            ]:
                db.execute("INSERT INTO prospective_shadow VALUES(?,?,?,?,?,?,?,?,?,?)",
                           (id, "XAUUSD.vx", "BUY", NOW.timestamp()-120,
                            bid, bid+.2, state, net, 0, NOW.timestamp()-130))
            def history(symbol, stamp):
                return [tick(int((stamp-1)*1000), 100., 100.2)], .01
            result = scorecard(db, history, as_of_utc=NOW)
            self.assertEqual(result["registered_shadow_events"], 3)
            self.assertEqual(result["entry_audit_counts"]["MATCHED_ARCHIVED_ENTRY"], 2)
            self.assertEqual(result["entry_audit_counts"]["MISMATCHED_ARCHIVED_ENTRY"], 1)
            self.assertEqual(result["previously_quoted_with_matching_entry"], 1)
            self.assertEqual(result["previously_quoted_matching_entry_negative"], 1)
            self.assertFalse(result["can_validate_profitability"])
            self.assertFalse(result["may_activate_live_trading"])
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
