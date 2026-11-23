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
//! [`consent`] and [`end_support`].

// Only the Flutter FFI calls the UI part of this module.
#![cfg_attr(not(feature = "flutter"), allow(dead_code))]

mod http;
mod join;
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

static QUICK_SUPPORT: AtomicBool = AtomicBool::new(false);
static LAST_INPUT_MS: AtomicI64 = AtomicI64::new(0);

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
}

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
    let quick = std::env::var(QUICK_SUPPORT_ENV).map_or(false, |v| v == "1")
        || pending.as_ref().map_or(false, |invite| invite.kind == Some(Kind::Support));
    if quick {
        enter_quick_support_mode();
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

/// The state as JSON for the UI, with `inputActive` and `quickSupport`.
pub fn state_json() -> String {
    let mut value = serde_json::to_value(STATE.get()).unwrap_or(Value::Null);
    value["inputActive"] = Value::Bool(input_active());
    value["quickSupport"] = Value::Bool(is_quick_support());
    value["hasServer"] = Value::Bool(has_server());
    value.to_string()
}

/// True when this client already has an ID server.
fn has_server() -> bool {
    !crate::common::get_custom_rendezvous_server(Config::get_option(
        config::keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
    ))
    .is_empty()
}

/// The console of an earlier join, where a bare code goes.
fn known_console() -> Option<Console> {
    Console::from_base(&Config::get_option(OPTION_CONSOLE))
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
            STATE.update(|s| s.link = Some(text.trim().to_owned()));
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
/// outside any async runtime.
fn join_now(console: Option<Console>, code: &str) -> Result<Joined, OnboardError> {
    {
        let mut joining = JOINING.lock().unwrap();
        if joining.as_deref() == Some(code) {
            return Err(OnboardError::WrongState);
        }
        *joining = Some(code.to_owned());
    }
    let result = join_with(console, code);
    STATE.update(|s| match &result {
        Ok(joined) => {
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
    if result.is_err() {
        *JOINING.lock().unwrap() = None;
    }
    result
}

fn join_with(console: Option<Console>, code: &str) -> Result<Joined, OnboardError> {
    let console = console.or_else(known_console).ok_or(OnboardError::NeedsServer)?;
    STATE.update(|s| {
        s.phase = Phase::Joining;
        s.join_step = 0;
        s.server = Some(console.host.clone());
        s.clear_error();
    });
    let device = DeviceIdentity::of_this_device(crate::ipc::get_id(), true);
    let joined = block_on(async {
        let http = http::Http::new(console).await?;
        join::redeem_join(&http, code, &device).await
    })
    .unwrap_or(Err(OnboardError::Server(0)))?;
    STATE.update(|s| s.join_step = 1);
    apply_join(&joined, &device.device_id);
    STATE.update(|s| {
        s.join_step = 2;
        s.device_id = Some(device.device_id.clone());
    });
    log::info!("Joined {} as device {}", joined.console, device.device_id);
    Ok(joined)
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
        store_device_token(&payload);
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
    STATE.update(|s| s.messages.clear());
    let (tx, rx) = mpsc::channel();
    *running = Some(tx);
    std::thread::spawn(move || {
        support::run(console, code, &AppHost, &STATE, &rx, support::Timing::default());
        *SUPPORT.lock().unwrap() = None;
    });
}

/// The person's answer on the consent screen.
pub fn consent(allow: bool) {
    if let Some(tx) = SUPPORT.lock().unwrap().as_ref() {
        tx.send(support::Command::Consent(allow)).ok();
    }
}

/// Ends the quick support session, for Stop and when the app closes.
pub fn end_support() {
    if let Some(tx) = SUPPORT.lock().unwrap().as_ref() {
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

/// The running app as quick support sees it. The server runs in this
/// process.
struct AppHost;

impl support::SupportHost for AppHost {
    fn device(&self) -> DeviceIdentity {
        DeviceIdentity::of_this_device(Config::get_id(), false)
    }

    fn apply_server(&self, server: &ServerSettings) {
        // Only the one-time password opens a session, and nobody can ask to
        // be let in by a click: the person allowed one supporter already.
        Config::set_option("verification-method".to_owned(), "use-temporary-password".to_owned());
        Config::set_option("approve-mode".to_owned(), "password".to_owned());
        Config::set_option("temporary-password-length".to_owned(), "10".to_owned());
        // An earlier session in this config folder stopped the service.
        Config::set_option("stop-service".to_owned(), "".to_owned());
        password_security::update_temporary_password();
        for (key, value) in join::option_changes(server) {
            Config::set_option(key.to_owned(), value);
        }
        crate::RendezvousMediator::restart();
    }

    fn password(&self) -> String {
        password_security::temporary_password()
    }

    fn in_session(&self) -> bool {
        !crate::server::AUTHED_CONNS.lock().unwrap().is_empty()
    }

    fn shut_down(&self) {
        Config::set_option("stop-service".to_owned(), "Y".to_owned());
        crate::hbbs_http::sync::disconnect(crate::Connection::alive_conns());
        password_security::update_temporary_password();
        crate::RendezvousMediator::restart();
    }
}

/// Handles `--join <link or code>` and a support link as the only argument.
/// None lets `core_main` go on.
pub fn core_main_hook(args: &[String]) -> Option<Option<CoreMainAction>> {
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

/// Prints for the command line; a message box on Windows, where the client
/// has no console.
fn say(text: &str) {
    #[cfg(windows)]
    crate::platform::message_box(text);
    #[cfg(not(windows))]
    println!("{text}");
}

fn exit_with(err: &OnboardError, server: &str) -> ! {
    #[cfg(windows)]
    say(&err.message(server));
    #[cfg(not(windows))]
    eprintln!("{}", err.message(server));
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
        Ok(joined) => {
            let name = if joined.device_name.is_empty() {
                String::new()
            } else {
                format!(" as {}", joined.device_name)
            };
            say(&format!(
                "This computer joined {server}{name}. ID: {}",
                Config::get_id()
            ));
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
                Phase::SupportConsent => consent(line == "y" || line == "yes"),
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
