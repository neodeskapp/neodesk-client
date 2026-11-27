//! The tray icon of a kept quick support app (Windows): Open, Remove
//! NeoDesk Quick Support and Quit. It runs on a thread of its own, since
//! the window's thread belongs to Flutter.

use std::time::{Duration, Instant};

use hbb_common::{anyhow::Context, log, ResultType};

use crate::client::translate;

/// What the tray's entries do.
pub struct Actions {
    pub open: fn(),
    pub remove: fn(),
    pub quit: fn(),
}

/// Shows the tray icon once per process.
pub fn start(actions: Actions) {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(move || {
        std::thread::spawn(move || {
            if let Err(err) = run(actions) {
                log::error!("Quick support tray: {err}");
            }
        });
    });
}

fn icon() -> ResultType<tray_icon::Icon> {
    let next_to_exe = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join(r"data\flutter_assets\assets\icon.png")))
        .filter(|path| path.is_file())
        .and_then(|path| image::open(path).ok());
    let image = match next_to_exe {
        Some(image) => image,
        None => image::load_from_memory(include_bytes!("../../res/tray-icon.ico"))
            .context("tray icon")?,
    }
    .into_rgba8();
    let (width, height) = image.dimensions();
    Ok(tray_icon::Icon::from_rgba(image.into_raw(), width, height)?)
}

fn run(actions: Actions) -> ResultType<()> {
    use tao::{
        event::{Event, StartCause},
        event_loop::{ControlFlow, EventLoopBuilder},
        platform::windows::EventLoopBuilderExtWindows,
    };
    use tray_icon::{
        menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem},
        MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent,
    };

    let icon = icon()?;
    let open = MenuItem::new(translate("Open".to_owned()), true, None);
    let remove = MenuItem::new(translate("nd-qs-tray-remove".to_owned()), true, None);
    let quit = MenuItem::new(translate("Quit".to_owned()), true, None);
    let menu = Menu::new();
    menu.append(&open)?;
    menu.append(&remove)?;
    menu.append(&PredefinedMenuItem::separator())?;
    menu.append(&quit)?;
    let (open, remove, quit) = (open.id().clone(), remove.id().clone(), quit.id().clone());

    let event_loop = EventLoopBuilder::new().with_any_thread(true).build();
    let mut tray: Option<TrayIcon> = None;
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(Instant::now() + Duration::from_millis(100));
        if let Event::NewEvents(StartCause::Init) = event {
            // Made once the loop runs (tauri-apps/tray-icon#90)
            match TrayIconBuilder::new()
                .with_menu(Box::new(menu.clone()))
                .with_tooltip(translate("nd-qs-window-title".to_owned()))
                .with_icon(icon.clone())
                .with_menu_on_left_click(false)
                .build()
            {
                Ok(icon) => tray = Some(icon),
                Err(err) => log::error!("Quick support tray icon: {err}"),
            }
        }
        if let Ok(event) = MenuEvent::receiver().try_recv() {
            if event.id == open {
                (actions.open)();
            } else if event.id == remove {
                (actions.remove)();
            } else if event.id == quit {
                tray.take();
                (actions.quit)();
            }
        }
        if let Ok(TrayIconEvent::Click {
            button: MouseButton::Left,
            button_state: MouseButtonState::Up,
            ..
        }) = TrayIconEvent::receiver().try_recv()
        {
            (actions.open)();
        }
    })
}
