#!/usr/bin/env python3
"""KATARINA: record a confirmed site onboarding state; never store credentials.
Use from Termux/VPS Git checkout: python3 profiles/register-site.py --domain example.com --status discovered [--sync].
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess

BASE = pathlib.Path(__file__).resolve().parent
REPO = BASE.parent
REGISTRY = BASE / "site-registry.json"
ALLOWED_STATUS = ("discovered", "signup_started", "verification_pending", "registered", "verified", "blocked", "inactive")
ALLOWED_SOURCE = ("manual", "browser_check", "email_confirmation")
DOMAIN_PATTERN = re.compile(r"^(?=.{4,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$", re.I)
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def run_git(*arguments):
    environment = dict(os.environ)
    environment["GIT_TERMINAL_PROMPT"] = "0"
    result = subprocess.run(["git", "-C", str(REPO), *arguments], capture_output=True,
                            text=True, timeout=70, env=environment)
    if result.returncode:
        raise RuntimeError("Git operation failed: " + (result.stderr or result.stdout)[:250].strip())
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description="Safely update private KATARINA site registry.")
    parser.add_argument("--domain", required=True, help="Site hostname (no URL, paths, or login tokens)")
    parser.add_argument("--status", required=True, choices=ALLOWED_STATUS)
    parser.add_argument("--email", default="", help="Site-specific contact email; never password or OTP")
    parser.add_argument("--source", choices=ALLOWED_SOURCE, default="manual")
    parser.add_argument("--sync", action="store_true", help="Commit and push this one registry file via Git")
    parser.add_argument("--dry-run", action="store_true", help="Validate only; change nothing")
    args = parser.parse_args()
    domain = args.domain.strip().lower()
    email = args.email.strip().lower()

    if not DOMAIN_PATTERN.fullmatch(domain):
        parser.error("Use a valid hostname only, e.g. example.com; no https:// or credentials")
    if email and not EMAIL_PATTERN.fullmatch(email):
        parser.error("Invalid email; never supply password, OTP, or session tokens")
    if args.dry_run:
        print(json.dumps({"valid": True, "domain": domain, "status": args.status, "dry_run": True}))
        return
    if args.sync:
        if run_git("status", "--porcelain", "--", "profiles/site-registry.json").strip():
            raise RuntimeError("Registry has uncommitted changes; resolve them before syncing")
        run_git("pull", "--ff-only", "origin", "main")

    registry = json.loads(REGISTRY.read_text(encoding="utf-8-sig"))
    platforms = registry.setdefault("platforms", [])
    now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    existing = next((x for x in platforms if x.get("domain") == domain), None)
    if existing is None:
        existing = {"domain": domain, "purpose": "job platform; classification pending"}
        platforms.append(existing)
    existing["last_known_status"] = args.status
    existing["last_checked_utc"] = now
    existing["source"] = args.source
    existing["access_policy"] = "mobile_cellular"
    existing["submit_policy"] = "manual_confirm_and_platform_rules"
    if email:
        existing["contact_email"] = email
    registry.setdefault("registrations_log", []).append({
        "domain": domain, "status": args.status, "source": args.source, "timestamp_utc": now
    })
    registry["updated_utc"] = now
    REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.sync:
        run_git("add", "--", "profiles/site-registry.json")
        run_git("commit", "-m", "registry: update onboarding for " + domain, "--only", "--", "profiles/site-registry.json")
        run_git("push", "origin", "main")
    print(json.dumps({"ok": True, "domain": domain, "status": args.status, "synced": bool(args.sync)}))


if __name__ == "__main__":
    main()
