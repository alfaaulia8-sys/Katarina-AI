"""Fault injection for recovery transactions; clean installation is exercised by CI."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.pc.environment_recovery import EnvironmentManager, RecoveryBlocked, python_at, recovery_lock


class EnvironmentRecoveryTests(unittest.TestCase):
    def manager(self,root,*,install_ok=True,accept=True):
        base=Path(root)/'envs';base.mkdir(exist_ok=True)
        calls=[]
        def builder(folder):
            target=python_at(folder);target.parent.mkdir(parents=True);target.write_text('test-interpreter-placeholder')
        def runner(command,**kwargs):
            calls.append(command)
            return SimpleNamespace(returncode=0 if install_ok else 1)
        manager=EnvironmentManager(root,base=base,runner=runner,builder=builder,clock=lambda:1000.)
        manager.healthy=lambda folder,mt5=False:python_at(folder).is_file()
        manager._accept=lambda folder:accept
        return manager,calls

    def seed(self,manager,char,*,healthy=True):
        name='env-'+char*32
        path=python_at(manager.base/name);path.parent.mkdir(parents=True)
        if healthy:path.write_text('old-environment-preserved')
        return name

    def test_candidate_activated_only_after_acceptance(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            python=manager.ensure()
            data=json.loads(manager.pointer.read_text())
            self.assertEqual(python,python_at(manager.base/data['active']))
            self.assertEqual(len(calls),1)
            self.assertIsNone(data['previous'])
            self.assertIn('CANDIDATE_VALIDATED',(manager.base/'recovery-audit.jsonl').read_text())

    def test_failed_install_retains_active_pointer_and_old_files(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root,install_ok=False)
            old=self.seed(manager,'a');manager._activate(old,None,False)
            before=manager.pointer.read_bytes()
            with self.assertRaisesRegex(RecoveryBlocked,'DEPENDENCY_INSTALL_FAILED'):
                manager.ensure(force=True,explicit=True)
            self.assertEqual(before,manager.pointer.read_bytes())
            self.assertTrue(python_at(manager.base/old).is_file())
            self.assertEqual(len(list(manager.base.glob('env-*'))),2)

    def test_smoke_rejection_never_activates_candidate(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root,accept=False)
            with self.assertRaisesRegex(RecoveryBlocked,'CANDIDATE_ACCEPTANCE_FAILED'):manager.ensure()
            self.assertFalse(manager.pointer.exists())

    def test_validated_previous_environment_rolls_back_without_install(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            bad=self.seed(manager,'a',healthy=False); good=self.seed(manager,'b')
            manager._activate(bad,good,False)
            self.assertEqual(manager.ensure(),python_at(manager.base/good))
            self.assertFalse(calls)
            self.assertEqual(json.loads(manager.pointer.read_text())['active'],good)
            self.assertTrue((manager.base/bad).is_dir())

    def test_healthy_environment_never_downloads(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            good=self.seed(manager,'b');manager._activate(good,None,False)
            manager.ensure()
            self.assertFalse(calls)

    def test_auto_repair_can_be_disabled(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            with self.assertRaisesRegex(RecoveryBlocked,'REPAIR_REQUIRED'):manager.ensure(auto=False)
            self.assertFalse(calls)

    def test_failure_cooldown_limits_repeated_launches_but_explicit_repair_retries(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root,install_ok=False)
            with self.assertRaises(RecoveryBlocked):manager.ensure()
            with self.assertRaisesRegex(RecoveryBlocked,'COOLDOWN'):manager.ensure()
            self.assertEqual(len(calls),1)
            with self.assertRaises(RecoveryBlocked):manager.ensure(explicit=True)
            self.assertEqual(len(calls),2)

    def test_pointer_path_traversal_is_blocked(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            manager.pointer.write_text(json.dumps(dict(version=1,active='../../python',previous=None,mt5_required=False)))
            with self.assertRaisesRegex(RecoveryBlocked,'POINTER_INVALID'):manager.ensure()
            self.assertFalse(calls)

    def test_lock_prevents_concurrent_repair(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            with recovery_lock(manager.base):
                with self.assertRaisesRegex(RecoveryBlocked,'ALREADY_RUNNING'):manager.ensure()
            self.assertFalse(calls)

    def test_existing_memory_and_source_are_never_rewritten(self):
        with tempfile.TemporaryDirectory() as root:
            memory=Path(root)/'cognitive-memory.sqlite3';memory.write_bytes(b'owner-state-do-not-change')
            source=Path(root)/'strategy.py';source.write_text('OWNER_SOURCE')
            manager,calls=self.manager(root)
            manager.ensure()
            self.assertEqual(memory.read_bytes(),b'owner-state-do-not-change')
            self.assertEqual(source.read_text(),'OWNER_SOURCE')

    def test_install_exception_text_is_not_persisted(self):
        with tempfile.TemporaryDirectory() as root:
            manager,calls=self.manager(root)
            def fail(*a,**kw):raise OSError('secret-password-in-proxy-url')
            manager.runner=fail
            with self.assertRaises(RecoveryBlocked):manager.ensure()
            self.assertNotIn('secret-password',(manager.base/'recovery-audit.jsonl').read_text())

    def test_unwritable_checkout_uses_separate_per_checkout_user_environment(self):
        import tempfile as module
        original=module.TemporaryFile
        with tempfile.TemporaryDirectory() as root:
            checkout=(Path(root)/'repo').resolve();checkout.mkdir()
            home=(Path(root)/'user').resolve();home.mkdir()
            def writable(*a,**kwargs):
                if Path(kwargs.get('dir','')).resolve().parent==checkout:raise OSError('read only checkout')
                return original(*a,**kwargs)
            with patch.dict('os.environ',{},clear=True), patch('pathlib.Path.home',return_value=home), \
                 patch('scripts.pc.environment_recovery.tempfile.TemporaryFile',side_effect=writable):
                manager=EnvironmentManager(checkout)
                self.assertTrue(manager.base.is_relative_to(home))
