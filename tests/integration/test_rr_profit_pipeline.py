import unittest

from katarina.engines.execution import ExecutionEngine
from katarina.engines.position import PositionManager, RRPositionState


class RRProfitPipelineTests(unittest.TestCase):
    def test_2r_event_creates_partial_and_protection_commands(self):
        p=RRPositionState(
            position_id="ticket-100",
            side="BUY",
            entry=2000,
            current=2020,
            stop=1990,
            risk_distance=10,
            target_rr=3,
            authorized_volume=.10,
            current_volume=.10,
            volume_min=.01,
            volume_step=.01,
        )
        plan=PositionManager().decide_rr(p)
        commands=ExecutionEngine.management_commands(plan)
        self.assertEqual(len(commands),2)
        self.assertEqual(commands[0].message_type,"REDUCE_INTENT")
        self.assertAlmostEqual(commands[0].reduce_volume,.08)
        self.assertEqual(commands[1].message_type,"MODIFY_PROTECTION_INTENT")
        self.assertAlmostEqual(commands[1].new_stop,2006)

    def test_high_water_trail_does_not_retreat(self):
        manager=PositionManager()
        first=manager.decide_rr(RRPositionState(
            "p","BUY",2000,2025,1990,10,3,.10,.02,.01,.01
        ))
        second=manager.decide_rr(RRPositionState(
            "p","BUY",2000,2022,first.new_stop,10,3,.10,.02,.01,.01
        ))
        self.assertAlmostEqual(first.new_stop,2007.5)
        self.assertFalse(second.modify_sl_required)
        self.assertEqual(ExecutionEngine.management_commands(second),())


if __name__=="__main__":
    unittest.main()
