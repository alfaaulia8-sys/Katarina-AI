@echo off
setlocal
cd /d "%~dp0"
title KATARINA VPS - GitHub Connection Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\vps2012\Test-KatarinaVpsBridge.ps1"
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" echo [KATARINA] VPS-GitHub handshake PASS.
if not "%RC%"=="0" echo [KATARINA] Handshake gagal. Kirim screenshot error ini.
pause
exit /b %RC%
