import unittest
from katarina.adapters.paper import PaperExecutionVenue,PaperOrder
from katarina.engines.stress import StressTestEngine,StressScenario
from katarina.governance.live_validation import LiveMicroRiskValidator,LiveValidationEvidence
from katarina.monitoring.performance import PerformanceMonitor
from katarina.governance.evolution import ContinuousEvolutionController,EvolutionProposal

class Stage3640Tests(unittest.TestCase):
    def test_paper_execution(self):
        f=PaperExecutionVenue(slippage_bps=1,commission_per_lot=5).execute(PaperOrder("1","BUY",2000,.1)); self.assertGreater(f.fill_price,2000)

    def test_stress_fail_closed(self):
        self.assertFalse(StressTestEngine().evaluate(StressScenario(transport_up=False)).new_risk_allowed)
        self.assertFalse(StressTestEngine().evaluate(StressScenario(latency_ms=5000)).new_risk_allowed)

    def test_live_requires_all_gates_but_uses_same_five_percent_cap(self):
        v=LiveMicroRiskValidator()
        blocked=v.evaluate(LiveValidationEvidence(False,True,True,True,True,True,.05))
        self.assertFalse(blocked.allowed)

        approved=v.evaluate(LiveValidationEvidence(True,True,True,True,True,True,.10))
        self.assertTrue(approved.allowed)
        self.assertAlmostEqual(approved.approved_risk_fraction,.05)
        self.assertAlmostEqual(v.HARD_RISK_CAP,.05)

    def test_performance_degradation_and_recovery_factor(self):
        r=PerformanceMonitor().evaluate([-1,-1,.2],baseline_expectancy=.2)
        self.assertTrue(r.degraded)
        self.assertAlmostEqual(r.recovery_factor,-.9)

    def test_positive_recovery_factor(self):
        r=PerformanceMonitor().evaluate([2,-1,2])
        self.assertAlmostEqual(r.recovery_factor,3.0)

    def test_evolution_never_auto_promotes_live(self):
        c=ContinuousEvolutionController(); d=c.decide(EvolutionProposal("p","h","v2",True,True)); self.assertEqual(d.action,"PROMOTION_REVIEW"); self.assertFalse(c.autonomous_live_promotion_allowed())

    def test_constitution_change_rejected(self):
        d=ContinuousEvolutionController().decide(EvolutionProposal("p","h","v2",True,True,True)); self.assertEqual(d.action,"REJECT")

if __name__=="__main__": unittest.main()
