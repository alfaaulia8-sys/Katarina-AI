"""Maintenance must preserve source-backed/dynamic workflows and all run history."""
from pathlib import Path
import tempfile
import unittest
from scripts.governance.clean_orphaned_workflow_catalog import cleanup


class WorkflowCatalogHygieneTests(unittest.TestCase):
    def test_disables_only_active_orphan_and_never_dynamic_or_existing_source(self):
        with tempfile.TemporaryDirectory() as root:
            source = Path(root)/'.github/workflows/current.yml'
            source.parent.mkdir(parents=True); source.write_text('name: current')
            mutations=[]
            def api(path, *, method='GET'):
                if method!='GET':
                    mutations.append((path,method)); return None
                if path=='/branches/main':return {'commit':{'sha':'verified-main'}}
                return {'workflows':[
                    {'id':1,'path':'.github/workflows/current.yml','state':'active'},
                    {'id':2,'path':'.github/workflows/removed.yml','state':'active'},
                    {'id':3,'path':'dynamic/dependabot/update-graph','state':'active'},
                    {'id':4,'path':'.github/workflows/disabled.yml','state':'disabled_manually'}]}
            result=cleanup(api,root,'verified-main',execute=True)
            self.assertEqual(mutations,[('/actions/workflows/2/disable','PUT')])
            self.assertEqual(result['workflow_runs_deleted'],0)
            self.assertTrue(source.is_file())

    def test_dry_run_does_not_mutate(self):
        with tempfile.TemporaryDirectory() as root:
            def api(path, *, method='GET'):
                self.assertEqual(method,'GET')
                return ({'commit':{'sha':'main'}} if path=='/branches/main' else
                        {'workflows':[{'id':1,'path':'.github/workflows/gone.yml','state':'active'}]})
            self.assertFalse(cleanup(api,root,'main')['disabled'])

    def test_main_change_between_scan_and_write_blocks_mutation(self):
        reads=iter(['main','new-main'])
        def api(path, *, method='GET'):
            self.assertEqual(method,'GET')
            return ({'commit':{'sha':next(reads)}} if path=='/branches/main' else
                    {'workflows':[{'id':1,'path':'.github/workflows/gone.yml','state':'active'}]})
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError,'main_changed'):
                cleanup(api,root,'main',execute=True)

    def test_wrong_source_revision_cannot_scan_or_disable(self):
        def api(path, *, method='GET'):
            self.assertEqual(path,'/branches/main')
            self.assertEqual(method,'GET')
            return {'commit':{'sha':'new-main'}}
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError,'current_main'):
                cleanup(api,root,'old-main',execute=True)
