@echo off
for %%I in ("%~dp0..\..") do set "KATARINA_REPO=%%~fI"
set "PYTHONPATH=%KATARINA_REPO%\src"
"C:\KatarinaDev\brain-runtime\Scripts\python.exe" "%KATARINA_REPO%\scripts\ai\run_readonly_decisions.py" > "C:\KatarinaDev\artifacts\decision-observer\last-run.log" 2>&1
exit /b %ERRORLEVEL%
