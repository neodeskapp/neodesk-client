//! The key combination that takes the keyboard back from a remote session.
//!
//! While the grab loop sends every key to the remote computer, this chord
//! still reaches this computer: Ctrl+Alt+Shift+G on Windows and Linux,
//! Command+Option+Shift+G on macOS. The grab loop feeds every key to
//! [ReleaseChord::on_key]; on [ChordOutcome::Fire] it stops forwarding and
//! tells the session window, which moves focus to the session toolbar.
//!
//! Plain Rust with no dependencies, so `rustc --test` can check it alone.

/// The keys the chord looks at. Everything else is `Other`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChordKey {
    Ctrl,
    Alt,
    Shift,
    Meta,
    G,
    Other,
}

/// What the grab loop does with a key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChordOutcome {
    /// Handle the key as usual.
    Pass,
    /// The chord was pressed: do not forward the key, release the keyboard.
    Fire,
    /// The release of the G that fired: do not forward it either.
    Swallow,
}

#[derive(Default, Debug)]
pub struct ReleaseChord {
    ctrl: u8,
    alt: u8,
    shift: u8,
    meta: u8,
    fired: bool,
}

impl ReleaseChord {
    /// `use_command`: macOS, where the chord uses Command instead of Ctrl.
    /// `left_right` lets the caller count left and right modifiers apart
    /// (true for the left one); the chord needs one of each kind held.
    pub fn on_key(
        &mut self,
        key: ChordKey,
        is_press: bool,
        use_command: bool,
        left: bool,
    ) -> ChordOutcome {
        let bit = if left { 1 } else { 2 };
        let set = |v: &mut u8| {
            if is_press {
                *v |= bit
            } else {
                *v &= !bit
            }
        };
        match key {
            ChordKey::Ctrl => set(&mut self.ctrl),
            ChordKey::Alt => set(&mut self.alt),
            ChordKey::Shift => set(&mut self.shift),
            ChordKey::Meta => set(&mut self.meta),
            ChordKey::G => {
                if !is_press {
                    if self.fired {
                        self.fired = false;
                        return ChordOutcome::Swallow;
                    }
                    return ChordOutcome::Pass;
                }
                let first = if use_command { self.meta } else { self.ctrl };
                if first != 0 && self.alt != 0 && self.shift != 0 {
                    // Key repeat sends more presses while G is held: fire once.
                    if self.fired {
                        return ChordOutcome::Swallow;
                    }
                    self.fired = true;
                    return ChordOutcome::Fire;
                }
            }
            ChordKey::Other => {}
        }
        ChordOutcome::Pass
    }

    /// Forget held keys, for example when the window lost focus and the
    /// releases went elsewhere.
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Forget the held modifiers but remember a fired G, so its release is
    /// still kept from the remote computer.
    pub fn reset_modifiers(&mut self) {
        *self = Self {
            fired: self.fired,
            ..Self::default()
        };
    }
}

/// The scan code Windows gives the left Ctrl it sends ahead of AltGr on
/// layouts with AltGr. Nobody pressed that Ctrl.
pub const WINDOWS_ALTGR_CTRL_SCAN_CODE: u32 = 0x021D;

/// The chord key of a left or right Ctrl with this scan code.
pub fn ctrl_chord_key(scan_code: u32, windows: bool) -> ChordKey {
    if windows && scan_code == WINDOWS_ALTGR_CTRL_SCAN_CODE {
        ChordKey::Other
    } else {
        ChordKey::Ctrl
    }
}

/// How long the grab loop keeps key presses from the remote computer after
/// the chord fired, waiting for the session window to end the grab. If the
/// window never does (it hangs, or the event went to another window), keys
/// flow again after this.
pub const RELEASE_PENDING_MAX: std::time::Duration = std::time::Duration::from_millis(1000);

/// What the grab loop does with a key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GuardAction {
    /// Handle the key as usual.
    Forward,
    /// Keep the key from the remote computer.
    Drop,
    /// The chord fired: keep the key and tell the session window.
    FireAndDrop,
}

/// The chord and the state around it in the grab loop.
#[derive(Default, Debug)]
pub struct ReleaseGuard {
    chord: ReleaseChord,
    /// When the chord fired while the grab ran; until the session window ends
    /// the grab, no key press goes to the remote computer.
    pending_since: Option<std::time::Instant>,
    /// The chord's G press was kept from the remote computer, so its repeats
    /// and its release are kept too.
    swallowed: bool,
}

impl ReleaseGuard {
    /// `hooked`: the grab runs and keys go to the remote computer.
    pub fn on_key(
        &mut self,
        key: ChordKey,
        is_press: bool,
        use_command: bool,
        left: bool,
        hooked: bool,
        now: std::time::Instant,
    ) -> GuardAction {
        match self.chord.on_key(key, is_press, use_command, left) {
            ChordOutcome::Fire if hooked => {
                self.pending_since = Some(now);
                self.swallowed = true;
                GuardAction::FireAndDrop
            }
            // Not hooked: the keys reach Flutter, which gives the keyboard back.
            ChordOutcome::Fire => GuardAction::Forward,
            ChordOutcome::Swallow if is_press => {
                if self.swallowed {
                    GuardAction::Drop
                } else {
                    GuardAction::Forward
                }
            }
            ChordOutcome::Swallow => {
                if std::mem::take(&mut self.swallowed) {
                    GuardAction::Drop
                } else {
                    GuardAction::Forward
                }
            }
            // Until the session window has ended the grab, no other key press
            // goes out. Modifiers still pass, so the platform's modifier state
            // stays right.
            ChordOutcome::Pass => {
                self.expire(now);
                let pending = self.pending_since.is_some();
                if hooked
                    && is_press
                    && matches!(key, ChordKey::Other | ChordKey::G)
                    && pending
                {
                    GuardAction::Drop
                } else {
                    GuardAction::Forward
                }
            }
        }
    }

    /// The grab started or ended (the session window got or lost the
    /// keyboard): the pending release is over, and modifiers held until now
    /// are forgotten, since their releases may go where the grab loop does
    /// not see them.
    pub fn on_grab_change(&mut self) {
        self.pending_since = None;
        self.chord.reset_modifiers();
    }

    /// The session window answered (it changed the grab), so a fired chord
    /// no longer keeps keys back. Held modifiers stay counted.
    pub fn end_pending(&mut self) {
        self.pending_since = None;
    }

    /// True while key presses are kept back for a fired chord.
    pub fn is_pending(&self) -> bool {
        self.pending_since.is_some()
    }

    /// Ends a pending release that waited longer than [RELEASE_PENDING_MAX].
    pub fn expire(&mut self, now: std::time::Instant) {
        if matches!(self.pending_since,
            Some(t) if now.saturating_duration_since(t) > RELEASE_PENDING_MAX)
        {
            self.pending_since = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ChordKey::*;
    use super::ChordOutcome::*;
    use super::*;

    fn press(c: &mut ReleaseChord, k: ChordKey, mac: bool) -> ChordOutcome {
        c.on_key(k, true, mac, true)
    }
    fn release(c: &mut ReleaseChord, k: ChordKey, mac: bool) -> ChordOutcome {
        c.on_key(k, false, mac, true)
    }

    #[test]
    fn ctrl_alt_shift_g_fires_once_and_swallows_g() {
        let mut c = ReleaseChord::default();
        assert_eq!(press(&mut c, Ctrl, false), Pass);
        assert_eq!(press(&mut c, Alt, false), Pass);
        assert_eq!(press(&mut c, Shift, false), Pass);
        assert_eq!(press(&mut c, G, false), Fire);
        // Key repeat while G is held.
        assert_eq!(press(&mut c, G, false), Swallow);
        assert_eq!(release(&mut c, G, false), Swallow);
        // A later G with the modifiers still held fires again.
        assert_eq!(press(&mut c, G, false), Fire);
    }

    #[test]
    fn g_alone_or_with_fewer_modifiers_passes() {
        let mut c = ReleaseChord::default();
        assert_eq!(press(&mut c, G, false), Pass);
        assert_eq!(release(&mut c, G, false), Pass);
        press(&mut c, Ctrl, false);
        press(&mut c, Alt, false);
        assert_eq!(press(&mut c, G, false), Pass, "Ctrl+Alt+G is not the chord");
        release(&mut c, G, false);
        release(&mut c, Alt, false);
        press(&mut c, Shift, false);
        assert_eq!(press(&mut c, G, false), Pass, "Ctrl+Shift+G is not the chord");
    }

    #[test]
    fn released_modifier_no_longer_counts() {
        let mut c = ReleaseChord::default();
        press(&mut c, Ctrl, false);
        press(&mut c, Alt, false);
        press(&mut c, Shift, false);
        release(&mut c, Shift, false);
        assert_eq!(press(&mut c, G, false), Pass);
    }

    #[test]
    fn left_and_right_modifiers_are_tracked_apart() {
        let mut c = ReleaseChord::default();
        c.on_key(Shift, true, false, true);
        c.on_key(Shift, true, false, false);
        c.on_key(Shift, false, false, true);
        press(&mut c, Ctrl, false);
        press(&mut c, Alt, false);
        assert_eq!(press(&mut c, G, false), Fire, "right Shift is still down");
    }

    #[test]
    fn macos_needs_command_not_ctrl() {
        let mut c = ReleaseChord::default();
        press(&mut c, Ctrl, true);
        press(&mut c, Alt, true);
        press(&mut c, Shift, true);
        assert_eq!(press(&mut c, G, true), Pass);
        release(&mut c, G, true);
        press(&mut c, Meta, true);
        assert_eq!(press(&mut c, G, true), Fire);
    }

    #[test]
    fn reset_forgets_held_keys() {
        let mut c = ReleaseChord::default();
        press(&mut c, Ctrl, false);
        press(&mut c, Alt, false);
        press(&mut c, Shift, false);
        c.reset();
        assert_eq!(press(&mut c, G, false), Pass);
    }

    use std::time::{Duration, Instant};

    fn key(g: &mut ReleaseGuard, k: ChordKey, down: bool, left: bool, at: Instant) -> GuardAction {
        g.on_key(k, down, false, left, true, at)
    }

    fn hold_chord_modifiers(g: &mut ReleaseGuard, at: Instant) {
        key(g, Ctrl, true, true, at);
        key(g, Alt, true, true, at);
        key(g, Shift, true, true, at);
    }

    #[test]
    fn guard_fires_and_keeps_keys_back_until_the_grab_changes() {
        let t = Instant::now();
        let mut g = ReleaseGuard::default();
        hold_chord_modifiers(&mut g, t);
        assert_eq!(key(&mut g, G, true, true, t), GuardAction::FireAndDrop);
        assert_eq!(key(&mut g, Other, true, true, t), GuardAction::Drop);
        assert_eq!(key(&mut g, Shift, false, true, t), GuardAction::Forward, "modifiers pass");
        g.on_grab_change();
        assert_eq!(key(&mut g, Other, true, true, t), GuardAction::Forward);
    }

    #[test]
    fn grab_change_forgets_held_modifiers() {
        // Ctrl, Alt and Shift were down when the grab ended; their releases
        // went elsewhere (another window, the secure desktop).
        let t = Instant::now();
        let mut g = ReleaseGuard::default();
        hold_chord_modifiers(&mut g, t);
        g.on_grab_change();
        assert_eq!(
            key(&mut g, G, true, true, t),
            GuardAction::Forward,
            "a G after the grab came back must go to the remote computer"
        );
    }

    #[test]
    fn the_fired_g_release_is_kept_back_after_the_grab_ends() {
        let t = Instant::now();
        let mut g = ReleaseGuard::default();
        hold_chord_modifiers(&mut g, t);
        key(&mut g, G, true, true, t);
        g.on_grab_change();
        assert_eq!(key(&mut g, G, false, true, t), GuardAction::Drop);
    }

    #[test]
    fn keys_flow_again_when_the_session_window_never_ends_the_grab() {
        let t = Instant::now();
        let mut g = ReleaseGuard::default();
        hold_chord_modifiers(&mut g, t);
        key(&mut g, G, true, true, t);
        let soon = t + Duration::from_millis(100);
        assert_eq!(key(&mut g, Other, true, true, soon), GuardAction::Drop);
        let late = t + RELEASE_PENDING_MAX + Duration::from_millis(1);
        assert_eq!(key(&mut g, Other, true, true, late), GuardAction::Forward);
        assert!(!g.is_pending());
    }

    #[test]
    fn altgr_shift_g_is_not_the_chord_on_windows() {
        // Windows sends AltGr as a left Ctrl with scan code 0x21D and a
        // right Alt.
        let t = Instant::now();
        let mut g = ReleaseGuard::default();
        let fake_ctrl = ctrl_chord_key(WINDOWS_ALTGR_CTRL_SCAN_CODE, true);
        key(&mut g, fake_ctrl, true, true, t);
        key(&mut g, Alt, true, false, t);
        key(&mut g, Shift, true, true, t);
        assert_eq!(key(&mut g, G, true, true, t), GuardAction::Forward);
        key(&mut g, G, false, true, t);
        // A real left Ctrl with the right Alt still is.
        key(&mut g, ctrl_chord_key(0x1D, true), true, true, t);
        assert_eq!(key(&mut g, G, true, true, t), GuardAction::FireAndDrop);
    }
}
