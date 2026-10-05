from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / 'START_KATARINA.bat'
STARTER = ROOT / 'scripts' / 'windows' / 'Start-KatarinaAll.ps1'
WATCHER = ROOT / 'scripts' / 'windows' / 'Watch-KatarinaErrors.ps1'
PUBLISHER = ROOT / 'scripts' / 'windows' / 'Publish-KatarinaError.ps1'

class WindowsErrorSupervisorStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.launcher = LAUNCHER.read_text(encoding='utf-8')
        cls.starter = STARTER.read_text(encoding='utf-8')
        cls.watcher = WATCHER.read_text(encoding='utf-8')
        cls.publisher = PUBLISHER.read_text(encoding='utf-8')

    def test_one_click_launcher(self):
        self.assertIn('Start-KatarinaAll.ps1', self.launcher)

    def test_watches_mt5_and_tester_logs(self):
        self.assertIn('MetaQuotes\\Terminal', self.watcher)
        self.assertIn('MetaQuotes\\Tester', self.watcher)

    def test_errors_use_dedicated_branch(self):
        self.assertIn('katarina-errors', self.publisher)
        self.assertIn('HEAD:refs/heads/katarina-errors', self.publisher)
        self.assertNotIn('HEAD:refs/heads/main', self.publisher)

    def test_offline_queue_and_retry(self):
        self.assertIn('error-outbox', self.publisher)
        self.assertIn('RetryQueued', self.publisher)
        self.assertIn('RetryQueued', self.watcher)

    def test_bundle_records_source_commit(self):
        self.assertIn('source_commit', self.publisher)
        self.assertIn('rev-parse HEAD', self.publisher)

    def test_no_live_authority(self):
        self.assertIn('live_risk_ready', self.publisher)
        self.assertIn('live_execution_enabled', self.publisher)

    def test_startup_failure_auto_published(self):
        self.assertIn('STARTUP_VERIFY_ERROR', self.starter)

if __name__ == '__main__':
    unittest.main()
