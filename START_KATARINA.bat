@echo off
setlocal
cd /d "%~dp0"
title KATARINA PC Test - LIVE OFF
where py.exe >nul 2>nul
if errorlevel 1 goto UsePython
py -3.12 "%~dp0katarina_pc.py" test %*
goto Finished
:UsePython
python "%~dp0katarina_pc.py" test %*
:Finished
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo [KATARINA] Belum lulus. Periksa pesan di atas. Code %RC%.
if not "%KATARINA_NO_PAUSE%"=="1" pause
exit /b %RC%
