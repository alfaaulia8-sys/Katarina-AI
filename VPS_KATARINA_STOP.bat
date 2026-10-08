@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\vps2012\Katarina-Vps2012.ps1" -Mode Stop
pause
