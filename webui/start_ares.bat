@echo off
REM ARES Web UI — Windows launcher
REM Double-click this file. If ARES isn't installed yet, it installs everything.
REM Then starts the server.

setlocal enabledelayedexpansion

set "ARES_HOME=%USERPROFILE%\.ares"
set "INSTALL_DIR=%ARES_HOME%"
set "WEBUI_DIR=%ARES_HOME%\webui"
set "PORT=8787"
set "HOST=0.0.0.0"

REM === If not inside the repo, check if installed or clone ===
if not exist "%~dp0fastapi_app\main.py" (
    if exist "%WEBUI_DIR%\fastapi_app\main.py" (
        cd /d "%WEBUI_DIR%"
    ) else (
        echo.
        echo === ARES Web UI Installer ===
        echo.
        where git >nul 2>&1
        if errorlevel 1 (
            echo [..] Git not found. Downloading ARES directly...
            if not exist "%ARES_HOME%" mkdir "%ARES_HOME%"
            powershell -Command "Invoke-WebRequest -Uri 'https://github.com/shuwalker/ARES/archive/refs/heads/main.zip' -OutFile '%TEMP%\ARES.zip'"
            powershell -Command "Expand-Archive -Path '%TEMP%\ARES.zip' -DestinationPath '%TEMP%\ARES-tmp' -Force"
            if exist "%INSTALL_DIR%" rmdir /S /Q "%INSTALL_DIR%"
            move "%TEMP%\ARES-tmp\ARES-main\webui" "%INSTALL_DIR%" >nul
            rmdir /S /Q "%TEMP%\ARES-tmp" 2>nul
            del "%TEMP%\ARES.zip" 2>nul
        ) else (
            echo [..] Cloning ARES Web UI...
            if not exist "%ARES_HOME%" mkdir "%ARES_HOME%"
            if exist "%INSTALL_DIR%" (
                cd /d "%INSTALL_DIR%"
                git pull
            ) else (
                git clone --depth 1 https://github.com/shuwalker/ARES.git "%INSTALL_DIR%"
            )
        )
        cd /d "%WEBUI_DIR%"
    )
)

REM === Find Python ===
set "PYTHON="
where python >nul 2>&1
if not errorlevel 1 ( set "PYTHON=python" ) else (
    where python3 >nul 2>&1
    if not errorlevel 1 ( set "PYTHON=python3" )
)
if not defined PYTHON (
    echo [..] Python not found. Downloading Python 3.12...
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe' -OutFile '%TEMP%\python-install.exe'"
    start /wait "" "%TEMP%\python-install.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
    del "%TEMP%\python-install.exe" 2>nul
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
    .venv\Scripts\python -m pip install -q ares-agent 2>nul
    if not exist ".env" if exist ".env.example" copy ".env.example" ".env" >nul
)

REM === Start server ===
set ARES_WEBUI_HOST=%HOST%
set ARES_WEBUI_PORT=%PORT%
echo.
echo === ARES Web UI === Open http://localhost:%PORT%
echo.
.venv\Scripts\python -m uvicorn fastapi_app.main:app --host %ARES_WEBUI_HOST% --port %ARES_WEBUI_PORT% --no-server-header
if errorlevel 1 ( echo [ERROR] Server crashed. & pause )
