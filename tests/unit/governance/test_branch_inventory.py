"""Read-only branch hygiene decisions must never silently promote code."""
import unittest
from scripts.governance.audit_branch_inventory import classify


class BranchInventoryTests(unittest.TestCase):
    def test_already_contained_is_only_prune_candidate(self):
        self.assertEqual(classify({'ahead_by': 0, 'behind_by': 12}), 'PRUNE_CANDIDATE_ALREADY_CONTAINED')

    def test_diverged_unique_commits_need_review(self):
        self.assertEqual(classify({'ahead_by': 4, 'behind_by': 12}), 'REVIEW_UNMERGED_COMMITS')

    def test_newer_branch_requires_review(self):
        self.assertEqual(classify({'ahead_by': 2, 'behind_by': 0}), 'REVIEW_UNMERGED_COMMITS')

    def test_unknown_requires_review(self):
        self.assertEqual(classify({'ahead_by': None, 'behind_by': 0}), 'REVIEW_UNKNOWN')


if __name__ == '__main__':
    unittest.main()
