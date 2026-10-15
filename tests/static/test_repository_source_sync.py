"""Repository defaults must agree before any installer or bridge is run."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RepositorySourceSyncTests(unittest.TestCase):
    def test_installer_and_bridge_defaults_match_project_identity(self):
        identity = json.loads((ROOT / "config/project_identity.json").read_text())
        repository = identity["canonical_repository"]
        self.assertEqual(repository, identity["canonical_owner"] + "/" + identity["canonical_name"])
        self.assertEqual(repository, "alfaauliau-katarinaAI/Katarina-AI")
        paths = (
            "ops/bridge/install-termux.sh",
            "ops/bridge/katarina_agent.py",
            "scripts/vps/Invoke-KatarinaRemoteTask.ps1",
            "scripts/vps/Invoke-KatarinaWorkspaceTask.ps1",
            "scripts/vps/legacy/OneClick-KatarinaVpsInstaller.ps1",
            "scripts/vps/legacy/Install-KatarinaVpsAgent.ps1",
            "scripts/vps/legacy/Repair-KatarinaVpsAgent.ps1",
        )
        for path in paths:
            with self.subTest(path=path):
                source = (ROOT / path).read_text()
                self.assertIn(repository, source)
                self.assertNotIn("alfaaulia8-sys/Katarina-AI", source)


if __name__ == "__main__":
    unittest.main()
