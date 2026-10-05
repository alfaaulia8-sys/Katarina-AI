# VPS 2012 R2 GitHub / runtime references

Reviewed before implementing the VPS control/report bridge.

- Git for Windows prerequisites:
  https://gitforwindows.org/requirements.html
- Git for Windows requirements source:
  https://github.com/git-for-windows/git-for-windows.github.io/blob/main/content/requirements.md
- Python 3.12 Windows support:
  https://docs.python.org/3.12/using/windows.html
- MetaEditor CLI compile prior art:
  https://github.com/abhidp/metatrader5-utilities/blob/main/compile.bat
- Windows-native MT5 compile/test prior art:
  https://github.com/NadirAliOfficial/mt5-cli
- MT5 data-folder build pattern:
  https://github.com/undo83/XAUUSDTrader

KATARINA adaptation:
- no GitHub Actions runner;
- GitHub is a sparse bidirectional mailbox;
- source edits stay on VPS;
- `vps-control` is read-only to VPS;
- `vps-reports` is written only on meaningful build/error events;
- `main` is never written by the bridge;
- live-risk/live-execution authority remain false.
