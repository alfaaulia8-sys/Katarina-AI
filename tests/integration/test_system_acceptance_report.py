from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile
import unittest
from scripts.pc.run_system_acceptance import snapshot_check


class SystemAcceptanceReportTests(unittest.TestCase):
    def test_snapshot_is_fresh_readonly_evidence_never_process_or_live_clearance(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            now = datetime.now(timezone.utc).isoformat()
            safety = dict(orders_submitted=0,live_execution_authorized=False,production_execution=False)
            runtime = dict(safety,heartbeat_utc=now,status='WAITING',successful_cycles=3)
            report = dict(safety,observed_at_utc=now,market_snapshot_tick_utc=now,
                          received_market_data_symbols=3,symbols={'EURUSD':dict(blocking_reasons=[])})
            (root/'continuous-status.json').write_text(json.dumps(runtime))
            (root/'latest.json').write_text(json.dumps(report))
            result = snapshot_check(root)
            self.assertEqual(result['status'],'FRESH_READONLY_SNAPSHOT')
            self.assertFalse(result['process_liveness_independently_verified'])
            self.assertFalse(result['snapshot_is_execution_clearance'])
            for changed in [dict(report,orders_submitted=1),
                            dict(report,market_snapshot_tick_utc=(datetime.now(timezone.utc)-timedelta(days=1)).isoformat()),
                            dict(report,received_market_data_symbols=0),
                            dict(report,symbols={'EURUSD':dict(blocking_reasons=['sensor_error:ValueError'])})]:
                (root/'latest.json').write_text(json.dumps(changed))
                self.assertEqual(snapshot_check(root)['status'],'BLOCKED')

    def test_missing_or_invalid_snapshot_is_explicitly_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(snapshot_check(tmp)['status'],'BLOCKED')
            (Path(tmp)/'continuous-status.json').write_text('not json')
            self.assertEqual(snapshot_check(tmp)['status'],'BLOCKED')

    def test_child_bootstrap_works_when_python_ignores_pythonpath(self):
        import subprocess
        import sys
        from scripts.pc.run_system_acceptance import TEST_BOOTSTRAP, ROOT
        result = subprocess.run([sys.executable,'-I','-c',TEST_BOOTSTRAP,'discover',
            '-s','tests/integration','-p','test_brain_owned_workflow.py','-q'],
            cwd=ROOT,capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('OK',result.stderr)
