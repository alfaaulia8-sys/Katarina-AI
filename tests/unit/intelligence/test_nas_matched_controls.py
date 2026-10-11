"""Independent NAS timestamp matching, fee stress and source integrity tests."""
import sys,unittest
from datetime import datetime,timezone
from pathlib import Path
SCRIPTS=Path(__file__).resolve().parents[3]/"scripts"/"research"
sys.path.insert(0,str(SCRIPTS))
from nas_matched_controls import pool,atr_at,bootstrap_pair,ATR_TOLERANCE
from audit_nas_matched_controls import audit

class MatchedNAS100Tests(unittest.TestCase):
    def test_session_time_match_uses_only_same_date_and_earlier_bar(self):
        start=datetime(2026,9,23,11,0,tzinfo=timezone.utc).timestamp()
        rows=[]
        for i in range(600):
            rows.append(dict(time=start+60*i,open=100,high=100.3,
                   low=99.7,close=100.1,tick_volume=100))
        anchor=datetime(2026,9,23,16,0,tzinfo=timezone.utc).timestamp()
        choices=pool(rows,anchor,.6)
        self.assertGreater(len(choices),10)
        self.assertTrue(all(45*60<=abs(t-anchor)<=120*60 for t,a in choices))
        self.assertTrue(all(datetime.fromtimestamp(t,timezone.utc).date()==
            datetime.fromtimestamp(anchor,timezone.utc).date() for t,a in choices))
        self.assertTrue(all(abs(a/.6-1)<=ATR_TOLERANCE for t,a in choices))

    def test_ATR_ignores_future_price_bar(self):
        rows=[dict(time=i*60,open=100,high=101,low=99,close=100)
              for i in range(30)]
        reference=atr_at(rows,20)
        rows[25]["high"]=10000
        self.assertEqual(reference,atr_at(rows,20))

    def test_day_resample_seed_reproduces(self):
        values=[dict(signal_utc=f"2026-09-{x:02d}T14:00:00+00:00",lift_R=v)
                for x,v in ((20,.5),(21,-.1),(22,.3),(23,-.2))]
        self.assertEqual(bootstrap_pair(values),bootstrap_pair(values))

    def test_tampered_report_live_risk_fails_closed(self):
        doc=dict(kind="NAS100_matched_timestamp_random_control_v1",
                 live_execution_enabled=True,model_promotion_allowed=False,
                 trade_decision="NO_TRADE",fixed_seed=2026101107,
                 evidence_sources=[],matched_entries=0,matched_pairs=[])
        with self.assertRaisesRegex(ValueError,"study_attempted_promotion"):
            audit(doc)

if __name__=="__main__":
    unittest.main()
