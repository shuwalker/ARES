use std::process::Command;

fn main() {
  // When building in release mode with the Tauri CLI, ensure the web UI has
  // its static assets prepared. The server also serves directly from
  // webui/static/ so this step is a build-time hint; failure is non-fatal.
  println!("cargo:warning=Preparing web UI assets for Tauri bundle...");
  let _ = Command::new("python")
    .args(["server.py", "preflight"])
    .current_dir("..")
    .status();

  // Placed here so cargo sees the distDir files; actual bundling is handled
  // by tauri.conf.json → "distDir": "../webui".
  if cfg!(feature = "custom-protocol") {
    println!("cargo:warning=Tauri custom-protocol build: shipping bundled web assets.");
  }
}
