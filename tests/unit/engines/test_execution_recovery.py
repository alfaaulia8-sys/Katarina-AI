import unittest

from katarina.engines.execution_recovery import ManagementRecoveryCoordinator
from katarina.engines.position import RRProfitManager, RRPositionState


def plan():
    return RRProfitManager().evaluate(RRPositionState(
        "p","BUY",2000,2020,1990,10,3,.10,.10,.01,.01
    ))


class ExecutionRecoveryTests(unittest.TestCase):
    def test_first_reconcile_emits_reduce_and_modify(self):
        c=ManagementRecoveryCoordinator(); c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin="KATARINA")
        cmd=c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)
        self.assertEqual([x.message_type for x in cmd],["REDUCE_INTENT","MODIFY_PROTECTION_INTENT"])

    def test_owner_manual_positions_never_receive_recovery_commands(self):
        for origin in ("MANUAL_DESKTOP","MANUAL_MOBILE","MANUAL_WEB","UNKNOWN","FOREIGN_EA"):
            with self.subTest(origin=origin):
                c=ManagementRecoveryCoordinator()
                with self.assertRaises(PermissionError):
                    c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin=origin)
                self.assertEqual(c.reconcile("p",current_volume=.10,
                                   current_stop=1990,volume_step=.01),())
        with self.assertRaises(ValueError):
            ManagementRecoveryCoordinator().restore_state({
                "p":{"side":"BUY","target_remaining_volume":.1,"desired_stop":None}
            })

    def test_no_duplicate_while_inflight(self):
        c=ManagementRecoveryCoordinator(); c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin="KATARINA")
        self.assertEqual(len(c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)),2)
        self.assertEqual(c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01),())

    def test_partial_fill_retries_only_remainder_after_reconcile(self):
        c=ManagementRecoveryCoordinator(); c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin="KATARINA")
        c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)
        # Broker reduced .05 instead of requested .08; SL succeeded.
        cmd=c.reconcile("p",current_volume=.05,current_stop=2006,volume_step=.01)
        self.assertEqual(len(cmd),1)
        self.assertEqual(cmd[0].message_type,"REDUCE_INTENT")
        self.assertAlmostEqual(cmd[0].reduce_volume,.03)

    def test_failed_modify_can_retry(self):
        c=ManagementRecoveryCoordinator(); c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin="KATARINA")
        c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)
        c.ack_failure("p","MODIFY_PROTECTION_INTENT")
        cmd=c.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)
        self.assertEqual(len(cmd),1)
        self.assertEqual(cmd[0].message_type,"MODIFY_PROTECTION_INTENT")

    def test_state_round_trip(self):
        c=ManagementRecoveryCoordinator(); c.apply_plan(plan(),side="BUY",current_stop=1990,position_origin="KATARINA")
        state=c.snapshot_state()
        r=ManagementRecoveryCoordinator(); r.restore_state(state)
        self.assertEqual(len(r.reconcile("p",current_volume=.10,current_stop=1990,volume_step=.01)),2)


if __name__=="__main__": unittest.main()
