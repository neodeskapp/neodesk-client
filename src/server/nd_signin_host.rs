//! The device side of saved sign-in (L469): the console's state from the
//! platform. The wire format is in nd_signin.rs.

use super::nd_signin::{self, LogonState};
use hbb_common::message_proto::{Message, Misc, PluginRequest};
use std::{
    sync::Mutex,
    time::{Duration, Instant},
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
                hbb_common::log::debug!("Failed to detect the sign-in UI: {:?}", err);
                None
            }
        }
    };
    // Only Windows has a separate sign-in UI in the session
    #[cfg(not(windows))]
    let logon_ui = Some(false);
    nd_signin::logon_state_of(prelogin, locked, logon_ui)
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
