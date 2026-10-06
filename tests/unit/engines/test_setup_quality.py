import unittest

from katarina.engines.scalper_entry import EntryMode, EntryProposal, EntrySide
from katarina.engines.setup_quality import SetupQualityEngine, SetupQualityInput


def proposal(score=.9):
    return EntryProposal(True,EntrySide.BUY,EntryMode.TREND_PULLBACK,score,1-score,2.0,1.0,3,("test",))


class SetupQualityTests(unittest.TestCase):
    def test_high_quality_keeps_requested_risk(self):
        x=SetupQualityInput(proposal(),.9,.5,3.0,.95,1.1,True,False,.1,.9,.0)
        r=SetupQualityEngine().evaluate(x)
        self.assertTrue(r.valid)
        self.assertEqual(r.risk_multiplier,1.0)

    def test_extreme_volatility_fails_closed(self):
        x=SetupQualityInput(proposal(),.9,.5,3.0,.95,3.0,True,False,.1,.9,.0)
        r=SetupQualityEngine().evaluate(x)
        self.assertFalse(r.valid)
        self.assertEqual(r.risk_multiplier,0.0)
        self.assertIn("volatility_extreme",r.reasons)

    def test_medium_quality_only_reduces_risk(self):
        x=SetupQualityInput(proposal(.78),.70,1.5,3.0,.65,1.8,True,False,.45,.65,.10)
        r=SetupQualityEngine(min_adjusted_score=.50).evaluate(x)
        self.assertTrue(r.valid)
        self.assertLessEqual(r.risk_multiplier,1.0)

    def test_news_blackout_rejects(self):
        x=SetupQualityInput(proposal(),.9,.5,3.0,.9,1.0,True,True,.9,.9,0)
        self.assertFalse(SetupQualityEngine().evaluate(x).valid)


if __name__=="__main__": unittest.main()
