#!/usr/bin/env python3
"""KATARINA unified bridge: Android Termux agent.
Uses the existing Katarina-VPS-Control private repository.
No shell/code execution from job payloads, secrets, or browser cookies are uploaded.
"""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
STATE = Path.home() / ".katarina-unified-bridge"
SEEN_PATH = STATE / "termux-processed.json"
SAFE_ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,89}$")


def utcnow():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def load_json(path, fallback=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return fallback


def write_json(path, value):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    temp = p.with_suffix(p.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(p)


def git(*args):
    result = subprocess.run(
        ["git", "-C", str(ROOT), "-c", "user.name=KATARINA Termux Agent",
         "-c", "user.email=termux-agent@users.noreply.github.com", *args],
        capture_output=True, text=True, timeout=45, check=False,
    )
    if result.returncode:
        raise RuntimeError("git " + " ".join(args) + " failed: " +
                           (result.stderr or result.stdout).strip()[:450])
    return result.stdout.strip()


def owned_paths():
    paths = ["status/termux.json"]
    paths += sorted(p.relative_to(ROOT).as_posix()
                    for p in (ROOT / "results").glob("*.termux.json"))
    return paths


def has_owned_changes():
    return bool(git("status", "--porcelain", "--", *owned_paths()))


def commit_owned():
    if not (ROOT / "status" / "termux.json").exists():
        return False
    paths = owned_paths()
    git("add", "--", *paths)
    if not has_owned_changes():
        return False
    git("-c", "user.name=KATARINA Termux Agent",
        "-c", "user.email=termux-agent@users.noreply.github.com",
        "commit", "-m", "termux: heartbeat and job results",
        "--", *paths)
    return True


def push_changes():
    for attempt in range(3):
        try:
            git("pull", "--rebase", "origin", "main")
            git("push", "origin", "main")
            return
        except RuntimeError:
            if attempt == 2:
                raise
            time.sleep(3)


def chrome_tab_summary():
    """Safe summary of local Debian/Termux Chrome CDP; no URLs or cookies."""
    for port in (9223, 9222):
        try:
            with urlopen("http://127.0.0.1:%d/json/list" % port, timeout=2) as r:
                data = json.load(r)
            domains = set()
            count = 0
            for tab in data:
                if tab.get("type") != "page":
                    continue
                count += 1
                hostname = urlsplit(tab.get("url", "")).hostname
                if hostname:
                    domains.add(hostname.lower())
            permitted = (
                "mql5.com", "freelancer.com", "upwork.com", "guru.com",
                "contra.com", "peopleperhour.com", "payhip.com",
                "clickworker.com", "crowdgen.com", "github.com", "truelancer.com",
            )
            marketplaces = sorted(
                host for host in domains
                if any(host == domain or host.endswith("." + domain)
                       for domain in permitted)
            )
            return {"available": True, "open_tab_count": count,
                    "browser": "debian_chromium" if port == 9223 else "termux_chrome",
                    "marketplace_domains": marketplaces[:15]}
        except Exception:
            pass
    return {"available": False, "reason": "local Chrome debugging not connected"}


def device_status():
    return {
        "timestamp_utc": utcnow(),
        "agent_version": "1.4.0",
        "target": "termux",
        "runtime": platform.system(),
        "python": platform.python_version(),
        "chrome_debugging_available": chrome_tab_summary()["available"],
        "transport": "github-private-repository",
    }


def browser_playwright_probe():
    """Read-only browser readiness probe. Never expose live URLs or secrets."""
    tool = ROOT / "agent" / "android-browser" / "browser-probe.js"
    if not tool.is_file():
        return {"available": False, "detail": "browser_probe_not_installed"}
    try:
        proc = subprocess.run(
            ["node", str(tool)],
            capture_output=True, text=True, timeout=20, check=False,
            cwd=str(tool.parent),
        )
        data = json.loads(proc.stdout.strip())
        allowed_fields = (
            "protocol", "cdp_available", "playwright_installed",
            "playwright_connected", "open_tabs", "detail",
        )
        return {key: data[key] for key in allowed_fields if key in data}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {"available": False, "detail": "local_browser_probe_failed"}

def debian_status():
    """Non-destructive check of an existing Debian PRoot installation."""
    if shutil.which("proot-distro") is None:
        return {"ready": False, "reason": "proot_distro_command_missing"}
    try:
        proc = subprocess.run(
            ["proot-distro", "login", "katarina-debian", "--", "/bin/sh", "-c",
             "test -f /etc/debian_version && printf 'DEBIAN_READY'"],
            capture_output=True, text=True, timeout=45, check=False,
        )
    except subprocess.TimeoutExpired:
        return {"ready": False, "reason": "debian_login_timeout"}
    except OSError:
        return {"ready": False, "reason": "debian_probe_failed"}
    if proc.returncode == 0 and proc.stdout.strip() == "DEBIAN_READY":
        return {"ready": True, "distro": "katarina-debian", "method": "proot-distro"}
    return {"ready": False, "reason": "debian_login_failed_or_not_installed"}


def debian_browser_request(mode, urls=None):
    """Allowed browser tasks execute INSIDE Debian; results contain no session secrets."""
    script = ROOT / "agent" / "android-browser" / "debian-browser.js"
    module_path = Path.home() / ".katarina-ai" / "browser-worker" / "node_modules"
    if not script.is_file() or not module_path.is_dir():
        return {"ok": False, "error": "DEBIAN_BROWSER_WORKER_NOT_INSTALLED"}
    if mode == "audit" and (not isinstance(urls, list) or not (1 <= len(urls) <= 3)
                             or any(not isinstance(u, str) or len(u) > 500 for u in urls)):
        return {"ok": False, "error": "INVALID_AUDIT_URLS"}
    try:
        result = subprocess.run(
            ["proot-distro", "login", "katarina-debian", "--", "/usr/bin/env",
             "NODE_PATH=" + str(module_path), "node", str(script), mode],
            input=json.dumps({"urls": urls or []}),
            text=True, capture_output=True, timeout=85, check=False,
        )
        if result.returncode:
            return {"ok": False, "error": "DEBIAN_BROWSER_WORKER_EXITED"}
        data = json.loads(result.stdout.strip())
        if not isinstance(data, dict) or not isinstance(data.get("ok"), bool):
            return {"ok": False, "error": "UNEXPECTED_BROWSER_RESULT"}
        return data
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "DEBIAN_BROWSER_TIMEOUT_OR_UNAVAILABLE"}



def debian_marketplace_scan():
    """Low-frequency public listing extraction in existing authenticated Chromium, no submissions."""
    script = ROOT / "agent" / "android-browser" / "marketplace-scan.js"
    modules = Path.home() / ".katarina-ai" / "browser-worker" / "node_modules"
    if not script.is_file() or not modules.is_dir():
        return {"ok": False, "error": "MARKETPLACE_SCANNER_UNAVAILABLE"}
    try:
        run = subprocess.run(
            ["proot-distro", "login", "katarina-debian", "--", "/usr/bin/env",
             "NODE_PATH=" + str(modules), "node", str(script), "scan"],
            text=True, capture_output=True, timeout=85, check=False,
        )
        if run.returncode:
            return {"ok": False, "error": "MARKETPLACE_SCAN_WORKER_FAILED"}
        result = json.loads(run.stdout.strip())
        return result if isinstance(result, dict) and result.get("mode") == "public_listing_scan" else {
            "ok": False, "error": "BAD_MARKETPLACE_SCAN_RESULT"
        }
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "MARKETPLACE_SCAN_TIMEOUT"}

def run_job(job):
    action = job.get("action")
    if action == "status":
        return {"ok": True, "action": action, "data": device_status()}
    if action == "debian_status":
        data = debian_status()
        return {"ok": data["ready"], "action": action, "data": data}
    if action == "debian_browser_status":
        data = debian_browser_request("status")
        return {"ok": data.get("ok") is True, "action": action, "data": data}
    if action == "debian_marketplace_scan":
        data = debian_marketplace_scan()
        return {"ok": data.get("ok") is True, "action": action, "data": data}
    if action == "debian_browser_audit":
        data = debian_browser_request("audit", job.get("urls"))
        return {"ok": data.get("ok") is True, "action": action, "data": data}
    if action == "chrome_tabs":
        return {"ok": True, "action": action, "data": chrome_tab_summary()}
    if action == "browser_probe":
        data = browser_playwright_probe()
        return {"ok": data.get("playwright_connected") is True,
                "action": action, "data": data}
    if action == "agent_capabilities":
        return {"ok": True, "action": action, "data":
                ["status", "debian_status", "debian_browser_status", "debian_browser_audit", "debian_marketplace_scan", "chrome_tabs", "browser_probe", "agent_capabilities"]}
    return {"ok": False, "action": action, "error": "Unsupported action"}


def cycle():
    STATE.mkdir(exist_ok=True, parents=True)
    cfg = load_json(ROOT / "connection.json")
    if not isinstance(cfg, dict) or cfg.get("connection_id") != "katarina-unified":
        raise RuntimeError("Missing or invalid shared connection.json")
    if cfg.get("devices", {}).get("termux", {}).get("target") != "termux":
        raise RuntimeError("Termux target missing in shared connection.json")

    # Commit prior local results before syncing to avoid overwriting them.
    commit_owned()
    push_changes()
    seen = set(load_json(SEEN_PATH, []))
    heartbeat_file = ROOT / "status" / "termux.json"
    heartbeat_seconds = max(60, int(cfg.get("heartbeat_seconds", 300)))
    if not heartbeat_file.exists() or time.time() - heartbeat_file.stat().st_mtime >= heartbeat_seconds:
        write_json(heartbeat_file, device_status())

    for path in sorted((ROOT / "jobs").glob("*.json")):
        if not SAFE_ID.fullmatch(path.stem) or path.stem in seen:
            continue
        job = load_json(path)
        if not isinstance(job, dict):
            continue
        if job.get("target") not in ("termux", "android"):
            # Untargeted/legacy jobs belong only to VPS.
            continue
        result = run_job(job)
        result.update({"job_id": path.stem, "target": "termux",
                       "timestamp_utc": utcnow()})
        write_json(ROOT / "results" / (path.stem + ".termux.json"), result)
        seen.add(path.stem)
        write_json(SEEN_PATH, sorted(seen))
    commit_owned()
    push_changes()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true",
                        help="Process one cycle then exit")
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    lock_handle = open(STATE / "termux-agent.lock", "a+", encoding="utf-8")
    try:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("A TermuxAgent instance is already running; duplicate stopped.",
              file=sys.stderr, flush=True)
        return 3
    while True:
        try:
            cycle()
            print(utcnow() + " termux cycle OK", flush=True)
        except Exception as error:
            print(utcnow() + " termux cycle ERROR: " + str(error),
                  file=sys.stderr, flush=True)
            if args.once:
                return 2
        if args.once:
            return 0
        config = load_json(ROOT / "connection.json", {})
        seconds = max(30, min(600, int(config.get("poll_seconds", 60))))
        time.sleep(seconds)


if __name__ == "__main__":
    sys.exit(main())
