import unittest
from scripts.github.check_access import assess


class GithubAccessReportTests(unittest.TestCase):
    def test_owner_role_does_not_claim_write_scope_is_tested(self):
        report = assess({'login': 'owner'}, {'full_name': 'owner/repo', 'permissions': {'pull': True, 'push': True, 'admin': True}}, {'repository': True})
        self.assertTrue(report['owner_role_available'])
        self.assertFalse(report['write_operations_verified'])
        self.assertFalse(report['credentials_exported'])

    def test_wrong_account_is_visible_even_with_read_access(self):
        report = assess({'login': 'other'}, {'full_name': 'owner/repo', 'permissions': {'pull': True}}, {'repository': True})
        self.assertFalse(report['owner_matches'])
        self.assertFalse(report['owner_role_available'])

    def test_failed_admin_read_is_not_reported_as_complete(self):
        report = assess({'login': 'owner'}, {'full_name': 'owner/repo', 'permissions': {'admin': True, 'push': True}}, {'repository': True, 'protection_administration_read': False})
        self.assertEqual(report['result'], 'READ_ACCESS_INCOMPLETE')
