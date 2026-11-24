//! The device side of saved sign-in (L469): the console's state from the
//! platform, and the typing at the sign-in screen. The wire format and the
//! checks are in nd_signin.rs.

use super::nd_signin::{self, ConnGate, LogonState, Outcome};
use hbb_common::{
    config::Config,
    log,
    message_proto::{Message, Misc, PluginRequest},
    sodiumoxide::utils::memzero,
};
use std::{
    sync::Mutex,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

/// How long a computed state is reused: the checks start processes (Linux,
/// macOS) or walk the process list (Windows), and every connection asks
/// once a second
const STATE_TTL: Duration = Duration::from_millis(900);

/// The console's state, at most STATE_TTL old; None when unknown
pub fn logon_state() -> Option<LogonState> {
    static CACHE: Mutex<Option<(Instant, Option<LogonState>)>> = Mutex::new(None);
    let mut cache = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some((at, state)) = *cache {
        if at.elapsed() < STATE_TTL {
            return state;
        }
    }
    let state = logon_state_now();
    *cache = Some((Instant::now(), state));
    state
}

/// The console's state now, in the order of the wire format: prelogin,
/// locked, logon_ui, desktop
pub fn logon_state_now() -> Option<LogonState> {
    let prelogin = crate::platform::is_prelogin();
    let locked = !prelogin && crate::platform::is_locked();
    #[cfg(windows)]
    let logon_ui = if prelogin || locked {
        Some(false)
    } else {
        match crate::platform::is_logon_ui() {
            Ok(ui) => Some(ui),
            Err(err) => {
                log::debug!("Failed to detect the sign-in UI: {:?}", err);
                None
            }
        }
    };
    // Only Windows has a separate sign-in UI in the session
    #[cfg(not(windows))]
    let logon_ui = Some(false);
    nd_signin::logon_state_of(prelogin, locked, logon_ui)
}

/// Whether this process can type a sign-in at the secure desktop: the
/// server process the Windows service of an installed client starts as
/// LocalSystem, which holds the device's key (L442)
pub fn can_sign_in() -> bool {
    #[cfg(windows)]
    {
        return crate::platform::is_installed()
            && crate::platform::is_root()
            && Config::holds_secrets();
    }
    #[allow(unreachable_code)]
    false
}

pub fn plugin_message(id: &str, content: Vec<u8>) -> Message {
    let mut misc = Misc::new();
    misc.set_plugin_request(PluginRequest {
        id: id.to_owned(),
        content: content.into(),
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

pub fn logon_state_message(state: LogonState) -> Message {
    plugin_message(
        nd_signin::ID_LOGON_STATE,
        nd_signin::logon_state_content(state),
    )
}

pub fn result_message(outcome: Outcome, nonce: &str) -> Message {
    plugin_message(
        nd_signin::ID_SIGNIN_RESULT,
        nd_signin::result_content(outcome, nonce),
    )
}

fn device_keys() -> Option<nd_signin::DeviceKeys> {
    let (mut sk, pk) = Config::get_key_pair();
    let keys = nd_signin::DeviceKeys::from_ed25519(&pk, &sk);
    memzero(&mut sk);
    keys
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// Handles the nd.signin packet of a connection that may use the keyboard:
/// checks it here, types it on a thread of its own, and answers through
/// answer, once.
pub fn on_request(
    packet: &[u8],
    relay_uuid: Option<&str>,
    gate: &mut ConnGate,
    answer: impl FnOnce(Message) + Send + 'static,
) {
    if !can_sign_in() {
        log::info!("saved sign-in refused: this process can't type at the sign-in screen");
        answer(result_message(Outcome::BadBlob, ""));
        return;
    }
    let Some(keys) = device_keys() else {
        log::warn!("saved sign-in refused: no device key");
        answer(result_message(Outcome::BadBlob, ""));
        return;
    };
    let device_id = Config::get_id();
    // Before the book's lock: on Windows this walks the process list
    let state = logon_state_now();
    let checked = {
        let mut book = nd_signin::nonce_book()
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        nd_signin::accept(
            packet,
            &keys,
            &nd_signin::Expect {
                device_id: &device_id,
                relay_uuid,
            },
            gate,
            &mut book,
            now_secs(),
            state,
        )
    };
    drop(keys);
    match checked {
        Err(refusal) => answer(result_message(refusal.outcome, &refusal.nonce)),
        Ok(request) => start_typing(request, answer),
    }
}

#[cfg(windows)]
fn start_typing(request: nd_signin::Request, answer: impl FnOnce(Message) + Send + 'static) {
    let nonce = request.nonce().to_owned();
    std::thread::spawn(move || {
        let outcome = {
            let _typing = nd_signin::typing_lock()
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            nd_signin::type_signin(request, &mut HostKeys)
        };
        answer(result_message(outcome, &nonce));
    });
}

#[cfg(not(windows))]
fn start_typing(request: nd_signin::Request, answer: impl FnOnce(Message) + Send + 'static) {
    // can_sign_in is false here, so no request gets this far
    let nonce = request.nonce().to_owned();
    drop(request);
    answer(result_message(Outcome::BadBlob, &nonce));
}

/// The keyboard of the console the service's server process runs in
#[cfg(windows)]
struct HostKeys;

#[cfg(windows)]
impl nd_signin::SigninKeys for HostKeys {
    fn logon_state(&mut self) -> Option<LogonState> {
        logon_state_now()
    }

    fn sas(&mut self) {
        super::input_service::nd_signin_sas();
    }

    fn sleep(&mut self, ms: u64) {
        std::thread::sleep(Duration::from_millis(ms));
    }

    fn text(&mut self, text: &str) {
        super::input_service::nd_signin_text(text);
    }

    fn tab(&mut self) {
        super::input_service::nd_signin_key(enigo::Key::Tab);
    }

    fn enter(&mut self) {
        super::input_service::nd_signin_key(enigo::Key::Return);
    }
}
