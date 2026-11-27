//! Add a computer and quick support, the client half.
//!
//! An invite reaches the client as the name of the downloaded file
//! (Windows), as a `neodesk://join|support/...` link, as
//! `--join <link or code>` on the command line, or typed into the first
//! start screen. A join code makes this client a member of the server for
//! good (see [`join`]). A support code starts quick support mode: one
//! session, incoming only, nothing installed, with its own config folder and
//! its own IPC names, so an installed NeoDesk on the same computer is left
//! alone (see [`support`]).
//!
//! The UI reads [`state_json`] and calls [`redeem_join`], [`redeem_support`],
//! [`consent`] and [`end_support`]. In quick support a supporter's session
//! gets only what the person allowed ([`quick_support_allows`]), and the
//! files they send or take show in the state as it happens.

// Only the Flutter FFI calls the UI part of this module.
#![cfg_attr(not(feature = "flutter"), allow(dead_code))]

mod caller;
#[cfg_attr(not(windows), allow(dead_code))]
mod cli_output;
mod device_key;
mod grants;
mod http;
mod join;
#[cfg_attr(not(windows), allow(dead_code))]
mod keep;
#[cfg(windows)]
mod keep_tray;
mod link;
mod support;

use std::{
    sync::{
        atomic::{AtomicBool, AtomicI64, Ordering},
        mpsc, Arc, Mutex,
    },
    time::Duration,
};

use hbb_common::{
    config::{self, Config},
    log, password_security,
};
use serde::Serialize;
use serde_json::{json, Value};

use crate::core_main::CoreMainAction;
pub use grants::Grants;
pub use http::OnboardError;
pub use join::{DeviceIdentity, Joined, ServerSettings};
pub use link::{Console, Invite, Kind};

/// Inherited by the processes a quick support process starts (connection
/// manager and the like), so they run in the same mode.
const QUICK_SUPPORT_ENV: &str = "NEODESK_QUICK_SUPPORT";
/// Names the config folder and the windows of quick support mode.
const QUICK_SUPPORT_APP_NAME: &str = "NeoDesk Quick Support";
/// Set once a quick support config folder has an ID of its own.
const OPTION_OWN_ID: &str = "neodesk-quick-support-id";
/// Config option with the console a join came from; a bare code goes there.
const OPTION_CONSOLE: &str = "neodesk-console";
/// How long after the last input event a supporter counts as using the computer.
const INPUT_ACTIVE_FOR_MS: i64 = 2_000;
/// The chat lines the state keeps.
const CHAT_LINES_KEPT: usize = 200;
/// The file lines the state keeps.
const FILE_LINES_KEPT: usize = 200;

static QUICK_SUPPORT: AtomicBool = AtomicBool::new(false);
static LAST_INPUT_MS: AtomicI64 = AtomicI64::new(0);
/// This process is the quick support app kept on the computer, or became it
/// with Keep (see [`keep`]).
static KEPT: AtomicBool = AtomicBool::new(false);
/// The kept app started at sign-in: its window stays hidden.
static START_HIDDEN: AtomicBool = AtomicBool::new(false);
/// Keep did not work; the ended screen says so.
static KEEP_FAILED: AtomicBool = AtomicBool::new(false);
/// The kept app went to the background while its session still ended: the
/// window opens on the ready screen next time.
static REST_AFTER_SESSION: AtomicBool = AtomicBool::new(false);
/// A full NeoDesk was installed while the kept app had a session: the kept
/// app removes itself and quits once the session has ended.
static GIVE_WAY_AFTER_SESSION: AtomicBool = AtomicBool::new(false);

/// Where onboarding stands, as the UI shows it. The names are the ones of
/// the UI's `OnboardingPhase`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Phase {
    #[default]
    NotSetUp,
    Joining,
    Joined,
    JoinFailed,
    SupportWaiting,
    SupportConsent,
    SupportConnecting,
    SupportInSession,
    SupportEnded,
    SupportExpired,
}

/// The state the UI reads.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub phase: Phase,
    /// The console's host.
    pub server: Option<String>,
    pub supporter_name: Option<String>,
    pub company: Option<String>,
    /// An [`OnboardError::code`], or "declined".
    pub error: Option<String>,
    /// The error in plain words, with the server's reason when it gave one.
    pub error_text: Option<String>,
    /// The server's own words when it refused this computer.
    pub error_reason: Option<String>,
    /// While joining: 0 checks the invite, 1 takes over the settings, 2 hands
    /// the device token to the service.
    pub join_step: u8,
    /// After a join: this computer's ID, and the name and folder the invite
    /// gave it.
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub folder_id: Option<i64>,
    /// The link or code being redeemed, for Try again.
    pub link: Option<String>,
    /// The quick support file this app was started from (Windows).
    pub file_name: Option<String>,
    /// The chat with the supporter in a quick support session, oldest first.
    pub messages: Vec<ChatLine>,
    /// While the supporter's connection waits for the person to accept in
    /// the connection manager: the name it gave. The quick support window
    /// then says so instead of "has not connected yet".
    pub asking: Option<String>,
    /// What the supporter sent to this computer or took from it in a quick
    /// support session, oldest first.
    pub files: Vec<FileLine>,
}

/// A file transfer of a quick support session, as it started.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileLine {
    /// The supporter sent it to this computer; otherwise they took it.
    pub to_this_computer: bool,
    /// The file or folder on this computer.
    pub path: String,
    /// The file's name when it is one file, else empty.
    pub name: String,
    pub count: usize,
    /// Bytes in all.
    pub size: i64,
    /// Milliseconds since 1970.
    pub time: i64,
}

impl FileLine {
    fn of(to_this_computer: bool, path: &str, files: &[(String, i64)]) -> Self {
        let name = match files {
            [(name, _)] if !name.is_empty() => name.clone(),
            [_] => path
                .rsplit(['/', '\\'])
                .find(|part| !part.is_empty())
                .unwrap_or_default()
                .to_owned(),
            _ => String::new(),
        };
        Self {
            to_this_computer,
            path: path.to_owned(),
            name,
            count: files.len(),
            size: files.iter().map(|(_, size)| (*size).max(0)).sum(),
            time: hbb_common::get_time(),
        }
    }
}

/// A chat line of a quick support session.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatLine {
    pub from_supporter: bool,
    pub text: String,
    /// Milliseconds since 1970.
    pub time: i64,
}

impl State {
    fn add_chat(&mut self, from_supporter: bool, text: String) {
        self.messages.push(ChatLine {
            from_supporter,
            text,
            time: hbb_common::get_time(),
        });
        if self.messages.len() > CHAT_LINES_KEPT {
            self.messages.remove(0);
        }
    }

    fn add_file(&mut self, line: FileLine) {
        self.files.push(line);
        if self.files.len() > FILE_LINES_KEPT {
            self.files.remove(0);
        }
    }

    /// Records `err` as the error, in code and words.
    pub fn fail(&mut self, err: &OnboardError) {
        let server = self.server.clone().unwrap_or_default();
        self.error = Some(err.code().to_owned());
        self.error_text = Some(err.message(&server));
        self.error_reason = match err {
            OnboardError::Refused(reason) if !reason.trim().is_empty() => {
                Some(reason.trim().to_owned())
            }
            _ => None,
        };
    }

    pub fn clear_error(&mut self) {
        self.error = None;
        self.error_text = None;
        self.error_reason = None;
    }
}

/// The state shared between a running flow and the UI.
#[derive(Clone, Default)]
pub struct SharedState(Arc<Mutex<State>>);

impl SharedState {
    pub fn update(&self, change: impl FnOnce(&mut State)) {
        change(&mut self.0.lock().unwrap());
    }

    pub fn get(&self) -> State {
        self.0.lock().unwrap().clone()
    }
}

lazy_static::lazy_static! {
    static ref STATE: SharedState = SharedState::default();
    static ref PENDING: Mutex<Option<Invite>> = Mutex::new(None);
    static ref SUPPORT: Mutex<Option<mpsc::Sender<support::Command>>> = Mutex::new(None);
    static ref JOINING: Mutex<Option<String>> = Mutex::new(None);
    static ref GRANTS: Mutex<Grants> = Mutex::new(Grants::default());
    /// The full path of the file the person started (Windows, from the
    /// packer), which Remove deletes.
    static ref STARTED_FILE: Mutex<Option<String>> = Mutex::new(None);
}

/// The client's own name, before quick support mode renames the app.
static FULL_APP_NAME: std::sync::OnceLock<String> = std::sync::OnceLock::new();
/// Whether the ended screen offers Keep, decided once.
static CAN_KEEP: std::sync::OnceLock<bool> = std::sync::OnceLock::new();

/// True in a quick support process.
pub fn is_quick_support() -> bool {
    QUICK_SUPPORT.load(Ordering::Relaxed)
}

/// The IPC path a quick support process uses instead of `path`: the same
/// name under `neodesk-qs` instead of `neodesk`.
pub fn namespaced_ipc_path(path: &str) -> String {
    path.replacen(config::EXE_NAME, &format!("{}-qs", config::EXE_NAME), 1)
}

/// The `--join` value, or a support link as the only argument.
fn invite_argument(args: &[String]) -> Option<&str> {
    match args {
        [flag, value, ..] if flag == "--join" => Some(value.as_str()),
        [value] if crate::common::is_supported_uni_link(value) => Some(value.as_str()),
        _ => None,
    }
}

/// The file the person started: the packed exe whose name the portable
/// packer passes on, or else this exe.
fn started_file<'a>(exe: Option<&'a str>, packed: Option<&'a str>) -> Option<&'a str> {
    packed.filter(|name| !name.trim().is_empty()).or(exe)
}

fn packed_file_name() -> Option<String> {
    #[cfg(windows)]
    return std::env::var(crate::common::PORTABLE_APPNAME_RUNTIME_ENV_KEY).ok();
    #[cfg(not(windows))]
    None
}

/// Decides the mode of this process from its file name, its arguments and
/// what its parent passed on. Runs before anything reads the config, since
/// quick support mode has its own config folder.
pub fn init_process_mode() {
    let args: Vec<String> = std::env::args().collect();
    let packed = packed_file_name();
    let started = started_file(args.first().map(String::as_str), packed.as_deref());
    let mut pending = None;
    #[cfg(windows)]
    if let Some(exe) = started {
        pending = link::parse_file_name(exe);
    }
    let file_name = pending
        .as_ref()
        .and(started)
        .and_then(|exe| std::path::Path::new(exe).file_name())
        .map(|name| name.to_string_lossy().into_owned());
    if let Some(text) = invite_argument(args.get(1..).unwrap_or(&[])) {
        match link::parse(text) {
            Ok(invite) if args[1] == "--join" || invite.kind == Some(Kind::Support) => {
                pending = Some(invite)
            }
            _ => {}
        }
    }
    // The kept app is quick support without a link of its own
    #[cfg(windows)]
    let kept = started.map_or(false, keep::is_kept_file);
    #[cfg(not(windows))]
    let kept = false;
    #[cfg(windows)]
    {
        *STARTED_FILE.lock().unwrap() = keep::win::started_file()
            .map(|path| path.display().to_string());
    }
    let quick = std::env::var(QUICK_SUPPORT_ENV).map_or(false, |v| v == "1")
        || kept
        || pending.as_ref().map_or(false, |invite| invite.kind == Some(Kind::Support));
    if quick {
        enter_quick_support_mode();
        KEPT.store(kept, Ordering::Relaxed);
    }
    if let Some(invite) = &pending {
        STATE.update(|s| {
            s.server = invite.console.as_ref().map(|c| c.host.clone());
            s.link = invite.deep_link();
            s.file_name = file_name;
            if quick {
                s.phase = Phase::SupportConnecting;
            }
        });
    }
    *PENDING.lock().unwrap() = pending;
}

fn enter_quick_support_mode() {
    FULL_APP_NAME.get_or_init(crate::get_app_name);
    std::env::set_var(QUICK_SUPPORT_ENV, "1");
    *config::APP_NAME.write().unwrap() = QUICK_SUPPORT_APP_NAME.to_owned();
    let mut hard = config::HARD_SETTINGS.write().unwrap();
    hard.insert("conn-type".to_owned(), "incoming".to_owned());
    hard.insert("disable-installation".to_owned(), "Y".to_owned());
    drop(hard);
    QUICK_SUPPORT.store(true, Ordering::Relaxed);
    use_own_id();
}

/// Gives the quick support config an ID of its own. The ID a client derives
/// from the machine is the one an installed NeoDesk on this computer has.
fn use_own_id() {
    use hbb_common::rand::Rng;
    if Config::get_option(OPTION_OWN_ID) == "Y" {
        return;
    }
    let id = hbb_common::rand::thread_rng()
        .gen_range(100_000_000..1_000_000_000u32)
        .to_string();
    Config::set_id(&id);
    Config::set_option(OPTION_OWN_ID.to_owned(), "Y".to_owned());
}

/// True for a Windows setup file that carries a join code, so double-clicking
/// it shows the install page like `...install.exe`.
pub fn is_setup_file(exe: &str) -> bool {
    let packed = packed_file_name();
    let exe = started_file(Some(exe), packed.as_deref()).unwrap_or(exe);
    !is_quick_support()
        && link::parse_file_name(exe).map_or(false, |invite| invite.kind == Some(Kind::Join))
}

/// The `neodesk://join/...` link of the setup file's invite, which the
/// installer hands to the installed client when it starts it.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn pending_join_deep_link() -> Option<String> {
    let pending = PENDING.lock().unwrap();
    let invite = pending.as_ref()?;
    if invite.kind != Some(Kind::Join) {
        return None;
    }
    invite.deep_link()
}

/// Starts what the file name asked for, once the server runs: a quick
/// support session, or a join when the client runs without installing.
pub fn start_pending() {
    let Some(invite) = PENDING.lock().unwrap().clone() else {
        return;
    };
    let Some(console) = invite.console.clone() else {
        return;
    };
    match invite.kind {
        Some(Kind::Support) if is_quick_support() => start_support(console, invite.code),
        Some(Kind::Join) if !is_quick_support() => {
            std::thread::spawn(move || {
                let _ = join_now(Some(console), &invite.code);
            });
        }
        _ => {}
    }
}

/// Records that a supporter's input arrived.
#[inline]
pub fn note_input() {
    LAST_INPUT_MS.store(hbb_common::get_time(), Ordering::Relaxed);
}

fn input_active() -> bool {
    let last = LAST_INPUT_MS.load(Ordering::Relaxed);
    last > 0 && hbb_common::get_time() - last < INPUT_ACTIVE_FOR_MS
}

/// True while a supporter has a file transfer session open on this
/// computer in quick support.
fn files_open() -> bool {
    is_quick_support()
        && crate::server::AUTHED_CONNS
            .lock()
            .unwrap()
            .iter()
            .any(|conn| conn.conn_type == crate::server::AuthConnType::FileTransfer)
}

/// Whether a supporter's session may have the permission of the `enable-*`
/// option `option`: in quick support only what the person allowed, always
/// otherwise. The connection asks before it gives a permission.
pub fn quick_support_allows(option: &str) -> bool {
    !is_quick_support() || GRANTS.lock().unwrap().allow(option)
}

/// Keeps a file transfer the supporter started, for the session bar. Called
/// by the connection for each one, sent (`to_this_computer`) or taken.
pub fn note_file_transfer(to_this_computer: bool, path: &str, files: &[(String, i64)]) {
    if is_quick_support() {
        STATE.update(|s| s.add_file(FileLine::of(to_this_computer, path, files)));
    }
}

/// The state as JSON for the UI, with `inputActive` and `quickSupport`.
pub fn state_json() -> String {
    let mut value = serde_json::to_value(STATE.get()).unwrap_or(Value::Null);
    value["inputActive"] = Value::Bool(input_active());
    value["filesOpen"] = Value::Bool(files_open());
    value["quickSupport"] = Value::Bool(is_quick_support());
    value["hasServer"] = Value::Bool(has_server());
    value["canKeep"] = Value::Bool(can_keep());
    value["kept"] = Value::Bool(is_kept());
    value["startHidden"] = Value::Bool(START_HIDDEN.load(Ordering::Relaxed));
    value["keepFailed"] = Value::Bool(KEEP_FAILED.load(Ordering::Relaxed));
    value.to_string()
}

/// True in the quick support app kept on this computer.
pub fn is_kept() -> bool {
    is_quick_support() && KEPT.load(Ordering::Relaxed)
}

/// Whether the ended screen offers to keep quick support on this computer:
/// on Windows, in a downloaded quick support file the packer named, and not
/// on a computer with a full NeoDesk, which opens support links itself.
fn can_keep() -> bool {
    *CAN_KEEP.get_or_init(|| {
        #[cfg(windows)]
        {
            is_quick_support()
                && !is_kept()
                && STARTED_FILE
                    .lock()
                    .unwrap()
                    .as_deref()
                    .map_or(false, keep::deletes_handed_file)
                && !keep::win::full_client_installed(&full_app_name())
        }
        #[cfg(not(windows))]
        false
    })
}

fn full_app_name() -> String {
    FULL_APP_NAME.get().cloned().unwrap_or_else(crate::get_app_name)
}

/// Keep on the ended screen: copies the downloaded file to its place,
/// registers it, deletes the download and goes on in the background. False
/// when that did not work; the screen then says so.
pub fn keep_quick_support() -> bool {
    #[cfg(windows)]
    if can_keep() {
        let full = keep::win::full_client_installed(&full_app_name());
        match keep::win::keep(full) {
            Ok((exe, downloaded)) => {
                log::info!("Quick support kept at {}", exe.display());
                if let Some(file) = downloaded {
                    keep::win::delete_file(&file);
                }
                KEPT.store(true, Ordering::Relaxed);
                KEEP_FAILED.store(false, Ordering::Relaxed);
                listen_for_handoffs();
                start_tray();
                rest_quick_support();
                return true;
            }
            Err(err) => log::error!("Quick support not kept: {err}"),
        }
    }
    KEEP_FAILED.store(true, Ordering::Relaxed);
    false
}

/// Remove: deletes the downloaded file, and in the kept app the kept app
/// with its entries. The app quits after it.
pub fn remove_quick_support() {
    #[cfg(windows)]
    {
        let started = STARTED_FILE.lock().unwrap().clone();
        let cleanup = keep::cleanup(is_kept(), started.as_deref());
        if let Some(file) = started.filter(|_| cleanup.started_file) {
            keep::win::delete_file(std::path::Path::new(&file));
        }
        if cleanup.kept {
            keep::win::remove_kept();
        }
    }
}

/// Close in the kept app: the window goes, the app waits in the background
/// for the next link, and opens on the screen that says so.
pub fn rest_quick_support() {
    if SUPPORT.lock().unwrap().is_none() {
        STATE.update(|s| *s = State::default());
    } else {
        REST_AFTER_SESSION.store(true, Ordering::Relaxed);
    }
    START_HIDDEN.store(false, Ordering::Relaxed);
}

/// A full NeoDesk is installed: a quick support app this person kept goes.
/// Its neodesk:// under HKCU would override the full NeoDesk's. A quick
/// support app that runs does that itself, so a session there goes on
/// until it ends ([`keep::give_way`]).
pub fn give_way_to_full_client() {
    #[cfg(windows)]
    if !is_quick_support() && keep::win::is_kept() && !send_handoff(&keep::Handoff::GiveWay) {
        log::info!("NeoDesk is installed, the kept quick support app goes");
        keep::win::remove_kept();
    }
}

/// Does in this quick support app what a full NeoDesk that was installed
/// asks for.
#[cfg(windows)]
fn give_way() {
    let in_session = SUPPORT.lock().unwrap().is_some();
    match keep::give_way(is_kept(), in_session) {
        keep::GiveWay::RemoveAndQuit => {
            log::info!("NeoDesk is installed, the kept quick support app goes");
            quit(true);
        }
        keep::GiveWay::EntriesNowFilesAfterSession => {
            if !GIVE_WAY_AFTER_SESSION.swap(true, Ordering::Relaxed) {
                log::info!("NeoDesk is installed, the kept quick support app goes after the session");
            }
            keep::win::remove_entries();
        }
        keep::GiveWay::RemoveKept => keep::win::remove_kept(),
    }
}

/// Hands `handoff` to the quick support app that runs in this Windows
/// session. False when none runs.
#[cfg(windows)]
fn send_handoff(handoff: &keep::Handoff) -> bool {
    let text = handoff.encode();
    block_on(async move {
        let mut conn = crate::ipc::connect_quick_support(1_000, &keep::win::handoff_ipc()).await?;
        conn.send(&crate::ipc::Data::UrlLink(text)).await
    })
    .map_or(false, |sent| sent.is_ok())
}

/// Takes the handoffs of quick support apps started later, once per process.
#[cfg(windows)]
fn listen_for_handoffs() {
    static LISTENING: std::sync::Once = std::sync::Once::new();
    LISTENING.call_once(|| {
        std::thread::spawn(|| {
            block_on(async {
                use hbb_common::futures::StreamExt as _;
                let mut incoming =
                    match crate::ipc::new_listener(&keep::win::handoff_ipc()).await {
                        Ok(incoming) => incoming,
                        Err(err) => {
                            log::error!("Quick support takes no handoffs: {err}");
                            return;
                        }
                    };
                // A failed accept (a sender that wrote and quit while the last
                // one was read) leaves the listener on; each sender is read on
                // its own task, so a slow one holds up no other.
                while let Some(conn) = incoming.next().await {
                    let conn = match conn {
                        Ok(conn) => conn,
                        Err(err) => {
                            log::warn!("Quick support missed a handoff: {err}");
                            continue;
                        }
                    };
                    hbb_common::tokio::spawn(async move {
                        let mut conn = crate::ipc::Connection::new(conn);
                        if let Ok(Some(crate::ipc::Data::UrlLink(text))) =
                            conn.next_timeout(2_000).await
                        {
                            match keep::Handoff::decode(&text) {
                                Some(handoff) => {
                                    hbb_common::tokio::task::spawn_blocking(move || {
                                        take_handoff(handoff)
                                    });
                                }
                                None => log::warn!("Quick support ignored a handoff"),
                            }
                        }
                    });
                }
                log::error!("Quick support takes no more handoffs");
            });
        });
    });
}

/// Does what a later start handed over.
#[cfg_attr(not(windows), allow(dead_code))]
fn take_handoff(handoff: keep::Handoff) {
    match handoff {
        keep::Handoff::Ping => {}
        keep::Handoff::Show => show_window(),
        // From Apps & installed apps. A downloaded app's session goes on
        // without the kept app.
        keep::Handoff::Remove if is_kept() => quit(true),
        keep::Handoff::Remove => {
            #[cfg(windows)]
            keep::win::remove_kept();
        }
        // From a full NeoDesk that was installed
        keep::Handoff::GiveWay => {
            #[cfg(windows)]
            give_way();
        }
        keep::Handoff::Open { link, file } => {
            // The kept app opens the next links itself, so the download goes,
            // after the kept app took it over when it is another version
            #[cfg(windows)]
            if let Some(file) = file.filter(|f| is_kept() && keep::deletes_handed_file(f)) {
                let file = std::path::Path::new(&file);
                keep::win::adopt(file);
                keep::win::delete_file(file);
            }
            #[cfg(not(windows))]
            let _ = file;
            // A session that runs keeps the screen; the link waits for the next
            if SUPPORT.lock().unwrap().is_none() {
                START_HIDDEN.store(false, Ordering::Relaxed);
                redeem_support(link);
            }
            show_window();
        }
    }
}

/// Tells the quick support window to show itself.
#[cfg_attr(not(windows), allow(dead_code))]
fn show_window() {
    START_HIDDEN.store(false, Ordering::Relaxed);
    #[cfg(feature = "flutter")]
    {
        let event = json!({ "name": "quick_support_show" }).to_string();
        if crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, event).is_none() {
            log::warn!("Quick support has no window to show");
        }
    }
}

/// Ends a session that runs and quits, after removing quick support from
/// this computer when `remove` or a full NeoDesk was installed meanwhile.
#[cfg_attr(not(windows), allow(dead_code))]
fn quit(remove: bool) {
    end_support();
    if remove || GIVE_WAY_AFTER_SESSION.load(Ordering::Relaxed) {
        remove_quick_support();
    }
    std::process::exit(0);
}

#[cfg(windows)]
fn start_tray() {
    keep_tray::start(keep_tray::Actions {
        open: show_window,
        remove: || quit(true),
        quit: || quit(false),
    });
}

/// True when this client already has an ID server.
fn has_server() -> bool {
    !crate::common::get_custom_rendezvous_server(Config::get_option(
        config::keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
    ))
    .is_empty()
}

/// Leaves a failed join: the screens show the first start again, or Home
/// once the computer has a server (set up by hand).
pub fn dismiss_failed_join() {
    STATE.update(|s| {
        if s.phase == Phase::JoinFailed {
            s.phase = Phase::NotSetUp;
            s.clear_error();
        }
    });
}

/// The console of an earlier join, where a bare code goes.
fn known_console() -> Option<Console> {
    Console::from_base(&Config::get_option(OPTION_CONSOLE))
}

/// The port the console listens on since server 3.6.0, before that 5000.
const CONSOLE_PORT: u16 = 3375;

/// Where to try a bare code again when the console of an earlier join no
/// longer answers on its port: the same host on [`CONSOLE_PORT`] (L508).
/// The server updated and its console moved; the join then stores the
/// address the console gives. A console without its own port (behind a
/// proxy on 443 or 80) did not move.
fn moved_console(known: &Console) -> Option<Console> {
    match known.port {
        Some(port) if port != CONSOLE_PORT => Some(Console {
            port: Some(CONSOLE_PORT),
            ..known.clone()
        }),
        _ => None,
    }
}

fn block_on<F: std::future::Future>(future: F) -> Option<F::Output> {
    match hbb_common::tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => Some(runtime.block_on(future)),
        Err(err) => {
            log::error!("Onboarding could not start a runtime: {err}");
            None
        }
    }
}

/// Redeems a join code from a link or code. For a support link it starts
/// quick support instead. Runs the request on its own thread.
pub fn redeem_join(text: String) {
    match link::parse(&text) {
        Ok(invite) if invite.kind == Some(Kind::Support) => redeem_support(text),
        Ok(invite) => {
            // The screens see at once that this join runs, also when an
            // earlier one failed and its screen is still up.
            STATE.update(|s| {
                s.link = Some(text.trim().to_owned());
                s.phase = Phase::Joining;
                s.join_step = 0;
                s.clear_error();
            });
            std::thread::spawn(move || {
                let _ = join_now(invite.console, &invite.code);
            });
        }
        Err(_) => STATE.update(|s| {
            s.phase = Phase::JoinFailed;
            s.fail(&OnboardError::NotALink);
        }),
    }
}

/// Joins the console with `code` and takes over its settings. Blocks; runs
/// outside any async runtime. With the join, the console that answered.
fn join_now(console: Option<Console>, code: &str) -> Result<(Joined, Console), OnboardError> {
    // The join of this code that runs tells the screens how it ends
    let Some(_run) = JoinRun::start(code) else {
        return Err(OnboardError::WrongState);
    };
    let result = join_with(console, code);
    STATE.update(|s| match &result {
        Ok((joined, _)) => {
            s.phase = Phase::Joined;
            s.clear_error();
            s.device_name = Some(joined.device_name.clone()).filter(|n| !n.is_empty());
            s.folder_id = joined.folder_id;
        }
        Err(err) => {
            s.phase = Phase::JoinFailed;
            s.fail(err);
        }
    });
    result
}

/// A join of a code that runs. A link can arrive twice at once, and the
/// same code is joined once at a time. The code is free again once that
/// join ended, also after it joined: a code kept after a join refused the
/// next join of it without a word, and the screen waited for ever (L524).
struct JoinRun(String);

impl JoinRun {
    fn start(code: &str) -> Option<Self> {
        let mut joining = JOINING.lock().unwrap();
        if joining.as_deref() == Some(code) {
            return None;
        }
        *joining = Some(code.to_owned());
        Some(JoinRun(code.to_owned()))
    }
}

impl Drop for JoinRun {
    fn drop(&mut self) {
        let mut joining = JOINING.lock().unwrap();
        if joining.as_deref() == Some(self.0.as_str()) {
            *joining = None;
        }
    }
}

fn join_with(console: Option<Console>, code: &str) -> Result<(Joined, Console), OnboardError> {
    let from_invite = console.is_some();
    let console = console.or_else(known_console).ok_or(OnboardError::NeedsServer)?;
    STATE.update(|s| {
        s.phase = Phase::Joining;
        s.join_step = 0;
        s.server = Some(console.host.clone());
        s.clear_error();
    });
    // The server process's ID, which it signs the join with (L483)
    let device_id = crate::ipc::get_id();
    let from_server_process = block_on(crate::ipc::pairing_proof(
        crate::hbbs_http::pairing_proof::JOIN_PATH,
    ))
    .flatten();
    let (device, proof) = DeviceIdentity::for_join(device_id, from_server_process);
    let redeem = |console: Console| {
        block_on(async {
            let http = http::Http::new(console).await?;
            join::redeem_join(&http, code, &device, &proof).await
        })
        .unwrap_or(Err(OnboardError::Server(0)))
    };
    let (joined, answered) = redeem_at(console, from_invite, redeem)?;
    STATE.update(|s| s.join_step = 1);
    apply_join(&joined, &device.device_id);
    STATE.update(|s| {
        s.join_step = 2;
        s.device_id = Some(device.device_id.clone());
    });
    log::info!("Joined {} as device {}", joined.console, device.device_id);
    Ok((joined, answered))
}

/// Redeems the code at `console`, and for a code without a console of its
/// own (`from_invite` false) once more where the console moved
/// ([`moved_console`]) when it does not answer. With the join, the console
/// that answered (L525).
fn redeem_at(
    console: Console,
    from_invite: bool,
    mut redeem: impl FnMut(Console) -> Result<Joined, OnboardError>,
) -> Result<(Joined, Console), OnboardError> {
    match redeem(console.clone()) {
        Err(OnboardError::Unreachable) if !from_invite => {
            let Some(moved) = moved_console(&console) else {
                return Err(OnboardError::Unreachable);
            };
            log::info!(
                "{} does not answer, trying {} for the code",
                console.base(),
                moved.base()
            );
            let mut joined = redeem(moved.clone())?;
            if joined.console.is_empty() {
                joined.console = moved.base();
            }
            Ok((joined, moved))
        }
        result => result.map(|joined| (joined, console)),
    }
}

/// The line `--join` prints: the console that answered, the device's name
/// when the invite gave one, and the ID.
fn joined_line(answered: &Console, device_name: &str, id: &str) -> String {
    let name = if device_name.is_empty() {
        String::new()
    } else {
        format!(" as {device_name}")
    };
    format!("This computer joined {}{name}. ID: {id}", answered.host_port())
}

/// Takes over the server settings of a join, in the server process when one
/// runs, and hands it the device token.
fn apply_join(joined: &Joined, device_id: &str) {
    let mut options = crate::ipc::get_options();
    for (key, value) in join::option_changes(&joined.server) {
        if value.is_empty() {
            options.remove(key);
        } else {
            options.insert(key.to_owned(), value);
        }
    }
    if !joined.console.is_empty() {
        options.insert(OPTION_CONSOLE.to_owned(), joined.console.clone());
    }
    if let Err(err) = crate::ipc::set_options(options) {
        log::warn!("Join settings not saved: {err}");
    }
    let api = crate::get_api_server(
        joined.server.api_server.clone(),
        joined.server.id_server.clone(),
    );
    let payload = json!({
        "token": joined.device_token,
        "device_id": device_id,
        "api": api.trim_end_matches('/'),
    })
    .to_string();
    if crate::ipc::set_config(crate::ipc::IPC_JOINED_DEVICE_TOKEN, payload.clone()).is_err() {
        // The service of an installed client keeps the device token; its
        // window never keeps one of its own (L442)
        if Config::holds_secrets() {
            store_device_token(&payload);
        } else {
            log::warn!("The service did not take the device token of the join");
        }
    }
}

/// Keeps the device token of a join or a pairing in this process, which runs
/// the sync loop.
/// Called by the IPC server for [`crate::ipc::IPC_JOINED_DEVICE_TOKEN`].
pub fn store_device_token(payload: &str) {
    let Some(handed) = read_device_token(payload, &Config::get_id()) else {
        log::warn!("Ignored a device token for another device or without server");
        return;
    };
    crate::hbbs_http::neodesk::record_enrollment_answer(
        handed.status,
        Some(&handed.token),
        &handed.device_id,
        &handed.api,
    );
}

/// A device token another process of this client handed over.
#[derive(Debug, PartialEq, Eq)]
struct HandedToken {
    status: &'static str,
    token: String,
    device_id: String,
    api: String,
}

/// Reads a handed-over device token for `this_device`. A join sends no
/// status, its device is approved; a pairing sends "approved" or "pending".
fn read_device_token(payload: &str, this_device: &str) -> Option<HandedToken> {
    let value = serde_json::from_str::<Value>(payload).ok()?;
    let text = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_owned()
    };
    let (token, device_id, api) = (text("token"), text("device_id"), text("api"));
    if token.is_empty() || api.is_empty() || device_id != this_device {
        return None;
    }
    let status = match text("status").as_str() {
        "" | "approved" => "approved",
        "pending" => "pending",
        _ => return None,
    };
    Some(HandedToken {
        status,
        token,
        device_id,
        api,
    })
}

/// Starts quick support for a link or code. Outside quick support mode it
/// starts a quick support process for the link. An empty text in a quick
/// support process tries the invite it was started with again.
pub fn redeem_support(text: String) {
    if text.trim().is_empty() && is_quick_support() {
        if let Some(invite) = PENDING.lock().unwrap().clone() {
            if let (Some(Kind::Support), Some(console)) = (invite.kind, invite.console) {
                start_support(console, invite.code);
            }
        }
        return;
    }
    let invite = match link::parse(&text) {
        Ok(invite) if invite.kind == Some(Kind::Join) => return redeem_join(text),
        Ok(invite) => invite,
        Err(_) => return STATE.update(|s| s.fail(&OnboardError::NotALink)),
    };
    let Some(console) = invite.console.clone().or_else(known_console) else {
        return STATE.update(|s| s.fail(&OnboardError::NeedsServer));
    };
    if is_quick_support() {
        STATE.update(|s| s.link = Some(text.trim().to_owned()));
        return start_support(console, invite.code);
    }
    let link = format!("{}/s/{}", console.base(), invite.code);
    match std::env::current_exe() {
        Ok(exe) => {
            if let Err(err) = std::process::Command::new(exe).arg("--join").arg(&link).spawn() {
                log::error!("Quick support could not start: {err}");
            }
        }
        Err(err) => log::error!("Quick support could not start: {err}"),
    }
}

/// Runs a quick support session on a thread of its own, unless one runs.
fn start_support(console: Console, code: String) {
    let mut running = SUPPORT.lock().unwrap();
    if running.is_some() {
        return;
    }
    STATE.update(|s| {
        s.messages.clear();
        s.files.clear();
        // The kept app's window shows the session from the start, not the
        // screen it waits on
        s.phase = Phase::SupportConnecting;
        s.supporter_name = None;
        s.company = None;
        s.asking = None;
        s.clear_error();
    });
    *GRANTS.lock().unwrap() = Grants::default();
    let (tx, rx) = mpsc::channel();
    *running = Some(tx);
    std::thread::spawn(move || {
        support::run(console, code, &AppHost, &STATE, &rx, support::Timing::default());
        *SUPPORT.lock().unwrap() = None;
        if GIVE_WAY_AFTER_SESSION.load(Ordering::Relaxed) {
            log::info!("Quick support session ended, the kept quick support app goes");
            quit(true);
        }
        if REST_AFTER_SESSION.swap(false, Ordering::Relaxed) {
            STATE.update(|s| *s = State::default());
        }
    });
}

/// The person's answer on the consent screen, with what they ticked besides
/// the screen, the mouse and the keyboard.
pub fn consent(allow: bool, grants: Grants) {
    if let Some(tx) = SUPPORT.lock().unwrap().as_ref() {
        tx.send(support::Command::Consent(allow, grants)).ok();
    }
}

/// Ends the quick support session, for Stop and when the app closes. Once
/// the person allowed it, the supporter is cut off here at once, even while
/// the session waits for an answer of the console.
pub fn end_support() {
    if let Some(tx) = SUPPORT.lock().unwrap().as_ref() {
        if matches!(
            STATE.get().phase,
            Phase::SupportWaiting | Phase::SupportInSession
        ) {
            support::stop(&AppHost, &STATE);
        }
        tx.send(support::Command::End).ok();
    }
}

/// Keeps a chat line the supporter sent, for the quick support screen.
/// Called by the connection for each chat message of its peer.
pub fn note_chat(text: &str) {
    if is_quick_support() {
        STATE.update(|s| s.add_chat(true, text.to_owned()));
    }
}

/// Sends a chat line from the quick support screen to the supporter.
pub fn send_chat(text: String) {
    if is_quick_support() {
        chat_to_supporter(&STATE, text, send_to_sessions);
    }
}

/// Hands `text` to `send` and keeps it as the person's line once a session
/// took it.
fn chat_to_supporter(state: &SharedState, text: String, send: impl FnOnce(&str) -> bool) {
    if text.trim().is_empty() {
        return;
    }
    if send(&text) {
        state.update(|s| s.add_chat(false, text));
    }
}

/// Hands `text` to the remote sessions of this process, which send it to
/// their peer. False when no remote session runs.
fn send_to_sessions(text: &str) -> bool {
    let mut sent = false;
    for conn in crate::server::AUTHED_CONNS.lock().unwrap().iter() {
        if conn.conn_type == crate::server::AuthConnType::Remote {
            sent |= conn
                .sender
                .send(crate::ipc::Data::ChatMessage {
                    text: text.to_owned(),
                })
                .is_ok();
        }
    }
    sent
}

/// The options quick support sets: the one-time password, which the app
/// hands to the supporter through the console, and nothing else opens a
/// session. A connection without the password (the console lost it, or a
/// second Connect) waits for the person's click only when the server
/// vouches that it is a signed-in helper of the web console (A271, see
/// [`caller`]); the connection decides that, not the approve mode.
pub(crate) fn quick_support_options() -> [(&'static str, &'static str); 3] {
    [
        ("verification-method", "use-temporary-password"),
        ("approve-mode", "password"),
        ("temporary-password-length", "10"),
    ]
}

/// The helper behind a connection that came through the relay session
/// `relay_session` without a password, when the server vouches for it
/// (A271); None for every other caller, and outside quick support.
pub async fn vouched_caller(device_id: &str, relay_session: &str) -> Option<String> {
    if !is_quick_support() {
        return None;
    }
    caller::vouched_caller(device_id, relay_session).await
}

/// Whether the connection manager's Allow may let a connection in: in
/// quick support only one the server vouched for.
pub fn click_may_let_in(vouched: bool) -> bool {
    caller::click_may_let_in(is_quick_support(), vouched)
}

/// The connections of this process that wait for the person to accept in
/// the connection manager, oldest first, with the name each gave.
#[derive(Default)]
pub(crate) struct Requests(Mutex<Vec<(i32, String)>>);

impl Requests {
    const fn new() -> Self {
        Self(Mutex::new(Vec::new()))
    }

    /// A connection asks (authorized false) or was let in (true).
    pub(crate) fn note(&self, conn_id: i32, name: &str, authorized: bool) {
        let mut list = self.0.lock().unwrap();
        list.retain(|(id, _)| *id != conn_id);
        if !authorized {
            list.push((conn_id, name.to_owned()));
        }
    }

    /// The connection closed.
    pub(crate) fn gone(&self, conn_id: i32) {
        self.0.lock().unwrap().retain(|(id, _)| *id != conn_id);
    }

    /// The name of the newest connection that still waits.
    pub(crate) fn newest(&self) -> Option<String> {
        self.0.lock().unwrap().last().map(|(_, name)| name.clone())
    }
}

static REQUESTS: Requests = Requests::new();

/// The connection `conn_id` asks the person (authorized false) or was let
/// in; the quick support window follows it.
pub fn note_request(conn_id: i32, name: &str, authorized: bool) {
    if is_quick_support() {
        REQUESTS.note(conn_id, name, authorized);
    }
}

/// The connection `conn_id` was let in or closed.
pub fn request_gone(conn_id: i32) {
    REQUESTS.gone(conn_id);
}

/// The running app as quick support sees it. The server runs in this
/// process.
struct AppHost;

impl support::SupportHost for AppHost {
    fn device(&self) -> DeviceIdentity {
        DeviceIdentity::of_this_device(Config::get_id())
    }

    fn apply_server(&self, server: &ServerSettings) {
        // The one-time password goes to the supporter; without it the
        // person accepts by click only a caller the server vouches for.
        for (key, value) in quick_support_options() {
            Config::set_option(key.to_owned(), value.to_owned());
        }
        // An earlier session in this config folder stopped the service.
        Config::set_option("stop-service".to_owned(), "".to_owned());
        password_security::update_temporary_password();
        for (key, value) in join::option_changes(server) {
            Config::set_option(key.to_owned(), value);
        }
        crate::RendezvousMediator::restart();
    }

    fn set_grants(&self, grants: Grants) {
        *GRANTS.lock().unwrap() = grants;
    }

    fn password(&self) -> String {
        password_security::temporary_password()
    }

    fn in_session(&self) -> bool {
        !crate::server::AUTHED_CONNS.lock().unwrap().is_empty()
    }

    fn asking(&self) -> Option<String> {
        REQUESTS.newest()
    }

    fn caller_channel(&self, channel: Option<caller::Channel>) {
        match channel {
            Some(channel) => caller::open(channel),
            None => caller::close(),
        }
    }

    fn shut_down(&self) {
        // Nobody is vouched for once the session ends here
        caller::close();
        Config::set_option("stop-service".to_owned(), "Y".to_owned());
        crate::hbbs_http::sync::disconnect(crate::Connection::alive_conns());
        password_security::update_temporary_password();
        crate::RendezvousMediator::restart();
    }
}

/// Handles `--join <link or code>` and a support link as the only argument.
/// None lets `core_main` go on.
pub fn core_main_hook(args: &[String]) -> Option<Option<CoreMainAction>> {
    #[cfg(windows)]
    if is_quick_support() {
        if let Some(action) = single_quick_support(args) {
            return Some(action);
        }
    }
    let text = invite_argument(args)?;
    let invite = match link::parse(text) {
        Ok(invite) => invite,
        Err(_) if args[0] == "--join" => exit_with(&OnboardError::NotALink, ""),
        Err(_) => return None,
    };
    match invite.kind {
        Some(Kind::Support) => Some(start_quick_support_process(invite)),
        _ if args[0] == "--join" => Some(cli_join(invite)),
        _ => None,
    }
}

/// One quick support app per Windows session: a start while one runs hands
/// its link, Open or Remove over and quits. Otherwise this process becomes
/// the one that takes the handoffs; the kept app started without a link
/// waits with its tray icon. None lets the start go on as before.
#[cfg(windows)]
fn single_quick_support(args: &[String]) -> Option<Option<CoreMainAction>> {
    let link = PENDING
        .lock()
        .unwrap()
        .as_ref()
        .filter(|invite| invite.kind == Some(Kind::Support))
        .and_then(Invite::deep_link);
    let launch = keep::launch_of(args, link.as_deref(), is_kept())?;
    let started = STARTED_FILE.lock().unwrap().clone();
    if send_handoff(&keep::Handoff::of(&launch, started.as_deref())) {
        log::info!("Quick support runs already, handed {launch:?} over");
        return Some(None);
    }
    match launch {
        keep::Launch::Remove => {
            remove_quick_support();
            Some(None)
        }
        keep::Launch::Background | keep::Launch::Open => {
            if !keep::stays(keep::win::full_client_installed(&full_app_name())) {
                log::info!("NeoDesk is installed, the kept quick support app goes");
                remove_quick_support();
                return Some(None);
            }
            START_HIDDEN.store(launch == keep::Launch::Background, Ordering::Relaxed);
            listen_for_handoffs();
            start_tray();
            // Offline until a link comes, also when the last session did not
            // end cleanly and so left the service on
            Config::set_option("stop-service".to_owned(), "Y".to_owned());
            std::thread::spawn(|| crate::start_server(false, false));
            Some(Some(CoreMainAction::StartUi(Vec::new())))
        }
        keep::Launch::Link(_) => {
            listen_for_handoffs();
            if is_kept() {
                start_tray();
            }
            None
        }
    }
}

/// Prints for the command line. On Windows, where the client has no console
/// of its own, see cli_output.rs (L521).
fn say(text: &str) {
    say_to(text, false);
}

fn say_to(text: &str, error: bool) {
    #[cfg(windows)]
    if cli_output::say(&mut cli_output::Process, text, error) == cli_output::Channel::MessageBox {
        crate::platform::message_box(text);
    }
    #[cfg(not(windows))]
    if error {
        eprintln!("{text}");
    } else {
        println!("{text}");
    }
}

fn exit_with(err: &OnboardError, server: &str) -> ! {
    say_to(&err.message(server), true);
    std::process::exit(1);
}

/// `--join` with a join link or code: joins, prints the result and exits.
fn cli_join(invite: Invite) -> Option<CoreMainAction> {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let _user_main_ipc_scope = (crate::platform::is_installed() && crate::platform::is_root())
        .then(crate::ipc::UserMainIpcScope::new);
    let server = invite
        .console
        .clone()
        .or_else(known_console)
        .map(|c| c.host_port())
        .unwrap_or_default();
    match join_now(invite.console, &invite.code) {
        Ok((joined, answered)) => {
            say(&joined_line(&answered, &joined.device_name, &Config::get_id()));
            None
        }
        Err(err) => exit_with(&err, &server),
    }
}

/// A support link: runs this process as the quick support app, with the
/// server in this process. Without a screen (Linux without a display) the
/// person answers in the terminal.
fn start_quick_support_process(invite: Invite) -> Option<CoreMainAction> {
    let Some(console) = invite.console.clone().or_else(known_console) else {
        exit_with(&OnboardError::NeedsServer, "");
    };
    std::thread::spawn(|| crate::start_server(false, false));
    start_support(console, invite.code);
    if has_screen() {
        return Some(CoreMainAction::StartUi(Vec::new()));
    }
    run_in_terminal();
    None
}

fn has_screen() -> bool {
    #[cfg(target_os = "linux")]
    {
        let set = |name: &str| std::env::var(name).map_or(false, |v| !v.is_empty());
        set("DISPLAY") || set("WAYLAND_DISPLAY")
    }
    #[cfg(not(target_os = "linux"))]
    true
}

/// Quick support in a terminal: the consent question on stdin, then
/// "end" stops the session.
fn run_in_terminal() {
    use std::io::BufRead;
    let (lines_tx, lines_rx) = mpsc::channel::<String>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines().map_while(Result::ok) {
            if lines_tx.send(line).is_err() {
                break;
            }
        }
    });
    let mut shown = State::default();
    loop {
        let state = STATE.get();
        if state != shown {
            print_terminal_state(&state, &shown);
            shown = state.clone();
        }
        match state.phase {
            Phase::SupportEnded | Phase::SupportExpired => return,
            Phase::SupportConnecting if state.error.is_some() => std::process::exit(1),
            _ => {}
        }
        // Lines typed before the question are kept for it.
        let takes_input = matches!(
            state.phase,
            Phase::SupportConsent | Phase::SupportWaiting | Phase::SupportInSession
        );
        if !takes_input {
            std::thread::sleep(Duration::from_millis(250));
            continue;
        }
        if let Ok(line) = lines_rx.recv_timeout(Duration::from_millis(250)) {
            let line = line.trim().to_ascii_lowercase();
            match state.phase {
                Phase::SupportConsent => {
                    consent(line == "y" || line == "yes", Grants::default())
                }
                _ if matches!(line.as_str(), "end" | "stop" | "q") => end_support(),
                _ => {}
            }
        }
    }
}

fn print_terminal_state(state: &State, before: &State) {
    let supporter = state.supporter_name.clone().unwrap_or_default();
    let server = state.server.clone().unwrap_or_default();
    let new_error = state.error.is_some() && state.error != before.error;
    if state.phase == before.phase && !new_error {
        return;
    }
    match (state.phase, state.error.as_deref()) {
        (Phase::SupportConnecting, None) => println!("Getting your support session ready ({server})"),
        (Phase::SupportConnecting, Some(_)) => {
            println!("{}", state.error_text.clone().unwrap_or_default())
        }
        (Phase::SupportConsent, _) => {
            let company = state
                .company
                .as_ref()
                .map(|c| format!(" from {c}"))
                .unwrap_or_default();
            println!("{supporter}{company} wants to see your screen to help you.");
            println!(
                "If you allow it, {supporter} can see your screen and use your mouse and keyboard. Copying text and sending files stay off."
            );
            println!("Allow? Type y and press Enter. Anything else declines.");
        }
        (Phase::SupportWaiting | Phase::SupportInSession, Some(_)) if new_error => {
            println!("{}", state.error_text.clone().unwrap_or_default())
        }
        (Phase::SupportWaiting, _) => {
            println!("Waiting for {supporter} to connect. Type end and press Enter to stop.")
        }
        (Phase::SupportInSession, _) => println!("{supporter} is connected."),
        (Phase::SupportEnded, Some("declined")) => println!("You declined. {supporter} has been told."),
        (Phase::SupportEnded, _) => println!("The session has ended."),
        (Phase::SupportExpired, _) => {
            println!("This link has expired. Support links work for one hour and only once.")
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests;
