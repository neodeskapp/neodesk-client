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
//!   `{"session": "<relay session UUID>"}`: `RequestRelay.uuid` as signal
//!   sent it to this device, which the caller does not choose.
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

pub fn request_body(session: &str) -> Value {
    json!({ "session": session })
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
pub async fn ask(channel: &Channel, device_id: &str, session: &str, wait: Duration) -> Option<Helper> {
    let asked = async {
        let http = Http::new(channel.console.clone()).await.ok()?;
        let answer = http
            .post(PATH, &request_body(session), Some(channel.token.as_str()))
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
pub async fn vouched_caller(device_id: &str, session: &str) -> Option<Helper> {
    let channel = CHANNEL.lock().unwrap().clone()?;
    if !may_ask(&channel) {
        log::info!("Quick support: the console is not on HTTPS; a caller needs the password");
        return None;
    }
    let helper = ask(&channel, device_id, session, WAIT).await;
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
