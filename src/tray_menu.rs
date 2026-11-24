//! The tray menu's items and what they do. tray_model.rs decides which
//! entries the menu has; this file keeps the menu in step with what the
//! service reports, from a thread that asks it every second, so opening
//! the menu never waits for the service or the server.

use crate::client::translate;
use crate::ipc::Data;
use crate::tray_model::{self, Action, Facts, Item, Offers, Online, Standing};
use hbb_common::{config, log, tokio};
use std::{
    collections::HashMap,
    sync::mpsc,
    time::{Duration, Instant},
};
use tray_icon::menu::{Menu, MenuId, MenuItem, PredefinedMenuItem};

/// How long the ID entry reads "ID copied" after a click.
const COPIED_FOR: Duration = Duration::from_secs(3);

/// What the service told the tray last.
#[derive(Clone, Debug, PartialEq)]
struct Report {
    facts: Facts,
    id: String,
}

/// One line of the menu as shown: its action (None for a separator), its
/// text and whether it can be clicked.
type Shown = (Option<Action>, String, bool);

pub struct TrayMenu {
    pub menu: Menu,
    items: Vec<(Action, MenuItem)>,
    shown: Vec<Shown>,
    /// The report or the copied state changed since the menu was made.
    changed: bool,
    report: Report,
    reports: mpsc::Receiver<Report>,
    offers: Offers,
    copied_at: Option<Instant>,
    clipboard: Option<arboard::Clipboard>,
    /// Menus replaced while one may still be open.
    retired: Vec<Menu>,
}

impl TrayMenu {
    /// The menu for what this process knows now; a thread keeps it up to
    /// date from the service.
    pub fn new() -> Self {
        let (sender, reports) = mpsc::channel();
        std::thread::spawn(move || watch(sender));
        let mut menu = TrayMenu {
            menu: Menu::new(),
            items: Vec::new(),
            shown: Vec::new(),
            changed: true,
            report: Report {
                facts: facts_of(&local_options(), Online::Connecting, ""),
                id: String::new(),
            },
            reports,
            offers: Offers {
                settings: !config::is_disable_settings() && !config::is_incoming_only(),
                stop_service: crate::ui_interface::get_builtin_option(
                    config::keys::OPTION_HIDE_STOP_SERVICE,
                ) != "Y",
            },
            copied_at: None,
            clipboard: None,
            retired: Vec::new(),
        };
        menu.update();
        menu
    }

    /// Takes the service's latest report and changes the menu to match.
    /// Returns the new menu when its entries changed, for the tray icon.
    pub fn update(&mut self) -> Option<Menu> {
        while let Ok(report) = self.reports.try_recv() {
            self.report = report;
            self.changed = true;
        }
        if self
            .copied_at
            .is_some_and(|at| at.elapsed() >= COPIED_FOR)
        {
            self.copied_at = None;
            self.changed = true;
        }
        if !self.changed {
            return None;
        }
        self.changed = false;
        let shown = self.lines();
        if shown == self.shown {
            return None;
        }
        let same_entries = shown.len() == self.shown.len()
            && shown.iter().zip(&self.shown).all(|(a, b)| a.0 == b.0);
        if same_entries {
            for ((_, text, enabled), (_, item)) in
                shown.iter().filter(|s| s.0.is_some()).zip(&self.items)
            {
                item.set_text(text);
                item.set_enabled(*enabled);
            }
            self.shown = shown;
            return None;
        }
        self.rebuild(&shown);
        self.shown = shown;
        Some(self.menu.clone())
    }

    fn lines(&self) -> Vec<Shown> {
        let items = tray_model::menu(
            &self.report.facts,
            &self.report.id,
            crate::VERSION,
            self.offers,
        );
        items
            .into_iter()
            .map(|item| match item {
                Item::Separator => (None, String::new(), false),
                Item::Entry {
                    action,
                    key,
                    arg,
                    enabled,
                } => {
                    let text = if action == Action::CopyId && self.copied_at.is_some() {
                        translate("nd-tray-id-copied".to_owned())
                    } else {
                        translate(key.to_owned()).replace("{}", &arg)
                    };
                    (Some(action), text, enabled)
                }
            })
            .collect()
    }

    fn rebuild(&mut self, shown: &[Shown]) {
        let menu = Menu::new();
        let mut items = Vec::new();
        for (action, text, enabled) in shown {
            match action {
                Some(action) => {
                    let item = MenuItem::new(text, *enabled, None);
                    menu.append(&item).ok();
                    items.push((*action, item));
                }
                None => {
                    menu.append(&PredefinedMenuItem::separator()).ok();
                }
            }
        }
        // The old menu may be open right now: keep it alive until the next
        // change.
        let old = std::mem::replace(&mut self.menu, menu);
        if !self.shown.is_empty() {
            self.retired.truncate(1);
            self.retired.push(old);
        }
        self.items = items;
    }

    /// The action of the clicked menu item.
    pub fn action(&self, id: &MenuId) -> Option<Action> {
        self.items
            .iter()
            .find(|(_, item)| item.id() == id)
            .map(|(action, _)| *action)
    }

    /// The first line of the menu, for the tooltip.
    pub fn status(&self) -> String {
        self.shown
            .first()
            .map(|(_, text, _)| text.clone())
            .unwrap_or_default()
    }

    /// Runs the actions that need nothing from the tray icon itself.
    pub fn run(&mut self, action: Action) {
        match action {
            Action::CopyId => self.copy_id(),
            Action::Settings => open_link("settings"),
            Action::About => open_link("settings/about"),
            Action::StopService => set_paused(true),
            Action::AcceptConnections => set_paused(false),
            Action::Status | Action::Open => {}
        }
    }

    fn copy_id(&mut self) {
        let id = tray_model::format_id(&self.report.id);
        // Kept: on X11 the copied text lives only as long as its clipboard.
        if self.clipboard.is_none() {
            match arboard::Clipboard::new() {
                Ok(clipboard) => self.clipboard = Some(clipboard),
                Err(err) => log::warn!("Failed to open the clipboard from the tray: {err}"),
            }
        }
        let Some(clipboard) = self.clipboard.as_mut() else {
            return;
        };
        match clipboard.set_text(id.replace(' ', "")) {
            Ok(()) => {
                self.copied_at = Some(Instant::now());
                self.changed = true;
                #[cfg(windows)]
                notify_copied(&id);
            }
            Err(err) => log::warn!("Failed to copy the ID from the tray: {err}"),
        }
    }

    /// Whether the ID entry says "ID copied" right now.
    pub fn just_copied(&self) -> bool {
        self.copied_at.is_some()
    }
}

/// Pauses or resumes connections to this computer with the service's option
/// stop-service, which the service already obeys: it stops registering with
/// the server, ends the sessions and closes the direct port, and keeps
/// running, so no permission prompt comes up. The option is in the
/// service's config, so a pause outlasts a restart.
fn set_paused(paused: bool) {
    std::thread::spawn(move || {
        crate::ipc::set_option("stop-service", if paused { "Y" } else { "" });
    });
}

/// Opens the main window at a page, with a link the window handles:
/// neodesk://settings and neodesk://settings/about.
fn open_link(page: &str) {
    let link = format!("{}{}", crate::get_uri_prefix(), page);
    #[cfg(target_os = "windows")]
    {
        // As Open does: a new process hands the link to the open window.
        crate::run_me(vec![link.as_str()]).ok();
    }
    #[cfg(target_os = "linux")]
    {
        if crate::dbus::invoke_new_connection(link.clone()).is_err() {
            if let Ok(task) = crate::run_me(vec![link.as_str()]) {
                crate::server::CHILD_PROCESS.lock().unwrap().push(task);
            }
        }
    }
    #[cfg(target_os = "macos")]
    {
        std::thread::spawn(move || crate::handle_url_scheme(link));
    }
}

/// "ID copied" as a notification from NeoDesk, under the app's own name
/// and icon rather than PowerShell's.
#[cfg(windows)]
fn notify_copied(id: &str) {
    use tauri_winrt_notification::{Duration as ToastDuration, Toast};
    let app_id = format!("{}.Tray", crate::get_app_name().replace(' ', ""));
    if let Err(err) = register_toast_sender(&app_id) {
        log::debug!("Failed to register {app_id} for notifications: {err}");
    }
    Toast::new(&app_id)
        .title(&translate("nd-tray-id-copied".to_owned()))
        .text1(id)
        .sound(None)
        .duration(ToastDuration::Short)
        .show()
        .ok();
}

/// Names the notification sender in the current user's registry, which is
/// what Windows shows on the notification.
#[cfg(windows)]
fn register_toast_sender(app_id: &str) -> std::io::Result<()> {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
        .create_subkey(format!("Software\\Classes\\AppUserModelId\\{app_id}"))?;
    key.set_value("DisplayName", &crate::get_app_name())?;
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let icon = dir.join(r"data\flutter_assets\assets\icon.png");
            if icon.exists() {
                key.set_value("IconUri", &icon.to_string_lossy().to_string())?;
            }
        }
    }
    Ok(())
}

/// This process's own copy of the options, until the service answers.
fn local_options() -> HashMap<String, String> {
    config::Config::get_options()
}

fn facts_of(options: &HashMap<String, String>, online: Online, reason: &str) -> Facts {
    let get = |key: &str| options.get(key).cloned().unwrap_or_default();
    let custom = get("custom-rendezvous-server");
    let server = tray_model::server_name(&custom, &get("api-server"));
    Facts {
        no_server: server.is_empty() && crate::get_custom_rendezvous_server(custom).is_empty(),
        server,
        online,
        reason: reason.to_owned(),
        standing: standing_of(&get("neodesk-device-standing")),
        service_stopped: config::option2bool("stop-service", &get("stop-service")),
    }
}

/// The option neodesk-device-standing, read as Home reads it.
fn standing_of(raw: &str) -> Standing {
    let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(raw)
    else {
        return Standing::default();
    };
    let text = |key: &str| {
        map.get(key)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned()
    };
    Standing {
        banned: map.get("banned").and_then(|v| v.as_bool()) == Some(true),
        enrollment: text("enrollment"),
        reason: text("reason"),
        signal: text("signal"),
    }
}

/// Asks the service every second for its online state, its options and
/// this computer's ID, and sends a report whenever they change.
#[tokio::main(flavor = "current_thread")]
async fn watch(sender: mpsc::Sender<Report>) {
    let mut options = local_options();
    let mut id = String::new();
    let mut last: Option<Report> = None;
    loop {
        if let Ok(mut c) = crate::ipc::connect(1000, "").await {
            let mut online = None;
            let mut timer =
                crate::rustdesk_interval(tokio::time::interval(Duration::from_secs(1)));
            loop {
                tokio::select! {
                    res = c.next() => {
                        match res {
                            Err(err) => {
                                log::debug!("Tray menu: ipc connection closed: {err}");
                                break;
                            }
                            Ok(Some(Data::OnlineStatus(Some((status, confirmed))))) => {
                                online = Some(Online::of(status, confirmed));
                            }
                            Ok(Some(Data::Options(Some(v)))) => options = v,
                            Ok(Some(Data::Config((name, Some(value))))) if name == "id" => {
                                id = value;
                            }
                            _ => {}
                        }
                    }
                    _ = timer.tick() => {
                        c.send(&Data::OnlineStatus(None)).await.ok();
                        c.send(&Data::Options(None)).await.ok();
                        c.send(&Data::Config(("id".to_owned(), None))).await.ok();
                    }
                }
                let Some(online) = online else {
                    continue;
                };
                let report = Report {
                    facts: facts_of(&options, online, ""),
                    id: id.clone(),
                };
                if last.as_ref() != Some(&report) {
                    sender.send(report.clone()).ok();
                    last = Some(report);
                }
            }
        }
        let report = Report {
            facts: facts_of(&options, Online::NotReady, "ipc_disconnected"),
            id: id.clone(),
        };
        if last.as_ref() != Some(&report) {
            sender.send(report.clone()).ok();
            last = Some(report);
        }
        hbb_common::sleep(1.).await;
    }
}
