import unittest

from katarina.engines.execution import ExecutionEngine
from katarina.engines.position import (
    RRPositionState,
    RRProfitManager,
    RRProfitTracker,
)


def pos(
    *,
    position_id="p1",
    side="BUY",
    entry=2000.0,
    current=2010.0,
    stop=1990.0,
    risk_distance=10.0,
    target_rr=3.0,
    authorized_volume=.10,
    current_volume=.10,
    volume_min=.01,
    volume_step=.01,
):
    return RRPositionState(
        position_id,side,entry,current,stop,risk_distance,target_rr,
        authorized_volume,current_volume,volume_min,volume_step
    )


class RRProfitManagementTests(unittest.TestCase):
    def test_target_1_to_3_triggers_at_2r(self):
        m=RRProfitManager()
        plan=m.evaluate(pos(current=2020.0))
        self.assertAlmostEqual(plan.trigger_r,2.0)
        self.assertTrue(plan.partial_triggered)

    def test_at_2r_closes_80_percent_and_leaves_20_percent(self):
        plan=RRProfitManager().evaluate(pos(current=2020.0))
        self.assertAlmostEqual(plan.partial_close_volume,.08)
        self.assertAlmostEqual(plan.target_remaining_volume,.02)
        self.assertAlmostEqual(plan.partial_close_fraction_of_authorized,.80)

    def test_at_2r_stop_locks_30_percent_of_running_profit(self):
        plan=RRProfitManager().evaluate(pos(current=2020.0))
        # 2R running profit = 20 price units; 30% = 6 -> SL 2006.
        self.assertTrue(plan.modify_sl_required)
        self.assertAlmostEqual(plan.new_stop,2006.0)

    def test_profit_rise_ratchets_stop_up(self):
        tracker=RRProfitTracker()
        first=tracker.evaluate(pos(current=2020.0))
        second=tracker.evaluate(pos(current=2025.0,current_volume=.02,stop=first.new_stop))
        self.assertAlmostEqual(first.new_stop,2006.0)
        self.assertAlmostEqual(second.new_stop,2007.5)
        self.assertAlmostEqual(second.peak_r,2.5)

    def test_profit_fall_never_moves_stop_back(self):
        tracker=RRProfitTracker()
        first=tracker.evaluate(pos(current=2025.0,current_volume=.02,stop=2006.0))
        falling=tracker.evaluate(pos(current=2023.0,current_volume=.02,stop=first.new_stop))
        self.assertAlmostEqual(first.new_stop,2007.5)
        self.assertEqual(falling.peak_r,2.5)
        self.assertFalse(falling.modify_sl_required)
        self.assertIsNone(falling.new_stop)

    def test_peak_state_survives_snapshot_restore(self):
        t1=RRProfitTracker()
        first=t1.evaluate(pos(current=2025.0,current_volume=.02,stop=2006.0))
        snap=t1.snapshot()
        t2=RRProfitTracker()
        t2.restore(snap)
        falling=t2.evaluate(pos(current=2022.0,current_volume=.02,stop=first.new_stop))
        self.assertAlmostEqual(falling.peak_r,2.5)
        self.assertFalse(falling.modify_sl_required)

    def test_partial_is_not_repeated_after_broker_volume_reaches_runner(self):
        tracker=RRProfitTracker()
        first=tracker.evaluate(pos(current=2020.0))
        self.assertAlmostEqual(first.partial_close_volume,.08)
        after_fill=tracker.evaluate(pos(current=2021.0,current_volume=.02,stop=2006.0))
        self.assertEqual(after_fill.partial_close_volume,0.0)

    def test_target_ratio_drives_trigger_dynamically(self):
        plan=RRProfitManager().evaluate(pos(target_rr=4.0,current=2030.0))
        self.assertAlmostEqual(plan.trigger_r,3.0)
        self.assertTrue(plan.partial_triggered)

    def test_before_trigger_no_partial_and_no_trailing(self):
        plan=RRProfitManager().evaluate(pos(current=2019.0))
        self.assertFalse(plan.partial_triggered)
        self.assertEqual(plan.partial_close_volume,0.0)
        self.assertFalse(plan.modify_sl_required)

    def test_sell_uses_symmetric_math(self):
        plan=RRProfitManager().evaluate(pos(
            side="SELL",entry=2000,current=1980,stop=2010,risk_distance=10
        ))
        self.assertAlmostEqual(plan.partial_close_volume,.08)
        self.assertAlmostEqual(plan.new_stop,1994.0)

    def test_minimum_lot_prevents_invalid_partial_close(self):
        plan=RRProfitManager().evaluate(pos(
            authorized_volume=.01,current_volume=.01,volume_min=.01,volume_step=.01,
            current=2020
        ))
        self.assertEqual(plan.partial_close_volume,0.0)
        self.assertAlmostEqual(plan.target_remaining_volume,.01)
        self.assertTrue(plan.modify_sl_required)

    def test_broker_step_quantization_keeps_valid_runner(self):
        plan=RRProfitManager().evaluate(pos(
            authorized_volume=.07,current_volume=.07,volume_min=.01,volume_step=.01,
            current=2020
        ))
        # 20% raw runner=.014 -> ceil to .02, close .05.
        self.assertAlmostEqual(plan.target_remaining_volume,.02)
        self.assertAlmostEqual(plan.partial_close_volume,.05)

    def test_existing_tighter_stop_is_never_loosened(self):
        plan=RRProfitManager().evaluate(pos(current=2025,current_volume=.02,stop=2009))
        self.assertFalse(plan.modify_sl_required)

    def test_execution_maps_plan_to_reduce_and_modify_intents(self):
        plan=RRProfitManager().evaluate(pos(current=2020))
        commands=ExecutionEngine.management_commands(plan)
        self.assertEqual([x.message_type for x in commands],[
            "REDUCE_INTENT","MODIFY_PROTECTION_INTENT"
        ])
        self.assertAlmostEqual(commands[0].reduce_volume,.08)
        self.assertAlmostEqual(commands[1].new_stop,2006.0)


if __name__=="__main__":
    unittest.main()
