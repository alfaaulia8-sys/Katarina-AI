#!/usr/bin/env python3
"""Fail-closed repository hygiene guard.

Only examines Git-tracked paths for accidental editor artifacts, binaries,
private configuration files, and empty executable source. Does not read
credential contents, contact a broker/VPS, or mutate Git.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path, PurePosixPath
import subprocess
from typing import Iterable


_JUNK_NAMES = {".ds_store", "thumbs.db", "desktop.ini"}
_JUNK_SUFFIXES = (
    ".tmp", ".temp", ".bak", ".orig", ".rej", ".swp",
    ".swo", ".pyc", ".pyo", ".stackdump",
)
_EMPTY_SOURCE_SUFFIXES = (".ps1", ".py", ".sh", ".cmd", ".bat", ".mq5", ".mqh", ".js")
_SAFE_ENV_TEMPLATES = {".env.example", ".env.sample"}


def tracked_paths(root: Path) -> list[str]:
    """Return exact index paths; ignored local build caches are not audited."""
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
            timeout=20,
        )
    except (FileNotFoundError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return []
    return [p for p in result.stdout.decode("utf-8", "surrogateescape").split("\0") if p]


def audit_tracked_files(root: Path, paths: Iterable[str]) -> tuple[list[str], list[str]]:
    """Categorize unintended tracked artifacts without reading file contents."""
    accidental: set[str] = set()
    empty_source: set[str] = set()
    for rel in paths:
        normalized = rel.replace("\\", "/")
        parts = PurePosixPath(normalized).parts
        if not parts or ".." in parts:
            accidental.add(rel)
            continue
        name = parts[-1].lower()
        lower = normalized.lower()
        is_secret_name = (name == ".env" or name.startswith(".env.")) and name not in _SAFE_ENV_TEMPLATES
        if (
            name in _JUNK_NAMES
            or name.endswith(_JUNK_SUFFIXES)
            or name.endswith("~")
            or "__pycache__" in parts
            or "node_modules" in parts
            or is_secret_name
            or lower.startswith(("build/", "dist/", "scratch/", "tmp/", "temp/"))
        ):
            accidental.add(normalized)
        path = root / normalized
        if (
            name.endswith(_EMPTY_SOURCE_SUFFIXES)
            and name != "__init__.py"
            and path.is_file()
            and path.stat().st_size == 0
        ):
            empty_source.add(normalized)
    return sorted(accidental), sorted(empty_source)


def audit(root: Path, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    root = root.resolve()
    forbidden = [
        *root.glob("ops/vps/bootstrap/**/*"),
        *root.glob("ops/vps/rescue/*.trigger"),
        *root.glob("infrastructure/legacy-vps-control/**/*"),
        root / "docs/operations/VPS_FIRST_DEVELOPMENT.md",
        root / "ops/bridge/CONTROL_TEST.txt",
    ]
    forbidden = sorted(str(p.relative_to(root)) for p in forbidden if p.is_file())
    bad_requests: list[dict] = []
    valid_requests = 0
    for p in sorted((root / "ops/vps/requests").glob("**/*.json")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root))
        try:
            request = json.loads(p.read_text(encoding="utf-8"))
            expiry = request["expires_utc"]
            expires_at = datetime.fromisoformat(expiry.replace("Z", "+00:00"))
            if expires_at.tzinfo is None:
                raise ValueError("Missing expiry timezone")
            if expires_at <= now:
                bad_requests.append({"path": rel, "reason": "expired"})
            else:
                valid_requests += 1
        except (ValueError, KeyError, TypeError, json.JSONDecodeError):
            bad_requests.append({"path": rel, "reason": "invalid request or expiry"})
    indexed = tracked_paths(root)
    accidental, empty_source = audit_tracked_files(root, indexed)
    return {
        "schema_version": 2,
        "result": (
            "PASS_REPOSITORY_HYGIENE"
            if not forbidden and not bad_requests and not accidental and not empty_source
            else "FAIL_REPOSITORY_HYGIENE"
        ),
        "checked_utc": now.isoformat(),
        "live_risk_ready": False,
        "forbidden_artifacts": forbidden,
        "expired_or_invalid_requests": bad_requests,
        "unexpired_request_count": valid_requests,
        "tracked_paths_examined": len(indexed),
        "accidental_tracked_files": accidental,
        "empty_executable_sources": empty_source,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, default=Path("build/repository-hygiene.json"))
    args = parser.parse_args()
    report = audit(args.repo_root)
    output = args.output
    if not output.is_absolute():
        output = args.repo_root / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(report["result"])
    print(
        "forbidden={} expired_or_invalid={} tracked_junk={} empty_source={}".format(
            len(report["forbidden_artifacts"]),
            len(report["expired_or_invalid_requests"]),
            len(report["accidental_tracked_files"]),
            len(report["empty_executable_sources"]),
        )
    )
    return 0 if report["result"].startswith("PASS") else 1


if __name__ == "__main__":
    raise SystemExit(main())
