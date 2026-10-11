"""Portability contract for research and observer entrypoints (read-only)."""
from pathlib import Path
import subprocess
import unittest


REPO = Path(__file__).resolve().parents[2]
_LEGACY = "github" + "-main"
_OLD_RESEARCH = "indicator" + "-research"


class WorkspacePathContractTests(unittest.TestCase):
    def test_no_obsolete_checkout_in_active_scripts(self):
        tracked = subprocess.check_output(
            ["git", "-C", str(REPO), "ls-files", "scripts"],
            text=True,
        ).splitlines()
        offenders = []
        for rel in tracked:
            p = REPO / rel
            if p.suffix.lower() not in {".py", ".ps1", ".cmd", ".bat", ".sh"}:
                continue
            txt = p.read_text(encoding="utf-8-sig", errors="replace").lower()
            if "katarinadev" in txt and (_LEGACY in txt or _OLD_RESEARCH in txt):
                offenders.append(rel)
        self.assertEqual(offenders, [])

    def test_research_modules_resolve_from_themselves(self):
        expected = [
            "audit_adaptive_risk_tiers_2026.py",
            "audit_pair_correlations_2025.py",
            "backtest_brain_v2_from_2025.py",
            "intraday_session_2025.py",
            "xau_exit_three_way_tick_2025.py",
        ]
        for name in expected:
            with self.subTest(name=name):
                content = (REPO / "scripts" / "research" / name).read_text(encoding="utf-8-sig")
                self.assertIn("Path(__file__).resolve().parents[2]", content)

    def test_windows_readonly_launcher_uses_its_location(self):
        launcher = (REPO / "scripts" / "ai" / "RUN_READONLY_DECISIONS.cmd").read_text()
        self.assertIn('for %%I in ("%~dp0..\\..")', launcher)
        self.assertIn('%KATARINA_REPO%\\scripts\\ai\\run_readonly_decisions.py', launcher)
        self.assertIn("exit /b %ERRORLEVEL%", launcher)

    def test_analog_scheduler_is_repo_relative(self):
        scheduler = (REPO / "scripts" / "research" / "register_analog_shadow_task.ps1").read_text()
        self.assertIn("(Join-Path $PSScriptRoot '..\\..')", scheduler)
        self.assertIn("New-ScheduledTaskAction", scheduler)


if __name__ == "__main__":
    unittest.main()

