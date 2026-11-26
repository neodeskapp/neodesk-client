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
}
