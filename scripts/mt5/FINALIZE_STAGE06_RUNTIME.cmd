@echo off
setlocal
cd /d "%~dp0"
title KATARINA AI - Stage 06 Runtime Finalizer

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Stage06RuntimeInteractive.ps1"
set EXITCODE=%ERRORLEVEL%

echo.
if "%EXITCODE%"=="0" (
  echo ============================================================
  echo STAGE 06 RUNTIME FINALIZER COMPLETE
  echo Return to ChatGPT and type: cek Stage 06 runtime
  echo ============================================================
) else (
  echo ============================================================
  echo STAGE 06 RUNTIME FINALIZER STOPPED
  echo Read the error above. No trading orders were submitted.
  echo ============================================================
)
echo.
pause
exit /b %EXITCODE%
