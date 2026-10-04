from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import time
from typing import Any

from pywinauto import Desktop, keyboard


def text_of(control: Any) -> str:
    try:
        return control.window_text().strip()
    except Exception:
        return ""


def window_snapshot(backend: str = "win32") -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        for window in Desktop(backend=backend).windows():
            try:
                rows.append(
                    {
                        "title": window.window_text(),
                        "class_name": window.class_name(),
                        "process_id": int(window.process_id()),
                        "visible": bool(window.is_visible()),
                        "enabled": bool(window.is_enabled()),
                    }
                )
            except Exception as exc:
                rows.append({"error": repr(exc)})
    except Exception as exc:
        rows.append({"desktop_error": repr(exc)})
    return rows


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


def process_windows(pid: int, backend: str = "win32") -> list[Any]:
    result: list[Any] = []
    for window in Desktop(backend=backend).windows():
        try:
            if int(window.process_id()) == pid and window.is_visible():
                result.append(window)
        except Exception:
            pass
    return result


def wait_for_main_window(pid: int, timeout: float = 45.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        candidates = process_windows(pid, "win32")
        for window in candidates:
            try:
                title = window.window_text()
                if "MetaTrader 5" in title:
                    return window
            except Exception:
                pass
        # Some MT5 builds omit the product name from the account/chart title.
        for window in candidates:
            try:
                cls = window.class_name()
                if "MetaQuotes" in cls or "MetaTrader" in cls:
                    return window
            except Exception:
                pass
        time.sleep(0.25)
    raise RuntimeError("MetaTrader 5 main window was not found for launched process")


def dismiss_first_run_dialogs(pid: int) -> list[str]:
    dismissed: list[str] = []
    safe_titles = (
        "Open an Account",
        "Authorization",
        "Login",
        "Warning",
        "MetaTrader 5",
    )
    for _ in range(4):
        changed = False
        for window in process_windows(pid, "win32"):
            try:
                title = window.window_text().strip()
                if title == "Options":
                    continue
                if any(token.lower() in title.lower() for token in safe_titles):
                    # Never close the actual main frame. Only close dialog-class windows.
                    cls = window.class_name()
                    if cls in {"#32770", "Dialog"}:
                        window.set_focus()
                        keyboard.send_keys("{ESC}")
                        dismissed.append(title)
                        changed = True
                        time.sleep(0.5)
            except Exception:
                pass
        if not changed:
            break
    return dismissed


def wait_for_options(pid: int, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for backend in ("win32", "uia"):
            for window in process_windows(pid, backend):
                try:
                    title = window.window_text().strip()
                    if title == "Options" or title.endswith(" - Options"):
                        return window
                except Exception:
                    pass
        time.sleep(0.2)
    raise RuntimeError("MetaTrader 5 Options dialog was not found")


def open_options(main_window: Any, pid: int) -> tuple[Any, str]:
    attempts: list[tuple[str, Any]] = []

    def menu_attempt() -> None:
        main_window.set_focus()
        main_window.menu_select("Tools->Options")

    def alt_menu_attempt() -> None:
        main_window.set_focus()
        keyboard.send_keys("%t")
        time.sleep(0.4)
        keyboard.send_keys("o")

    def ctrl_attempt() -> None:
        main_window.set_focus()
        keyboard.send_keys("^o")

    attempts.extend(
        [
            ("win32_menu_tools_options", menu_attempt),
            ("alt_tools_options", alt_menu_attempt),
            ("ctrl_o", ctrl_attempt),
        ]
    )

    errors: list[str] = []
    for name, action in attempts:
        try:
            action()
            return wait_for_options(pid, timeout=8.0), name
        except Exception as exc:
            errors.append(f"{name}:{exc!r}")
            time.sleep(0.5)

    raise RuntimeError("Unable to open MT5 Options dialog; " + " | ".join(errors))


def find_webrequest_control(dialog: Any):
    for backend in ("win32", "uia"):
        try:
            d = Desktop(backend=backend).window(handle=dialog.handle)
            for control in d.descendants():
                if "Allow WebRequest for listed URL" in text_of(control):
                    return control
        except Exception:
            pass
    return None


def choose_expert_advisors(dialog: Any) -> str:
    # Prefer the native Win32 tab control. MT5's Options window does not always
    # expose TabItem children through UI Automation on hosted Windows runners.
    try:
        win = Desktop(backend="win32").window(handle=dialog.handle)
        for tab in win.descendants(class_name="SysTabControl32"):
            try:
                count = int(tab.tab_count())
                names = [str(tab.get_tab_text(i)).strip() for i in range(count)]
                for index, name in enumerate(names):
                    if name == "Expert Advisors":
                        tab.select(index)
                        time.sleep(0.5)
                        if find_webrequest_control(dialog) is not None:
                            return "win32_tabcontrol"
            except Exception:
                pass
    except Exception:
        pass

    # Fallback: cycle the tab control and identify the Expert Advisors page by
    # its unique WebRequest checkbox, so localization/accessibility quirks in
    # the tab label do not matter.
    dialog.set_focus()
    for index in range(16):
        if find_webrequest_control(dialog) is not None:
            return f"keyboard_cycle_{index}"
        keyboard.send_keys("^{TAB}")
        time.sleep(0.35)

    raise RuntimeError("Expert Advisors page/WebRequest control was not found")

def enable_webrequest_checkbox(dialog: Any) -> str:
    control = find_webrequest_control(dialog)
    if control is None:
        raise RuntimeError("Allow WebRequest checkbox was not found")

    state = None
    for method in ("get_toggle_state", "get_check_state"):
        try:
            state = int(getattr(control, method)())
            break
        except Exception:
            pass

    if state != 1:
        try:
            control.toggle()
        except Exception:
            try:
                control.check_by_click()
            except Exception:
                control.click_input()
        time.sleep(0.4)

    verified = None
    for method in ("get_toggle_state", "get_check_state"):
        try:
            verified = int(getattr(control, method)())
            break
        except Exception:
            pass
    if verified not in (1, None):
        raise RuntimeError("Allow WebRequest checkbox did not become enabled")
    return text_of(control)


def find_add_row(dialog: Any):
    uia = Desktop(backend="uia").window(handle=dialog.handle)
    for control in uia.descendants():
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

    # Current MT5 builds expose the URL editor as a SysListView32 containing
    # an empty insertion ListItem. Double-clicking that row creates the inline
    # edit control. This is more reliable than searching for an Edit before
    # edit mode is active.
    for backend in ("uia", "win32"):
        try:
            d = Desktop(backend=backend).window(handle=dialog.handle)
            lists = []
            for control in d.descendants():
                try:
                    info = control.element_info
                    control_type = str(getattr(info, "control_type", ""))
                    class_name = str(getattr(info, "class_name", ""))
                    automation_id = str(getattr(info, "automation_id", ""))
                    if (
                        control_type == "List"
                        or class_name == "SysListView32"
                        or automation_id == "10191"
                    ):
                        lists.append(control)
                except Exception:
                    pass

            for list_control in lists:
                items = []
                try:
                    items = list_control.descendants(control_type="ListItem")
                except Exception:
                    pass
                if not items:
                    try:
                        items = list_control.children()
                    except Exception:
                        items = []

                target = items[-1] if items else list_control
                try:
                    target.double_click_input()
                except Exception:
                    target.click_input()
                    keyboard.send_keys("{F2}")
                time.sleep(0.35)

                # Inline edit exists only after the ListView item enters edit mode.
                inline = None
                try:
                    uia = Desktop(backend="uia").window(handle=dialog.handle)
                    edits = [
                        edit for edit in uia.descendants(control_type="Edit")
                        if edit.is_visible() and edit.is_enabled()
                    ]
                    if edits:
                        inline = edits[-1]
                except Exception:
                    pass

                if inline is not None:
                    try:
                        inline.set_edit_text(value)
                    except Exception:
                        inline.click_input()
                        keyboard.send_keys("^a")
                        keyboard.write(value, with_spaces=True)
                else:
                    keyboard.send_keys("^a")
                    keyboard.write(value, with_spaces=True)

                keyboard.send_keys("{ENTER}")
                time.sleep(0.6)
                return
        except Exception:
            pass

    raise RuntimeError("MetaTrader URL insertion ListView could not enter edit mode")

def visible_url_texts(dialog: Any) -> list[str]:
    uia = Desktop(backend="uia").window(handle=dialog.handle)
    values: list[str] = []
    for control in uia.descendants():
        value = text_of(control)
        if value and (
            "127.0.0.1" in value
            or value.startswith("http://")
            or value.startswith("https://")
        ):
            values.append(value)
    return sorted(set(values))


def press_ok(dialog: Any) -> None:
    uia = Desktop(backend="uia").window(handle=dialog.handle)
    buttons = [
        control
        for control in uia.descendants(control_type="Button")
        if text_of(control) == "OK"
    ]
    if buttons:
        buttons[0].click_input()
        time.sleep(1.0)
        return
    dialog.set_focus()
    keyboard.send_keys("{ENTER}")
    time.sleep(1.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terminal", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    evidence: dict[str, Any] = {
        "schema_version": 2,
        "proof_type": "KATARINA_MT5_NETWORK_ALLOWLIST_UI_AUTOMATION",
        "terminal": str(args.terminal),
        "requested_entries": ["127.0.0.1", "http://127.0.0.1"],
        "windows_before": [],
        "windows_on_failure": [],
        "dismissed_first_run_dialogs": [],
        "open_method": None,
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
        evidence["terminal_pid"] = process.pid
        main_window = wait_for_main_window(process.pid)
        evidence["main_window_title"] = main_window.window_text()
        evidence["main_window_class"] = main_window.class_name()
        evidence["windows_before"] = window_snapshot()
        evidence["dismissed_first_run_dialogs"] = dismiss_first_run_dialogs(process.pid)

        main_window = wait_for_main_window(process.pid, timeout=10.0)
        dialog, method = open_options(main_window, process.pid)
        evidence["open_method"] = method
        evidence["expert_page_method"] = choose_expert_advisors(dialog)

        uia_dialog = Desktop(backend="uia").window(handle=dialog.handle)
        evidence["controls_before"] = control_snapshot(uia_dialog)
        evidence["checkbox"] = enable_webrequest_checkbox(dialog)

        for entry in evidence["requested_entries"]:
            current = visible_url_texts(dialog)
            if any(entry in value for value in current):
                continue
            add_url(dialog, entry)

        evidence["visible_urls"] = visible_url_texts(dialog)
        evidence["controls_after"] = control_snapshot(
            Desktop(backend="uia").window(handle=dialog.handle)
        )

        if not any("127.0.0.1" in item for item in evidence["visible_urls"]):
            raise RuntimeError(
                "127.0.0.1 was not visible in the trusted URL list after UI entry"
            )

        press_ok(dialog)
        time.sleep(1.0)

        main_window = wait_for_main_window(process.pid, timeout=10.0)
        main_window.set_focus()
        keyboard.send_keys("%{F4}")
        deadline = time.monotonic() + 12.0
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
        evidence["windows_on_failure"] = window_snapshot()
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
