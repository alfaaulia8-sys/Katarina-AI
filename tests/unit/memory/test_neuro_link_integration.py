import unittest
from dataclasses import replace
from tempfile import TemporaryDirectory
from pathlib import Path

from katarina.memory import MemoryStore, CognitiveEvidence, NeuroLinkMemory


class NeuroLinkIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.store = MemoryStore(Path(self.temp.name) / 'memory.sqlite3')
        self.memory = NeuroLinkMemory(self.store)
        self.evidence = CognitiveEvidence(
            evidence_id='one', event_group_id='market-one', observed_ns=10,
            known_ns=20, hypothesis='trend evidence', tags=('gold',),
            decision='WAIT', outcome_net_r=1., quality='INDEPENDENTLY_VALIDATED')

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_future_outcomes_are_invisible(self):
        self.memory.remember(self.evidence)
        self.assertEqual(self.memory.recall(('gold',), as_of_ns=19).links, ())

    def test_replicated_market_event_does_not_inflate_evidence(self):
        for n in range(4):
            self.memory.remember(replace(self.evidence, evidence_id=str(n)))
        result = self.memory.recall(('gold',), as_of_ns=30)
        self.assertEqual(result.links[0].independent_events, 1)
        self.assertTrue(result.links[0].quarantined)
        self.assertFalse(result.live_risk_authorized)

    def test_recall_rejects_tampered_persistent_payload(self):
        self.memory.remember(self.evidence)
        with self.store._conn:
            self.store._conn.execute('DROP TRIGGER operational_events_no_update')
            self.store._conn.execute("UPDATE operational_events SET payload_json='{}'")
        with self.assertRaisesRegex(ValueError, 'digest_mismatch'):
            self.memory.recall(('gold',), as_of_ns=30)

    def test_incomplete_window_is_disclosed(self):
        memory = NeuroLinkMemory(self.store, max_fast_records=1, max_deep_records=2)
        for n in range(3):
            memory.remember(replace(self.evidence, evidence_id=str(n), event_group_id=str(n)))
        self.assertTrue(memory.recall(('gold',), as_of_ns=30).history_truncated)
