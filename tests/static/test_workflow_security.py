"""Public CI must not inherit write access or execute mutable actions."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class WorkflowSecurityTests(unittest.TestCase):
    def test_all_remote_actions_are_pinned_and_checkouts_drop_credentials(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            source = path.read_text()
            with self.subTest(workflow=path.name):
                self.assertRegex(source, r'(?m)^permissions:\n  contents: read\s*$')
                self.assertNotRegex(source, r'(?m)^  pull_request_target:')
                for action in re.findall(r'uses:\s*([^\s#]+)', source):
                    self.assertRegex(action, r'^actions/[\w-]+@[a-f0-9]{40}$')
                for match in re.finditer(r'(?m)^([ ]*)(?:- )?uses: actions/checkout@[^\n]+\n((?:[ ]+[^\n]*\n){1,5})', source):
                    self.assertIn('persist-credentials: false', match.group(2))
                self.assertNotIn('persist-credentials: true', source)

    def test_automatic_jobs_cannot_dispatch_other_workflows_or_push_news_to_main(self):
        body = (ROOT / '.github/workflows/katarina-body-ci.yml').read_text()
        news = (ROOT / '.github/workflows/katarina-hotnews.yml').read_text()
        self.assertNotIn('actions: write', body)
        self.assertNotIn('gh workflow run', body)
        self.assertNotIn('paths-ignore:', body)
        self.assertNotIn('git push', news)
        self.assertNotIn('contents: write', news)

    def test_only_manual_main_cleanup_has_repository_write_permission(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            source = path.read_text()
            if 'contents: write' in source:
                self.assertEqual(path.name, 'katarina-guarded-branch-cleanup.yml')
                self.assertIn("if: github.ref == 'refs/heads/main'", source)
                self.assertIn('cancel-in-progress: false', source)

    def test_codeowners_use_current_repository_owner(self):
        source = (ROOT / '.github/CODEOWNERS').read_text()
        self.assertIn('* @alfaauliau-katarinaAI', source)
        self.assertNotIn('@alfaaulia-katarina\n', source)
