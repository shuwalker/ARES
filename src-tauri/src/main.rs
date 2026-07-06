#![cfg_attr(
  all(not(debug_assertions), target_os = "windows"),
  windows_subsystem = "windows"
)]

use tauri::Manager;

#[tauri::command]
fn show_window(window: tauri::Window) {
  let _ = window.show();
  let _ = window.set_focus();
}

fn main() {
  tauri::Builder::default()
    .plugin(tauri_plugin_autostart::init(None, Some("ARES")))
    .invoke_handler(tauri::generate_handler![show_window])
    .on_system_tray_event(|app, event| match event {
      tauri::SystemTrayEvent::LeftClick { .. } => {
        if let Some(window) = app.get_window("main") {
          let _ = window.show();
          let _ = window.set_focus();
        }
      }
      tauri::SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
        "show_hide" => {
          if let Some(window) = app.get_window("main") {
            if window.is_visible().ok() == Some(true) && window.is_focused().ok() == Some(true) {
              let _ = window.hide();
            } else {
              let _ = window.show();
              let _ = window.set_focus();
            }
          }
        }
        "quit" => {
          std::process::exit(0);
        }
        _ => {}
      },
      _ => {}
    })
    .on_window_event(|event| match event.event() {
      tauri::WindowEvent::CloseRequested { api, .. } => {
        // Hide to tray instead of closing on Windows
        api.prevent_close();
        let _ = event.window().hide();
      }
      _ => {}
    })
    .system_tray(tauri::SystemTray::new().with_menu(
      tauri::SystemTrayMenu::new()
        .add_item(tauri::CustomMenuItem::new("show_hide".into(), "Show / Hide"))
        .add_item(tauri::CustomMenuItem::new("quit".into(), "Quit")),
    ))
    .setup(|app| {
      // Enable tray; in release mode on Windows start minimized to tray
      if cfg!(target_os = "windows") && !cfg!(debug_assertions) {
        if let Some(window) = app.get_window("main") {
          let _ = window.hide();
        }
      }
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
