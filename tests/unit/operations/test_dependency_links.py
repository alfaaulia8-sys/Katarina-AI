"""Regression tests for KATARINA GitHub dependency linkage guard."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.governance.audit_dependency_links import audit, site_target


class DependencyLinkTests(unittest.TestCase):
    def test_local_url_resolution(self):
        self.assertEqual(site_target("/research.html#calendar", "index.html"), "research.html")
        self.assertEqual(site_target("./site.js?v=2", "index.html"), "site.js")
        self.assertIsNone(site_target("https://example.org", "index.html"))
        self.assertIsNone(site_target("mailto:team@example.org", "index.html"))

    def test_missing_site_asset_is_failure(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "website").mkdir()
            (root / "website/index.html").write_text('<script src="missing.js"></script>', encoding="utf-8")
            report = audit(root, {"website/index.html"})
            self.assertEqual(report["result"], "FAIL_LOCAL_DEPENDENCY_LINKS")
            self.assertEqual(len(report["failures"]["missing_website_asset"]), 1)

    def test_missing_mql_include_is_failure(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "mt5/Experts").mkdir(parents=True)
            (root / "mt5/Experts/Main.mq5").write_text("#include <Katarina/Missing.mqh>\n", encoding="utf-8")
            report = audit(root, {"mt5/Experts/Main.mq5"})
            self.assertEqual(len(report["failures"]["missing_mql_include"]), 1)

    def test_valid_local_imports_links_and_json(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            content = {
                "src/katarina/__init__.py": "",
                "src/katarina/core/__init__.py": "",
                "src/katarina/core/engine.py": "from katarina.core import registry\n",
                "src/katarina/core/registry.py": "READY=True\n",
                "mt5/Experts/Main.mq5": "#include <Katarina/Example.mqh>\n",
                "mt5/Include/Katarina/Example.mqh": "// example",
                "website/index.html": '<script src="/site.js"></script>',
                "website/site.js": "fetch('/index.html')",
                "config/valid.json": json.dumps({"ok": True}),
            }
            for name, body in content.items():
                location = root / name
                location.parent.mkdir(parents=True, exist_ok=True)
                location.write_text(body, encoding="utf-8")
            report = audit(root, set(content))
            self.assertEqual(report["result"], "PASS_LOCAL_DEPENDENCY_LINKS")
            self.assertGreater(report["checked"]["website_links"], 0)
            self.assertGreater(report["checked"]["python_imports"], 0)
            self.assertGreater(report["checked"]["mql_includes"], 0)

    def test_invalid_json_is_failure(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "bad.json").write_text("{bad", encoding="utf-8")
            report = audit(root, {"bad.json"})
            self.assertEqual(len(report["failures"]["invalid_json"]), 1)


if __name__ == "__main__":
    unittest.main()
