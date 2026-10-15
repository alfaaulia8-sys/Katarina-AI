@echo off
setlocal
cd /d "%~dp0"
title KATARINA PC Test - LIVE OFF
python -c "import sys; sys.exit(sys.version_info[:2] != (3, 12))" >nul 2>nul
if not errorlevel 1 goto UsePython
where py.exe >nul 2>nul
if errorlevel 1 goto MissingPython
py -3.12 "%~dp0katarina_pc.py" test %*
goto Finished
:UsePython
python "%~dp0katarina_pc.py" test %*
goto Finished
:MissingPython
echo [KATARINA] Install Python 3.12 64-bit lalu jalankan kembali.
if not "%KATARINA_NO_PAUSE%"=="1" pause
exit /b 2
:Finished
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo [KATARINA] Belum lulus. Periksa pesan di atas. Code %RC%.
if not "%KATARINA_NO_PAUSE%"=="1" pause
exit /b %RC%
