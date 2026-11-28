use crate::client::translate;
#[cfg(windows)]
use crate::ipc::Data;
#[cfg(windows)]
use hbb_common::tokio;
use hbb_common::{allow_err, log};
use std::sync::{Arc, Mutex};
#[cfg(windows)]
use std::time::Duration;

pub fn start_tray() {
    if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
        #[cfg(not(target_os = "macos"))]
        {
            return;
        }
    }

    // Session 0 has no desktop: a tray an installer run over SSH or by a
    // management tool started there shows nothing (L528)
    #[cfg(windows)]
    if !shows_in_session(crate::platform::windows::get_current_process_session_id()) {
        log::info!("No tray in session 0, exit");
        return;
    }

    #[cfg(target_os = "linux")]
    crate::server::check_zombie();

    allow_err!(make_tray());
}

/// Whether a tray in the Windows session `session` can be seen: not in
/// session 0, where services and remote shells run.
#[cfg(any(windows, test))]
fn shows_in_session(session: Option<u32>) -> bool {
    session != Some(0)
}

/// How long after it starts the service looks for a person signed in
/// without a tray. An install or update ends the person's tray and starts
/// the service again (L528); a later sign-in starts the tray itself.
#[cfg(any(windows, test))]
pub const SERVICE_TRAY_WINDOW: std::time::Duration = std::time::Duration::from_secs(120);

/// Whether the service starts the tray in the session it serves, `session`,
/// `since_start` after it started, with trays running in `tray_sessions`:
/// in a session someone sees, without a tray there, soon after the start.
#[cfg(any(windows, test))]
pub fn service_starts_tray(
    session: u32,
    tray_sessions: &[u32],
    since_start: std::time::Duration,
) -> bool {
    session != u32::MAX
        && shows_in_session(Some(session))
        && since_start <= SERVICE_TRAY_WINDOW
        && !tray_sessions.contains(&session)
}

fn make_tray() -> hbb_common::ResultType<()> {
    // https://github.com/tauri-apps/tray-icon/blob/dev/examples/tao.rs
    use hbb_common::anyhow::Context;
    use tao::event_loop::{ControlFlow, EventLoopBuilder};
    use crate::tray_model::Action;
    use tray_icon::{menu::MenuEvent, TrayIcon, TrayIconBuilder, TrayIconEvent as TrayEvent};

    // Duplicated tray icons kept piling up through the blind spots of
    // `check_process("--tray", ..)`. https://github.com/rustdesk/rustdesk/issues/15689
    #[cfg(windows)]
    if !crate::platform::windows::try_lock_tray_single_instance() {
        log::info!("Another tray process is already running in this session, exit");
        return Ok(());
    }

    let icon;
    #[cfg(target_os = "macos")]
    {
        icon = include_bytes!("../res/mac-tray-dark-x2.png"); // use as template, so color is not important
    }
    #[cfg(not(target_os = "macos"))]
    {
        icon = include_bytes!("../res/tray-icon.ico");
    }

    let (icon_rgba, icon_width, icon_height) = {
        let image = load_icon_from_asset()
            .unwrap_or(image::load_from_memory(icon).context("Failed to open icon path")?)
            .into_rgba8();
        let (width, height) = image.dimensions();
        let rgba = image.into_raw();
        (rgba, width, height)
    };
    // The receiver's icon while something is new: the same with a dot
    #[cfg(not(target_os = "macos"))]
    let dot_icon = tray_icon::Icon::from_rgba(
        crate::tray_model::with_dot(
            &icon_rgba,
            icon_width,
            icon_height,
            [0xd9, 0x30, 0x25, 0xff],
            [0xff, 0xff, 0xff, 0xff],
        ),
        icon_width,
        icon_height,
    )
    .ok();
    let icon = tray_icon::Icon::from_rgba(icon_rgba, icon_width, icon_height)
        .context("Failed to open icon")?;

    let event_loop = EventLoopBuilder::new().build();
    #[cfg(target_os = "macos")]
    let mut event_loop = event_loop;

    // The entries and what the service reports: tray_menu.rs.
    let mut tray_menu = crate::tray_menu::TrayMenu::new();
    let tooltip = |count: usize, status: &str| {
        if count == 0 {
            format!("{}\n{}", crate::get_app_name(), status)
        } else {
            format!(
                "{} - {}\n{}",
                crate::get_app_name(),
                translate("Ready".to_owned()),
                translate("{".to_string() + &format!("{count}") + "} sessions"),
            )
        }
    };
    let mut _tray_icon: Arc<Mutex<Option<TrayIcon>>> = Default::default();

    let menu_channel = MenuEvent::receiver();
    let tray_channel = TrayEvent::receiver();
    #[cfg(windows)]
    let (ipc_sender, ipc_receiver) = std::sync::mpsc::channel::<Data>();

    let open_func = move || {
        if cfg!(not(feature = "flutter")) {
            crate::run_me::<&str>(vec![]).ok();
            return;
        }
        #[cfg(target_os = "macos")]
        crate::platform::macos::handle_application_should_open_untitled_file();
        #[cfg(target_os = "windows")]
        {
            // Do not use "start uni link" way, it may not work on some Windows, and pop out error
            // dialog, I found on one user's desktop, but no idea why, Windows is shit.
            // Use `run_me` instead.
            // `allow_multiple_instances` in `flutter/windows/runner/main.cpp` allows only one instance without args.
            crate::run_me::<&str>(vec![]).ok();
        }
        #[cfg(target_os = "linux")]
        {
            // Do not use "xdg-open", it won't read the config.
            if crate::dbus::invoke_new_connection(crate::get_uri_prefix()).is_err() {
                if let Ok(task) = crate::run_me::<&str>(vec![]) {
                    crate::server::CHILD_PROCESS.lock().unwrap().push(task);
                }
            }
        }
    };

    #[cfg(windows)]
    std::thread::spawn(move || {
        start_query_session_count(ipc_sender.clone());
    });
    #[cfg(windows)]
    let mut last_click = std::time::Instant::now();
    #[cfg_attr(not(windows), allow(unused_mut))]
    let mut sessions = 0;
    #[cfg(not(target_os = "macos"))]
    let mut dotted = false;
    #[cfg(target_os = "macos")]
    {
        use tao::platform::macos::EventLoopExtMacOS;
        event_loop.set_activation_policy(tao::platform::macos::ActivationPolicy::Accessory);
    }
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(
            std::time::Instant::now() + std::time::Duration::from_millis(100),
        );

        if let tao::event::Event::NewEvents(tao::event::StartCause::Init) = event {
            // for fixing https://github.com/rustdesk/rustdesk/discussions/10210#discussioncomment-14600745
            // so we start tray, but not to show it
            if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
                return;
            }
            // We create the icon once the event loop is actually running
            // to prevent issues like https://github.com/tauri-apps/tray-icon/issues/90
            let mut builder = TrayIconBuilder::new()
                .with_id(crate::get_exe_name())
                .with_menu(Box::new(tray_menu.menu.clone()))
                .with_tooltip(tooltip(0, &tray_menu.tooltip_status()))
                .with_icon(icon.clone());
            #[cfg(target_os = "macos")]
            {
                builder = builder.with_icon_as_template(true);
            }
            #[cfg(target_os = "windows")]
            {
                // Required since tray-icon 0.17
                // Fixes #15215, #15222, #15410
                builder = builder.with_menu_on_left_click(false);
            }
            let tray = builder.build();
            match tray {
                Ok(tray) => _tray_icon = Arc::new(Mutex::new(Some(tray))),
                Err(err) => {
                    log::error!("Failed to create tray icon: {}", err);
                }
            };

            // We have to request a redraw here to have the icon actually show up.
            // Tao only exposes a redraw method on the Window so we use core-foundation directly.
            #[cfg(target_os = "macos")]
            unsafe {
                use core_foundation::runloop::{CFRunLoopGetMain, CFRunLoopWakeUp};

                let rl = CFRunLoopGetMain();
                CFRunLoopWakeUp(rl);
            }
        }

        if let Ok(event) = menu_channel.try_recv() {
            match tray_menu.action(&event.id) {
                Some(Action::Open) => open_func(),
                Some(action) => tray_menu.run(action),
                None => {}
            }
        }

        let status = tray_menu.tooltip_status();
        let copied = tray_menu.just_copied();
        if let Some(menu) = tray_menu.update() {
            let _ = _tray_icon
                .lock()
                .unwrap()
                .as_mut()
                .map(|t| t.set_menu(Some(Box::new(menu))));
        }
        #[cfg(not(target_os = "macos"))]
        if (tray_menu.badge() > 0) != dotted {
            dotted = !dotted;
            let next = if dotted {
                dot_icon.clone()
            } else {
                Some(icon.clone())
            };
            if let Some(next) = next {
                let _ = _tray_icon
                    .lock()
                    .unwrap()
                    .as_mut()
                    .map(|t| t.set_icon(Some(next)));
            }
        }
        if status != tray_menu.tooltip_status() || copied != tray_menu.just_copied() {
            let text = if tray_menu.just_copied() {
                format!(
                    "{}\n{}",
                    crate::get_app_name(),
                    translate("nd-tray-id-copied".to_owned())
                )
            } else {
                tooltip(sessions, &tray_menu.tooltip_status())
            };
            let _ = _tray_icon
                .lock()
                .unwrap()
                .as_mut()
                .map(|t| t.set_tooltip(Some(text)));
        }

        if let Ok(_event) = tray_channel.try_recv() {
            #[cfg(target_os = "windows")]
            match _event {
                TrayEvent::Click {
                    button,
                    button_state,
                    ..
                } => {
                    if button == tray_icon::MouseButton::Left
                        && button_state == tray_icon::MouseButtonState::Up
                    {
                        if last_click.elapsed() < std::time::Duration::from_secs(1) {
                            return;
                        }
                        open_func();
                        last_click = std::time::Instant::now();
                    }
                }
                _ => {}
            }
        }

        #[cfg(windows)]
        if let Ok(data) = ipc_receiver.try_recv() {
            match data {
                Data::ControlledSessionCount(count) => {
                    sessions = count;
                    _tray_icon
                        .lock()
                        .unwrap()
                        .as_mut()
                        .map(|t| t.set_tooltip(Some(tooltip(count, &tray_menu.tooltip_status()))));
                }
                _ => {}
            }
        }
    });
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn start_query_session_count(sender: std::sync::mpsc::Sender<Data>) {
    let mut last_count = 0;
    loop {
        if let Ok(mut c) = crate::ipc::connect(1000, "").await {
            let mut timer = crate::rustdesk_interval(tokio::time::interval(Duration::from_secs(1)));
            loop {
                tokio::select! {
                    res = c.next() => {
                        match res {
                            Err(err) => {
                                log::error!("ipc connection closed: {}", err);
                                break;
                            }

                            Ok(Some(Data::ControlledSessionCount(count))) => {
                                if count != last_count {
                                    last_count = count;
                                    sender.send(Data::ControlledSessionCount(count)).ok();
                                }
                            }
                            _ => {}
                        }
                    }

                    _ = timer.tick() => {
                        c.send(&Data::ControlledSessionCount(0)).await.ok();
                    }
                }
            }
        }
        hbb_common::sleep(1.).await;
    }
}

fn load_icon_from_asset() -> Option<image::DynamicImage> {
    let Some(path) = std::env::current_exe().map_or(None, |x| x.parent().map(|x| x.to_path_buf()))
    else {
        return None;
    };
    #[cfg(target_os = "macos")]
    let path = path.join("../Frameworks/App.framework/Resources/flutter_assets/assets/icon.png");
    #[cfg(windows)]
    let path = path.join(r"data\flutter_assets\assets\icon.png");
    #[cfg(target_os = "linux")]
    let path = path.join(r"data/flutter_assets/assets/icon.png");
    if path.exists() {
        if let Ok(image) = image::open(path) {
            return Some(image);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    /// L528: an MSI update from an elevated SSH session left a tray in
    /// session 0, next to the person's.
    #[test]
    fn no_tray_in_session_0() {
        assert!(!super::shows_in_session(Some(0)));
        assert!(super::shows_in_session(Some(1)));
        assert!(super::shows_in_session(Some(3)));
        // Unknown session: as before
        assert!(super::shows_in_session(None));
    }

    /// L528: a quiet MSI update ended the person's tray and nothing started
    /// it again. The service, started by the update, starts it in the
    /// session it serves, once, and never a second one.
    #[test]
    fn the_service_brings_back_the_persons_tray() {
        use std::time::Duration;
        let soon = Duration::from_secs(5);
        assert!(super::service_starts_tray(1, &[], soon));
        assert!(super::service_starts_tray(2, &[1], soon));
        // A tray runs there already
        assert!(!super::service_starts_tray(1, &[1], soon));
        // Nobody signed in to see it
        assert!(!super::service_starts_tray(0, &[], soon));
        assert!(!super::service_starts_tray(u32::MAX, &[], soon));
        // Long after the start a sign-in starts the tray itself
        assert!(!super::service_starts_tray(
            1,
            &[],
            super::SERVICE_TRAY_WINDOW + Duration::from_secs(1)
        ));
    }

    /// L540: the installer started the tray with its own token, elevated
    /// after the UAC prompt. No custom action of the MSI starts the tray;
    /// the service starts it as the person.
    #[test]
    fn the_installer_starts_no_tray() {
        let wxs = include_str!("../res/msi/Package/Components/RustDesk.wxs");
        for line in wxs.lines().filter(|l| l.contains("<CustomAction ")) {
            assert!(!line.contains("--tray"), "{line}");
        }
        assert!(!wxs.contains("Action=\"LaunchAppTray\""));
    }
}
