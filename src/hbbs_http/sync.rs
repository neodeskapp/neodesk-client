use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

#[cfg(not(any(target_os = "ios")))]
use crate::{ui_interface::get_builtin_option, Connection};
#[cfg(not(target_os = "ios"))]
use crate::telemetry;
use hbb_common::{
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::{self, keys, Config, LocalConfig},
    log,
    tokio::{self, sync::broadcast, time::Instant},
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const TIME_HEARTBEAT: Duration = Duration::from_secs(15);
const TIME_TELEMETRY: Duration = Duration::from_secs(60);
const TELEMETRY_JITTER_SECS: u64 = 30;
const UPLOAD_SYSINFO_TIMEOUT: Duration = Duration::from_secs(120);
const TIME_CONN: Duration = Duration::from_secs(3);

fn telemetry_interval(device_id: &str) -> Duration {
    let jitter = device_id.bytes().fold(0_u64, |value, byte| {
        value.wrapping_mul(31).wrapping_add(byte as u64)
    }) % (TELEMETRY_JITTER_SECS + 1);
    TIME_TELEMETRY + Duration::from_secs(jitter)
}

#[cfg(not(any(target_os = "ios")))]
lazy_static::lazy_static! {
    static ref SENDER : Mutex<broadcast::Sender<Vec<i32>>> = Mutex::new(start_hbbs_sync());
    static ref PRO: Arc<Mutex<bool>> = Default::default();
}

#[cfg(not(any(target_os = "ios")))]
pub fn start() {
    let _sender = SENDER.lock().unwrap();
}

#[cfg(not(target_os = "ios"))]
pub fn signal_receiver() -> broadcast::Receiver<Vec<i32>> {
    SENDER.lock().unwrap().subscribe()
}

/// Closes the connections with these ids, as the console's disconnect list does.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn disconnect(conns: Vec<i32>) {
    SENDER.lock().unwrap().send(conns).ok();
}

#[cfg(not(any(target_os = "ios")))]
fn start_hbbs_sync() -> broadcast::Sender<Vec<i32>> {
    let (tx, _rx) = broadcast::channel::<Vec<i32>>(16);
    std::thread::spawn(move || start_hbbs_sync_async());
    return tx;
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StrategyOptions {
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub config_options: HashMap<String, String>,
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub extra: HashMap<String, String>,
}

struct InfoUploaded {
    uploaded: bool,
    url: String,
    last_uploaded: Option<Instant>,
    id: String,
    username: Option<String>,
}

impl Default for InfoUploaded {
    fn default() -> Self {
        Self {
            uploaded: false,
            url: "".to_owned(),
            last_uploaded: None,
            id: "".to_owned(),
            username: None,
        }
    }
}

impl InfoUploaded {
    fn uploaded(url: String, id: String, username: String) -> Self {
        Self {
            uploaded: true,
            url,
            last_uploaded: None,
            id,
            username: Some(username),
        }
    }
}

#[cfg(not(any(target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
async fn start_hbbs_sync_async() {
    let mut interval = crate::rustdesk_interval(tokio::time::interval_at(
        Instant::now() + TIME_CONN,
        TIME_CONN,
    ));
    let mut last_sent: Option<Instant> = None;
    let mut last_telemetry_sent: Option<Instant> = None;
    let mut info_uploaded = InfoUploaded::default();
    let mut sysinfo_ver = "".to_owned();
    let mut telemetry_results: Vec<Value> = Vec::new();
    loop {
        tokio::select! {
            _ = interval.tick() => {
                let url = heartbeat_url();
                let id = Config::get_id();
                if url.is_empty() {
                    *PRO.lock().unwrap() = false;
                    crate::hbbs_http::betterdesk::sync_client_branding().await;
                    crate::hbbs_http::betterdesk::sync_device_enrollment().await;
                    continue;
                }
                if config::option2bool("stop-service", &Config::get_option("stop-service")) {
                    continue;
                }
                let conns = Connection::alive_conns();
                if info_uploaded.uploaded && (url != info_uploaded.url || id != info_uploaded.id) {
                    info_uploaded.uploaded = false;
                    *PRO.lock().unwrap() = false;
                }
                // For Windows:
                // We can't skip uploading sysinfo when the username is empty, because the username may
                // always be empty before login. We also need to upload the other sysinfo info.
                //
                // https://github.com/rustdesk/rustdesk/discussions/8031
                // We still need to check the username after uploading sysinfo, because
                // 1. The username may be empty when logining in, and it can be fetched after a while.
                //    In this case, we need to upload sysinfo again.
                // 2. The username may be changed after uploading sysinfo, and we need to upload sysinfo again.
                //
                // The Windows session will switch to the last user session before the restart,
                // so it may be able to get the username before login.
                // But strangely, sometimes we can get the username before login,
                // we may not be able to get the username before login after the next restart.
                let mut v = crate::get_sysinfo();
                let sys_username = v["username"].as_str().unwrap_or_default().to_string();
                // Though the username comparison is only necessary on Windows,
                // we still keep the comparison on other platforms for consistency.
                let need_upload = (!info_uploaded.uploaded || info_uploaded.username.as_ref() != Some(&sys_username)) &&
                    info_uploaded.last_uploaded.map(|x| x.elapsed() >= UPLOAD_SYSINFO_TIMEOUT).unwrap_or(true);
                if need_upload {
                    v["version"] = json!(crate::VERSION);
                    v["id"] = json!(id);
                    v["uuid"] = json!(crate::encode64(hbb_common::get_uuid()));
                    let ab_name = Config::get_option(keys::OPTION_PRESET_ADDRESS_BOOK_NAME);
                    if !ab_name.is_empty() {
                        v[keys::OPTION_PRESET_ADDRESS_BOOK_NAME] = json!(ab_name);
                    }
                    let ab_tag = Config::get_option(keys::OPTION_PRESET_ADDRESS_BOOK_TAG);
                    if !ab_tag.is_empty() {
                        v[keys::OPTION_PRESET_ADDRESS_BOOK_TAG] = json!(ab_tag);
                    }
                    let ab_alias = Config::get_option(keys::OPTION_PRESET_ADDRESS_BOOK_ALIAS);
                    if !ab_alias.is_empty() {
                        v[keys::OPTION_PRESET_ADDRESS_BOOK_ALIAS] = json!(ab_alias);
                    }
                    let ab_password = Config::get_option(keys::OPTION_PRESET_ADDRESS_BOOK_PASSWORD);
                    if !ab_password.is_empty() {
                        v[keys::OPTION_PRESET_ADDRESS_BOOK_PASSWORD] = json!(ab_password);
                    }
                    let ab_note = Config::get_option(keys::OPTION_PRESET_ADDRESS_BOOK_NOTE);
                    if !ab_note.is_empty() {
                        v[keys::OPTION_PRESET_ADDRESS_BOOK_NOTE] = json!(ab_note);
                    }
                    let username = get_builtin_option(keys::OPTION_PRESET_USERNAME);
                    if !username.is_empty() {
                        v[keys::OPTION_PRESET_USERNAME] = json!(username);
                    }
                    let strategy_name = get_builtin_option(keys::OPTION_PRESET_STRATEGY_NAME);
                    if !strategy_name.is_empty() {
                        v[keys::OPTION_PRESET_STRATEGY_NAME] = json!(strategy_name);
                    }
                    let device_group_name = get_builtin_option(keys::OPTION_PRESET_DEVICE_GROUP_NAME);
                    if !device_group_name.is_empty() {
                        v[keys::OPTION_PRESET_DEVICE_GROUP_NAME] = json!(device_group_name);
                    }
                    let device_username = Config::get_option(keys::OPTION_PRESET_DEVICE_USERNAME);
                    if !device_username.is_empty() {
                        v["username"] = json!(device_username);
                    }
                    let device_name = Config::get_option(keys::OPTION_PRESET_DEVICE_NAME);
                    if !device_name.is_empty() {
                        v["hostname"] = json!(device_name);
                    }
                    let note = Config::get_option(keys::OPTION_PRESET_NOTE);
                    if !note.is_empty() {
                        v[keys::OPTION_PRESET_NOTE] = json!(note);
                    }
                    let v = v.to_string();
                    let mut hash = "".to_owned();
                    if crate::is_public(&url) {
                        use sha2::{Digest, Sha256};
                        let mut hasher = Sha256::new();
                        hasher.update(url.as_bytes());
                        hasher.update(&v.as_bytes());
                        let res = hasher.finalize();
                        hash = STANDARD.encode(&res[..]);
                        let old_hash = config::Status::get("sysinfo_hash");
                        let ver = config::Status::get("sysinfo_ver"); // sysinfo_ver is the version of sysinfo on server's side
                        if hash == old_hash {
                            // When the api doesn't exist, Ok("") will be returned in test.
                            let samever = match crate::post_request(url.replace("heartbeat", "sysinfo_ver"), "".to_owned(), "").await {
                                Ok(x)  => {
                                    sysinfo_ver = x.clone();
                                    *PRO.lock().unwrap() = true;
                                    x == ver
                                }
                                _ => {
                                    false // to make sure Pro can be assigned in below post for old
                                            // hbbs pro not supporting sysinfo_ver, use false for ensuring
                                }
                            };
                            if samever {
                                info_uploaded = InfoUploaded::uploaded(url.clone(), id.clone(), sys_username);
                                log::info!("sysinfo not changed, skip upload");
                                continue;
                            }
                        }
                    }
                    match crate::post_request(url.replace("heartbeat", "sysinfo"), v, "").await {
                        Ok(x)  => {
                            if x == "SYSINFO_UPDATED" {
                                info_uploaded = InfoUploaded::uploaded(url.clone(), id.clone(), sys_username);
                                log::info!("sysinfo updated");
                                if !hash.is_empty() {
                                    config::Status::set("sysinfo_hash", hash);
                                    config::Status::set("sysinfo_ver", sysinfo_ver.clone());
                                }
                                *PRO.lock().unwrap() = true;
                            } else if x == "ID_NOT_FOUND" {
                                info_uploaded.last_uploaded = None; // next heartbeat will upload sysinfo again
                            } else {
                                info_uploaded.last_uploaded = Some(Instant::now());
                            }
                        }
                        _ => {
                            info_uploaded.last_uploaded = Some(Instant::now());
                        }
                    }
                }
                if conns.is_empty()
                    && telemetry_results.is_empty()
                    && last_sent.map(|x| x.elapsed() < TIME_HEARTBEAT).unwrap_or(false)
                {
                    continue;
                }
                last_sent = Some(Instant::now());
                let mut v = Value::default();
                v["id"] = json!(id);
                v["uuid"] = json!(crate::encode64(hbb_common::get_uuid()));
                v["ver"] = json!(hbb_common::get_version_number(crate::VERSION));
                if !conns.is_empty() {
                    v["conns"] = json!(conns);
                }
                let modified_at = LocalConfig::get_option("strategy_timestamp").parse::<i64>().unwrap_or(0);
                v["modified_at"] = json!(modified_at);
                crate::hbbs_http::betterdesk::merge_device_identity(&mut v);
                let telemetry_due = !telemetry_results.is_empty()
                    || last_telemetry_sent
                        .map(|sent| sent.elapsed() >= telemetry_interval(&id))
                        .unwrap_or(true);
                let secure_command_poll = config::is_remote_connection_mode_controlled();
                if telemetry_due {
                    v["telemetry_schema"] = json!(1);
                    let mut telemetry_payload = telemetry::heartbeat();
                    if !telemetry_results.is_empty() {
                        telemetry_payload["results"] =
                            Value::Array(std::mem::take(&mut telemetry_results));
                    }
                    v["telemetry"] = telemetry_payload;
                    last_telemetry_sent = Some(Instant::now());
                }
                let mut request = v.clone();
                let telemetry_base = url.trim_end_matches("/api/heartbeat");
                let use_secure_request = telemetry_due || secure_command_poll;
                if use_secure_request {
                    match crate::hbbs_http::betterdesk::fetch_telemetry_server_key().await {
                        Ok((key_id, public_key)) => {
                            match telemetry::seal_payload(&v, &key_id, &public_key, &id) {
                                Ok(envelope) => {
                                    request = json!({
                                        "id": id,
                                        "uuid": v["uuid"],
                                        "betterdesk_envelope": envelope,
                                    });
                                }
                                Err(err) => {
                                    log::warn!("BetterDesk telemetry payload was not sealed: {err}");
                                    if telemetry_base.starts_with("https://") {
                                        request = v.clone();
                                    }
                                }
                            }
                        }
                        Err(err) => {
                            log::debug!("BetterDesk telemetry key unavailable: {err}");
                            if telemetry_base.starts_with("https://") {
                                request = v.clone();
                            }
                        }
                    }
                }
                if !telemetry_base.starts_with("https://") && request.get("betterdesk_envelope").is_none() {
                    if telemetry_due {
                        log::debug!(
                            "BetterDesk telemetry omitted because the configured API is plain HTTP"
                        );
                    }
                    request = json!({
                        "id": id,
                        "uuid": v["uuid"],
                    });
                }
                if let Ok(s) = crate::post_request(url.clone(), request.to_string(), "").await {
                    if let Some(answer) = read_heartbeat_answer(&s, telemetry::open_response) {
                        let HeartbeatAnswer { fields: mut rsp, mut sealed_only, sealed: secure_response } = answer;
                        if rsp.remove("sysinfo").is_some() {
                            info_uploaded.uploaded = false;
                            config::Status::set("sysinfo_hash", "".to_owned());
                            log::info!("sysinfo required to forcely update");
                        }
                        if let Some(conns)  = rsp.remove("disconnect") {
                                if let Ok(conns) = serde_json::from_value::<Vec<i32>>(conns) {
                                    SENDER.lock().unwrap().send(conns).ok();
                                }
                        }
                        if let Some(rsp_modified_at) = sealed_only.remove("modified_at") {
                            if let Ok(rsp_modified_at) = serde_json::from_value::<i64>(rsp_modified_at) {
                                if rsp_modified_at != modified_at {
                                    LocalConfig::set_option("strategy_timestamp".to_string(), rsp_modified_at.to_string());
                                }
                            }
                        }
                        if let Some(strategy) = sealed_only.remove("strategy") {
                            if let Ok(strategy) = serde_json::from_value::<StrategyOptions>(strategy) {
                                log::info!("strategy updated");
                                handle_config_options(strategy.config_options);
                            }
                        }
                        if let Some(command) = sealed_only.remove("connection_mode_command") {
                            if secure_response && telemetry_base.starts_with("https://") {
                                let result =
                                    telemetry::process_connection_mode_command(&command);
                                let status = result
                                    .get("status")
                                    .and_then(Value::as_str)
                                    .unwrap_or("rejected");
                                if matches!(status, "applied" | "already_applied") {
                                    log::info!(
                                        "connection mode command {}: {}",
                                        result
                                            .get("command_id")
                                            .and_then(Value::as_str)
                                            .unwrap_or(""),
                                        status
                                    );
                                }
                            } else {
                                log::warn!(
                                    "Ignoring connection mode command without HTTPS-protected envelope"
                                );
                            }
                        }
                        if let Some(commands) = sealed_only.remove("telemetry_commands") {
                            if let Ok(commands) = serde_json::from_value::<Vec<Value>>(commands) {
                                telemetry_results = telemetry::process_commands(&commands);
                            }
                        }
                    }
                }
                crate::hbbs_http::betterdesk::sync_client_branding().await;
                crate::hbbs_http::betterdesk::sync_device_enrollment().await;
            }
        }
    }
}

/// Fields of a heartbeat answer that count only from inside the sealed
/// envelope. They run commands on the device and change its settings, and
/// the plain fields can come from anyone between the device and the server.
#[cfg(not(target_os = "ios"))]
const SEALED_ONLY: &[&str] = &[
    "telemetry_commands",
    "connection_mode_command",
    "strategy",
    "modified_at",
];

/// A heartbeat answer as the sync loop reads it.
#[cfg(not(target_os = "ios"))]
struct HeartbeatAnswer {
    /// The plain fields, with the fields of the sealed envelope over them,
    /// without the [`SEALED_ONLY`] ones.
    fields: HashMap<String, Value>,
    /// The [`SEALED_ONLY`] fields from inside the envelope.
    sealed_only: HashMap<String, Value>,
    /// True when an envelope signed with the server key opened.
    sealed: bool,
}

#[cfg(not(target_os = "ios"))]
fn read_heartbeat_answer(
    text: &str,
    open: impl FnOnce(&Value) -> Result<Value, String>,
) -> Option<HeartbeatAnswer> {
    let mut fields = serde_json::from_str::<HashMap<String, Value>>(text).ok()?;
    fields.retain(|key, _| !SEALED_ONLY.contains(&key.as_str()));
    let mut sealed_only = HashMap::new();
    let mut sealed = false;
    if let Some(envelope) = fields.remove("betterdesk_envelope") {
        match open(&envelope) {
            Ok(response) => {
                sealed = true;
                for (key, value) in response.as_object().into_iter().flatten() {
                    if SEALED_ONLY.contains(&key.as_str()) {
                        sealed_only.insert(key.clone(), value.clone());
                    } else {
                        fields.insert(key.clone(), value.clone());
                    }
                }
            }
            Err(err) => log::warn!("BetterDesk response decryption failed: {err}"),
        }
    }
    Some(HeartbeatAnswer {
        fields,
        sealed_only,
        sealed,
    })
}

fn heartbeat_url() -> String {
    let url = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if url.is_empty() || crate::is_public(&url) {
        return "".to_owned();
    }
    format!("{}/api/heartbeat", url)
}

fn strategy_option_locked(key: &str) -> bool {
    // Bake-in override-* / overwrite maps must win over heartbeat strategy.
    if crate::ui_interface::is_option_fixed(key) {
        return true;
    }
    if matches!(key, "conn-type" | "remote-connection-mode") {
        return true;
    }
    // Support Agent: never accept server/network flips that would leave incoming-only fleet.
    if config::is_incoming_only() {
        matches!(
            key,
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER
                | keys::OPTION_RELAY_SERVER
                | keys::OPTION_API_SERVER
                | keys::OPTION_KEY
                | "disable-settings"
                | "hide-server-settings"
                | "hide-help-cards"
        )
    } else {
        false
    }
}

fn handle_config_options(config_options: HashMap<String, String>) {
    let mut options = Config::get_options();
    let default_settings = config::DEFAULT_SETTINGS.read().unwrap().clone();
    for (k, v) in config_options.iter() {
        if strategy_option_locked(k) {
            log::debug!("strategy skipped locked option {k}");
            continue;
        }
        // Priority: user config > default advanced options.
        // Only when default advanced options are also empty, remove user option (fallback to built-in default);
        // otherwise insert an empty value so user config remains present.
        if v.is_empty() && default_settings.get(k).map_or("", |v| v).is_empty() {
            options.remove(k);
        } else {
            options.insert(k.to_string(), v.to_string());
        }
    }
    Config::set_options(options);
}

#[allow(unused)]
#[cfg(not(any(target_os = "ios")))]
pub fn is_pro() -> bool {
    *PRO.lock().unwrap() || crate::common::is_custom_client()
}

// Fire-and-forget by design: the switch flow must not block on this POST.
// If the device clock is outside the server's accepted window, the server
// returns its current Unix time and this task re-signs and retries once.
#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn register_switch_grant(switch_uuid: String) {
    tokio::spawn(async move {
        let api_server = crate::ui_interface::get_api_server();
        if api_server.is_empty() || crate::is_public(&api_server) {
            return;
        }
        use hbb_common::sodiumoxide::crypto::{hash::sha256, sign};
        let switch_code = crate::encode64(sha256::hash(switch_uuid.as_bytes()).0);
        let switch_code_verifier = switch_code_verifier(&switch_code);
        let timestamp = (hbb_common::get_time() / 1000).to_string();
        let id = Config::get_id();
        let kp = Config::get_key_pair();
        let Some(sk) = sign::SecretKey::from_slice(&kp.0) else {
            log::error!("Failed to register switch grant: no device key");
            return;
        };
        let url = format!("{}/api/switch-grant", api_server);
        let mut timestamp = timestamp;
        for attempt in 0..2 {
            let signature = sign::sign_detached(
                &switch_grant_signed_msg(&id, &switch_code_verifier, &timestamp),
                &sk,
            );
            let body = json!({
                "id": &id,
                "switch_code_verifier": &switch_code_verifier,
                "timestamp": &timestamp,
                "signature": crate::encode64(signature.to_bytes()),
            })
            .to_string();
            let response = match crate::post_request(url.clone(), body, "").await {
                Ok(response) => response,
                Err(e) => {
                    log::error!("Failed to register switch grant: {}", e);
                    return;
                }
            };
            let response = match serde_json::from_str::<Value>(&response) {
                Ok(response) => response,
                Err(e) => {
                    log::error!("Failed to register switch grant: invalid response: {}", e);
                    return;
                }
            };
            match response.get("accepted").and_then(Value::as_bool) {
                Some(true) => return,
                Some(false) => {}
                None => {
                    log::error!("Failed to register switch grant: missing accepted response");
                    return;
                }
            }
            let Some(server_time) = response["server_time"].as_i64() else {
                log::error!("Failed to register switch grant: rejected by server");
                return;
            };
            if attempt == 0 {
                log::warn!("Switch grant timestamp rejected, retrying with server time");
                timestamp = server_time.to_string();
            } else {
                log::error!("Failed to register switch grant after retrying with server time");
            }
        }
    });
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn switch_code_verifier(switch_code: &str) -> String {
    use hbb_common::sodiumoxide::crypto::hash::sha256;

    let prefix = b"switch-grant-verifier\0";
    let mut msg = Vec::with_capacity(prefix.len() + switch_code.len());
    msg.extend_from_slice(prefix);
    msg.extend_from_slice(switch_code.as_bytes());
    crate::encode64(sha256::hash(&msg).0)
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn switch_grant_signed_msg(id: &str, switch_code_verifier: &str, timestamp: &str) -> Vec<u8> {
    let mut msg =
        Vec::with_capacity(13 + id.len() + 1 + switch_code_verifier.len() + 1 + timestamp.len());
    msg.extend_from_slice(b"switch-grant\0");
    msg.extend_from_slice(id.as_bytes());
    msg.push(0);
    msg.extend_from_slice(switch_code_verifier.as_bytes());
    msg.push(0);
    msg.extend_from_slice(timestamp.as_bytes());
    msg
}

#[cfg(all(
    test,
    feature = "flutter",
    not(any(target_os = "android", target_os = "ios"))
))]
mod tests {
    use std::time::Duration;

    use serde_json::{json, Value};

    use super::{
        read_heartbeat_answer, switch_code_verifier, switch_grant_signed_msg, telemetry_interval,
        HeartbeatAnswer, TIME_TELEMETRY,
    };

    #[test]
    fn telemetry_interval_is_spread_across_devices() {
        let first = telemetry_interval("device-a");
        let second = telemetry_interval("device-b");
        assert!(first >= TIME_TELEMETRY);
        assert!(first <= TIME_TELEMETRY + Duration::from_secs(30));
        assert!(second >= TIME_TELEMETRY);
        assert!(second <= TIME_TELEMETRY + Duration::from_secs(30));
    }

    #[test]
    fn test_switch_code_verifier_is_not_raw_switch_code() {
        let switch_code = "code-abc";
        let verifier = switch_code_verifier(switch_code);
        assert_ne!(verifier, switch_code);
        assert_eq!(verifier, switch_code_verifier(switch_code));
        assert_eq!(
            verifier,
            "dMIn3uiPe77XodFB5IKi7PrKJ7l7+zVquNn0ObSaHQc="
        );
    }

    #[test]
    fn test_switch_grant_signed_msg_layout() {
        let expected: Vec<u8> = [
            &b"switch-grant\0"[..],
            b"id1",
            b"\0",
            b"c1",
            b"\0",
            b"1700000000",
        ]
        .concat();
        assert_eq!(switch_grant_signed_msg("id1", "c1", "1700000000"), expected);
    }

    fn file_read() -> Value {
        json!({"id": 7, "command": "files.read", "args": {"path": "/etc/shadow"}})
    }

    /// Reads `answer`; its envelope opens to `opened`, or fails to open.
    fn read(answer: Value, opened: Result<Value, String>) -> HeartbeatAnswer {
        read_heartbeat_answer(&answer.to_string(), |_| opened).unwrap()
    }

    #[test]
    fn telemetry_commands_of_a_plain_answer_are_not_run() {
        let answer = read(
            json!({"modified_at": 1, "telemetry_commands": [file_read()]}),
            Err("the answer has no envelope".to_owned()),
        );
        assert!(!answer.sealed);
        assert_eq!(answer.fields.get("telemetry_commands"), None);
        assert_eq!(answer.sealed_only.get("telemetry_commands"), None);
    }

    #[test]
    fn telemetry_commands_come_from_inside_the_envelope_only() {
        let envelope = json!({"version": 1});
        let answer = read(
            json!({"betterdesk_envelope": envelope}),
            Ok(json!({"telemetry_commands": [file_read()]})),
        );
        assert!(answer.sealed);
        assert_eq!(
            answer.sealed_only.get("telemetry_commands"),
            Some(&json!([file_read()]))
        );

        let beside = json!({"betterdesk_envelope": envelope, "telemetry_commands": [file_read()]});
        let answer = read(beside.clone(), Ok(json!({"sysinfo": true})));
        assert!(answer.sealed);
        assert_eq!(answer.fields.get("sysinfo"), Some(&json!(true)));
        assert_eq!(answer.fields.get("telemetry_commands"), None);
        assert_eq!(answer.sealed_only.get("telemetry_commands"), None);

        let answer = read(beside, Err("response signature mismatch".to_owned()));
        assert!(!answer.sealed);
        assert_eq!(answer.fields.get("telemetry_commands"), None);
        assert_eq!(answer.sealed_only.get("telemetry_commands"), None);
    }

    #[test]
    fn a_connection_mode_command_counts_only_from_inside_the_envelope() {
        let command = json!({"command_id": "c1", "mode": "incoming-only", "revision": 2});
        let answer = read(
            json!({"betterdesk_envelope": {"version": 1}}),
            Ok(json!({"connection_mode_command": command})),
        );
        assert_eq!(answer.sealed_only.get("connection_mode_command"), Some(&command));

        let answer = read(
            json!({"betterdesk_envelope": {"version": 1}, "connection_mode_command": command}),
            Ok(json!({})),
        );
        assert!(answer.sealed);
        assert_eq!(answer.fields.get("connection_mode_command"), None);
        assert_eq!(answer.sealed_only.get("connection_mode_command"), None);
    }

    #[test]
    fn strategy_and_its_time_count_only_from_inside_the_envelope() {
        let strategy = json!({"config_options": {"custom-rendezvous-server": "evil.example"}});
        let answer = read(
            json!({"modified_at": 5, "strategy": strategy}),
            Err("the answer has no envelope".to_owned()),
        );
        for key in ["strategy", "modified_at"] {
            assert_eq!(answer.fields.get(key), None, "{key} of a plain answer");
            assert_eq!(answer.sealed_only.get(key), None, "{key} of a plain answer");
        }

        let answer = read(
            json!({"betterdesk_envelope": {"version": 1}, "modified_at": 5, "strategy": strategy}),
            Ok(json!({"modified_at": 4})),
        );
        assert_eq!(answer.fields.get("strategy"), None);
        assert_eq!(answer.sealed_only.get("strategy"), None);
        assert_eq!(answer.sealed_only.get("modified_at"), Some(&json!(4)));

        let answer = read(
            json!({"betterdesk_envelope": {"version": 1}}),
            Ok(json!({"modified_at": 4, "strategy": strategy})),
        );
        assert_eq!(answer.sealed_only.get("strategy"), Some(&strategy));
    }
}
