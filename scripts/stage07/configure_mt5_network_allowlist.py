from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time
from typing import Any

from pywinauto import Desktop, keyboard


def control_snapshot(dialog: Any) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for control in dialog.descendants():
        try:
            info = control.element_info
            rows.append(
                {
                    "control_type": str(getattr(info, "control_type", "")),
                    "class_name": str(getattr(info, "class_name", "")),
                    "automation_id": str(getattr(info, "automation_id", "")),
                    "name": str(control.window_text()),
                }
            )
        except Exception as exc:
            rows.append({"error": repr(exc)})
    return rows


def sha256(path: pathlib.Path) -> str | None:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def wait_for_main_window(timeout: float = 30.0):
    deadline = time.monotonic() + timeout
    desktop = Desktop(backend="uia")
    while time.monotonic() < deadline:
        for window in desktop.windows():
            try:
                title = window.window_text()
                if "MetaTrader 5" in title and window.is_visible():
                    return window
            except Exception:
                pass
        time.sleep(0.25)
    raise RuntimeError("MetaTrader 5 main window was not found")


def wait_for_options(timeout: float = 10.0):
    deadline = time.monotonic() + timeout
    desktop = Desktop(backend="uia")
    while time.monotonic() < deadline:
        for window in desktop.windows():
            try:
                title = window.window_text().strip()
                if title == "Options" and window.is_visible():
                    return window
            except Exception:
                pass
        time.sleep(0.2)
    raise RuntimeError("MetaTrader 5 Options dialog was not found")


def text_of(control: Any) -> str:
    try:
        return control.window_text().strip()
    except Exception:
        return ""


def choose_expert_advisors(dialog: Any) -> None:
    tabs = [
        control
        for control in dialog.descendants(control_type="TabItem")
        if text_of(control) == "Expert Advisors"
    ]
    if not tabs:
        raise RuntimeError("Expert Advisors tab was not found")
    tab = tabs[0]
    try:
        tab.select()
    except Exception:
        tab.click_input()
    time.sleep(0.5)


def enable_webrequest_checkbox(dialog: Any) -> str:
    candidates = []
    for control in dialog.descendants():
        name = text_of(control)
        if "Allow WebRequest for listed URL" in name:
            candidates.append(control)
    if not candidates:
        raise RuntimeError("Allow WebRequest checkbox was not found")

    control = candidates[0]
    state = None
    try:
        state = int(control.get_toggle_state())
    except Exception:
        pass

    if state != 1:
        try:
            control.toggle()
        except Exception:
            control.click_input()
        time.sleep(0.3)

    try:
        state = int(control.get_toggle_state())
    except Exception:
        state = None
    if state not in (1, None):
        raise RuntimeError("Allow WebRequest checkbox did not become enabled")
    return text_of(control)


def find_add_row(dialog: Any):
    for control in dialog.descendants():
        name = text_of(control).lower()
        if "add new url" in name:
            return control
    return None


def add_url(dialog: Any, value: str) -> None:
    row = find_add_row(dialog)
    if row is not None:
        try:
            row.double_click_input()
        except Exception:
            row.click_input()
        time.sleep(0.2)
        keyboard.send_keys("^a")
        keyboard.write(value, with_spaces=True)
        keyboard.send_keys("{ENTER}")
        time.sleep(0.5)
        return

    # Some builds expose the insertion row as an Edit after the WebRequest
    # checkbox is enabled. Prefer an empty visible edit in the lower half.
    rect = dialog.rectangle()
    edits = []
    for control in dialog.descendants(control_type="Edit"):
        try:
            if control.is_visible() and control.is_enabled():
                crect = control.rectangle()
                if crect.top > rect.top + (rect.height() // 2):
                    edits.append(control)
        except Exception:
            pass
    if edits:
        edit = edits[-1]
        edit.set_edit_text(value)
        keyboard.send_keys("{ENTER}")
        time.sleep(0.5)
        return

    raise RuntimeError("MetaTrader URL insertion row/edit control was not found")


def visible_url_texts(dialog: Any) -> list[str]:
    values: list[str] = []
    for control in dialog.descendants():
        value = text_of(control)
        if value and (
            "127.0.0.1" in value
            or value.startswith("http://")
            or value.startswith("https://")
        ):
            values.append(value)
    return sorted(set(values))


def press_ok(dialog: Any) -> None:
    buttons = [
        control
        for control in dialog.descendants(control_type="Button")
        if text_of(control) == "OK"
    ]
    if not buttons:
        raise RuntimeError("Options OK button was not found")
    buttons[0].click_input()
    time.sleep(1.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terminal", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    evidence: dict[str, Any] = {
        "schema_version": 1,
        "proof_type": "KATARINA_MT5_NETWORK_ALLOWLIST_UI_AUTOMATION",
        "terminal": str(args.terminal),
        "requested_entries": ["127.0.0.1", "http://127.0.0.1"],
        "controls_before": [],
        "controls_after": [],
        "visible_urls": [],
        "experts_ini_sha256": None,
        "result": "FAIL",
    }

    process: subprocess.Popen[str] | None = None
    try:
        if not args.terminal.is_file():
            raise RuntimeError(f"terminal not found: {args.terminal}")

        process = subprocess.Popen(
            [str(args.terminal), "/portable"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        main_window = wait_for_main_window()
        main_window.set_focus()
        keyboard.send_keys("^o")
        dialog = wait_for_options()
        choose_expert_advisors(dialog)

        evidence["controls_before"] = control_snapshot(dialog)
        evidence["checkbox"] = enable_webrequest_checkbox(dialog)

        for entry in evidence["requested_entries"]:
            current = visible_url_texts(dialog)
            if any(entry in value for value in current):
                continue
            add_url(dialog, entry)

        evidence["visible_urls"] = visible_url_texts(dialog)
        evidence["controls_after"] = control_snapshot(dialog)

        if not any("127.0.0.1" in item for item in evidence["visible_urls"]):
            raise RuntimeError(
                "127.0.0.1 was not visible in the trusted URL list after UI entry"
            )

        press_ok(dialog)
        time.sleep(1.0)

        # Persist the security setting by closing the terminal normally.
        main_window = wait_for_main_window(timeout=10.0)
        main_window.set_focus()
        keyboard.send_keys("%{F4}")
        deadline = time.monotonic() + 10.0
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.2)
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)

        experts_ini = args.terminal.parent / "config" / "experts.ini"
        evidence["experts_ini_exists"] = experts_ini.is_file()
        evidence["experts_ini_sha256"] = sha256(experts_ini)
        evidence["result"] = "PASS_MT5_NETWORK_ALLOWLIST_UI"
        output.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
        print(json.dumps(evidence, indent=2))
        return 0
    except Exception as exc:
        evidence["error"] = repr(exc)
        output.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
        print(json.dumps(evidence, indent=2))
        return 1
    finally:
        if process is not None and process.poll() is None:
            try:
                process.terminate()
                process.wait(timeout=5)
            except Exception:
                try:
                    process.kill()
                except Exception:
                    pass


if __name__ == "__main__":
    raise SystemExit(main())
