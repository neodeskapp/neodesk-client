//! Keeps keys from a remote computer away from the connection manager.
//!
//! The connection manager's Allow, Decline, switches and Stop session take
//! keyboard focus, so the person at this computer can use them by keyboard.
//! Keys the remote computer sends are typed into this computer by the server
//! (enigo and rdev, with dwExtraInfo set to ENIGO_INPUT_EXTRA_VALUE on
//! Windows). On Windows a low-level keyboard hook in the connection manager's
//! process drops every such key while one of its windows is in front, so a
//! remote key never reaches its controls, however late it arrives.
//!
//! Where this hook does not run (other platforms, or the hook could not be
//! set), the connection manager keeps its controls out of keyboard focus
//! while a remote computer may send keys (server_page.dart).
//!
//! The hook is in cm_remote_keys_win.rs. This file is plain Rust, so
//! `rustc --test` can check it alone.

use std::collections::HashSet;

/// Decides which keys the hook drops. A key is (virtual key, scan code):
/// typed characters all share one virtual key and differ by scan code.
#[derive(Default, Debug)]
pub struct RemoteKeyFilter {
    dropped: HashSet<(u32, u32)>,
}

impl RemoteKeyFilter {
    /// Returns true when the key must not reach any window.
    ///
    /// `from_remote`: the server typed it for a remote computer.
    /// `cm_in_front`: asked only for a remote key press; true when a window
    /// of the connection manager is in front and the remote side may not
    /// change it.
    pub fn on_key(
        &mut self,
        key: (u32, u32),
        down: bool,
        from_remote: bool,
        cm_in_front: impl FnOnce() -> bool,
    ) -> bool {
        if down {
            if from_remote && cm_in_front() {
                self.dropped.insert(key);
                return true;
            }
            false
        } else {
            // A release goes where its press went: dropped with it, or let
            // through so no key stays down on this computer.
            self.dropped.remove(&key)
        }
    }
}

/// Starts keeping remote keys away from the connection manager, where the
/// platform tells remote keys apart. Call it in the connection manager's
/// process only.
pub fn start() {
    #[cfg(all(windows, not(test)))]
    crate::cm_remote_keys_win::start();
}

/// True while remote keys cannot reach the connection manager's windows.
pub fn remote_keys_blocked() -> bool {
    #[cfg(all(windows, not(test)))]
    return crate::cm_remote_keys_win::is_running();
    #[cfg(not(all(windows, not(test))))]
    return false;
}

#[cfg(test)]
mod tests {
    use super::*;

    const A: (u32, u32) = (0x41, 0x1E);
    const PACKET_X: (u32, u32) = (0xE7, 'x' as u32);
    const PACKET_Y: (u32, u32) = (0xE7, 'y' as u32);

    #[test]
    fn remote_keys_never_reach_the_connection_manager_in_front() {
        let mut f = RemoteKeyFilter::default();
        assert!(f.on_key(A, true, true, || true), "remote press is dropped");
        assert!(f.on_key(A, false, true, || true), "and its release");
    }

    #[test]
    fn local_keys_reach_the_connection_manager() {
        let mut f = RemoteKeyFilter::default();
        assert!(!f.on_key(A, true, false, || true));
        assert!(!f.on_key(A, false, false, || true));
    }

    #[test]
    fn remote_keys_reach_other_windows() {
        let mut f = RemoteKeyFilter::default();
        assert!(!f.on_key(A, true, true, || false));
        assert!(!f.on_key(A, false, true, || false));
    }

    #[test]
    fn a_release_follows_its_press() {
        let mut f = RemoteKeyFilter::default();
        // Pressed while another window was in front, released over the
        // connection manager: the release must pass or the key stays down.
        assert!(!f.on_key(A, true, true, || false));
        assert!(!f.on_key(A, false, true, || true));
        // Pressed over the connection manager, released elsewhere: dropped
        // with its press.
        assert!(f.on_key(A, true, true, || true));
        assert!(f.on_key(A, false, true, || false));
    }

    #[test]
    fn typed_characters_are_told_apart_by_scan_code() {
        let mut f = RemoteKeyFilter::default();
        assert!(f.on_key(PACKET_X, true, true, || true));
        assert!(!f.on_key(PACKET_Y, true, true, || false));
        assert!(f.on_key(PACKET_X, false, true, || false));
        assert!(!f.on_key(PACKET_Y, false, true, || false));
    }

    #[test]
    fn front_window_is_only_asked_for_remote_presses() {
        let mut f = RemoteKeyFilter::default();
        f.on_key(A, true, false, || panic!("asked for a local key"));
        f.on_key(A, false, true, || panic!("asked for a release"));
    }
}
