//! Quick support callers (A271): who may be let in by a click.
//!
//! In quick support the person accepts a connection by click instead of
//! the one-time password only when the server vouches that the connection
//! is the browser viewer of a signed-in helper of the web console. The app
//! never trusts what the connection says about itself (its ID, its name):
//! it asks the console over the quick support session's own channel. The
//! server's half and the full table of its checks are in the server repo,
//! `neodesk-server/console/routes/onboard/PROTOCOL.md`.
//!
//! Wire format 1:
//!
//! - When: the person allowed quick support, a connection came through the
//!   relay, its first login request has no password, and the console's
//!   address is HTTPS. Once per connection. On a console reached over
//!   plain HTTP the app never asks (A273): someone on the way could fake
//!   the answer, so quick support takes only the one-time password there,
//!   and the server refuses to vouch over plain HTTP as well
//!   (`not_https`).
//! - Request: `POST /api/support/session/caller` on the console, with
//!   `Authorization: Bearer <session token>` and the body
//!   `{"session": "<relay session UUID>", "secret": "<caller secret>"}`:
//!   `RequestRelay.uuid` as signal sent it to this device, which the caller
//!   does not choose, and the one-time secret signal gave only the real
//!   caller, which its login request carries (`nd_caller_secret`). A login
//!   without the secret is never asked about ([`caller_check_of`]): the
//!   relay UUID travels in plain text, so knowing it proves nothing.
//! - Vouched: `200 {"success": true, "vouched": true, "device_id": "<this
//!   device's ID>", "session": "<the same UUID>", "helper": "<name>"}`.
//!   The server vouches once per relay session, only in the first minute
//!   after both sides met on the relay, and only for an account that may
//!   connect to this device.
//! - Anything else is not vouched: `409 {"error": "not_vouched", "reason":
//!   ...}`, a `404` from a server without the route, a `401`, any other
//!   status, a body that does not read, an answer for another device or
//!   relay session, an empty helper, or no answer within [`WAIT`].
//!
//! Not vouched, the connection needs the password as before quick support
//! offered clicks, and the connection manager names the caller unknown.
//! Vouched, the connection manager names the helper with the server's name
//! and "From the NeoDesk web console", and offers Allow.

use std::{sync::Mutex, time::Duration};

use hbb_common::{log, tokio};
use serde_json::{json, Value};

use super::{
    http::{Answer, Http},
    link::Console,
};

/// The console's route.
pub const PATH: &str = "/api/support/session/caller";
/// How long a connection waits for the answer.
pub const WAIT: Duration = Duration::from_secs(5);
/// The longest caller secret taken from a login, in characters.
const SECRET_MAX_CHARS: usize = 256;
/// The longest helper name shown, in characters.
const HELPER_MAX_CHARS: usize = 128;
/// The longest helper picture taken, as the data URL's characters.
const AVATAR_MAX_CHARS: usize = 64 * 1024;

/// The helper the server vouched for: the name, and the console account's
/// picture as a data URL when it has one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Helper {
    pub name: String,
    pub avatar: Option<String>,
}

/// Where to ask: the console of the quick support session and its token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Channel {
    pub console: Console,
    pub token: String,
}

/// The channel while the person allowed quick support; None before and
/// after.
static CHANNEL: Mutex<Option<Channel>> = Mutex::new(None);

pub fn open(channel: Channel) {
    *CHANNEL.lock().unwrap() = Some(channel);
}

pub fn close() {
    *CHANNEL.lock().unwrap() = None;
}

pub fn request_body(session: &str, secret: &str) -> Value {
    json!({ "session": session, "secret": secret })
}

/// What a login brings for the server's caller check: the relay session it
/// came through and the caller secret it carries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallerCheck {
    pub session: String,
    pub secret: String,
}

/// The caller check of a login (A271, A279), from whether the peer
/// connection is encrypted (`secured`), its password and its
/// `nd_caller_secret`: only a login on an encrypted connection, without a
/// password, through the relay, with the caller secret of its relay
/// response (base64url, at most [`SECRET_MAX_CHARS`]), and not a
/// terminal's OS login. None for every other login: nobody asks the
/// server, and the person decides as before.
pub fn caller_check_of(
    secured: bool,
    password: &[u8],
    secret: &str,
    relay_session: Option<&str>,
    terminal_os_login: bool,
) -> Option<CallerCheck> {
    if !secured || !password.is_empty() || terminal_os_login {
        return None;
    }
    let session = relay_session.map(str::trim).filter(|s| !s.is_empty())?;
    let secret = secret.trim();
    let base64url = |c: char| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '=');
    if secret.is_empty() || secret.len() > SECRET_MAX_CHARS || !secret.chars().all(base64url) {
        return None;
    }
    Some(CallerCheck {
        session: session.to_owned(),
        secret: secret.to_owned(),
    })
}

/// The helper's name when `answer` vouches for the relay session `session`
/// of the device `device_id`; None for anything else.
pub fn vouched_helper(answer: &Answer, device_id: &str, session: &str) -> Option<String> {
    let body = &answer.body;
    if answer.status != 200
        || body.get("success").and_then(Value::as_bool) != Some(true)
        || body.get("vouched").and_then(Value::as_bool) != Some(true)
        || device_id.is_empty()
        || session.is_empty()
        || body.get("device_id").and_then(Value::as_str) != Some(device_id)
        || body.get("session").and_then(Value::as_str) != Some(session)
    {
        return None;
    }
    let helper: String = body
        .get("helper")
        .and_then(Value::as_str)
        .unwrap_or("")
        .chars()
        .filter(|c| !c.is_control())
        .take(HELPER_MAX_CHARS)
        .collect();
    let helper = helper.trim();
    (!helper.is_empty()).then(|| helper.to_owned())
}

/// The helper's picture in a vouching `answer`: a PNG, JPEG or WebP data
/// URL of at most [`AVATAR_MAX_CHARS`]. Anything else is no picture.
pub fn helper_avatar(answer: &Answer) -> Option<String> {
    let avatar = answer.body.get("helper_avatar")?.as_str()?.trim();
    if avatar.len() > AVATAR_MAX_CHARS {
        return None;
    }
    let data = ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,"]
        .iter()
        .find_map(|prefix| avatar.strip_prefix(prefix))?;
    let base64 = |c: char| c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '=');
    (!data.is_empty() && data.chars().all(base64)).then(|| avatar.to_owned())
}

/// The helper when `answer` vouches for the relay session `session` of the
/// device `device_id`.
pub fn vouched(answer: &Answer, device_id: &str, session: &str) -> Option<Helper> {
    let name = vouched_helper(answer, device_id, session)?;
    Some(Helper {
        name,
        avatar: helper_avatar(answer),
    })
}

/// Asks the console about the relay session `session`; the helper when it
/// vouches within `wait`.
pub async fn ask(
    channel: &Channel,
    device_id: &str,
    session: &str,
    secret: &str,
    wait: Duration,
) -> Option<Helper> {
    if secret.is_empty() {
        return None;
    }
    let asked = async {
        let http = Http::new(channel.console.clone()).await.ok()?;
        let answer = http
            .post(PATH, &request_body(session, secret), Some(channel.token.as_str()))
            .await
            .ok()?;
        vouched(&answer, device_id, session)
    };
    tokio::time::timeout(wait, asked).await.ok().flatten()
}

/// The helper behind a connection that came through the relay session
/// `session` without a password, when the server vouches for it. None
/// outside quick support, before the person allowed it, and for every
/// caller the server does not confirm.
pub async fn vouched_caller(device_id: &str, check: &CallerCheck) -> Option<Helper> {
    let channel = CHANNEL.lock().unwrap().clone()?;
    if !may_ask(&channel) {
        log::info!("Quick support: the console is not on HTTPS; a caller needs the password");
        return None;
    }
    let helper = ask(&channel, device_id, &check.session, &check.secret, WAIT).await;
    match &helper {
        Some(_) => log::info!("Quick support: the server vouched for the caller of a relay session"),
        None => log::info!("Quick support: the server did not vouch for a caller; it needs the password"),
    }
    helper
}

/// Whether the app may ask `channel` about a caller: only a console on
/// HTTPS (A273).
pub fn may_ask(channel: &Channel) -> bool {
    channel.console.https
}

/// Whether the connection manager's Allow may let a connection in: in
/// quick support only a connection the server vouched for, elsewhere what
/// the approve mode says, as before.
pub fn click_may_let_in(quick_support: bool, vouched: bool) -> bool {
    !quick_support || vouched
}
