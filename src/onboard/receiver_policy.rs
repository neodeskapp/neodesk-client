//! What the receiver does with its server's policy (A277, A279).
//!
//! The installed receiver reads `GET /api/nd/device-policy` with its device
//! token and the access policy of the sealed heartbeat answer, and follows
//! them as the device's resolved policy; it has no default of its own.
//!
//! - Session approval: nobody gets in with a password outside a Get help
//!   session, and the person's Allow lets a caller in
//!   ([`connection_options`]). A caller the server vouches for gets in
//!   without Allow when [`unattended_rule`] allows it for that caller now
//!   (lead/receiver-app/UNATTENDED-CONTRACT.md, the same rule as the
//!   server's, checked against the same test vectors).
//! - `policies.security.allow_uninstall`: false hides the app's entry in
//!   Settings › Apps and blocks its removal there ([`uninstall_entry_values`]).
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/receiver_policy.rs`. The time
//! zone database comes in as a function ([`OffsetOf`]).

/// The policy as the receiver applies it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Resolved {
    /// The person may remove the app.
    pub allow_uninstall: bool,
}

/// The policy for `allow_uninstall` (None when the server does not say:
/// allowed).
pub fn resolve(allow_uninstall: Option<bool>) -> Resolved {
    Resolved {
        allow_uninstall: allow_uninstall.unwrap_or(true),
    }
}

/// The client options for the session approval outside a Get help session:
/// only the person's click lets a caller in, and no password does (a
/// receiver has no permanent password, A279). A caller the server vouches
/// for skips the click in the connection itself, not through these.
pub fn connection_options() -> [(&'static str, &'static str); 2] {
    [
        ("approve-mode", "click"),
        ("verification-method", "use-temporary-password"),
    ]
}

/// Whether the logon screen password fallback
/// (`allow-logon-screen-password`) may take a permanent password: never on
/// the receiver.
pub fn logon_screen_password_allowed(option_on: bool, on_logon_screen: bool, receiver: bool) -> bool {
    option_on && on_logon_screen && !receiver
}

/// The days of a schedule, in the contract's words, Monday first.
pub const DAYS: [&str; 7] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

/// The device's access policy as the sealed heartbeat answer carries it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AccessPolicy {
    pub unattended_enabled: bool,
    pub password_set: bool,
    pub schedule_enabled: bool,
    pub schedule_days: Vec<String>,
    /// "HH:MM", 24 h.
    pub schedule_start: String,
    pub schedule_end: String,
    /// An IANA name such as Europe/Berlin.
    pub schedule_timezone: String,
    /// Usernames; empty lets every account in.
    pub allowed_operators: Vec<String>,
}

/// Why the rule refuses, with the reason names of the contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    AskAlways,
    NotEnabled,
    OutsideSchedule,
    OperatorNotAllowed,
}

impl Refusal {
    pub fn reason(self) -> &'static str {
        match self {
            Refusal::AskAlways => "ask_always",
            Refusal::NotEnabled => "not_enabled",
            Refusal::OutsideSchedule => "outside_schedule",
            Refusal::OperatorNotAllowed => "operator_not_allowed",
        }
    }
}

/// The UTC offset in seconds of the time zone named first at the Unix time
/// second; None for a zone it does not know.
pub type OffsetOf<'a> = &'a dyn Fn(&str, i64) -> Option<i32>;

/// Steps 1 to 3 of the rule: whether the organization's session approval
/// `mode` and the device's access policy (None when it has none) let staff
/// in without asking at all.
pub fn unattended_offered(mode: Option<&str>, access: Option<&AccessPolicy>) -> Result<(), Refusal> {
    match mode.map(str::trim) {
        Some("ask_always") => Err(Refusal::AskAlways),
        Some("unattended") => Ok(()),
        _ if access.map_or(false, |a| a.unattended_enabled) => Ok(()),
        _ => Err(Refusal::NotEnabled),
    }
}

/// The rule of the contract: whether `caller` (the vouched account's
/// username) may connect without the person's Allow at `now` (Unix
/// seconds), for the organization's `mode` and `org_operators` and the
/// device's access policy. First match wins.
pub fn unattended_rule(
    mode: Option<&str>,
    org_operators: &[String],
    access: Option<&AccessPolicy>,
    caller: &str,
    now: i64,
    offset_of: OffsetOf,
) -> Result<(), Refusal> {
    unattended_offered(mode, access)?;
    if let Some(access) = access.filter(|a| a.schedule_enabled) {
        if !in_schedule(access, now, offset_of) {
            return Err(Refusal::OutsideSchedule);
        }
    }
    let device_operators = access.map_or(&[][..], |a| &a.allowed_operators[..]);
    if !operator_allowed(org_operators, caller) || !operator_allowed(device_operators, caller) {
        return Err(Refusal::OperatorNotAllowed);
    }
    Ok(())
}

/// Whether `caller` is in `list`, trimmed and in any case; an empty list
/// (or one of blanks only) lets everyone in.
fn operator_allowed(list: &[String], caller: &str) -> bool {
    let caller = caller.trim().to_lowercase();
    let mut names = list.iter().map(|n| n.trim()).filter(|n| !n.is_empty()).peekable();
    if names.peek().is_none() {
        return true;
    }
    !caller.is_empty() && names.any(|n| n.to_lowercase() == caller)
}

/// "HH:MM" (24 h, two digits each) as minutes after midnight.
pub fn parse_time(text: &str) -> Option<u32> {
    let (h, m) = text.trim().split_once(':')?;
    let digits = |s: &str| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit());
    if !digits(h) || h.len() != 2 || !digits(m) || m.len() != 2 {
        return None;
    }
    let (h, m): (u32, u32) = (h.parse().ok()?, m.parse().ok()?);
    (h < 24 && m < 60).then_some(h * 60 + m)
}

/// The index in [`DAYS`] of a day name, in any case.
fn day_index(name: &str) -> Option<usize> {
    let name = name.trim().to_ascii_lowercase();
    DAYS.iter().position(|d| *d == name)
}

/// The weekday (index in [`DAYS`]) and the minute of the day of a local
/// time given as seconds since 1970-01-01 00:00 local.
fn local_day_and_minute(local: i64) -> (usize, u32) {
    let days = local.div_euclid(86_400);
    // 1970-01-01 was a Thursday
    let weekday = (days + 3).rem_euclid(7) as usize;
    (weekday, (local.rem_euclid(86_400) / 60) as u32)
}

/// A valid schedule: its days (as a week of flags, Monday first), start
/// and end in minutes. None when the time zone is unknown, a time does not
/// read or no day is listed.
fn schedule_of(access: &AccessPolicy, now: i64, offset_of: OffsetOf) -> Option<([bool; 7], u32, u32, i32)> {
    let offset = offset_of(access.schedule_timezone.trim(), now)?;
    let start = parse_time(&access.schedule_start)?;
    let end = parse_time(&access.schedule_end)?;
    let mut days = [false; 7];
    for day in &access.schedule_days {
        if let Some(i) = day_index(day) {
            days[i] = true;
        }
    }
    days.iter().any(|d| *d).then_some((days, start, end, offset))
}

/// Step 4: whether `now` lies in the device's schedule, in its time zone.
/// A window whose end comes before its start runs over midnight and
/// belongs to the day it started on; start equal to end is the whole day.
pub fn in_schedule(access: &AccessPolicy, now: i64, offset_of: OffsetOf) -> bool {
    let Some((days, start, end, offset)) = schedule_of(access, now, offset_of) else {
        return false;
    };
    let (weekday, t) = local_day_and_minute(now + i64::from(offset));
    let yesterday = (weekday + 6) % 7;
    if start == end {
        days[weekday]
    } else if start < end {
        days[weekday] && start <= t && t < end
    } else if t >= start {
        days[weekday]
    } else {
        t < end && days[yesterday]
    }
}

/// The schedule as the home window shows it: the days the window starts on
/// and its times, in minutes, in the computer's own time zone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScheduleView {
    /// Names from [`DAYS`], Monday first.
    pub days: Vec<&'static str>,
    pub start: u32,
    pub end: u32,
}

/// What the home window says under Get help (A279): None when staff can't
/// connect without asking (steps 1 to 3 refuse, or the schedule can never
/// match), Some(None) when they can at any time, Some(schedule) with the
/// schedule moved from its time zone into the computer's (`local_offset`,
/// seconds east of UTC, at `now`).
pub fn home_line(
    mode: Option<&str>,
    access: Option<&AccessPolicy>,
    now: i64,
    local_offset: i32,
    offset_of: OffsetOf,
) -> Option<Option<ScheduleView>> {
    unattended_offered(mode, access).ok()?;
    let Some(access) = access.filter(|a| a.schedule_enabled) else {
        return Some(None);
    };
    let (days, start, end, offset) = schedule_of(access, now, offset_of)?;
    if start == end && local_offset != offset {
        // A whole day in another zone straddles two local days: show the
        // days as they are, without times
        return Some(Some(ScheduleView {
            days: DAYS.iter().zip(days).filter(|(_, on)| *on).map(|(d, _)| *d).collect(),
            start,
            end,
        }));
    }
    let shift = (local_offset - offset) / 60;
    let moved = start as i32 + shift;
    let day_shift = moved.div_euclid(1440);
    let start = moved.rem_euclid(1440) as u32;
    let end = (end as i32 + shift).rem_euclid(1440) as u32;
    let mut local_days = [false; 7];
    for (i, on) in days.iter().enumerate() {
        if *on {
            local_days[(i as i32 + day_shift).rem_euclid(7) as usize] = true;
        }
    }
    Some(Some(ScheduleView {
        days: DAYS.iter().zip(local_days).filter(|(_, on)| *on).map(|(d, _)| *d).collect(),
        start,
        end,
    }))
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

    /// Berlin without its summer time, and UTC, for tests without a time
    /// zone database (the shared vectors run with the real one).
    fn offsets(zone: &str, _now: i64) -> Option<i32> {
        match zone {
            "UTC" => Some(0),
            "Test/Plus1" => Some(3600),
            "Test/Minus5" => Some(-5 * 3600),
            _ => None,
        }
    }

    fn policy(days: &[&str], start: &str, end: &str, zone: &str) -> AccessPolicy {
        AccessPolicy {
            unattended_enabled: true,
            schedule_enabled: true,
            schedule_days: days.iter().map(|d| d.to_string()).collect(),
            schedule_start: start.into(),
            schedule_end: end.into(),
            schedule_timezone: zone.into(),
            ..Default::default()
        }
    }

    // 2026-11-16 was a Monday
    const MON_0000_UTC: i64 = 1_794_787_200;
    fn at(day: i64, h: i64, m: i64) -> i64 {
        MON_0000_UTC + day * 86_400 + h * 3600 + m * 60
    }

    #[test]
    fn the_monday_constant_is_a_monday() {
        assert_eq!(local_day_and_minute(MON_0000_UTC), (0, 0));
        assert_eq!(local_day_and_minute(at(6, 23, 59)), (6, 23 * 60 + 59));
    }

    #[test]
    fn the_mode_and_the_device_decide_first() {
        let on = AccessPolicy { unattended_enabled: true, ..Default::default() };
        let off = AccessPolicy::default();
        let rule = |mode, access| unattended_rule(mode, &[], access, "anna", at(0, 9, 0), &offsets);
        assert_eq!(rule(Some("ask_always"), Some(&on)), Err(Refusal::AskAlways));
        assert_eq!(rule(Some("unattended"), None), Ok(()));
        assert_eq!(rule(Some("unattended"), Some(&off)), Ok(()));
        assert_eq!(rule(Some("attended"), Some(&on)), Ok(()));
        assert_eq!(rule(Some("attended"), Some(&off)), Err(Refusal::NotEnabled));
        assert_eq!(rule(None, None), Err(Refusal::NotEnabled));
        assert_eq!(rule(Some("something new"), Some(&on)), Ok(()));
    }

    #[test]
    fn the_schedule_holds_its_window() {
        let office = policy(&["mon", "tue", "wed", "thu", "fri"], "08:00", "18:00", "UTC");
        let check = |p: &AccessPolicy, t| in_schedule(p, t, &offsets);
        assert!(check(&office, at(0, 8, 0)));
        assert!(check(&office, at(4, 17, 59)));
        assert!(!check(&office, at(0, 18, 0)), "the end is outside");
        assert!(!check(&office, at(0, 7, 59)));
        assert!(!check(&office, at(5, 12, 0)), "Saturday");
        // In the device's zone: 7:30 UTC is 8:30 at UTC+1
        let plus1 = policy(&["mon"], "08:00", "18:00", "Test/Plus1");
        assert!(check(&plus1, at(0, 7, 30)));
        assert!(!check(&plus1, at(0, 17, 30)));
        // Over midnight: the night belongs to the day it started on
        let night = policy(&["fri"], "22:00", "06:00", "UTC");
        assert!(check(&night, at(4, 23, 0)));
        assert!(check(&night, at(5, 5, 59)), "Saturday morning of Friday's night");
        assert!(!check(&night, at(5, 6, 0)));
        assert!(!check(&night, at(4, 5, 0)), "Friday morning belongs to Thursday");
        // Start equal to end: the whole day
        let all_day = policy(&["sun"], "00:00", "00:00", "UTC");
        assert!(check(&all_day, at(6, 0, 0)));
        assert!(check(&all_day, at(6, 23, 59)));
        assert!(!check(&all_day, at(0, 0, 0)));
    }

    #[test]
    fn a_schedule_that_does_not_read_refuses() {
        let check = |p: &AccessPolicy| in_schedule(p, at(0, 12, 0), &offsets);
        assert!(!check(&policy(&["mon"], "08:00", "18:00", "Mars/Olympus")));
        assert!(!check(&policy(&["mon"], "8", "18:00", "UTC")));
        assert!(!check(&policy(&["mon"], "08:00", "24:00", "UTC")));
        assert!(!check(&policy(&["mon"], "08:0", "18:00", "UTC")));
        assert!(!check(&policy(&[], "08:00", "18:00", "UTC")));
        assert!(!check(&policy(&["monday"], "08:00", "18:00", "UTC")));
        assert!(!check(&policy(&["mon"], "8:00", "18:00", "UTC")));
        assert!(check(&policy(&[" MON "], "08:00", "18:00", "UTC")));
        let rule = unattended_rule(
            Some("unattended"),
            &[],
            Some(&policy(&["mon"], "08:00", "18:00", "Mars/Olympus")),
            "anna",
            at(0, 12, 0),
            &offsets,
        );
        assert_eq!(rule, Err(Refusal::OutsideSchedule));
    }

    #[test]
    fn every_operator_list_that_is_set_must_name_the_caller() {
        let names = |n: &[&str]| n.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        let device = AccessPolicy {
            unattended_enabled: true,
            allowed_operators: names(&["Anna"]),
            ..Default::default()
        };
        let rule = |org: &[String], access: &AccessPolicy, caller| {
            unattended_rule(Some("attended"), org, Some(access), caller, at(0, 9, 0), &offsets)
        };
        assert_eq!(rule(&[], &device, " anna "), Ok(()));
        assert_eq!(rule(&[], &device, "bert"), Err(Refusal::OperatorNotAllowed));
        assert_eq!(rule(&names(&["bert"]), &device, "anna"), Err(Refusal::OperatorNotAllowed));
        assert_eq!(rule(&names(&["ANNA", "bert"]), &device, "anna"), Ok(()));
        let open = AccessPolicy { unattended_enabled: true, ..Default::default() };
        assert_eq!(rule(&names(&["bert"]), &open, "Bert"), Ok(()));
        assert_eq!(rule(&names(&["bert"]), &open, ""), Err(Refusal::OperatorNotAllowed));
        assert_eq!(rule(&names(&[" "]), &open, "x"), Ok(()), "blanks name nobody");
    }

    #[test]
    fn the_home_line_follows_steps_one_to_three_and_shows_local_times() {
        let office = policy(&["mon", "tue", "wed", "thu", "fri"], "08:00", "18:00", "Test/Plus1");
        let now = at(0, 12, 0);
        let line = |mode, access: Option<&AccessPolicy>, local| home_line(mode, access, now, local, &offsets);
        assert_eq!(line(Some("ask_always"), Some(&office), 3600), None);
        assert_eq!(line(Some("attended"), None, 3600), None);
        let open = AccessPolicy { unattended_enabled: true, ..Default::default() };
        assert_eq!(line(Some("attended"), Some(&open), 3600), Some(None));
        assert_eq!(line(Some("unattended"), None, 0), Some(None));
        let weekdays = vec!["mon", "tue", "wed", "thu", "fri"];
        assert_eq!(
            line(None, Some(&office), 3600),
            Some(Some(ScheduleView { days: weekdays.clone(), start: 480, end: 1080 }))
        );
        // The computer in UTC sees 7:00 to 17:00
        assert_eq!(
            line(None, Some(&office), 0),
            Some(Some(ScheduleView { days: weekdays, start: 420, end: 1020 }))
        );
        // Moved over midnight, the window starts on the day before
        let early = policy(&["mon"], "02:00", "10:00", "UTC");
        assert_eq!(
            line(None, Some(&early), -5 * 3600),
            Some(Some(ScheduleView { days: vec!["sun"], start: 21 * 60, end: 5 * 60 }))
        );
        // A schedule that never matches: no line
        let broken = policy(&["mon"], "08:00", "18:00", "Mars/Olympus");
        assert_eq!(line(None, Some(&broken), 0), None);
    }

    #[test]
    fn approval_takes_no_password_and_the_logon_screen_none_either() {
        assert_eq!(
            connection_options(),
            [("approve-mode", "click"), ("verification-method", "use-temporary-password")]
        );
        assert!(logon_screen_password_allowed(true, true, false));
        assert!(!logon_screen_password_allowed(true, true, true));
        assert!(!logon_screen_password_allowed(true, false, false));
        assert!(!logon_screen_password_allowed(false, true, false));
    }

    #[test]
    fn allow_uninstall_false_hides_and_blocks_the_entry() {
        assert!(!resolve(Some(false)).allow_uninstall);
        assert!(resolve(Some(true)).allow_uninstall);
        assert!(resolve(None).allow_uninstall, "not set allows it");
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
