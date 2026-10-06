import unittest

from katarina.research.backtest import BacktestTrade, BacktestingEngine
from katarina.research.validation_suite import StrategyValidationSuite


class ValidationSuiteTests(unittest.TestCase):
    def test_combines_backtest_walkforward_and_montecarlo(self):
        r=[1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5,1,-.5]
        bt=BacktestingEngine().evaluate([BacktestTrade(x,0) for x in r])
        out=StrategyValidationSuite().evaluate(r,bt,train_size=8,test_size=4,simulations=50,min_trades=10,min_recovery_factor=.1)
        self.assertGreater(len(out.walkforward.folds),0)
        self.assertEqual(out.monte_carlo.simulations,50)

    def test_bad_system_fails(self):
        r=[-1]*24
        bt=BacktestingEngine().evaluate([BacktestTrade(x,0) for x in r])
        out=StrategyValidationSuite().evaluate(r,bt,train_size=8,test_size=4,simulations=50)
        self.assertFalse(out.passed)
        self.assertIn("profit_factor",out.reasons)


if __name__=="__main__": unittest.main()
