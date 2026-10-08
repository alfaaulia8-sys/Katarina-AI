@echo off
setlocal
cd /d "%~dp0"
title KATARINA AI - VPS 2012 R2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\vps2012\Katarina-Vps2012.ps1" -Mode Setup
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" echo [KATARINA] VPS setup/build selesai. Bridge berjalan di background.
if not "%RC%"=="0" echo [KATARINA] Setup/build berhenti dengan code %RC%. Lihat C:\KatarinaRuntime.
pause
exit /b %RC%
