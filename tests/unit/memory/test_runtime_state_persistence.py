import tempfile, unittest
from pathlib import Path

from katarina.engines.account_risk_state import AccountRiskStateEngine, PendingOrderRiskInput
from katarina.engines.broker_risk import BrokerNativeRiskBook, BrokerRiskRequest
from katarina.engines.execution_recovery import ManagementRecoveryCoordinator
from katarina.engines.manual_risk import SymbolRiskSpec
from katarina.engines.position import RRPositionState, RRProfitTracker
from katarina.memory.store import MemoryStore
from katarina.memory.runtime_state import RuntimeStatePersistence
from katarina.engines.capital import CapitalCompoundingEngine


class RuntimePersistenceTests(unittest.TestCase):
    def test_restart_restores_risk_peak_and_recovery_state(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"k.db"
            risk=AccountRiskStateEngine(); risk.observe_equity("d",10000)
            risk.reservations.reserve("r1",.02)
            risk.upsert_pending(PendingOrderRiskInput("o1","KATARINA","BUY",.5,2000,1994,SymbolRiskSpec(.01,1)))
            rr=RRProfitTracker(); rr.evaluate(RRPositionState("p","BUY",2000,2025,1990,10,3,.1,.02,.01,.01))
            recovery=ManagementRecoveryCoordinator()
            broker=BrokerNativeRiskBook(); broker.register(BrokerRiskRequest("b1","p","BUY",1,1,.1,2025,2007.5))
            with MemoryStore(path) as store:
                RuntimeStatePersistence(store).save_components(account_risk=risk,rr_tracker=rr,execution_recovery=recovery,broker_risk=broker)

            risk2=AccountRiskStateEngine(); rr2=RRProfitTracker(); rec2=ManagementRecoveryCoordinator(); broker2=BrokerNativeRiskBook()
            with MemoryStore(path) as store:
                ok=RuntimeStatePersistence(store).restore_components(account_risk=risk2,rr_tracker=rr2,execution_recovery=rec2,broker_risk=broker2)
                self.assertTrue(ok)
            self.assertAlmostEqual(risk2.reservations.total_fraction,.02)
            self.assertAlmostEqual(rr2.snapshot()["p"],2.5)
            self.assertIsNone(broker2.loss_for("p"))

    def test_legacy_30pct_capital_snapshot_rejected_before_any_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            old_capital=CapitalCompoundingEngine(reserve_fraction=.30)
            old_capital.initialize(100)
            old_capital.observe_balance(200)
            old_risk=AccountRiskStateEngine()
            old_risk.observe_equity("d",1000)
            with MemoryStore(Path(folder)/"legacy.db") as store:
                RuntimeStatePersistence(store).save_components(
                    account_risk=old_risk,rr_tracker=RRProfitTracker(),
                    execution_recovery=ManagementRecoveryCoordinator(),
                    broker_risk=BrokerNativeRiskBook(),capital=old_capital)
            new_risk=AccountRiskStateEngine()
            new_risk.reservations.reserve("untouched",.01)
            new_capital=CapitalCompoundingEngine()
            with MemoryStore(Path(folder)/"legacy.db") as store:
                with self.assertRaisesRegex(ValueError,"approved_migration"):
                    RuntimeStatePersistence(store).restore_components(
                        account_risk=new_risk,rr_tracker=RRProfitTracker(),
                        execution_recovery=ManagementRecoveryCoordinator(),
                        broker_risk=BrokerNativeRiskBook(),capital=new_capital)
            self.assertAlmostEqual(new_risk.reservations.total_fraction,.01)
            self.assertFalse(new_capital.initialized)

    def test_legacy_drawdown_limits_rejected_before_any_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            old=AccountRiskStateEngine(daily_limit=.10,total_limit=.20)
            old.observe_equity("d",1000)
            with MemoryStore(Path(folder)/"legacy.db") as store:
                RuntimeStatePersistence(store).save_components(
                    account_risk=old,rr_tracker=RRProfitTracker(),
                    execution_recovery=ManagementRecoveryCoordinator(),
                    broker_risk=BrokerNativeRiskBook())
            fresh=AccountRiskStateEngine()
            fresh.reservations.reserve("must_remain",.02)
            with MemoryStore(Path(folder)/"legacy.db") as store:
                with self.assertRaisesRegex(ValueError,"legacy_drawdown"):
                    RuntimeStatePersistence(store).restore_components(
                        account_risk=fresh,rr_tracker=RRProfitTracker(),
                        execution_recovery=ManagementRecoveryCoordinator(),
                        broker_risk=BrokerNativeRiskBook())
            self.assertAlmostEqual(fresh.reservations.total_fraction,.02)

    def test_latest_operational_event(self):
        with tempfile.TemporaryDirectory() as d:
            with MemoryStore(Path(d)/"k.db") as store:
                store.append_operational_event("state",{"n":1},event_id="1")
                store.append_operational_event("state",{"n":2},event_id="2")
                self.assertEqual(store.load_latest_operational_event("state")["payload"]["n"],2)


if __name__=="__main__": unittest.main()
