// ARES Tauri desktop shell — library entry point.
// All app logic lives here; main.rs is a thin wrapper that calls app_lib::run().

use tauri::{
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Manager,
};

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec![]),
        ))
        .setup(|app| {
            let show = MenuItem::with_id(app, "show_hide", "Show / Hide", true, None::<&str>)
                .expect("failed to create show menu item");
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)
                .expect("failed to create quit menu item");
            let menu = Menu::with_items(app, &[&show, &quit]).expect("failed to build tray menu");

            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show_hide" => tray_show_hide(app),
                    "quit" => tray_quit(app),
                    other => eprintln!("unhandled tray menu item: {other:?}"),
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: tauri::tray::MouseButton::Left,
                        button_state: tauri::tray::MouseButtonState::Up,
                        ..
                    } = event
                    {
                        tray_show_hide(&tray.app_handle());
                    }
                })
                .build(app)
                .expect("failed to build tray icon");

            // Start minimized to tray in Windows release mode
            #[cfg(target_os = "windows")]
            if !cfg!(debug_assertions) {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
            }

            Ok(())
        })
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = window.hide();
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn tray_show_hide(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn tray_quit(app: &tauri::AppHandle) {
    app.exit(0);
}