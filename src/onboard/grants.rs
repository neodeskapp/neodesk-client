//! What the person allows on the quick support consent screen, and what a
//! supporter's session gets from it.
//!
//! The screen names seeing the screen and using the mouse and keyboard.
//! Copying text and sending files are choices of their own that stay off
//! until the person ticks them. A session gets nothing the screen does not
//! name (sound, camera, terminal, tunnels, restart, recording, blocking
//! input, privacy mode, printing), whatever the server sends with it.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/grants.rs`.

/// The grant names of `POST /api/support/session/consent`.
pub const CLIPBOARD: &str = "clipboard";
pub const FILE_TRANSFER: &str = "file_transfer";

/// The person's choices besides the screen, the mouse and the keyboard.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Grants {
    pub clipboard: bool,
    pub file_transfer: bool,
}

impl Grants {
    /// The names the consent request sends.
    pub fn names(&self) -> Vec<&'static str> {
        let mut names = Vec::new();
        if self.clipboard {
            names.push(CLIPBOARD);
        }
        if self.file_transfer {
            names.push(FILE_TRANSFER);
        }
        names
    }

    /// Whether a supporter's session may have the permission of the
    /// `enable-*` option `option`.
    pub fn allow(&self, option: &str) -> bool {
        match option {
            "enable-keyboard" => true,
            "enable-clipboard" => self.clipboard,
            "enable-file-transfer" => self.file_transfer,
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOT_ON_THE_SCREEN: [&str; 9] = [
        "enable-audio",
        "enable-camera",
        "enable-terminal",
        "enable-tunnel",
        "enable-remote-restart",
        "enable-record-session",
        "enable-block-input",
        "enable-privacy-mode",
        "enable-remote-printer",
    ];

    #[test]
    fn without_a_choice_the_session_gets_mouse_and_keyboard_only() {
        let none = Grants::default();
        assert!(none.names().is_empty());
        assert!(none.allow("enable-keyboard"));
        assert!(!none.allow("enable-clipboard"));
        assert!(!none.allow("enable-file-transfer"));
        for option in NOT_ON_THE_SCREEN {
            assert!(!none.allow(option), "{option}");
        }
    }

    #[test]
    fn each_choice_opens_only_its_own_permission() {
        let clipboard = Grants {
            clipboard: true,
            ..Grants::default()
        };
        assert_eq!(clipboard.names(), vec!["clipboard"]);
        assert!(clipboard.allow("enable-clipboard"));
        assert!(!clipboard.allow("enable-file-transfer"));

        let files = Grants {
            file_transfer: true,
            ..Grants::default()
        };
        assert_eq!(files.names(), vec!["file_transfer"]);
        assert!(files.allow("enable-file-transfer"));
        assert!(!files.allow("enable-clipboard"));

        let both = Grants {
            clipboard: true,
            file_transfer: true,
        };
        assert_eq!(both.names(), vec!["clipboard", "file_transfer"]);
        for option in NOT_ON_THE_SCREEN {
            assert!(!both.allow(option), "{option}");
        }
        assert!(!both.allow(""));
    }
}
