import tempfile, unittest
from pathlib import Path

from katarina.engines.account_risk_state import AccountRiskStateEngine, PendingOrderRiskInput
from katarina.engines.broker_risk import BrokerNativeRiskBook, BrokerRiskRequest
from katarina.engines.execution_recovery import ManagementRecoveryCoordinator
from katarina.engines.manual_risk import SymbolRiskSpec
from katarina.engines.position import RRPositionState, RRProfitTracker
from katarina.memory.store import MemoryStore
from katarina.memory.runtime_state import RuntimeStatePersistence


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

    def test_latest_operational_event(self):
        with tempfile.TemporaryDirectory() as d:
            with MemoryStore(Path(d)/"k.db") as store:
                store.append_operational_event("state",{"n":1},event_id="1")
                store.append_operational_event("state",{"n":2},event_id="2")
                self.assertEqual(store.load_latest_operational_event("state")["payload"]["n"],2)


if __name__=="__main__": unittest.main()
