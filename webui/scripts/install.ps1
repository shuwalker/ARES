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
#>

param(
    [int]$Port = 0,
    [string]$Host = '',
    [string]$InstallDir = '',
    [string]$Branch = 'main',
    [switch]$SkipSetup
)

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/shuwalker/ARES.git'
$AresHome = if ($env:ARES_HOME) { $env:ARES_HOME } else { Join-Path $env:USERPROFILE '.ares' }
$InstallDirFinal = if ($InstallDir) { $InstallDir } else { Join-Path $AresHome 'webui' }
$PortFinal = if ($Port) { $Port } elseif ($env:ARES_WEBUI_PORT) { $env:ARES_WEBUI_PORT } else { 8787 }
$HostFinal = if ($Host) { $Host } elseif ($env:ARES_WEBUI_HOST) { $env:ARES_WEBUI_HOST } else { '0.0.0.0' }

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
Push-Location $InstallDirFinal
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
& $VenvPython -m pip install -r (Join-Path $InstallDirFinal 'requirements.txt')
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
Write-Host "✓ Configuration ready" -ForegroundColor Green

# === Complete ===
Write-Host ""
Write-Host "✓ ARES Web UI installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Start the server:"
Write-Host "    cd $InstallDirFinal && .venv\Scripts\python server.py"
Write-Host ""
Write-Host "  Or set env and run:"
Write-Host "    `$env:HERMES_WEBUI_HOST='$HostFinal'"
Write-Host "    `$env:HERMES_WEBUI_PORT='$PortFinal'"
Write-Host "    $InstallDirFinal\.venv\Scripts\python $InstallDirFinal\server.py"
Write-Host ""
Write-Host "  Then open: http://localhost:$PortFinal"
Write-Host ""
Write-Host "  For remote access over Tailscale:"
Write-Host "    tailscale serve --https=$PortFinal reset"
Write-Host "    # Access via http://<tailscale-ip>:$PortFinal"
Write-Host ""

if (-not $SkipSetup) {
    Write-Host "  The onboarding wizard will guide you through setup when you open the browser."
}

# Auto-start if interactive
if ($Host.UI.RawUI -and -not $SkipSetup) {
    Write-Host "Starting ARES Web UI..." -ForegroundColor Cyan
    $env:HERMES_WEBUI_HOST = $HostFinal
    $env:HERMES_WEBUI_PORT = "$PortFinal"
    & $VenvPython (Join-Path $InstallDirFinal 'server.py')
}
