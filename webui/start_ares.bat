@echo off
REM ARES Web UI — one-click launcher for Windows
REM Download this file, double-click it. That's all.

setlocal enabledelayedexpansion
cd /d "%~dp0"

REM === If we're not inside the repo, download it ===
if not exist "server.py" (
    echo.
    echo === ARES Web UI ===
    echo.
    
    REM Check for git, fall back to ZIP download
    where git >nul 2>&1
    if not errorlevel 1 (
        echo [..] Cloning ARES...
        if exist "..\ARES" ( cd ..\ARES & git pull ) else ( git clone https://github.com/shuwalker/ARES.git ..\ARES )
        cd ..\ARES\webui
    ) else (
        echo [..] Downloading ARES...
        powershell -Command "Invoke-WebRequest -Uri 'https://github.com/shuwalker/ARES/archive/refs/heads/main.zip' -OutFile '%TEMP%\ARES.zip'"
        powershell -Command "Expand-Archive -Path '%TEMP%\ARES.zip' -DestinationPath '%TEMP%\ARES-tmp' -Force"
        xcopy /E /I /Y "%TEMP%\ARES-tmp\ARES-main\webui" "%~dp0" >nul
        rmdir /S /Q "%TEMP%\ARES-tmp" 2>nul
        del "%TEMP%\ARES.zip" 2>nul
    )
    
    REM Re-launch from the right location
    start "" "%~f0"
    exit /b
)

REM === Find or install Python ===
set "PYTHON="
where python >nul 2>&1
if not errorlevel 1 ( set "PYTHON=python" ) else (
    where python3 >nul 2>&1
    if not errorlevel 1 ( set "PYTHON=python3" )
)
if not defined PYTHON (
    echo [..] Installing Python 3...
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe' -OutFile '%TEMP%\python-install.exe'"
    start /wait "" "%TEMP%\python-install.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
    del "%TEMP%\python-install.exe" 2>nul
    REM Refresh PATH
    for /f "tokens=*" %%a in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path','User')"') do set "PATH=%%a;%PATH%"
    where python >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Python install failed. Install manually from https://python.org
        pause & exit /b 1
    )
    set "PYTHON=python"
)

REM === Auto-install deps if missing ===
if not exist ".venv\Scripts\python.exe" (
    echo [..] Setting up virtual environment...
    "%PYTHON%" -m venv .venv
    echo [..] Installing dependencies...
    .venv\Scripts\python -m pip install -q -r "%~dp0requirements.txt"
    .venv\Scripts\python -m pip install -q hermes-agent 2>nul
    if not exist ".env" if exist ".env.example" copy ".env.example" ".env" >nul
)

REM === Start server ===
set HERMES_WEBUI_HOST=0.0.0.0
set HERMES_WEBUI_PORT=8787
echo.
echo === ARES Web UI === Open http://localhost:8787
echo.
.venv\Scripts\python server.py
if errorlevel 1 ( echo [ERROR] Server crashed. & pause )
