#!/usr/bin/env python3
"""GitHub-only source linkage audit. No terminal, brokerage, or live trading."""
from __future__ import annotations
import argparse
import ast
from collections import Counter
from html.parser import HTMLParser
import json
import posixpath
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit


class LocalLinks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.targets = []

    def handle_starttag(self, tag, attrs):
        key = {"a": "href", "link": "href", "script": "src", "img": "src",
               "source": "src", "iframe": "src"}.get(tag.lower())
        if key:
            self.targets.extend(value for name, value in attrs if name == key and value)


def site_target(url: str, source: str) -> str | None:
    if not url or url.startswith(("#", "//", "{", "<%")):
        return None
    parsed = urlsplit(url)
    if parsed.scheme or parsed.netloc or not parsed.path or "{" in parsed.path:
        return None
    raw = parsed.path
    if raw == "/":
        return "index.html"  # Website root is the homepage, not a missing file.
    return posixpath.normpath(
        raw.lstrip("/") if raw.startswith("/")
        else posixpath.join(posixpath.dirname(source), raw)
    )


def audit(root: Path, tracked: set[str]) -> dict:
    root = root.resolve()
    available = {name for name in tracked if (root / name).is_file()}
    counts = Counter()
    failures = {key: [] for key in ("missing_file", "invalid_json", "invalid_python",
                "missing_python_import", "missing_mql_include", "missing_website_asset")}
    packages = {p.removeprefix("src/").removesuffix(".py").replace("/", ".")
                for p in available if p.startswith("src/katarina/") and p.endswith(".py")}
    packages.update(p.rsplit(".", 1)[0] for p in list(packages) if "." in p)
    packages.add("katarina")
    assets = {p.removeprefix("website/") for p in available if p.startswith("website/")}

    def check_url(raw, from_path):
        relative = site_target(raw, from_path.removeprefix("website/"))
        if relative is None:
            return
        if relative == ".." or relative.startswith("../") or relative not in assets:
            failures["missing_website_asset"].append(f"{from_path}: {raw} => {relative}")
        else:
            counts["website_links"] += 1

    for name in sorted(tracked):
        file = root / name
        if name not in available:
            failures["missing_file"].append(name)
            continue
        counts["tracked_files"] += 1
        if name.endswith(".json"):
            try:
                json.loads(file.read_text(encoding="utf-8-sig"))
                counts["json_files"] += 1
            except (UnicodeError, ValueError) as exc:
                failures["invalid_json"].append(f"{name}: {exc}")
        if name.endswith(".py"):
            try:
                tree = ast.parse(file.read_text(encoding="utf-8-sig"), filename=name)
                counts["python_files"] += 1
            except (SyntaxError, UnicodeError) as exc:
                failures["invalid_python"].append(f"{name}: {exc}")
                continue
            if name.startswith("src/katarina/"):
                module = name.removeprefix("src/").removesuffix(".py").replace("/", ".")
                package = module.removesuffix(".__init__") if name.endswith("/__init__.py") else module.rsplit(".", 1)[0]
                for node in ast.walk(tree):
                    imports = []
                    if isinstance(node, ast.Import):
                        imports = [a.name for a in node.names if a.name.startswith("katarina.")]
                    elif isinstance(node, ast.ImportFrom):
                        if node.level:
                            parts = package.split(".")
                            up = node.level - 1
                            if up >= len(parts):
                                failures["missing_python_import"].append(f"{name}:{node.lineno}: import escapes package")
                                continue
                            imports = [".".join(parts[:len(parts)-up] + (node.module.split(".") if node.module else []))]
                        elif node.module and node.module.startswith("katarina."):
                            imports = [node.module]
                    for import_name in imports:
                        if import_name.startswith("katarina.") and import_name not in packages:
                            failures["missing_python_import"].append(f"{name}:{node.lineno}: {import_name}")
                        elif import_name.startswith("katarina."):
                            counts["python_imports"] += 1
        if name.startswith("mt5/") and name.endswith((".mq5", ".mqh")):
            source = file.read_text(encoding="utf-8-sig", errors="replace")
            for match in re.finditer(r'^\s*#include\s*([<"])([^>"\r\n]+)[>"]', source, re.M):
                style, include = match.groups()
                include = include.replace("\\", "/")
                if style == "<" and not include.startswith("Katarina/"):
                    continue  # MetaEditor platform/third-party include, verified by native compiler.
                referenced = posixpath.normpath(
                    "mt5/Include/" + include if style == "<"
                    else posixpath.join(posixpath.dirname(name), include))
                if referenced not in available:
                    failures["missing_mql_include"].append(f"{name}: {include} => {referenced}")
                else:
                    counts["mql_includes"] += 1
        if name.startswith("website/") and name.endswith(".html"):
            p = LocalLinks()
            p.feed(file.read_text(encoding="utf-8-sig", errors="replace"))
            for href in p.targets:
                check_url(href, name)
        if name.startswith("website/") and name.endswith(".js"):
            source = file.read_text(encoding="utf-8-sig", errors="replace")
            for match in re.finditer(r'''fetch\(\s*(["'])(/[^"']+)\1''', source):
                check_url(match.group(2), name)

    problems = {k: v for k, v in failures.items() if v}
    return {
        "schema_version": 1,
        "result": "PASS_LOCAL_DEPENDENCY_LINKS" if not problems else "FAIL_LOCAL_DEPENDENCY_LINKS",
        "checked": dict(counts),
        "failures": problems,
        "live_execution_enabled": False,
        "mt5_runtime_validated": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, default=Path("build/validation/dependency-links.json"))
    options = parser.parse_args()
    root = options.repo_root.resolve()
    tracked_raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"], timeout=20)
    tracked = {p.decode("utf-8", "surrogateescape").replace("\\", "/")
               for p in tracked_raw.split(b"\0") if p}
    result = audit(root, tracked)
    destination = options.output if options.output.is_absolute() else root / options.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(result["result"], result["checked"])
    for category, details in result["failures"].items():
        for finding in details[:12]:
            print(category, finding)
    return 0 if result["result"].startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
