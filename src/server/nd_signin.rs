//! Saved sign-in at a lock or sign-in screen (L469), wire format 1.
//!
//! The device tells the viewer where its console is: `logon_state` in
//! PeerInfo.platform_additions at login, and a Misc.plugin_request
//! `nd.logon_state` whenever it changes during the session.
//!
//! Keep the wire format in this file, so a change to it stays in one place.

/// platform_additions key and JSON key of the console's state
pub const LOGON_STATE_KEY: &str = "logon_state";
/// Misc.plugin_request ids
pub const ID_LOGON_STATE: &str = "nd.logon_state";

/// Where the console is
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogonState {
    /// Nobody is signed in at the console
    Prelogin,
    /// A signed-in session is locked
    Locked,
    /// The sign-in UI runs in the active session, neither of the above
    LogonUi,
    /// An open desktop
    Desktop,
}

impl LogonState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Prelogin => "prelogin",
            Self::Locked => "locked",
            Self::LogonUi => "logon_ui",
            Self::Desktop => "desktop",
        }
    }
}

/// The console's state from the platform's checks, in this order:
/// prelogin, locked, logon_ui, desktop. logon_ui is None when the check
/// failed, and then the state is unknown.
pub fn logon_state_of(prelogin: bool, locked: bool, logon_ui: Option<bool>) -> Option<LogonState> {
    if prelogin {
        Some(LogonState::Prelogin)
    } else if locked {
        Some(LogonState::Locked)
    } else {
        logon_ui.map(|ui| {
            if ui {
                LogonState::LogonUi
            } else {
                LogonState::Desktop
            }
        })
    }
}

/// The content of an `nd.logon_state` request
pub fn logon_state_content(state: LogonState) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({ LOGON_STATE_KEY: state.as_str() })).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn logon_state_follows_prelogin_then_locked_then_logon_ui() {
        use LogonState::*;
        assert_eq!(logon_state_of(true, false, Some(false)), Some(Prelogin));
        assert_eq!(logon_state_of(true, true, Some(true)), Some(Prelogin));
        assert_eq!(logon_state_of(false, true, Some(true)), Some(Locked));
        assert_eq!(logon_state_of(false, true, None), Some(Locked));
        assert_eq!(logon_state_of(false, false, Some(true)), Some(LogonUi));
        assert_eq!(logon_state_of(false, false, Some(false)), Some(Desktop));
        assert_eq!(logon_state_of(false, false, None), None);
        let names: Vec<_> = [Prelogin, Locked, LogonUi, Desktop]
            .iter()
            .map(|s| s.as_str())
            .collect();
        assert_eq!(names, ["prelogin", "locked", "logon_ui", "desktop"]);
    }

    #[test]
    fn the_logon_state_content_is_the_agreed_json() {
        assert_eq!(
            logon_state_content(LogonState::LogonUi),
            br#"{"logon_state":"logon_ui"}"#.to_vec()
        );
    }
}
