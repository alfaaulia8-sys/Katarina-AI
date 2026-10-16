"""Exercise the actual legacy PowerShell script; never contact GitHub or MT5."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT/'scripts/vps/Invoke-KatarinaPretrialRelease.ps1'


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell host behavior')
class VpsPretrialReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='VPS source fixture ')
        self.repo = Path(self.tmp.name)
        self.git('init')
        self.git('config', 'user.name', 'Synthetic fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('remote', 'add', 'origin', 'https://github.com/alfaauliau-katarinaAI/Katarina-AI.git')
        (self.repo/'facts.txt').write_text('original', encoding='utf-8')
        self.git('add', 'facts.txt')
        self.git('commit', '-m', 'Synthetic fixture only')
        self.sha = self.git('rev-parse', 'HEAD').strip()

    def tearDown(self):
        # Windows Git sometimes leaves read-only pack/index metadata in fixtures.
        import shutil
        shutil.rmtree(self.repo, ignore_errors=True)
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args],
            text=True, stderr=subprocess.PIPE)

    def invoke(self, mode):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive',
            '-File', str(SCRIPT), '-Mode', mode, '-ExpectedCommit', self.sha,
            '-SourceRoot', str(self.repo), '-PythonExe', sys.executable],
            capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.lstrip('\ufeff'))

    def test_real_audit_reads_local_runtime_without_changing_source(self):
        result = self.invoke('Audit')
        self.assertTrue(result['ok'], result)
        self.assertTrue(result['source_matches'])
        self.assertTrue(result['python_found'])
        self.assertEqual(result['python']['version'][:2], [3, 12])
        self.assertFalse(result['live_execution_authorized'])
        self.assertEqual(result['orders_submitted'], 0)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_sync_refuses_dirty_source_before_fetch_or_reset(self):
        (self.repo/'facts.txt').write_text('Owner modification', encoding='utf-8')
        result = self.invoke('Sync')
        self.assertFalse(result['ok'])
        self.assertEqual(result['reason'], 'SOURCE_DIRTY_NO_AUTOSTASH_OR_RESET')
        self.assertEqual((self.repo/'facts.txt').read_text(), 'Owner modification')
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.sha)

    def test_untrusted_origin_is_blocked_without_running_python(self):
        self.git('remote', 'set-url', 'origin', 'https://example.invalid/private-token')
        result = self.invoke('Audit')
        self.assertFalse(result['ok'])
        self.assertEqual(result['reason'], 'SOURCE_ORIGIN_REJECTED')
        self.assertNotIn('private-token', json.dumps(result))
