//! What the receiver does with its server's policy (A277).
//!
//! The installed receiver reads `GET /api/nd/device-policy` with its device
//! token and the access policy of the sealed heartbeat answer, and follows
//! them as the device's resolved policy; it has no default of its own.
//!
//! - Session approval (`policies.connection.mode`): `unattended` lets an
//!   operator in with the device's permanent password, without anyone at
//!   the computer; `ask_always` needs the person's Allow for every session,
//!   whatever the device's own access policy says; `attended`, or no rule,
//!   follows the device's access policy (`unattended_enabled`), which is off
//!   unless an admin turned it on for this device.
//! - `policies.security.allow_uninstall`: false hides the app's entry in
//!   Settings › Apps and blocks its removal there ([`uninstall_entry_values`]).
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/receiver_policy.rs`.

/// The policy as the receiver applies it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Resolved {
    /// An operator may connect without the person's Allow.
    pub unattended: bool,
    /// The person may remove the app.
    pub allow_uninstall: bool,
}

/// The policy for the organization's session approval `mode`, the device's
/// own access policy `device_unattended` (None when it has none) and
/// `allow_uninstall` (None when the server does not say: allowed).
pub fn resolve(
    mode: Option<&str>,
    device_unattended: Option<bool>,
    allow_uninstall: Option<bool>,
) -> Resolved {
    let unattended = match mode.map(str::trim) {
        Some("unattended") => true,
        Some("ask_always") => false,
        _ => device_unattended.unwrap_or(false),
    };
    Resolved {
        unattended,
        allow_uninstall: allow_uninstall.unwrap_or(true),
    }
}

/// The client options for the session approval: with unattended access an
/// operator gets in with the permanent password or the person's click,
/// without it only the click lets anyone in.
pub fn connection_options(unattended: bool) -> [(&'static str, &'static str); 2] {
    if unattended {
        [
            ("approve-mode", ""),
            ("verification-method", "use-permanent-password"),
        ]
    } else {
        [
            ("approve-mode", "click"),
            ("verification-method", "use-permanent-password"),
        ]
    }
}

/// The values of the app's entry under Uninstall in the registry: with
/// removal blocked SystemComponent=1 (Settings › Apps and Programs and
/// Features do not list it) and NoRemove=1 (a list that shows it offers no
/// Uninstall); allowed, both go (None deletes the value).
pub fn uninstall_entry_values(allowed: bool) -> [(&'static str, Option<u32>); 2] {
    let value = if allowed { None } else { Some(1) };
    [("SystemComponent", value), ("NoRemove", value)]
}

/// Whether removal is blocked by the values of the app's uninstall entry
/// (NoRemove=1).
pub fn uninstall_blocked(no_remove: Option<u32>) -> bool {
    no_remove == Some(1)
}

/// The only telemetry command an incoming-only Support Agent runs.
pub const SUPPORT_AGENT_COMMAND: &str = "collect.metrics";

/// Whether a telemetry command is refused with support_agent_restricted:
/// an incoming-only build runs only collect.metrics, the receiver the full
/// client's commands.
pub fn telemetry_command_refused(incoming_only: bool, receiver: bool, command: &str) -> bool {
    incoming_only && !receiver && command != SUPPORT_AGENT_COMMAND
}

/// Whether fleet work (fleet-contract.md) is refused: an incoming-only
/// Support Agent takes none, the receiver takes it like the full client.
pub fn fleet_refused(incoming_only: bool, receiver: bool) -> bool {
    incoming_only && !receiver
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_organizations_mode_decides_and_attended_follows_the_device() {
        // Unattended for the organization: no Allow, whatever the device says
        assert!(resolve(Some("unattended"), None, None).unattended);
        assert!(resolve(Some("unattended"), Some(false), None).unattended);
        // Always ask: the device's own unattended access does not count
        assert!(!resolve(Some("ask_always"), Some(true), None).unattended);
        // Attended, or no rule: the device's access policy
        assert!(!resolve(Some("attended"), None, None).unattended);
        assert!(resolve(Some("attended"), Some(true), None).unattended);
        assert!(resolve(None, Some(true), None).unattended);
        assert!(!resolve(None, None, None).unattended);
        assert!(!resolve(Some("something new"), None, None).unattended);
    }

    #[test]
    fn approval_options_follow_the_policy() {
        let options = |unattended| {
            connection_options(unattended)
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
        };
        assert_eq!(
            options(false),
            ["approve-mode=click", "verification-method=use-permanent-password"]
        );
        assert_eq!(
            options(true),
            ["approve-mode=", "verification-method=use-permanent-password"]
        );
    }

    #[test]
    fn allow_uninstall_false_hides_and_blocks_the_entry() {
        assert!(!resolve(None, None, Some(false)).allow_uninstall);
        assert!(resolve(None, None, Some(true)).allow_uninstall);
        assert!(resolve(None, None, None).allow_uninstall, "not set allows it");
        assert_eq!(
            uninstall_entry_values(false),
            [("SystemComponent", Some(1)), ("NoRemove", Some(1))]
        );
        // Allowed again: the entry comes back
        assert_eq!(
            uninstall_entry_values(true),
            [("SystemComponent", None), ("NoRemove", None)]
        );
        assert!(uninstall_blocked(Some(1)));
        assert!(!uninstall_blocked(None));
        assert!(!uninstall_blocked(Some(0)));
    }

    #[test]
    fn the_receiver_runs_the_full_clients_telemetry_commands() {
        for command in ["collect.metrics", "collect.processes", "collect.services", "service.control", "files.browse"] {
            assert!(
                !telemetry_command_refused(true, true, command),
                "the receiver refused {command}"
            );
            assert!(!telemetry_command_refused(false, false, command));
        }
        // A plain incoming-only Support Agent keeps collect.metrics alone
        assert!(!telemetry_command_refused(true, false, "collect.metrics"));
        assert!(telemetry_command_refused(true, false, "collect.processes"));
        assert!(telemetry_command_refused(true, false, "service.control"));
        assert!(fleet_refused(true, false));
        assert!(!fleet_refused(true, true));
        assert!(!fleet_refused(false, false));
    }
}
