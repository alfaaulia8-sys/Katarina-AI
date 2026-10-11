@echo off
set "PYTHONPATH=C:\KatarinaDev\github-main\src"
"C:\KatarinaDev\brain-runtime\Scripts\python.exe" "C:\KatarinaDev\github-main\scripts\ai\run_readonly_decisions.py" > "C:\KatarinaDev\artifacts\decision-observer\last-run.log" 2>&1
exit /b %ERRORLEVEL%
