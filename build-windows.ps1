# Build script for ARES Tauri app on Windows

# Check if Rust is installed
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Rust..."
    Invoke-Expression "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
}

# Install Tauri CLI
Write-Host "Installing Tauri CLI..."
cargo install tauri-cli

# Build the application
Write-Host "Building ARES desktop app..."
cargo tauri build

Write-Host "Build complete. Installer can be found in src-tauri/target/release/bundle/"