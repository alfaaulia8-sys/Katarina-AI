import unittest
from katarina.research.research import ResearchEngine
from katarina.research.backtest import BacktestingEngine,BacktestTrade
from katarina.research.walkforward import WalkForwardEngine
from katarina.research.robustness import MonteCarloEngine
from katarina.research.shadow import ShadowKatarina

class Stage2125Tests(unittest.TestCase):
    def test_research_read_only(self):
        h=ResearchEngine().propose("Does x help?","reason","expectancy"); self.assertFalse(h.production_mutation_allowed)

    def test_backtest_costs_and_recovery_factor(self):
        r=BacktestingEngine().evaluate([BacktestTrade(2,.2),BacktestTrade(-1,.2)])
        self.assertAlmostEqual(r.net_pnl,.6)
        self.assertAlmostEqual(r.max_drawdown,1.2)
        self.assertAlmostEqual(r.recovery_factor,.5)

    def test_recovery_factor_positive_system(self):
        r=BacktestingEngine().evaluate([BacktestTrade(2,0),BacktestTrade(-1,0),BacktestTrade(2,0)])
        self.assertAlmostEqual(r.recovery_factor,3.0)

    def test_walkforward_no_leak_structure(self):
        r=WalkForwardEngine().split([1,2,3,4,5,6],train_size=3,test_size=1); self.assertEqual(r.folds[0].train,(1,2,3)); self.assertEqual(r.folds[0].test,(4,))

    def test_monte_carlo_deterministic_seed(self):
        e=MonteCarloEngine(); a=e.simulate([.01,-.01,.02],simulations=50,seed=7); b=e.simulate([.01,-.01,.02],simulations=50,seed=7); self.assertEqual(a,b)

    def test_shadow_never_mutates_broker(self):
        s=ShadowKatarina().compare("BUY","SELL",.7,.8); self.assertFalse(s.broker_mutation_allowed); self.assertFalse(s.agreement)

if __name__=="__main__": unittest.main()
