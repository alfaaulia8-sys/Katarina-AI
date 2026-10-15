"""Deletion boundary regressions use an in-memory fake GitHub API."""
import unittest
from scripts.governance.guarded_branch_cleanup import cleanup, eligible, active_pr_branches

REPO = 'owner/repo'


class GuardedCleanupTests(unittest.TestCase):
    def test_only_unprotected_strict_ancestor_without_active_pr_is_eligible(self):
        branch = {'name': 'old', 'protected': False}
        comparison = {'ahead_by': 0, 'behind_by': 2, 'status': 'behind'}
        self.assertTrue(eligible(branch, comparison, set()))
        self.assertFalse(eligible(branch, comparison, {'old'}))
        self.assertFalse(eligible({**branch, 'protected': True}, comparison, set()))
        self.assertFalse(eligible(branch, {**comparison, 'ahead_by': 1}, set()))
        self.assertFalse(eligible(branch, {'ahead_by': 0, 'behind_by': 0, 'status': 'identical'}, set()))
        self.assertFalse(eligible({'name': 'main', 'protected': False}, comparison, set()))

    def test_both_head_and_base_of_active_pr_are_protected(self):
        pr = {s: {'ref': s, 'repo': {'full_name': REPO}} for s in ('head', 'base')}
        self.assertEqual(active_pr_branches(lambda _: [pr], REPO), {'head', 'base'})

    def run_fake(self, *, execute=True, moved=False, new_pr=False):
        deleted = []
        calls = {'prs': 0}
        branch = {'name': 'old', 'protected': False, 'commit': {'sha': 'a'}}
        def api(path, method='GET'):
            if method == 'DELETE':
                deleted.append(path)
                return 204
            if path.startswith('/pulls?'):
                calls['prs'] += 1
                if new_pr and calls['prs'] > 1:
                    return [{'head': {'ref': 'old', 'repo': {'full_name': REPO}}}]
                return []
            if path.startswith('/branches?'):
                return [branch]
            if path.startswith('/branches/'):
                return {**branch, 'commit': {'sha': 'b' if moved else 'a'}}
            if path.startswith('/compare/'):
                return {'ahead_by': 0, 'behind_by': 2, 'status': 'behind'}
            raise AssertionError(path)
        result = cleanup(api, REPO, execute=execute)
        return result, deleted

    def test_dry_run_never_deletes(self):
        report, deleted = self.run_fake(execute=False)
        self.assertEqual(report['candidates'], ['old'])
        self.assertEqual(deleted, [])

    def test_sha_movement_blocks_delete(self):
        self.assertEqual(self.run_fake(moved=True)[1], [])

    def test_pr_opened_during_run_blocks_delete(self):
        self.assertEqual(self.run_fake(new_pr=True)[1], [])

    def test_verified_ancestor_is_deleted(self):
        report, deleted = self.run_fake()
        self.assertEqual(report['deleted'], ['old'])
        self.assertEqual(deleted, ['/git/refs/heads/old'])
