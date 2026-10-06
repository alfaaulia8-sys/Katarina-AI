import unittest

from katarina.research.real_tick import Tick, RealTickTradeSpec, RealTickBacktester


class RealTickBacktestTests(unittest.TestCase):
    def test_rr_1_3_partial_and_target(self):
        ticks=[
            Tick(1,1999.9,2000.0),
            Tick(2,2010.0,2010.1),
            Tick(3,2020.0,2020.1),
            Tick(4,2025.0,2025.1),
            Tick(5,2030.0,2030.1),
        ]
        spec=RealTickTradeSpec("t","BUY",0,10,3,.10,10,commission_per_lot=0)
        r=RealTickBacktester().simulate_trade(ticks,spec)
        self.assertTrue(r.partial_done)
        self.assertEqual(r.exit_reason,"TARGET")
        self.assertGreater(r.net_pnl,0)
        self.assertGreaterEqual(r.peak_r,2.0)

    def test_ratchet_stop_can_exit_runner(self):
        ticks=[
            Tick(1,1999.9,2000.0),
            Tick(2,2020.0,2020.1),
            Tick(3,2025.0,2025.1),
            Tick(4,2007.4,2007.5),
        ]
        spec=RealTickTradeSpec("t","BUY",0,10,3,.10,10)
        r=RealTickBacktester().simulate_trade(ticks,spec)
        self.assertTrue(r.partial_done)
        self.assertEqual(r.exit_reason,"STOP")
        self.assertAlmostEqual(r.final_stop,2007.5)

    def test_spread_is_reflected_in_execution(self):
        ticks=[Tick(1,99,101),Tick(2,111,113),Tick(3,121,123)]
        spec=RealTickTradeSpec("t","BUY",0,10,2,.1,1)
        r=RealTickBacktester().simulate_trade(ticks,spec)
        self.assertGreater(r.net_pnl,0)

    def test_batch_metrics_include_profit_factor(self):
        ticks=[Tick(1,100,100),Tick(2,110,110),Tick(3,120,120),Tick(4,90,90)]
        specs=[
            RealTickTradeSpec("a","BUY",0,10,2,.1,1),
            RealTickTradeSpec("b","SELL",2,10,2,.1,1),
        ]
        b=RealTickBacktester().run(ticks,specs)
        self.assertEqual(b.metrics.trades,2)
        self.assertGreaterEqual(b.metrics.profit_factor,0)


if __name__=="__main__": unittest.main()
