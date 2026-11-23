//! Pairing with a short code from the NeoDesk console.
//!
//! The user types the server and the code the console shows. The client sends
//! `POST {api}/api/pairing/redeem` with its identity and the device key proof.
//! The answer carries the connection settings, the server key and the
//! enrollment result. On "approved" or "pending" the client takes over the
//! settings and keeps the enrollment status and device token the same way the
//! register request does.

// Only the Flutter FFI calls the network part of this module.
#![cfg_attr(
    not(any(target_os = "android", target_os = "ios", feature = "flutter")),
    allow(dead_code)
)]

use hbb_common::{
    config::keys,
    log, tokio,
};
use serde_json::{json, Value};

use super::{create_http_client_async_with_url, enrollment, neodesk, pairing_proof};

pub const MESSAGE_CODE_INVALID: &str = "The code is wrong or has expired.";
const MESSAGE_SERVER_INVALID: &str = "Enter the address of your NeoDesk server.";
const MESSAGE_CODE_EMPTY: &str = "Enter the code.";
const MESSAGE_UNREACHABLE: &str = "Could not reach the server.";
const MESSAGE_REFUSED: &str = "The server did not accept the request.";
const MESSAGE_NOT_ADMITTED: &str = "The server did not admit this device.";

/// Upper-cases the code and drops spaces and dashes, as the server does.
pub fn normalize_code(code: &str) -> String {
    code.chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .flat_map(char::to_uppercase)
        .collect()
}

/// Where a pairing request goes, derived from what the user typed as server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingTarget {
    /// API base without a trailing slash.
    pub api: String,
    /// True when the user typed an http(s) URL. Only then it becomes api-server.
    pub typed_url: bool,
    /// The ID server to use when the answer names none.
    pub id_server: String,
}

/// An http(s) URL is used as the API base as typed. A host or host:port is
/// an ID server, and the API base follows the rule `get_api_server` uses
/// without api-server: plain http on the NeoDesk API port.
pub fn pairing_target(server: &str) -> Option<PairingTarget> {
    let server = server.trim();
    let lower = server.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        let url = url::Url::parse(server).ok()?;
        if url.query().is_some() || url.fragment().is_some() || !url.username().is_empty() {
            return None;
        }
        let host = url.host_str().filter(|host| !host.is_empty())?;
        return Some(PairingTarget {
            api: server.trim_end_matches('/').to_owned(),
            typed_url: true,
            id_server: host.to_owned(),
        });
    }
    let server = server.trim_end_matches('/');
    if server.is_empty()
        || server.ends_with(':')
        || server.contains(|c: char| c.is_whitespace() || matches!(c, '/' | '?' | '#' | '@'))
    {
        return None;
    }
    Some(PairingTarget {
        api: crate::common::api_server_of_id_server(server),
        typed_url: false,
        id_server: server.to_owned(),
    })
}

fn text(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or("")
        .to_owned()
}

/// The settings a redeem answer sets, in the order the ID/Relay server
/// dialog sets them. api-server stays empty unless the user typed a URL, so
/// it is derived from the ID server.
pub fn option_changes(answer: &Value, target: &PairingTarget) -> Vec<(&'static str, String)> {
    let connection = answer.get("connection").unwrap_or(&Value::Null);
    let signal = text(connection.get("signal"));
    let mut changes = vec![
        (
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
            if signal.is_empty() {
                target.id_server.clone()
            } else {
                signal
            },
        ),
        (keys::OPTION_RELAY_SERVER, text(connection.get("relay"))),
        (
            keys::OPTION_API_SERVER,
            if target.typed_url {
                target.api.clone()
            } else {
                String::new()
            },
        ),
    ];
    let server_key = text(answer.get("server_key"));
    if !server_key.is_empty() {
        changes.push((keys::OPTION_KEY, server_key));
    }
    changes
}

/// What the UI shows after a pairing attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairResult {
    pub ok: bool,
    pub status: String,
    pub message: String,
}

impl PairResult {
    fn error(message: impl Into<String>) -> Self {
        Self {
            ok: false,
            status: String::new(),
            message: message.into(),
        }
    }

    pub fn to_json(&self) -> String {
        json!({
            "ok": self.ok,
            "status": self.status,
            "message": self.message,
        })
        .to_string()
    }
}

/// What a redeem answer means for the user. Only "approved" and "pending"
/// count as paired.
pub fn redeem_result(http_status: u16, answer: &Value) -> PairResult {
    if http_status == 401 {
        return PairResult::error(MESSAGE_CODE_INVALID);
    }
    if http_status == 400 {
        return PairResult::error(MESSAGE_REFUSED);
    }
    if !(200..300).contains(&http_status) {
        return PairResult::error(format!("The server answered with HTTP {http_status}."));
    }
    let enrollment = enrollment::redeem_enrollment(answer);
    let status = enrollment::answer_status(enrollment);
    let message = text(enrollment.get("message"));
    match status {
        "approved" | "pending" => PairResult {
            ok: true,
            status: status.to_owned(),
            message,
        },
        _ => PairResult {
            ok: false,
            status: status.to_owned(),
            message: if message.is_empty() {
                MESSAGE_NOT_ADMITTED.to_owned()
            } else {
                message
            },
        },
    }
}

/// The result of a redeem request and, when the server admitted the device,
/// the settings and enrollment state to keep.
pub struct Pairing {
    pub result: PairResult,
    pub options: Vec<(&'static str, String)>,
    pub token: Option<String>,
    pub device_id: String,
    pub api: String,
}

impl Pairing {
    fn failed(message: impl Into<String>) -> Self {
        Self {
            result: PairResult::error(message),
            options: Vec::new(),
            token: None,
            device_id: String::new(),
            api: String::new(),
        }
    }
}

/// Redeems `code` at `server` for `device_id`. Changes nothing locally, see
/// [`pair_and_apply`].
pub async fn pair_with_code(server: &str, code: &str, device_id: String) -> Pairing {
    let Some(target) = pairing_target(server).filter(|target| !crate::is_public(&target.api))
    else {
        return Pairing::failed(MESSAGE_SERVER_INVALID);
    };
    let code = normalize_code(code);
    if code.is_empty() {
        return Pairing::failed(MESSAGE_CODE_EMPTY);
    }
    if device_id.is_empty() {
        return Pairing::failed(MESSAGE_NOT_ADMITTED);
    }

    let mut body = json!({
        "code": code,
        "device_id": device_id,
        "uuid": String::from_utf8_lossy(&hbb_common::get_uuid()).into_owned(),
        "hostname": crate::hostname(),
        "platform": std::env::consts::OS,
        "version": crate::VERSION,
        "device_type": neodesk::CLIENT_PRODUCT,
    });
    let url = format!("{}{}", target.api, pairing_proof::PATH);
    // The device's server process proves its key, the one the server binds
    // (pairing_proof.rs, L440); this process signs only when none runs
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let from_service = match enrollment::request_path(&url) {
        Some(path) => crate::ipc::pairing_proof(&path).await,
        None => None,
    };
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let from_service: Option<(String, Vec<(String, String)>)> = None;
    let (public_key, proof) = pairing_proof::proof_for_pairing(
        from_service.map(|(key, headers)| (Some(key), Some(headers))),
        || (enrollment::public_key_b64(), None),
    );
    if let Some(public_key) = public_key {
        body["public_key"] = Value::String(public_key);
    }

    let client = create_http_client_async_with_url(&url).await;
    let request = client.post(&url).json(&body);
    let request = match proof {
        Some(headers) => headers.into_iter().fold(request, |request, (name, value)| {
            request.header(name, value)
        }),
        None => enrollment::sign_request(request, pairing_proof::METHOD, &url, &device_id, None),
    };
    let resp = match request.send().await {
        Ok(resp) => resp,
        Err(err) => {
            log::warn!("NeoDesk pairing request failed: {err}");
            return Pairing::failed(MESSAGE_UNREACHABLE);
        }
    };
    let http_status = resp.status().as_u16();
    let text = resp.text().await.unwrap_or_default();
    let answer: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
    let result = redeem_result(http_status, &answer);
    if !result.ok {
        log::info!(
            "NeoDesk pairing refused: HTTP {http_status}, status={}",
            result.status
        );
        return Pairing {
            result,
            ..Pairing::failed("")
        };
    }
    Pairing {
        options: option_changes(&answer, &target),
        token: enrollment::answer_token(enrollment::redeem_enrollment(&answer)).map(str::to_owned),
        result,
        device_id,
        api: target.api,
    }
}

#[tokio::main(flavor = "current_thread")]
async fn pair_with_code_blocking(server: String, code: String, device_id: String) -> Pairing {
    pair_with_code(&server, &code, device_id).await
}

/// Pairs with `code` and, when the server admitted the device, takes over its
/// settings and keeps the enrollment status and device token. Runs outside
/// any async runtime, because setting options goes to the service over IPC.
pub fn pair_and_apply(server: String, code: String) -> PairResult {
    // The service's ID, which its sync loop sends the token with.
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let device_id = crate::ipc::get_id();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let device_id = hbb_common::config::Config::get_id();
    let pairing = pair_with_code_blocking(server, code, device_id);
    if pairing.result.ok {
        for (key, value) in pairing.options {
            crate::ui_interface::set_option(key.to_owned(), value);
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        let send = |payload: String| {
            crate::ipc::set_config(crate::ipc::IPC_JOINED_DEVICE_TOKEN, payload)
        };
        #[cfg(any(target_os = "android", target_os = "ios"))]
        let send = |_: String| -> hbb_common::ResultType<()> {
            hbb_common::bail!("the server runs in this process")
        };
        keep_enrollment(
            &pairing.result.status,
            pairing.token.as_deref(),
            &pairing.device_id,
            &pairing.api,
            send,
        );
        log::info!("NeoDesk pairing done, status={}", pairing.result.status);
    }
    pairing.result
}

/// Keeps the device token of a pairing where the sync loop runs: `send` hands
/// it to the server process (the service of an installed client) the way a
/// join does; when no server process takes it, this process keeps it.
/// Without a token there is nothing to hand over: the sync loop registers on
/// its own and gets the status.
fn keep_enrollment(
    status: &str,
    token: Option<&str>,
    device_id: &str,
    api: &str,
    send: impl FnOnce(String) -> hbb_common::ResultType<()>,
) {
    let Some(token) = token.filter(|token| !token.is_empty()) else {
        return;
    };
    let payload = json!({
        "status": status,
        "token": token,
        "device_id": device_id,
        "api": api,
    })
    .to_string();
    if let Err(err) = send(payload) {
        log::info!("NeoDesk pairing keeps its device token in this process: {err}");
        neodesk::record_enrollment_answer(status, Some(token), device_id, api);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn option<'a>(changes: &'a [(&'static str, String)], key: &str) -> Option<&'a str> {
        changes
            .iter()
            .find(|(name, _)| *name == key)
            .map(|(_, value)| value.as_str())
    }

    #[test]
    fn code_is_upper_cased_without_spaces_and_dashes() {
        assert_eq!(normalize_code(" ab3-k9 x\t"), "AB3K9X");
        assert_eq!(normalize_code("AB3K9X"), "AB3K9X");
        assert_eq!(normalize_code(" - "), "");
    }

    #[test]
    fn api_base_for_a_host_follows_the_id_server_rule() {
        let target = pairing_target("nd.example.com").unwrap();
        assert_eq!(target.api, "http://nd.example.com:21121");
        assert!(!target.typed_url);
        assert_eq!(target.id_server, "nd.example.com");

        let target = pairing_target(" 10.0.0.5:21116/ ").unwrap();
        assert_eq!(target.api, "http://10.0.0.5:21121");
        assert_eq!(target.id_server, "10.0.0.5:21116");
    }

    #[test]
    fn api_base_for_a_url_is_the_url_as_typed() {
        let target = pairing_target("https://nd.example.com/").unwrap();
        assert_eq!(target.api, "https://nd.example.com");
        assert!(target.typed_url);
        assert_eq!(target.id_server, "nd.example.com");

        let target = pairing_target("HTTP://10.0.0.5:21114/desk").unwrap();
        assert_eq!(target.api, "HTTP://10.0.0.5:21114/desk");
        assert_eq!(target.id_server, "10.0.0.5");
    }

    #[test]
    fn unusable_server_input_is_refused() {
        assert_eq!(pairing_target(""), None);
        assert_eq!(pairing_target("   "), None);
        assert_eq!(pairing_target("https://"), None);
        assert_eq!(pairing_target("https://nd.example.com/?x=1"), None);
        assert_eq!(pairing_target("nd.example.com/desk"), None);
        assert_eq!(pairing_target("nd example.com"), None);
        assert_eq!(pairing_target("nd.example.com:"), None);
    }

    fn redeem_answer() -> Value {
        json!({
            "success": true,
            "id": "pc_1",
            "enrollment": {"status": "approved", "device_id": "123456789"},
            "connection": {
                "host": "nd.example.com",
                "signal": "nd.example.com:21116",
                "relay": "nd.example.com:21117",
                "ws_signal": "nd.example.com:21118",
                "ws_relay": "nd.example.com:21119",
                "api": "https://nd.example.com:21114",
                "relay_servers": "",
            },
            "server_key": "c2VydmVyLWtleQ==",
        })
    }

    #[test]
    fn redeem_answer_sets_the_connection_options() {
        let changes = option_changes(&redeem_answer(), &pairing_target("nd.example.com").unwrap());
        assert_eq!(
            changes,
            vec![
                (
                    "custom-rendezvous-server",
                    "nd.example.com:21116".to_owned()
                ),
                ("relay-server", "nd.example.com:21117".to_owned()),
                ("api-server", String::new()),
                ("key", "c2VydmVyLWtleQ==".to_owned()),
            ]
        );
    }

    #[test]
    fn typed_url_becomes_api_server_and_missing_values_fall_back() {
        let answer = json!({
            "success": true,
            "enrollment": {"status": "pending"},
            "connection": {"signal": "", "relay": ""},
            "server_key": "",
        });
        let changes = option_changes(&answer, &pairing_target("https://nd.example.com").unwrap());
        assert_eq!(
            option(&changes, "custom-rendezvous-server"),
            Some("nd.example.com")
        );
        assert_eq!(option(&changes, "relay-server"), Some(""));
        assert_eq!(
            option(&changes, "api-server"),
            Some("https://nd.example.com")
        );
        assert_eq!(option(&changes, "key"), None);
    }

    #[test]
    fn redeem_answers_map_to_results() {
        let wrong_code = redeem_result(
            401,
            &json!({"success": false, "error": "invalid_or_expired"}),
        );
        assert!(!wrong_code.ok);
        assert_eq!(wrong_code.message, MESSAGE_CODE_INVALID);
        assert_eq!(wrong_code.message, "The code is wrong or has expired.");

        let approved = redeem_result(200, &redeem_answer());
        assert!(approved.ok);
        assert_eq!(approved.status, "approved");

        let pending = redeem_result(
            200,
            &json!({"success": true, "enrollment": {"status": "pending", "message": "Waiting for operator approval"}}),
        );
        assert!(pending.ok);
        assert_eq!(pending.status, "pending");

        let rejected = redeem_result(
            200,
            &json!({"success": false, "enrollment": {"status": "rejected", "message": "Device is banned"}}),
        );
        assert!(!rejected.ok);
        assert_eq!(rejected.status, "rejected");
        assert_eq!(rejected.message, "Device is banned");

        assert!(!redeem_result(400, &Value::Null).ok);
        assert!(!redeem_result(502, &Value::Null).ok);
        assert!(!redeem_result(200, &Value::Null).ok);
    }

    #[test]
    fn a_paired_device_token_goes_to_the_server_process() {
        let mut sent = None;
        keep_enrollment(
            "pending",
            Some("t0ken"),
            "123456789",
            "https://nd.example.com",
            |payload| {
                sent = Some(payload);
                Ok(())
            },
        );
        let sent: Value =
            serde_json::from_str(&sent.expect("nothing went to the server process")).unwrap();
        assert_eq!(
            sent,
            json!({
                "status": "pending",
                "token": "t0ken",
                "device_id": "123456789",
                "api": "https://nd.example.com",
            })
        );
    }

    #[test]
    fn result_json_has_ok_status_and_message() {
        let value: Value =
            serde_json::from_str(&redeem_result(200, &redeem_answer()).to_json()).unwrap();
        assert_eq!(
            value,
            json!({"ok": true, "status": "approved", "message": ""})
        );
    }
}
