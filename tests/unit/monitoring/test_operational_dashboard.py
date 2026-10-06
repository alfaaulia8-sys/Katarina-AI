import unittest

from katarina.monitoring.operational_dashboard import (
    ManagedPositionDashboard,
    OperationalDashboard,
    OperationalDashboardSnapshot,
)


class OperationalDashboardTests(unittest.TestCase):
    def test_renders_full_risk_and_rr_state(self):
        s=OperationalDashboardSnapshot(
            lifecycle="RUNNING",health="OK",execution_armed=False,equity=10000,
            daily_drawdown=.02,total_drawdown=.03,position_risk=.03,
            manual_position_risk=.01,pending_risk=.02,manual_pending_risk=0,
            reserved_risk=.01,total_committed_risk=.06,remaining_risk_capacity=.02,
            unbounded_risk=False,regime="TREND_UP",active_strategy="TREND_PULLBACK",
            decision="BUY",news_ready=True,news_blackout=False,profit_factor=1.6,
            recovery_factor=2.1,win_rate=.55,
            positions=(ManagedPositionDashboard("p","BUY",2.2,2.5,3,True,.02,2007.5),),
            data={},
        )
        text=OperationalDashboard().render_json(s)
        self.assertIn('"reserved_risk":0.01',text)
        self.assertIn('"peak_r":2.5',text)
        self.assertIn('"recovery_factor":2.1',text)


if __name__=="__main__": unittest.main()
