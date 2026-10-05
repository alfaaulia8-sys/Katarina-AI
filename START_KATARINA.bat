@echo off
setlocal
cd /d "%~dp0"
title KATARINA AI - One Click Supervisor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\Start-KatarinaAll.ps1"
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" echo [KATARINA] Ready. Error Supervisor berjalan di background.
if not "%RC%"=="0" echo [KATARINA] Launcher selesai dengan code %RC%. Error sudah diantrikan untuk GitHub.
pause
exit /b %RC%
