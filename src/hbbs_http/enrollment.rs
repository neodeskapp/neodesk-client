//! Key proof and device token for NeoDesk enrollment requests.
//!
//! Register, status and pairing requests carry a short-lived proof made with
//! the device's Ed25519 key, the same key the client registers with the
//! signal server. When a request proves the key and presents no working device
//! token, the server answers with a new `device_token`. The client keeps it in
//! LocalConfig, together with the device id and API base it was issued for,
//! and sends it as a bearer token on later enrollment requests to that server.
//! The token is never put in a URL or a log line.

use hbb_common::{
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::LocalConfig,
    sodiumoxide::{crypto::sign, randombytes},
};
use serde_json::Value;
use std::time::Duration;

/// Time between enrollment attempts while the device is not approved or
/// holds no token for the current id.
pub const ENROLLMENT_RETRY: Duration = Duration::from_secs(120);
/// Time between token checks once the device is approved and holds a token.
pub const TOKEN_CHECK_INTERVAL: Duration = Duration::from_secs(600);

pub const HEADER_TIMESTAMP: &str = "X-ND-Enrollment-Timestamp";
pub const HEADER_NONCE: &str = "X-ND-Enrollment-Nonce";
pub const HEADER_SIGNATURE: &str = "X-ND-Enrollment-Signature";
const HEADER_AUTHORIZATION: &str = "Authorization";
const PROOF_VERSION: &str = "nd-enrollment-v1";
const NONCE_BYTES: usize = 32;

const OPTION_DEVICE_TOKEN: &str = "neodesk-device-token";
const OPTION_DEVICE_TOKEN_ID: &str = "neodesk-device-token-id";
const OPTION_DEVICE_TOKEN_API: &str = "neodesk-device-token-api";

/// The text the device signs for one enrollment request.
pub fn proof_payload(
    method: &str,
    path: &str,
    device_id: &str,
    public_key_b64: &str,
    timestamp: &str,
    nonce: &str,
) -> String {
    format!(
        "{PROOF_VERSION}\n{method}\n{path}\n{device_id}\n{public_key_b64}\n{timestamp}\n{nonce}"
    )
}

/// Proof headers for one request, or None when the key pair is not an
/// Ed25519 pair. `path` is the request path as sent, without the query.
pub fn proof_headers(
    method: &str,
    path: &str,
    device_id: &str,
    public_key: &[u8],
    secret_key: &[u8],
    timestamp: &str,
    nonce: &str,
) -> Option<Vec<(&'static str, String)>> {
    if public_key.len() != sign::PUBLICKEYBYTES {
        return None;
    }
    let secret_key = sign::SecretKey::from_slice(secret_key)?;
    let payload = proof_payload(
        method,
        path,
        device_id,
        &STANDARD.encode(public_key),
        timestamp,
        nonce,
    );
    let signature = sign::sign_detached(payload.as_bytes(), &secret_key);
    Some(vec![
        (HEADER_TIMESTAMP, timestamp.to_owned()),
        (HEADER_NONCE, nonce.to_owned()),
        (HEADER_SIGNATURE, STANDARD.encode(signature.to_bytes())),
    ])
}

/// The path of `url` as reqwest sends it, without the query.
pub fn request_path(url: &str) -> Option<String> {
    url::Url::parse(url).ok().map(|url| url.path().to_owned())
}

/// The key proof plus, when given, the device token as a bearer token.
pub fn request_headers(
    proof: Vec<(&'static str, String)>,
    token: Option<&str>,
) -> Vec<(&'static str, String)> {
    let mut headers = proof;
    if let Some(token) = token.filter(|token| !token.is_empty()) {
        headers.push((HEADER_AUTHORIZATION, format!("Bearer {token}")));
    }
    headers
}

/// Adds the key proof (current time, fresh nonce) and the device token to a
/// request for `url`. The request goes out without proof when the device has
/// no usable key pair.
pub fn sign_request(
    request: reqwest::RequestBuilder,
    method: &str,
    url: &str,
    device_id: &str,
    token: Option<&str>,
) -> reqwest::RequestBuilder {
    let (secret_key, public_key) = hbb_common::config::Config::get_key_pair();
    let timestamp = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    let nonce = hex::encode(randombytes::randombytes(NONCE_BYTES));
    let proof = request_path(url)
        .and_then(|path| {
            proof_headers(
                method,
                &path,
                device_id,
                &public_key,
                &secret_key,
                &timestamp,
                &nonce,
            )
        })
        .unwrap_or_default();
    request_headers(proof, token)
        .into_iter()
        .fold(request, |request, (name, value)| {
            request.header(name, value)
        })
}

/// Base64 of the device's public key for the `public_key` body field, when
/// the key has the Ed25519 size.
pub fn public_key_b64() -> Option<String> {
    let (_, public_key) = hbb_common::config::Config::get_key_pair();
    (public_key.len() == sign::PUBLICKEYBYTES).then(|| STANDARD.encode(public_key))
}

/// This process's public key and key proof for a request another process
/// of this client sends in the device's name, for the pairing request
/// only (pairing_proof.rs). None for any other request or without a usable
/// key pair.
pub fn proof_for_others(method: &str, path: &str) -> Option<(String, Vec<(String, String)>)> {
    if !super::pairing_proof::signs_for_others(method, path) {
        return None;
    }
    let device_id = hbb_common::config::Config::get_id();
    let (secret_key, public_key) = hbb_common::config::Config::get_key_pair();
    let timestamp = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    let nonce = hex::encode(randombytes::randombytes(NONCE_BYTES));
    let headers = proof_headers(
        method,
        path,
        &device_id,
        &public_key,
        &secret_key,
        &timestamp,
        &nonce,
    )?;
    Some((
        STANDARD.encode(&public_key),
        headers
            .into_iter()
            .map(|(name, value)| (name.to_owned(), value))
            .collect(),
    ))
}

/// URL-encodes a query value.
pub fn query_value(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

/// The device token as stored, with the device id and API base it was issued for.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct StoredToken {
    pub token: String,
    pub device_id: String,
    pub api: String,
}

impl StoredToken {
    pub fn load() -> Self {
        Self {
            token: LocalConfig::get_option(OPTION_DEVICE_TOKEN),
            device_id: LocalConfig::get_option(OPTION_DEVICE_TOKEN_ID),
            api: LocalConfig::get_option(OPTION_DEVICE_TOKEN_API),
        }
    }

    /// The token when it was issued for this device id and API base. The
    /// server ends a device token when the id changes, and a token is never
    /// sent to another server. Its age does not matter.
    pub fn usable_for(&self, device_id: &str, api: &str) -> Option<&str> {
        if self.token.is_empty()
            || device_id.is_empty()
            || self.device_id != device_id
            || self.api != api
        {
            None
        } else {
            Some(&self.token)
        }
    }
}

pub fn store_token(token: &str, device_id: &str, api: &str) {
    LocalConfig::set_option(OPTION_DEVICE_TOKEN.to_owned(), token.to_owned());
    LocalConfig::set_option(OPTION_DEVICE_TOKEN_ID.to_owned(), device_id.to_owned());
    LocalConfig::set_option(OPTION_DEVICE_TOKEN_API.to_owned(), api.to_owned());
}

pub fn clear_token() {
    LocalConfig::set_option(OPTION_DEVICE_TOKEN.to_owned(), "".to_owned());
    LocalConfig::set_option(OPTION_DEVICE_TOKEN_ID.to_owned(), "".to_owned());
    LocalConfig::set_option(OPTION_DEVICE_TOKEN_API.to_owned(), "".to_owned());
}

fn non_empty_str<'a>(value: Option<&'a Value>) -> Option<&'a str> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
}

/// `status` of a register or status answer.
pub fn answer_status(answer: &Value) -> &str {
    non_empty_str(answer.get("status")).unwrap_or("")
}

/// `device_token` of a register or status answer.
pub fn answer_token(answer: &Value) -> Option<&str> {
    non_empty_str(answer.get("device_token"))
}

/// The enrollment part of a pairing redeem answer, which has the same shape
/// as a register answer.
pub fn redeem_enrollment(answer: &Value) -> &Value {
    answer.get("enrollment").unwrap_or(&Value::Null)
}

/// What an enrollment answer means for the stored device token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenChange {
    Keep,
    Replace(String),
    Clear,
}

pub fn token_change(status: &str, token: Option<&str>) -> TokenChange {
    if status == "rejected" {
        TokenChange::Clear
    } else if let Some(token) = token.filter(|token| !token.is_empty()) {
        TokenChange::Replace(token.to_owned())
    } else {
        TokenChange::Keep
    }
}

/// What the sync loop does next for enrollment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnrollmentStep {
    /// Nothing is due yet.
    Wait,
    /// Register, then ask for the status when the answer is "pending".
    Register,
    /// Ask for the status with the token, so a token the console issued
    /// after ending the old one reaches the device.
    CheckToken,
}

/// Until the device is approved and holds a token for the current id, it
/// registers every [`ENROLLMENT_RETRY`]. After that it checks its token every
/// [`TOKEN_CHECK_INTERVAL`]. `since_last` is the time since the last attempt,
/// None when there was none in this process.
pub fn next_enrollment_step(
    status: &str,
    has_token: bool,
    since_last: Option<Duration>,
) -> EnrollmentStep {
    let (step, interval) = if status == "approved" && has_token {
        (EnrollmentStep::CheckToken, TOKEN_CHECK_INTERVAL)
    } else {
        (EnrollmentStep::Register, ENROLLMENT_RETRY)
    };
    match since_last {
        Some(elapsed) if elapsed < interval => EnrollmentStep::Wait,
        _ => step,
    }
}

/// Config option with what the server last said about this device, as JSON
/// of [`Standing`]; empty when there is nothing to say. The status line reads
/// it.
pub const OPTION_STANDING: &str = "neodesk-device-standing";

/// What the server last said about this device.
#[derive(Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Standing {
    /// The heartbeat answered BANNED.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub banned: bool,
    /// "pending" or "rejected" from the last enrollment answer.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub enrollment: String,
    /// The server's message with a rejected enrollment.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub reason: String,
    /// What the signal server last answered to this device's key:
    /// "pending" (not approved yet) or "refused" (it keeps another key for
    /// this ID, or keeps the device out); empty once it took the key.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub signal: String,
}

/// The longest server message the status line shows.
const STANDING_REASON_MAX_CHARS: usize = 200;

impl Standing {
    fn read(stored: &str) -> Self {
        serde_json::from_str(stored).unwrap_or_default()
    }

    fn write(&self) -> String {
        if *self == Self::default() {
            return String::new();
        }
        serde_json::to_string(self).unwrap_or_default()
    }

    /// The stored standing after a heartbeat answer with `error`.
    pub fn after_heartbeat(stored: &str, error: Option<&str>) -> String {
        let mut standing = Self::read(stored);
        standing.banned = error == Some("BANNED");
        standing.write()
    }

    /// The stored standing after an enrollment answer.
    pub fn after_enrollment(stored: &str, status: &str, message: &str) -> String {
        let mut standing = Self::read(stored);
        standing.enrollment = match status {
            "pending" | "rejected" => status.to_owned(),
            _ => String::new(),
        };
        standing.reason = if status == "rejected" {
            message.trim().chars().take(STANDING_REASON_MAX_CHARS).collect()
        } else {
            String::new()
        };
        standing.write()
    }

    /// The stored standing after the signal server answered this device's
    /// key: "ok", "not_deployed" or "refused". Other answers change nothing.
    pub fn after_register_pk(stored: &str, answer: &str) -> String {
        let mut standing = Self::read(stored);
        standing.signal = match answer {
            "ok" => String::new(),
            "not_deployed" => "pending".to_owned(),
            "refused" => "refused".to_owned(),
            _ => return stored.to_owned(),
        };
        standing.write()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const TIMESTAMP: &str = "2026-11-22T10:00:00Z";
    const NONCE: &str = "6e6f6e6365";

    #[test]
    fn the_standing_says_why_the_server_refuses_this_device() {
        let read = |stored: &str| serde_json::from_str::<Value>(stored).unwrap();
        let removed = Standing::after_enrollment("", "rejected", "Device has been removed");
        assert_eq!(
            read(&removed),
            json!({"enrollment": "rejected", "reason": "Device has been removed"})
        );
        let banned = Standing::after_heartbeat(&removed, Some("BANNED"));
        assert_eq!(
            read(&banned),
            json!({"banned": true, "enrollment": "rejected", "reason": "Device has been removed"})
        );
        assert_eq!(Standing::after_heartbeat(&banned, None), removed);
        assert_eq!(Standing::after_enrollment(&removed, "approved", ""), "");
        assert_eq!(
            read(&Standing::after_enrollment("", "pending", "")),
            json!({"enrollment": "pending"})
        );
        assert_eq!(Standing::after_heartbeat("", None), "");
        assert_eq!(Standing::after_heartbeat("not json", Some("OTHER")), "");
    }

    #[test]
    fn the_standing_keeps_what_the_signal_server_said_about_the_key() {
        let read = |stored: &str| serde_json::from_str::<Value>(stored).unwrap();
        let refused = Standing::after_register_pk("", "refused");
        assert_eq!(read(&refused), json!({"signal": "refused"}));
        let pending = Standing::after_register_pk(&refused, "not_deployed");
        assert_eq!(read(&pending), json!({"signal": "pending"}));
        // Taking the key clears it, and only it.
        let banned = Standing::after_heartbeat(&refused, Some("BANNED"));
        assert_eq!(
            read(&Standing::after_register_pk(&banned, "ok")),
            json!({"banned": true})
        );
        assert_eq!(Standing::after_register_pk(&refused, "ok"), "");
        assert_eq!(Standing::after_register_pk(&refused, "uuid_mismatch"), refused);
        // An enrollment answer leaves the key's answer alone.
        assert_eq!(
            read(&Standing::after_enrollment(&refused, "approved", "")),
            json!({"signal": "refused"})
        );
    }

    fn key_pair() -> (sign::PublicKey, sign::SecretKey) {
        sign::keypair_from_seed(&sign::Seed([7; 32]))
    }

    fn header<'a>(headers: &'a [(&'static str, String)], name: &str) -> Option<&'a str> {
        headers
            .iter()
            .find(|(key, _)| *key == name)
            .map(|(_, value)| value.as_str())
    }

    #[test]
    fn proof_payload_has_the_exact_bytes() {
        let payload = proof_payload(
            "POST",
            "/api/devices/register",
            "123456789",
            "cHVibGljLWtleQ==",
            TIMESTAMP,
            NONCE,
        );
        assert_eq!(
            payload.as_bytes(),
            b"nd-enrollment-v1\nPOST\n/api/devices/register\n123456789\ncHVibGljLWtleQ==\n2026-11-22T10:00:00Z\n6e6f6e6365"
        );
    }

    #[test]
    fn proof_signature_verifies_and_binds_the_path() {
        let (pk, sk) = key_pair();
        let headers = proof_headers(
            "GET",
            "/api/devices/register/status",
            "123456789",
            &pk.0,
            &sk.0,
            TIMESTAMP,
            NONCE,
        )
        .unwrap();
        assert_eq!(
            header(&headers, "X-ND-Enrollment-Timestamp"),
            Some(TIMESTAMP)
        );
        assert_eq!(header(&headers, "X-ND-Enrollment-Nonce"), Some(NONCE));
        // Ed25519 signatures are deterministic, so the seed [7; 32] key always
        // signs this nd-enrollment-v1 payload with these bytes. The server's
        // Go crypto/ed25519 gives the same value.
        assert_eq!(
            header(&headers, "X-ND-Enrollment-Signature"),
            Some("FwtX80h2o3wuVl3Pe2Tkc5LCjMNhFAuURCMV1oASbl75h77AtC/v0tFsyMpRaCtD9+g1Nkj/i1NK2kBUkp3bAw==")
        );
        let decoded = STANDARD
            .decode(header(&headers, HEADER_SIGNATURE).unwrap())
            .unwrap();
        let mut bytes = [0u8; 64];
        bytes.copy_from_slice(&decoded);
        let signature = sign::Signature::from_bytes(&bytes).unwrap();
        let public_key_b64 = STANDARD.encode(pk.0);
        let signed = proof_payload(
            "GET",
            "/api/devices/register/status",
            "123456789",
            &public_key_b64,
            TIMESTAMP,
            NONCE,
        );
        assert!(sign::verify_detached(&signature, signed.as_bytes(), &pk));
        let other_path = proof_payload(
            "GET",
            "/api/devices/register",
            "123456789",
            &public_key_b64,
            TIMESTAMP,
            NONCE,
        );
        assert!(!sign::verify_detached(
            &signature,
            other_path.as_bytes(),
            &pk
        ));
    }

    #[test]
    fn proof_needs_an_ed25519_key_pair() {
        let (pk, sk) = key_pair();
        assert!(proof_headers("POST", "/", "1", &pk.0[..31], &sk.0, TIMESTAMP, NONCE).is_none());
        assert!(proof_headers("POST", "/", "1", &pk.0, &sk.0[..32], TIMESTAMP, NONCE).is_none());
    }

    #[test]
    fn request_path_keeps_the_prefix_and_drops_the_query() {
        assert_eq!(
            request_path("https://nd.example.com/desk/api/devices/register/status?device_id=1")
                .as_deref(),
            Some("/desk/api/devices/register/status")
        );
        assert_eq!(
            request_path("http://10.0.0.5:21114/api/pairing/redeem").as_deref(),
            Some("/api/pairing/redeem")
        );
    }

    #[test]
    fn bearer_only_for_a_token_of_this_device_and_server() {
        let stored = StoredToken {
            token: "tok".to_owned(),
            device_id: "123456789".to_owned(),
            api: "http://nd:21114".to_owned(),
        };
        let headers = request_headers(vec![], stored.usable_for("123456789", "http://nd:21114"));
        assert_eq!(header(&headers, "Authorization"), Some("Bearer tok"));

        let other_id = request_headers(vec![], stored.usable_for("987654321", "http://nd:21114"));
        assert_eq!(header(&other_id, "Authorization"), None);

        let other_server =
            request_headers(vec![], stored.usable_for("123456789", "http://other:21114"));
        assert_eq!(header(&other_server, "Authorization"), None);

        let empty = StoredToken::default();
        assert_eq!(empty.usable_for("", ""), None);
    }

    #[test]
    fn token_is_read_from_register_status_and_redeem_answers() {
        let register = json!({"status": "approved", "device_id": "1", "device_token": "reg-token"});
        assert_eq!(answer_status(&register), "approved");
        assert_eq!(answer_token(&register), Some("reg-token"));

        let status = json!({"status": "approved", "device_token": " status-token "});
        assert_eq!(answer_token(&status), Some("status-token"));

        let redeem = json!({
            "success": true,
            "device_token": "not-here",
            "enrollment": {"status": "approved", "device_token": "redeem-token"},
        });
        let enrollment = redeem_enrollment(&redeem);
        assert_eq!(answer_status(enrollment), "approved");
        assert_eq!(answer_token(enrollment), Some("redeem-token"));

        let pending = json!({"status": "pending", "device_token": ""});
        assert_eq!(answer_token(&pending), None);
        assert_eq!(
            answer_token(redeem_enrollment(&json!({"success": false}))),
            None
        );
    }

    #[test]
    fn rejected_clears_and_a_new_token_replaces() {
        assert_eq!(token_change("rejected", None), TokenChange::Clear);
        assert_eq!(token_change("rejected", Some("t")), TokenChange::Clear);
        assert_eq!(
            token_change("approved", Some("new")),
            TokenChange::Replace("new".to_owned())
        );
        assert_eq!(token_change("approved", None), TokenChange::Keep);
        assert_eq!(token_change("pending", None), TokenChange::Keep);
    }

    #[test]
    fn device_id_is_url_encoded() {
        assert_eq!(query_value("a b&c=d/é"), "a+b%26c%3Dd%2F%C3%A9");
        assert_eq!(query_value("123456789"), "123456789");
    }

    #[test]
    fn schedule_registers_every_120s_until_approved_with_a_token() {
        let secs = |s| Some(Duration::from_secs(s));
        assert_eq!(
            next_enrollment_step("", false, None),
            EnrollmentStep::Register
        );
        assert_eq!(
            next_enrollment_step("pending", false, secs(119)),
            EnrollmentStep::Wait
        );
        assert_eq!(
            next_enrollment_step("pending", false, secs(120)),
            EnrollmentStep::Register
        );
        assert_eq!(
            next_enrollment_step("rejected", false, secs(300)),
            EnrollmentStep::Register
        );
        // Approved earlier, but no token for this id yet.
        assert_eq!(
            next_enrollment_step("approved", false, secs(130)),
            EnrollmentStep::Register
        );
        // A token alone is not enough while the status is not approved.
        assert_eq!(
            next_enrollment_step("pending", true, secs(130)),
            EnrollmentStep::Register
        );
    }

    #[test]
    fn schedule_checks_the_token_every_600s_once_approved() {
        let secs = |s| Some(Duration::from_secs(s));
        assert_eq!(
            next_enrollment_step("approved", true, None),
            EnrollmentStep::CheckToken
        );
        assert_eq!(
            next_enrollment_step("approved", true, secs(130)),
            EnrollmentStep::Wait
        );
        assert_eq!(
            next_enrollment_step("approved", true, secs(599)),
            EnrollmentStep::Wait
        );
        assert_eq!(
            next_enrollment_step("approved", true, secs(600)),
            EnrollmentStep::CheckToken
        );
    }
}
