from pathlib import Path
import tempfile
import unittest
from scripts.pc.bind_portable_runtime import bind_runtime


class PortableRuntimeBindingTests(unittest.TestCase):
    def test_binding_precedes_stale_workspace_and_preserves_original_backup(self):
        with tempfile.TemporaryDirectory(prefix='source with spaces ') as tmp:
            root=Path(tmp); runtime=root/'runtime';runtime.mkdir()
            source=root/'canonical'; (source/'src/katarina/intelligence').mkdir(parents=True)
            (source/'src/katarina/intelligence/unified_brain.py').touch()
            target=runtime/'python312._pth'
            original=b'python312.zip\n.\n../../workspace/src\nLib/site-packages\nimport site\n'
            target.write_bytes(original)
            first=bind_runtime(runtime,source)
            self.assertTrue(first['changed'])
            lines=target.read_text().splitlines()
            self.assertEqual(lines[:2],[str(source/'src'),str(source)])
            self.assertIn('python312.zip',lines)
            self.assertIn('import site',lines)
            self.assertIn('../../workspace/src',lines)
            self.assertEqual(next(runtime.glob('*.bak')).read_bytes(),original)
            second=bind_runtime(runtime,source)
            self.assertFalse(second['changed'])
            self.assertEqual(first['after_sha256'],second['after_sha256'])
            self.assertFalse(second['import_probe_verified'])

    def test_unapproved_source_does_not_change_runtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);target=root/'python312._pth';target.write_text('python312.zip\n')
            with self.assertRaises(ValueError):
                bind_runtime(root,root/'missing')
            self.assertEqual(target.read_text(),'python312.zip\n')
            self.assertEqual(list(root.glob('*.bak')),[])
