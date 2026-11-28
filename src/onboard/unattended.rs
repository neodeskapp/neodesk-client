//! Unattended access on the installed receiver (A279,
//! lead/receiver-app/UNATTENDED-CONTRACT.md): staff get in without the
//! person's Allow when the server vouches for them and the device's rule
//! allows it now. No password is involved anywhere.
//!
//! - When: the installed, enrolled receiver, outside a Get help session
//!   (which keeps quick support's own check, [`super::caller`]), gets a
//!   login without a password through the relay, and its API address is
//!   HTTPS. Once per connection, within [`super::caller::WAIT`].
//! - Request: `POST /api/nd/unattended/caller` on the API address with the
//!   device token (`Authorization: Bearer`, `X-Device-Id`) and
//!   `{"session": "<relay session UUID>"}`.
//! - Vouched: `200 {"success": true, "vouched": true, "device_id",
//!   "session", "helper", "helper_username", "helper_avatar"?, "via"}` for
//!   this device and this relay session, with a helper's name. Anything
//!   else (a 409 with its reason, another status, another device or
//!   session, no answer in time) vouches for nobody.
//! - The receiver then applies the same rule as the server
//!   ([`receiver_policy::unattended_rule`]) to `helper_username` with its
//!   own copy of the organization's policy and the sealed access policy.
//!   Only when both agree does the caller get in without Allow
//!   ([`unattended_may_let_in`]); otherwise the connection asks the person
//!   as before.

use std::time::Duration;

use hbb_common::{config::Config, log, tokio};
use serde_json::{json, Value};

use super::{
    caller::{self, Helper},
    http::{Answer, Http},
    link::Console,
    receiver_policy::{self, AccessPolicy},
};

/// The console's route, reached on the API address.
pub const PATH: &str = "/api/nd/unattended/caller";
/// The longest username taken from the answer, in characters.
const USERNAME_MAX_CHARS: usize = 128;

/// What the connection knows about a login.
#[derive(Debug, Clone, Copy)]
pub struct Login<'a> {
    /// The installed receiver with a device token for its server.
    pub receiver: bool,
    /// A Get help session runs: quick support's rules apply.
    pub support_session: bool,
    /// The relay session's UUID; None for a direct connection.
    pub relay_session: Option<&'a str>,
    pub password_given: bool,
    /// The API address is HTTPS.
    pub https: bool,
    pub device_id: &'a str,
}

/// The policy the receiver holds for the rule.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Policy {
    /// GET /api/nd/device-policy answered in this process: the
    /// organization's session approval mode and allowed operators.
    pub org: Option<OrgPolicy>,
    /// The access policy of the last sealed heartbeat answer: None before
    /// the first one, Some(None) when the device has none.
    pub access: Option<Option<AccessPolicy>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct OrgPolicy {
    pub mode: Option<String>,
    pub operators: Vec<String>,
}

/// A caller let in without Allow.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unattended {
    pub helper: Helper,
    pub username: String,
    /// "console" for the browser viewer, "desktop" for a signed-in app.
    pub via: String,
}

/// Whether the connection asks the server about its caller at all: only
/// the receiver outside a Get help session, for a relayed login without a
/// password, with an HTTPS API address.
pub fn may_ask(login: &Login) -> bool {
    login.receiver
        && !login.support_session
        && !login.password_given
        && login.https
        && !login.device_id.is_empty()
        && login.relay_session.map_or(false, |s| !s.is_empty())
}

/// The decision: the caller to let in without the person's Allow, or None
/// for every login that keeps today's way (the connection manager with
/// Allow). `answer` is the server's answer to the check, None when it was
/// not asked or did not answer; `now` in Unix seconds.
pub fn unattended_may_let_in(
    login: &Login,
    answer: Option<&Answer>,
    policy: &Policy,
    now: i64,
) -> Result<Unattended, &'static str> {
    if !may_ask(login) {
        return Err("not_asked");
    }
    let answer = answer.ok_or("no_answer")?;
    let session = login.relay_session.unwrap_or_default();
    let Some(helper) = caller::vouched(answer, login.device_id, session) else {
        return Err(refusal_reason(answer));
    };
    let username = text_of(&answer.body, "helper_username", USERNAME_MAX_CHARS);
    let via = match answer.body.get("via").and_then(Value::as_str) {
        Some("desktop") => "desktop",
        _ => "console",
    };
    let org = policy.org.as_ref().ok_or("no_policy")?;
    let access = policy.access.as_ref().ok_or("no_access_policy")?;
    receiver_policy::unattended_rule(
        org.mode.as_deref(),
        &org.operators,
        access.as_ref(),
        &username,
        now,
        &offset_of,
    )
    .map_err(receiver_policy::Refusal::reason)?;
    Ok(Unattended {
        helper,
        username,
        via: via.to_owned(),
    })
}

/// The server's reason in a refusal, for the log.
fn refusal_reason(answer: &Answer) -> &'static str {
    const REASONS: [&str; 10] = [
        "not_https",
        "session_not_open",
        "too_late",
        "already_used",
        "no_account",
        "no_permission",
        "ask_always",
        "not_enabled",
        "outside_schedule",
        "operator_not_allowed",
    ];
    let reason = answer.body.get("reason").and_then(Value::as_str).unwrap_or("");
    match (answer.status, REASONS.iter().find(|r| **r == reason)) {
        (409, Some(reason)) => reason,
        (409, None) => "not_vouched",
        (200, _) => "not_for_this_connection",
        _ => "no_vouch",
    }
}

/// A text of the answer as shown: no control characters, trimmed, at most
/// `max` characters.
fn text_of(body: &Value, key: &str, max: usize) -> String {
    let text: String = body
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .chars()
        .filter(|c| !c.is_control())
        .take(max)
        .collect();
    text.trim().to_owned()
}

/// The UTC offset in seconds of the IANA time zone `zone` at Unix time
/// `now`; None for a name the database does not have exactly.
pub fn offset_of(zone: &str, now: i64) -> Option<i32> {
    if !tzdb::TZ_NAMES.contains(&zone) {
        return None;
    }
    let tz = tzdb::tz_by_name(zone)?;
    Some(tz.find_local_time_type(now).ok()?.ut_offset())
}

/// Reads the access policy of a sealed heartbeat answer.
pub fn access_policy_of(value: &Value) -> AccessPolicy {
    let flag = |key: &str| value.get(key).and_then(Value::as_bool) == Some(true);
    let text = |key: &str| value.get(key).and_then(Value::as_str).unwrap_or("").trim().to_owned();
    AccessPolicy {
        unattended_enabled: flag("unattended_enabled"),
        password_set: flag("password_set"),
        schedule_enabled: flag("schedule_enabled"),
        schedule_days: names_of(value.get("schedule_days")),
        schedule_start: text("schedule_start"),
        schedule_end: text("schedule_end"),
        schedule_timezone: text("schedule_timezone"),
        allowed_operators: names_of(value.get("allowed_operators")),
    }
}

/// A list of names: a JSON list of texts, or one text with commas.
pub fn names_of(value: Option<&Value>) -> Vec<String> {
    match value {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty())
            .collect(),
        Some(Value::String(text)) => text
            .split(',')
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty())
            .collect(),
        _ => Vec::new(),
    }
}

/// Asks the API address `api` about the relay session `session` with the
/// device token; the answer when it came within `wait`.
pub async fn ask(api: &Console, token: &str, device_id: &str, session: &str, wait: Duration) -> Option<Answer> {
    let asked = async {
        let http = Http::new(api.clone()).await.ok()?;
        http.post_with_headers(
            PATH,
            &json!({ "session": session }),
            Some(token),
            &[("X-Device-Id".to_owned(), device_id.to_owned())],
        )
        .await
        .ok()
    };
    tokio::time::timeout(wait, asked).await.ok().flatten()
}

/// The caller of a login that may get in without Allow, for the
/// connection: asks the server when [`may_ask`] says so and decides with
/// [`unattended_may_let_in`]. None keeps today's way.
pub async fn unattended_caller(relay_session: Option<&str>, password_given: bool) -> Option<Unattended> {
    let receiver = super::is_receiver() && super::receiver::installed();
    let access = if receiver { crate::nd_chat::access() } else { None };
    let api = access.as_ref().and_then(|a| Console::from_base(&a.api));
    let device_id = Config::get_id();
    let login = Login {
        receiver: receiver && access.is_some(),
        support_session: super::in_support_session(),
        relay_session,
        password_given,
        https: api.as_ref().map_or(false, |api| api.https),
        device_id: &device_id,
    };
    if !may_ask(&login) {
        if login.receiver && !login.support_session && !login.https {
            log::info!("Unattended access: the API address is not HTTPS; the caller needs Allow");
        }
        return None;
    }
    let (Some(access), Some(api)) = (access, api) else {
        return None;
    };
    let answer = ask(
        &api,
        &access.token,
        &device_id,
        relay_session.unwrap_or_default(),
        caller::WAIT,
    )
    .await;
    let policy = super::receiver::unattended_policy();
    match unattended_may_let_in(&login, answer.as_ref(), &policy, hbb_common::get_time() / 1000) {
        Ok(caller) => {
            log::info!("Unattended access: the server vouched for a caller ({}) and the rule allows it", caller.via);
            Some(caller)
        }
        Err(reason) => {
            log::info!("Unattended access refused ({reason}); the caller needs Allow");
            None
        }
    }
}

/// What the home window says under Get help, as the state's
/// `unattended`: null for no line, `{"schedule": null}` for any time,
/// `{"schedule": {"days": [...], "start": "8:00", "end": "18:00"}}` in the
/// computer's own time.
pub fn home_line_json(policy: &Policy, now: i64, local_offset: i32) -> Value {
    let (Some(org), Some(access)) = (&policy.org, &policy.access) else {
        return Value::Null;
    };
    match receiver_policy::home_line(org.mode.as_deref(), access.as_ref(), now, local_offset, &offset_of) {
        None => Value::Null,
        Some(None) => json!({ "schedule": null }),
        Some(Some(view)) => json!({
            "schedule": {
                "days": view.days,
                "start": clock(view.start),
                "end": clock(view.end),
                "allDay": view.start == view.end,
            }
        }),
    }
}

/// Minutes after midnight as "8:00".
fn clock(minutes: u32) -> String {
    format!("{}:{:02}", minutes / 60, minutes % 60)
}

/// The notification at the start of an unattended session, in the app's
/// language (A279).
pub fn notice_text(name: &str, company: &str) -> String {
    let (key, company) = match company.trim() {
        "" => ("nd-unattended-notice-nocompany", None),
        company => ("nd-unattended-notice", Some(company)),
    };
    let text = crate::lang::translate(key.to_owned()).replacen("{}", name, 1);
    match company {
        Some(company) => text.replacen("{}", company, 1),
        None => text,
    }
}

/// Shows the notification in this process's session: the connection
/// manager runs in the signed-in person's session, and never on the login
/// screen. A helper's second connection (files next to the screen) within
/// half a minute shows none.
pub fn show_notice(name: &str, company: &str) {
    static LAST: std::sync::Mutex<Option<(String, std::time::Instant)>> = std::sync::Mutex::new(None);
    if !notice_due(&mut LAST.lock().unwrap(), name, std::time::Instant::now()) {
        return;
    }
    let (title, body) = (crate::get_app_name(), notice_text(name, company));
    std::thread::spawn(move || crate::nd_chat::show_notification(&title, &body, || {}));
}

/// Whether the notification for `name` is due at `now`, given the last one
/// shown; keeps this one as the last.
fn notice_due(last: &mut Option<(String, std::time::Instant)>, name: &str, now: std::time::Instant) -> bool {
    let repeated = last
        .as_ref()
        .map_or(false, |(n, at)| n == name && now.duration_since(*at) < Duration::from_secs(30));
    if !repeated {
        *last = Some((name.to_owned(), now));
    }
    !repeated
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_second_connection_of_the_same_helper_shows_no_second_notice() {
        let start = std::time::Instant::now();
        let mut last = None;
        assert!(notice_due(&mut last, "Olga", start));
        assert!(!notice_due(&mut last, "Olga", start + Duration::from_secs(5)));
        assert!(notice_due(&mut last, "Bert", start + Duration::from_secs(6)));
        assert!(notice_due(&mut last, "Olga", start + Duration::from_secs(7)));
        assert!(notice_due(&mut last, "Olga", start + Duration::from_secs(40)));
    }

    #[test]
    fn time_zones_come_from_the_database_by_their_exact_name() {
        // 2026-07-06 12:00 UTC, summer time in Berlin
        let summer = 1_783_339_200;
        assert_eq!(offset_of("Europe/Berlin", summer), Some(7200));
        assert_eq!(offset_of("Europe/Berlin", summer - 200 * 86_400), Some(3600));
        assert_eq!(offset_of("UTC", summer), Some(0));
        assert_eq!(offset_of("America/New_York", summer), Some(-4 * 3600));
        assert_eq!(offset_of("Mars/Olympus", summer), None);
        assert_eq!(offset_of("", summer), None);
        assert_eq!(offset_of("europe/berlin", summer), None);
    }

    #[test]
    fn the_access_policy_reads_lists_and_texts() {
        let policy = access_policy_of(&json!({
            "unattended_enabled": true, "password_set": false, "schedule_enabled": true,
            "schedule_days": ["mon", " tue ", 3], "schedule_start": "08:00",
            "schedule_end": "18:00", "schedule_timezone": " Europe/Berlin ",
            "allowed_operators": "anna, bert,,"
        }));
        assert!(policy.unattended_enabled && policy.schedule_enabled && !policy.password_set);
        assert_eq!(policy.schedule_days, ["mon", "tue"]);
        assert_eq!(policy.schedule_timezone, "Europe/Berlin");
        assert_eq!(policy.allowed_operators, ["anna", "bert"]);
        assert_eq!(access_policy_of(&json!({"unattended_enabled": "yes"})), AccessPolicy::default());
    }

    #[test]
    fn the_home_line_needs_both_policies_and_shows_local_times() {
        let now = 1_794_830_400; // Monday 2026-11-16 12:00 UTC
        let office = AccessPolicy {
            unattended_enabled: true,
            schedule_enabled: true,
            schedule_days: vec!["mon".into(), "tue".into(), "wed".into(), "thu".into(), "fri".into()],
            schedule_start: "08:00".into(),
            schedule_end: "18:00".into(),
            schedule_timezone: "Europe/Berlin".into(),
            ..Default::default()
        };
        let org = |mode: &str| Some(OrgPolicy { mode: Some(mode.into()), operators: vec![] });
        let policy = Policy { org: org("attended"), access: Some(Some(office.clone())) };
        assert_eq!(
            home_line_json(&policy, now, 3600),
            json!({"schedule": {"days": ["mon", "tue", "wed", "thu", "fri"], "start": "8:00", "end": "18:00", "allDay": false}})
        );
        assert_eq!(home_line_json(&policy, now, 0)["schedule"]["start"], "7:00");
        assert_eq!(home_line_json(&Policy { org: org("ask_always"), ..policy.clone() }, now, 3600), Value::Null);
        assert_eq!(home_line_json(&Policy { org: None, ..policy.clone() }, now, 3600), Value::Null);
        assert_eq!(home_line_json(&Policy { access: None, ..policy.clone() }, now, 3600), Value::Null);
        assert_eq!(
            home_line_json(&Policy { org: org("unattended"), access: Some(None) }, now, 3600),
            json!({"schedule": null})
        );
        assert_eq!(home_line_json(&Policy { org: org("attended"), access: Some(None) }, now, 3600), Value::Null);
    }
}
