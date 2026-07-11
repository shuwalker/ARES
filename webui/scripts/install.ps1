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
    Backend mode: auto, hermes, jros, or hybrid (default: auto)
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
    $SelectedBackend = 'hermes'
    if ($JrosDetected) {
        Write-Host "JROS detected. Use JROS as the primary ARES backend? (default: No)" -ForegroundColor Yellow
        $response = Read-Host "  [y/N]"
        if ($response -match '^[yY]') {
            $SelectedBackend = 'jros'
        }
    }
}
switch ($SelectedBackend) {
    'hermes' { }
    'jros' { }
    'hybrid' { }
    default {
        Write-Error "✗ Invalid backend mode: $Backend (expected auto, hermes, jros, or hybrid)"
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

Write-Host "Installing Hermes Agent..."
& $VenvPython -m pip install hermes-agent 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ hermes-agent not found via pip" -ForegroundColor Yellow
    Write-Host "Trying git install..."
    & $VenvPython -m pip install "git+https://github.com/nousresearch/hermes-agent.git" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Could not install hermes-agent. WebUI will have limited functionality." -ForegroundColor Yellow
        Write-Host "  Install manually: pip install hermes-agent"
    }
}
Write-Host "✓ All dependencies installed" -ForegroundColor Green

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
Write-Host "    cd $WebuiDir && .venv\Scripts\python server.py"

if (-not $SkipSetup) {
    Write-Host "  The onboarding wizard will open in your browser."
}

# Auto-start if interactive and not skipped
if ($Host.UI.RawUI -and -not $SkipSetup -and -not $NoStart) {
    Write-Host "Starting ARES Web UI..." -ForegroundColor Cyan
    $env:HERMES_WEBUI_HOST = $HostFinal
    $env:HERMES_WEBUI_PORT = "$PortFinal"
    & $VenvPython (Join-Path $WebuiDir 'server.py')
} elseif ($NoStart) {
    Write-Host "→ To start the server later, run:" -ForegroundColor Cyan
    Write-Host "  cd $WebuiDir && `$env:HERMES_WEBUI_HOST=`"$HostFinal`" `$env:HERMES_WEBUI_PORT=`"$PortFinal`" .venv\Scripts\python server.py"
}
