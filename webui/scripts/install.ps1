<#
.SYNOPSIS
    ARES Web UI — one-line PowerShell installer for Windows
.DESCRIPTION
    iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)
    Clones the repo, sets up Python venv, installs deps, and starts the server.
    The WebUI onboarding wizard handles the rest (provider, password, etc.).
.PARAMETER Port
    TCP port (default: 8787)
.PARAMETER Host
    Bind address (default: 0.0.0.0)
.PARAMETER InstallDir
    Install directory (default: $env:USERPROFILE\ARES)
.PARAMETER Branch
    Git branch (default: main)
#>

param(
    [int]$Port = 0,
    [string]$Host = '',
    [string]$InstallDir = '',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/shuwalker/ARES.git'
$PortFinal = if ($Port) { $Port } else { 8787 }
$HostFinal = if ($Host) { $Host } else { '0.0.0.0' }
$InstallDirFinal = if ($InstallDir) { $InstallDir } else { Join-Path $env:USERPROFILE 'ARES' }

Write-Host "┌────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│           ARES Web UI Installer            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# === Check prerequisites ===
$Python = $null
foreach ($cmd in @('python3', 'python', 'py')) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) { $Python = $found.Source; break }
}
if (-not $Python) {
    Write-Error "Python 3 is required. Install from https://python.org"
    exit 1
}
Write-Host "✓ Found Python: $Python" -ForegroundColor Green

# === Check git ===
$Git = Get-Command git -ErrorAction SilentlyContinue
if (-not $Git) {
    Write-Error "git is required. Install from https://git-scm.com"
    exit 1
}

# === Clone / update repo ===
if (Test-Path $InstallDirFinal) {
    Write-Host "→ Updating existing install at $InstallDirFinal..." -ForegroundColor Cyan
    Push-Location $InstallDirFinal
    git stash --include-untracked 2>$null
    git checkout $Branch 2>$null
    git pull origin $Branch
} else {
    Write-Host "→ Cloning ARES into $InstallDirFinal..." -ForegroundColor Cyan
    git clone --depth 1 --branch $Branch $RepoUrl $InstallDirFinal
    Push-Location $InstallDirFinal
}
Push-Location webui

# === Create venv ===
if (-not (Test-Path ".venv\Scripts\python.exe")) {
    Write-Host "→ Creating virtual environment..." -ForegroundColor Cyan
    & $Python -m venv .venv
}

# === Install deps ===
Write-Host "→ Installing Python dependencies..." -ForegroundColor Cyan
.venv\Scripts\pip install -q -r requirements.txt
.venv\Scripts\pip install -q hermes-agent 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ hermes-agent not found via pip (WebUI will still work for basic use)" -ForegroundColor Yellow
}

# === Create .env if missing ===
if (-not (Test-Path ".env") -and (Test-Path ".env.example")) {
    Copy-Item ".env.example" ".env"
    Write-Host "✓ Created .env from template" -ForegroundColor Green
}

# === Start ===
Write-Host ""
Write-Host "✓ Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  ARES Web UI"
Write-Host "  Open: http://localhost:$PortFinal"
Write-Host "  Ctrl+C to stop"
Write-Host ""

$env:HERMES_WEBUI_HOST = $HostFinal
$env:HERMES_WEBUI_PORT = "$PortFinal"
.venv\Scripts\python server.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "Server exited with code $LASTEXITCODE" -ForegroundColor Red
    Read-Host "Press Enter to exit"
}
