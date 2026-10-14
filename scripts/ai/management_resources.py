"""Low-overhead Management resource guard (observes only; no deletion/kill).

This is management infrastructure, NOT an additional trading AI agent.
"""
from __future__ import annotations

import ctypes
import os
from pathlib import Path
import shutil


def available_ram_mb() -> int | None:
    """Best-effort host RAM availability using only the Python standard library."""
    if os.name == "nt":
        class MemoryStatus(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]
        value = MemoryStatus()
        value.dwLength = ctypes.sizeof(MemoryStatus)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(value)):
            return None
        return value.ullAvailPhys // (1024 * 1024)
    info = Path("/proc/meminfo")
    if info.is_file():
        for line in info.read_text(encoding="ascii").splitlines():
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) // 1024
    return None


def resource_policy(free_ram_mb: int | None, free_disk_mb: int) -> dict:
    """Recommend safe Management worker count; never touch MT5 or other apps."""
    if free_ram_mb is not None and free_ram_mb < 0 or free_disk_mb < 0:
        raise ValueError("invalid_resource_metrics")
    if free_ram_mb is None:
        workers, status = 1, "RAM_UNVERIFIED"
    elif free_ram_mb < 384:
        workers, status = 1, "LOW_RAM_GUARD"
    elif free_ram_mb < 1024:
        workers, status = 2, "LIMITED_RAM"
    else:
        workers, status = 4, "NORMAL"
    if free_disk_mb < 512:
        workers, status = 1, "LOW_DISK_GUARD"
    return {
        "status": status,
        "recommended_local_max_workers": workers,
        "available_ram_mb": free_ram_mb,
        "free_disk_mb": free_disk_mb,
        "processes_terminated": 0,
        "files_deleted": 0,
    }


def observe_workspace(root: Path) -> dict:
    if not root.is_dir():
        raise ValueError("workspace_not_found")
    disk = shutil.disk_usage(root)
    return resource_policy(available_ram_mb(), disk.free // (1024 * 1024))


def safe_cache_inventory(root: Path, *, max_paths: int = 200) -> dict:
    """List deletable-by-policy *candidates*; NEVER perform deletion here."""
    if not root.is_dir() or not 1 <= max_paths <= 2000:
        raise ValueError("invalid_cache_scan")
    root = root.resolve(strict=True)
    found = []
    # Only developer cache directories; no knowledge, tick, logs or trading state.
    for base, dirs, _ in os.walk(root):
        here = Path(base)
        if len(here.relative_to(root).parts) > 12:
            dirs[:] = []
            continue
        for name in list(dirs):
            if name in {".git", "data", "memory", "backups", "mt5", "broker", "artifacts"}:
                dirs.remove(name)
            elif name in {"__pycache__", ".pytest_cache", ".mypy_cache"}:
                candidate = here / name
                if not candidate.is_symlink():
                    found.append(candidate.relative_to(root).as_posix())
                dirs.remove(name)
                if len(found) >= max_paths:
                    return {"cache_candidates": found, "truncated": True, "deleted": 0}
    return {"cache_candidates": found, "truncated": False, "deleted": 0}
