"""Prevent CI request storms by checking all repository workflow triggers.

The regression protects expensive historical/Windows workflows from
accidentally becoming push or PR event fans. No Github network access.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
WORKFLOWS=ROOT/".github"/"workflows"
AUTOMATIC={
    "katarina-body-ci.yml":{"push","pull_request"},
    "stage35-tester-safety.yml":{"push","pull_request"},
    "katarina-hotnews.yml":{"schedule"},
}

def events(source: str) -> set[str]:
    lines=source.splitlines()
    found=False
    result=set()
    for line in lines:
        if re.fullmatch(r"on:\s*",line):
            found=True
            continue
        if not found:continue
        if line.strip() and not line.startswith((" ","\t","#")):
            break
        match=re.match(r"^  (push|pull_request|schedule|workflow_dispatch|workflow_run|repository_dispatch|issue_comment):",line)
        if match:result.add(match.group(1))
    return result

class TestActionRequestFanout(unittest.TestCase):
    def test_only_one_main_push_ci_and_scoped_native_tester(self):
        found=set()
        for path in WORKFLOWS.glob("*.yml"):
            source=path.read_text(encoding="utf-8")
            allowed=AUTOMATIC.get(path.name,set())
            live=events(source)
            self.assertTrue(live,"Workflow must declare an explicit event: "+path.name)
            self.assertEqual(live-{"workflow_dispatch"},allowed,
                             "Unexpected unattended CI webhook: "+path.name)
            if "workflow_dispatch" not in live:
                self.assertIn(path.name,AUTOMATIC)
            found.add(path.name)
        self.assertEqual(set(AUTOMATIC).intersection(found),set(AUTOMATIC))

    def test_primary_ci_has_concurrency_cancel_and_avoids_docs_noise(self):
        source=(WORKFLOWS/"katarina-body-ci.yml").read_text()
        self.assertIn("cancel-in-progress: true",source)
        self.assertIn("paths-ignore:",source)
        self.assertIn("'docs/**'",source)
        self.assertIn("'website/hot-news.json'",source)

    def test_native_tester_has_pr_scoped_and_manual_vps_only(self):
        st=(WORKFLOWS/"stage35-tester-safety.yml").read_text()
        on=st.split("on:",1)[1].split("permissions:",1)[0]
        self.assertIn("  pull_request:\n    paths:",on)
        self.assertIn("  push:\n    branches: [main]\n    paths:",on)
        for workflow in ("katarina-vps-lab.yml","katarina-vps-low-memory-rescue.yml"):
            source=(WORKFLOWS/workflow).read_text()
            self.assertEqual(events(source),{"workflow_dispatch"})
            self.assertIn("if: github.ref == 'refs/heads/main'",source)

if __name__=="__main__":
    unittest.main()
