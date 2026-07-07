# Manual Rust Installation and Tauri Testing Guide

## Installing Rust

Since the automated installation failed, here are the manual steps to install Rust on Windows:

1. Visit the Rust website at https://www.rust-lang.org/tools/install
2. Download the Windows installer (rustup-init.exe)
3. Run the installer and follow the setup wizard
4. Choose the default installation options
5. After installation, restart your command prompt or PowerShell

## Alternative Installation Method

If the website installer doesn't work:

1. Open PowerShell as Administrator
2. Run the following command:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```
3. Then run:
   ```powershell
   irm https://github.com/rust-lang-nursery/rustup.rs/raw/master/rustup-init.sh -OutFile rustup-init.sh
   .\rustup-init.sh
   ```

## Testing the Tauri Application

After installing Rust, follow these steps to test the Tauri application:

1. Open a new command prompt or PowerShell window
2. Navigate to the ARES directory:
   ```cmd
   cd C:\Users\Sean Jenkins\ARES\src-tauri
   ```
3. Run the Tauri development server:
   ```cmd
   cargo tauri dev
   ```
   
   This will:
   - Compile the Rust application
   - Start the Tauri window
   - Connect to the ARES backend at http://localhost:8787

4. Verify that:
   - The ARES web UI loads correctly in the Tauri window
   - All functionality works as expected
   - The auto-start feature is configured properly

## Building the Windows Installer

To create a Windows installer for distribution:

1. Run the build command:
   ```cmd
   cargo tauri build
   ```
   
2. The installer will be generated in:
   ```
   src-tauri/target/release/bundle/
   ```

## Troubleshooting

If you encounter issues:

1. Ensure the ARES backend is running on port 8787:
   ```cmd
   cd C:\Users\Sean Jenkins\ARES\webui
   python server.py
   ```

2. Check that all dependencies are installed:
   ```cmd
   cargo check
   ```

3. If there are compilation errors, try updating dependencies:
   ```cmd
   cargo update
   ```

4. For Windows-specific issues, ensure WebView2 is installed:
   - Download from https://developer.microsoft.com/en-us/microsoft-edge/webview2/
   - Install the WebView2 runtime

## Development Workflow

For ongoing development:

1. Keep the ARES backend running
2. Run Tauri in development mode for hot reloading:
   ```cmd
   cargo tauri dev
   ```
3. Make changes to the configuration or Rust code as needed
4. The application will automatically reload when changes are detected

## Next Steps

After successful testing:
1. Document any issues or improvements needed
2. Consider creating a release script for easier distribution
3. Test the auto-start functionality thoroughly
4. Verify that session saving/loading works through the Tauri wrapper