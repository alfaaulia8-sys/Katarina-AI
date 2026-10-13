"""Management worker limits and cache inventories never delete application data."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ai.management_resources import (
    resource_policy, safe_cache_inventory, observe_workspace,
)


class ResourceGuardTests(unittest.TestCase):
    def test_low_ram_throttles_to_one_worker(self):
        result = resource_policy(269, 9000)
        self.assertEqual(result["status"], "LOW_RAM_GUARD")
        self.assertEqual(result["recommended_local_max_workers"], 1)
        self.assertEqual(result["processes_terminated"], 0)

    def test_normal_and_limited_ram(self):
        self.assertEqual(resource_policy(512, 9000)["recommended_local_max_workers"], 2)
        self.assertEqual(resource_policy(4096, 9000)["recommended_local_max_workers"], 4)

    def test_unknown_ram_and_low_disk_fail_conservatively(self):
        self.assertEqual(resource_policy(None, 9000)["recommended_local_max_workers"], 1)
        self.assertEqual(resource_policy(4096, 200)["status"], "LOW_DISK_GUARD")

    def test_invalid_inputs_rejected(self):
        with self.assertRaises(ValueError):
            resource_policy(-1, 100)
        with self.assertRaises(ValueError):
            resource_policy(100, -1)

    def test_workspace_snapshot_does_not_modify_files(self):
        with TemporaryDirectory() as tmp:
            file = Path(tmp) / "keep.txt"
            file.write_text("safe", encoding="utf-8")
            report = observe_workspace(Path(tmp))
            self.assertIn(report["status"], {
                "NORMAL", "LIMITED_RAM", "LOW_RAM_GUARD", "LOW_DISK_GUARD",
                "RAM_UNVERIFIED",
            })
            self.assertEqual(file.read_text(encoding="utf-8"), "safe")

    def test_cache_scan_excludes_data_memory_and_backups(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in [
                "src/__pycache__", "tests/.pytest_cache",
                "memory/__pycache__", "data/.pytest_cache",
                "backups/__pycache__", "artifacts/.pytest_cache",
            ]:
                location = root / folder
                location.mkdir(parents=True)
                (location / "preserve.txt").write_text("untouched")
            report = safe_cache_inventory(root)
            self.assertEqual(
                set(report["cache_candidates"]),
                {"src/__pycache__", "tests/.pytest_cache"},
            )
            self.assertEqual(report["deleted"], 0)
            self.assertTrue((root / "memory/__pycache__/preserve.txt").is_file())
            self.assertTrue((root / "src/__pycache__/preserve.txt").is_file())


if __name__ == "__main__":
    unittest.main()
