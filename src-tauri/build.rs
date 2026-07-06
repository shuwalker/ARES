use std::process::Command;

fn main() {
  // When building in release mode, bundle the web UI
  if cfg!(feature = "custom-protocol") {
    // This is where we would build the web UI if we were bundling it
    // For now, we're just connecting to the local server
    println!("cargo:warning=Building in release mode - connecting to local ARES server at 127.0.0.1:8787");
  }
  
  // Build the web UI assets
  println!("cargo:warning=Building web UI assets...");
  let status = Command::new("npm")
    .args(&["run", "build"])
    .current_dir("../webui")
    .status();
    
  if let Err(e) = status {
    println!("cargo:warning=Failed to build web UI: {}", e);
  }
}