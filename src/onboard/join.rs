//! Add a computer: redeem a join code at the console.
//!
//! `POST /api/onboard/join` with the device's identity answers the ID
//! server, relay, API address and key, and a device token. The console has
//! approved the device, named it and put it into the invite's folder by then.
//!
//! The request proves the device's key the way register and pairing do
//! (`X-ND-Enrollment-*` headers, hbbs_http/enrollment.rs), made by the
//! device's server process (device_key.rs). The console refuses a join for
//! a device ID it knows unless it proves the key it holds for that ID; a
//! device it does not know yet joins without a proof too (L483).

use serde_json::{json, Value};

use super::http::{Answer, Http, OnboardError};
use crate::hbbs_http::{enrollment, pairing_proof};

/// The headers of a key proof, name and value; empty for none.
pub type Proof = Vec<(String, String)>;

/// The device as the console learns it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceIdentity {
    pub device_id: String,
    pub uuid: String,
    pub hostname: String,
    pub platform: String,
    pub version: String,
    pub public_key: Option<String>,
}

impl DeviceIdentity {
    /// This device under `device_id`, with the fields register sends and
    /// no public key.
    pub fn of_this_device(device_id: String) -> Self {
        Self {
            device_id,
            uuid: String::from_utf8_lossy(&hbb_common::get_uuid()).into_owned(),
            hostname: crate::hostname(),
            platform: std::env::consts::OS.to_owned(),
            version: crate::VERSION.to_owned(),
            public_key: None,
        }
    }

    /// This device for a join under `device_id`, the ID of the device's
    /// server process, with the public key and key proof the join sends.
    /// `from_server_process` is the key and proof that process made for
    /// the join, None when it did not answer. Runs outside any async
    /// runtime: it may ask the server process for its key over IPC.
    pub fn for_join(
        device_id: String,
        from_server_process: Option<(String, Proof)>,
    ) -> (Self, Proof) {
        let mut device = Self::of_this_device(device_id);
        // The key the device's server process signs with, not one this
        // process makes (device_key.rs, L438)
        let (public_key, proof) = super::device_key::key_and_proof_for_join(
            from_server_process,
            || {
                crate::ipc::get_config(crate::ipc::IPC_PUBLIC_KEY)
                    .ok()
                    .flatten()
            },
            enrollment::public_key_b64,
            hbb_common::config::Config::holds_secrets(),
            || {
                enrollment::own_proof(
                    pairing_proof::METHOD,
                    pairing_proof::JOIN_PATH,
                    &device.device_id,
                )
            },
        );
        device.public_key = public_key;
        (device, proof.unwrap_or_default())
    }

    pub fn to_json(&self) -> Value {
        let mut body = json!({
            "device_id": self.device_id,
            "uuid": self.uuid,
            "hostname": self.hostname,
            "platform": self.platform,
            "version": self.version,
        });
        if let Some(public_key) = &self.public_key {
            body["public_key"] = Value::String(public_key.clone());
        }
        body
    }
}

/// How to reach the server, as a redeem answers it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ServerSettings {
    pub id_server: String,
    pub relay_server: String,
    pub api_server: String,
    pub key: String,
}

impl ServerSettings {
    pub fn from_answer(server: &Value) -> Self {
        let text = |key: &str| {
            server
                .get(key)
                .and_then(Value::as_str)
                .map(str::trim)
                .unwrap_or("")
                .to_owned()
        };
        Self {
            id_server: text("id_server"),
            relay_server: text("relay_server"),
            api_server: text("api_server"),
            key: text("key"),
        }
    }
}

/// A redeemed join code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Joined {
    pub server: ServerSettings,
    pub device_token: String,
    /// The name the invite gave the device, empty when it gave none.
    pub device_name: String,
    pub folder_id: Option<i64>,
    /// The console's base address.
    pub console: String,
}

/// What a join answer means.
pub fn join_result(answer: &Answer) -> Result<Joined, OnboardError> {
    if let Some(err) = answer.common_error() {
        return Err(err);
    }
    if answer.body.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(OnboardError::Server(answer.status));
    }
    let server = ServerSettings::from_answer(answer.body.get("server").unwrap_or(&Value::Null));
    let device_token = answer.text("device_token");
    if server.id_server.is_empty() || device_token.is_empty() {
        return Err(OnboardError::Server(answer.status));
    }
    let device = answer.body.get("device").unwrap_or(&Value::Null);
    Ok(Joined {
        server,
        device_token,
        device_name: device
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_owned(),
        folder_id: device.get("folder_id").and_then(Value::as_i64),
        console: answer.text("console"),
    })
}

/// Redeems `code` for `device`, with the key proof `proof` (headers, empty
/// for none) made for `device`'s ID and public key.
pub async fn redeem_join(
    http: &Http,
    code: &str,
    device: &DeviceIdentity,
    proof: &[(String, String)],
) -> Result<Joined, OnboardError> {
    if device.device_id.is_empty() {
        return Err(OnboardError::NoDeviceId);
    }
    let mut body = device.to_json();
    body["code"] = Value::String(code.to_owned());
    let answer = http
        .post_with_headers(pairing_proof::JOIN_PATH, &body, None, proof)
        .await?;
    join_result(&answer)
}

/// The options a join sets, in the order the server dialog sets them. An
/// empty value removes the option.
pub fn option_changes(server: &ServerSettings) -> Vec<(&'static str, String)> {
    use hbb_common::config::keys;
    vec![
        (
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
            server.id_server.clone(),
        ),
        (keys::OPTION_RELAY_SERVER, server.relay_server.clone()),
        (keys::OPTION_API_SERVER, server.api_server.clone()),
        (keys::OPTION_KEY, server.key.clone()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer(status: u16, body: Value) -> Answer {
        Answer { status, body }
    }

    fn joined_body() -> Value {
        json!({
            "success": true,
            "server": {
                "id_server": "desk.example.com",
                "relay_server": "desk.example.com:21117",
                "api_server": "https://desk.example.com:21121",
                "key": "c2VydmVyLWtleQ==",
            },
            "device_token": "ab".repeat(32),
            "device": {"id": "123456789", "name": "Reception PC", "folder_id": 7},
            "console": "https://desk.example.com",
        })
    }

    #[test]
    fn a_join_answer_carries_server_token_and_name() {
        let joined = join_result(&answer(200, joined_body())).unwrap();
        assert_eq!(
            joined.server,
            ServerSettings {
                id_server: "desk.example.com".to_owned(),
                relay_server: "desk.example.com:21117".to_owned(),
                api_server: "https://desk.example.com:21121".to_owned(),
                key: "c2VydmVyLWtleQ==".to_owned(),
            }
        );
        assert_eq!(joined.device_token, "ab".repeat(32));
        assert_eq!(joined.device_name, "Reception PC");
        assert_eq!(joined.folder_id, Some(7));
        assert_eq!(joined.console, "https://desk.example.com");
    }

    #[test]
    fn an_invite_for_many_computers_names_none() {
        let mut body = joined_body();
        body["device"] = json!({"id": "123456789", "name": "", "folder_id": null});
        let joined = join_result(&answer(200, body)).unwrap();
        assert_eq!(joined.device_name, "");
        assert_eq!(joined.folder_id, None);
    }

    #[test]
    fn an_answer_without_server_or_token_is_an_error() {
        let mut body = joined_body();
        body["device_token"] = json!("");
        assert_eq!(
            join_result(&answer(200, body)),
            Err(OnboardError::Server(200))
        );
        let mut body = joined_body();
        body["server"] = json!({});
        assert_eq!(
            join_result(&answer(200, body)),
            Err(OnboardError::Server(200))
        );
        assert_eq!(
            join_result(&answer(200, json!({"success": false}))),
            Err(OnboardError::Server(200))
        );
    }

    #[test]
    fn refusals_keep_the_servers_reason() {
        assert_eq!(
            join_result(&answer(
                404,
                json!({"success": false, "error": "invalid_or_expired"})
            )),
            Err(OnboardError::InvalidOrExpired)
        );
        assert_eq!(
            join_result(&answer(
                403,
                json!({"success": false, "error": "device_refused", "message": "Device is banned"})
            )),
            Err(OnboardError::Refused("Device is banned".to_owned()))
        );
    }

    #[test]
    fn the_body_has_the_device_and_the_public_key_only_when_known() {
        let device = DeviceIdentity {
            device_id: "123456789".to_owned(),
            uuid: "uuid-1".to_owned(),
            hostname: "reception".to_owned(),
            platform: "windows".to_owned(),
            version: "1.4.6".to_owned(),
            public_key: None,
        };
        assert_eq!(
            device.to_json(),
            json!({"device_id": "123456789", "uuid": "uuid-1", "hostname": "reception",
                   "platform": "windows", "version": "1.4.6"})
        );
        let with_key = DeviceIdentity {
            public_key: Some("cGs=".to_owned()),
            ..device
        };
        assert_eq!(with_key.to_json()["public_key"], json!("cGs="));
    }

    #[test]
    fn options_set_server_relay_api_and_key() {
        let joined = join_result(&answer(200, joined_body())).unwrap();
        assert_eq!(
            option_changes(&joined.server),
            vec![
                ("custom-rendezvous-server", "desk.example.com".to_owned()),
                ("relay-server", "desk.example.com:21117".to_owned()),
                ("api-server", "https://desk.example.com:21121".to_owned()),
                ("key", "c2VydmVyLWtleQ==".to_owned()),
            ]
        );
    }
}
