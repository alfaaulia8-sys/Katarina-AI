@echo off
setlocal
cd /d "%~dp0"
title KATARINA AI VPS Installer - Windows Server 2012 R2

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator permission...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OneClick-KatarinaVpsInstaller.ps1"
set EXITCODE=%ERRORLEVEL%

echo.
if "%EXITCODE%"=="0" (
    echo ============================================================
    echo KATARINA INSTALLATION FINISHED
    echo ============================================================
) else (
    echo ============================================================
    echo KATARINA INSTALLATION FAILED - see message above
    echo ============================================================
)

echo.
pause
exit /b %EXITCODE%
