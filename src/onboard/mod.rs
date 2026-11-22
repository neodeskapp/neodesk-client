//! Add a computer, the client half.
//!
//! An invite reaches the client as the name of the downloaded file
//! (Windows), as a `betterdesk://join/...` link, as `--join <link or code>`
//! on the command line, or typed into the first start screen. A join code
//! makes this client a member of the server for good (see [`join`]).
//!
//! The UI reads [`state_json`] and calls [`redeem_join`].

// Only the Flutter FFI calls the UI part of this module.
#![cfg_attr(not(feature = "flutter"), allow(dead_code))]

mod http;
mod join;
mod link;

use std::sync::{Arc, Mutex};

use hbb_common::{
    config::{self, Config},
    log,
};
use serde::Serialize;
use serde_json::{json, Value};

use crate::core_main::CoreMainAction;
pub use http::OnboardError;
pub use join::{DeviceIdentity, Joined};
pub use link::{Console, Invite, Kind};

/// Config option with the console a join came from; a bare code goes there.
const OPTION_CONSOLE: &str = "betterdesk-console";
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
}

/// The state the UI reads.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub phase: Phase,
    /// The console's host.
    pub server: Option<String>,
    /// An [`OnboardError::code`].
    pub error: Option<String>,
    /// The error in plain words, with the server's reason when it gave one.
    pub error_text: Option<String>,
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
}

impl State {
    /// Records `err` as the error, in code and words.
    pub fn fail(&mut self, err: &OnboardError) {
        let server = self.server.clone().unwrap_or_default();
        self.error = Some(err.code().to_owned());
        self.error_text = Some(err.message(&server));
    }

    pub fn clear_error(&mut self) {
        self.error = None;
        self.error_text = None;
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
    static ref JOINING: Mutex<Option<String>> = Mutex::new(None);
}

/// The `--join` value.
fn invite_argument(args: &[String]) -> Option<&str> {
    match args {
        [flag, value, ..] if flag == "--join" => Some(value.as_str()),
        _ => None,
    }
}

/// Reads the invite this process was started with, from its file name or
/// its arguments.
pub fn init_process_mode() {
    let args: Vec<String> = std::env::args().collect();
    let mut pending = None;
    #[cfg(windows)]
    if let Some(exe) = args.first() {
        pending = link::parse_file_name(exe);
    }
    if let Some(text) = invite_argument(args.get(1..).unwrap_or(&[])) {
        if let Ok(invite) = link::parse(text) {
            pending = Some(invite);
        }
    }
    if let Some(invite) = &pending {
        STATE.update(|s| {
            s.server = invite.console.as_ref().map(|c| c.host.clone());
            s.link = invite.deep_link();
        });
    }
    *PENDING.lock().unwrap() = pending;
}

/// True for a Windows setup file that carries a join code, so double-clicking
/// it shows the install page like `...install.exe`.
pub fn is_setup_file(exe: &str) -> bool {
    link::parse_file_name(exe).map_or(false, |invite| invite.kind == Some(Kind::Join))
}

/// The `betterdesk://join/...` link of the setup file's invite, which the
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

/// Starts what the file name asked for, once the server runs: a join when
/// the client runs without installing.
pub fn start_pending() {
    let Some(invite) = PENDING.lock().unwrap().clone() else {
        return;
    };
    let Some(console) = invite.console.clone() else {
        return;
    };
    if invite.kind == Some(Kind::Join) {
        std::thread::spawn(move || {
            let _ = join_now(Some(console), &invite.code);
        });
    }
}

/// The state as JSON for the UI, with `hasServer`.
pub fn state_json() -> String {
    let mut value = serde_json::to_value(STATE.get()).unwrap_or(Value::Null);
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

/// Redeems a join code from a link or code. Runs the request on its own
/// thread.
pub fn redeem_join(text: String) {
    match link::parse(&text) {
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

/// Keeps a joined device token in this process, which runs the sync loop.
/// Called by the IPC server for [`crate::ipc::IPC_JOINED_DEVICE_TOKEN`].
pub fn store_device_token(payload: &str) {
    let Ok(value) = serde_json::from_str::<Value>(payload) else {
        return;
    };
    let text = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_owned()
    };
    let (token, device_id, api) = (text("token"), text("device_id"), text("api"));
    if token.is_empty() || api.is_empty() || device_id != Config::get_id() {
        log::warn!("Ignored a joined device token for another device or without server");
        return;
    }
    crate::hbbs_http::betterdesk::record_enrollment_answer("approved", Some(&token), &device_id, &api);
}

/// Handles `--join <link or code>`. None lets `core_main` go on.
pub fn core_main_hook(args: &[String]) -> Option<Option<CoreMainAction>> {
    let text = invite_argument(args)?;
    let invite = match link::parse(text) {
        Ok(invite) => invite,
        Err(_) if args[0] == "--join" => exit_with(&OnboardError::NotALink, ""),
        Err(_) => return None,
    };
    Some(cli_join(invite))
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

#[cfg(test)]
mod tests;
