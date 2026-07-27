<#
.SYNOPSIS
    ARES Web UI Installer for Windows
.DESCRIPTION
    iex (irm https://raw.githubusercontent.com/shuwalker/ARES/main/webui/scripts/install.ps1)
    Clones the repo, sets up Python venv, installs deps, and starts the server.
.PARAMETER Port
    TCP port (default: 8787)
.PARAMETER Host
    Bind address (default: 0.0.0.0)
.PARAMETER InstallDir
    Install directory (default: $env:USERPROFILE\.ares\webui)
.PARAMETER Branch
    Git branch (default: main)
.PARAMETER SkipSetup
    Skip the setup wizard
.PARAMETER Backend
    Backend mode: auto, ares, jros, or hybrid (default: auto)
.PARAMETER NoStart
    Skip auto-starting the server after installation
#>

param(
    [int]$Port = 0,
    [string]$Host = '',
    [string]$InstallDir = '',
    [string]$Branch = 'main',
    [switch]$SkipSetup,
    [string]$Backend = 'auto',
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/shuwalker/ARES.git'
$AresHome = if ($env:ARES_HOME) { $env:ARES_HOME } else { Join-Path $env:USERPROFILE '.ares' }
$InstallDirFinal = if ($InstallDir) { $InstallDir } else { $AresHome }
$PortFinal = if ($Port) { $Port } elseif ($env:ARES_WEBUI_PORT) { $env:ARES_WEBUI_PORT } else { 8787 }
$HostFinal = if ($Host) { $Host } elseif ($env:ARES_WEBUI_HOST) { $env:ARES_WEBUI_HOST } else { '0.0.0.0' }
$WebuiDir = Join-Path $InstallDirFinal 'webui'

Write-Host ""
Write-Host "┌────────────────────────────────────────────┐" -ForegroundColor Magenta
Write-Host "│           ARES Web UI Installer           │" -ForegroundColor Magenta
Write-Host "├────────────────────────────────────────────┤" -ForegroundColor Magenta
Write-Host "│  Artificial Reasoning Entity System        │" -ForegroundColor Magenta
Write-Host "└────────────────────────────────────────────┘" -ForegroundColor Magenta
Write-Host ""

# === Check prerequisites ===
Write-Host "→ Checking prerequisites..." -ForegroundColor Cyan

$Git = Get-Command git -ErrorAction SilentlyContinue
if (-not $Git) {
    Write-Error "✗ Git is required. Install from https://git-scm.com"
    exit 1
}
Write-Host "✓ Git $(& git --version) found" -ForegroundColor Green

$Python = $null
foreach ($cmd in @('python3', 'python', 'py')) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) { $Python = $found.Source; break }
}
if (-not $Python) {
    Write-Error "✗ Python 3.10+ is required. Install from https://python.org"
    exit 1
}
$PyVersion = & $Python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
Write-Host "✓ Python $PyVersion found" -ForegroundColor Green

$Node = Get-Command node -ErrorAction SilentlyContinue
$Npm = Get-Command npm -ErrorAction SilentlyContinue
if (-not $Node -or -not $Npm) {
    Write-Error "✗ Node.js and npm are required to build the ARES frontend. Install Node.js 20+ from https://nodejs.org"
    exit 1
}
$NodeMajor = [int]((& node -p "process.versions.node.split('.')[0]").Trim())
if ($NodeMajor -lt 20) {
    Write-Error "✗ Node.js 20 or newer is required (found $(& node --version))."
    exit 1
}
Write-Host "✓ Node.js $(& node --version) found" -ForegroundColor Green

# === JROS detection ===
function Detect-JROS {
    $jaegerHome = if ($env:ARES_JAEGER_HOME) { $env:ARES_JAEGER_HOME } `
        elseif ($env:JAEGER_HOME) { $env:JAEGER_HOME } `
        else { Join-Path $env:USERPROFILE 'jaeger' }
    $jaegerExe = Join-Path $jaegerHome 'jaeger.exe'
    if (Test-Path $jaegerExe) {
        Write-Host "✓ JROS detected at $jaegerHome" -ForegroundColor Green
        return $true
    } else {
        Write-Host "→ JROS not detected at $jaegerHome" -ForegroundColor Cyan
        return $false
    }
}
$JrosDetected = Detect-JROS

# Resolve backend mode
$SelectedBackend = $Backend.ToLower()
if ($SelectedBackend -eq 'auto') {
    $SelectedBackend = 'ares'
    if ($JrosDetected) {
        Write-Host "JROS detected. Use JROS as the primary ARES backend? (default: No)" -ForegroundColor Yellow
        $response = Read-Host "  [y/N]"
        if ($response -match '^[yY]') {
            $SelectedBackend = 'jros'
        }
    }
}
switch ($SelectedBackend) {
    'ares' { }
    'jros' { }
    'hybrid' { }
    default {
        Write-Error "✗ Invalid backend mode: $Backend (expected auto, ares, jros, or hybrid)"
        exit 1
    }
}

# === Clone / update repo ===
Write-Host "→ Installing to $InstallDirFinal..." -ForegroundColor Cyan

if (Test-Path $InstallDirFinal) {
    if (Test-Path (Join-Path $InstallDirFinal '.git')) {
        Write-Host "Existing installation found, updating..." -ForegroundColor Cyan
        Push-Location $InstallDirFinal
        $dirty = & git status --porcelain
        if ($dirty) {
            Write-Host "Local changes detected, stashing before update..." -ForegroundColor Yellow
            & git stash push --include-untracked -m "ares-install-autostash-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        & git remote set-branches origin $Branch 2>$null
        & git fetch origin $Branch
        & git checkout $Branch
        & git pull --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠ Fast-forward not possible; resetting to origin/$Branch..." -ForegroundColor Yellow
            & git reset --hard "origin/$Branch"
        }
    } else {
        Write-Error "Directory exists but is not a git repository: $InstallDirFinal"
        exit 1
    }
} else {
    $parent = Split-Path $InstallDirFinal -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Write-Host "Cloning ARES Web UI..." -ForegroundColor Cyan
    & git clone --depth 1 --branch $Branch $RepoUrl $InstallDirFinal
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone repository"
        exit 1
    }
}
Push-Location $WebuiDir
Write-Host "✓ Repository ready" -ForegroundColor Green

# === Create venv ===
Write-Host "→ Creating virtual environment..." -ForegroundColor Cyan
if (Test-Path ".venv\Scripts\python.exe") {
    Write-Host "Virtual environment already exists, recreating..."
    Remove-Item -Recurse -Force ".venv" -ErrorAction SilentlyContinue
}
& $Python -m venv .venv
Write-Host "✓ Virtual environment ready" -ForegroundColor Green

# === Install deps ===
Write-Host "→ Installing dependencies..." -ForegroundColor Cyan
$VenvPython = Join-Path (Get-Location) '.venv\Scripts\python.exe'

& $VenvPython -m pip install --upgrade pip -q

Write-Host "Installing WebUI Python dependencies..."
& $VenvPython -m pip install -r (Join-Path $WebuiDir 'requirements.txt')
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install WebUI dependencies"
    exit 1
}

Write-Host "Building React frontend..."
Push-Location (Join-Path $WebuiDir 'frontend')
try {
    & npm ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw "React production build failed" }
} finally {
    Pop-Location
}

Write-Host "Installing Ares Agent..."
& $VenvPython -m pip install ares-agent 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ ares-agent not found via pip" -ForegroundColor Yellow
    Write-Host "Trying git install..."
    & $VenvPython -m pip install "git+https://github.com/nousresearch/ares-agent.git" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Could not install ares-agent. WebUI will have limited functionality." -ForegroundColor Yellow
        Write-Host "  Install manually: pip install ares-agent"
    }
}
Write-Host "✓ All dependencies installed and frontend built" -ForegroundColor Green

# === Setup config ===
Write-Host "→ Preparing configuration..." -ForegroundColor Cyan
if (-not (Test-Path ".env") -and (Test-Path ".env.example")) {
    Copy-Item ".env.example" ".env"
    Write-Host "✓ Created .env from template" -ForegroundColor Green
}
$stateDir = Join-Path $AresHome 'webui'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }

# Write backend settings
$settingsPath = Join-Path $stateDir 'settings.json'
$settings = @{}
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch {
        $settings = @{}
    }
}
$settings['ares_backend'] = $SelectedBackend
$settings | ConvertTo-Json -Depth 4 | Out-File $settingsPath -Encoding UTF8
Write-Host "✓ Configured ARES backend: $SelectedBackend" -ForegroundColor Green
Write-Host "✓ Configuration ready" -ForegroundColor Green

# === Complete ===
Write-Host ""
Write-Host "✓ ARES Web UI installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Start the server:"
Write-Host "    cd $WebuiDir && .venv\Scripts\python -m uvicorn fastapi_app.main:app --host $HostFinal --port $PortFinal --no-server-header"

if (-not $SkipSetup) {
    Write-Host "  The onboarding wizard will open in your browser."
}

# Auto-start if interactive and not skipped
if ($Host.UI.RawUI -and -not $SkipSetup -and -not $NoStart) {
    Write-Host "Starting ARES Web UI..." -ForegroundColor Cyan
    $env:ARES_WEBUI_HOST = $HostFinal
    $env:ARES_WEBUI_PORT = "$PortFinal"
    Push-Location $WebuiDir
    try {
        & $VenvPython -m uvicorn fastapi_app.main:app --host $HostFinal --port $PortFinal --no-server-header
    } finally {
        Pop-Location
    }
} elseif ($NoStart) {
    Write-Host "→ To start the server later, run:" -ForegroundColor Cyan
    Write-Host "  cd $WebuiDir && `$env:ARES_WEBUI_HOST=`"$HostFinal`" `$env:ARES_WEBUI_PORT=`"$PortFinal`" .venv\Scripts\python -m uvicorn fastapi_app.main:app --host $HostFinal --port $PortFinal --no-server-header"
}
