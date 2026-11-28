//! The installed receiver (receiver plan, step 5): the app on a supported
//! computer with its service and tray.
//!
//! - Its install-time file ([`install_file`]) makes it the receiver, gives
//!   it the server, and the token, group or admission it enrolls with at the
//!   first start of the service. The token goes from the file once the
//!   server answered ([`enrollment_answered`]).
//! - A support link of its own server runs in the service's process, with
//!   the computer's enrolled ID: the window passes the person's answers on
//!   over the service's pipe ([`ask_service`]), and the tray takes the links
//!   that a quick support file started later hands over
//!   ([`listen_for_handoffs`]). A link of another server still starts a
//!   quick support app of its own.
//! - Session approval and removing the app follow the server's policy
//!   ([`apply_policy`], [`receiver_policy`]); a caller the server vouches
//!   for gets in without Allow when the rule allows it ([`unattended`]).

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};

use hbb_common::{
    config::{self, keys, Config},
    log, password_security,
};
use serde_json::{json, Value};

use super::{
    caller, install_file::InstallFile, join::DeviceIdentity, link, receiver_policy, support,
    unattended, Grants, Kind, ServerSettings, GRANTS, OPTION_CONSOLE, REQUESTS, STATE, SUPPORT,
};

/// The install-time file this process took, with what is left of it.
static FILE: Mutex<Option<InstallFile>> = Mutex::new(None);
/// Set while a support session runs in the receiver's service process.
pub(super) static SESSION: AtomicBool = AtomicBool::new(false);
/// The organization's policy and the device's access policy, as the
/// unattended access rule takes them ([`unattended::Policy`]).
static POLICY: Mutex<unattended::Policy> = Mutex::new(unattended::Policy {
    org: None,
    access: None,
});
/// The policy applied last.
static APPLIED: Mutex<Option<receiver_policy::Resolved>> = Mutex::new(None);
/// Whether the uninstall entry follows the policy already (None: not
/// touched in this process).
static UNINSTALL_APPLIED: Mutex<Option<bool>> = Mutex::new(None);
/// The options a session in the service's process changes, as they were.
static SAVED_OPTIONS: Mutex<Option<Vec<(String, String)>>> = Mutex::new(None);
/// The fixed options the install-time file added.
static INSERTED: Mutex<Vec<String>> = Mutex::new(Vec::new());

/// Reads the install-time file in the app's folder, when the app may take
/// it, and applies it. Runs once at the start of every process, right after
/// the signed config, whose settings win.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn load_install_file() {
    #[cfg(windows)]
    let text = crate::platform::windows::receiver_install_file_text();
    #[cfg(not(windows))]
    let text: Option<String> = None;
    let Some(text) = text else {
        return;
    };
    let file = InstallFile::parse(&text);
    apply_install_file(&file);
    *FILE.lock().unwrap() = Some(file);
}

/// Makes this process the receiver of the file's server. A value the
/// signed config fixes stays as the signed config has it.
#[cfg_attr(not(windows), allow(dead_code))]
pub(super) fn apply_install_file(file: &InstallFile) {
    let mut fixed = config::OVERWRITE_SETTINGS.write().unwrap();
    let before: Vec<String> = fixed.keys().cloned().collect();
    apply_to(file, &mut config::HARD_SETTINGS.write().unwrap(), &mut fixed);
    let mut inserted = INSERTED.lock().unwrap();
    for key in fixed.keys() {
        if !before.contains(key) && !inserted.contains(key) {
            inserted.push(key.clone());
        }
    }
}

/// A quick support app started from the receiver's folder (a link of
/// another server) is not the receiver: what the install-time file set
/// goes again.
pub(super) fn forget_install_file() {
    if FILE.lock().unwrap().take().is_none() {
        return;
    }
    let mut fixed = config::OVERWRITE_SETTINGS.write().unwrap();
    for key in INSERTED.lock().unwrap().drain(..) {
        fixed.remove(&key);
    }
}

/// [`apply_install_file`] on the maps of the hard settings and the fixed
/// options.
fn apply_to(
    file: &InstallFile,
    hard: &mut std::collections::HashMap<String, String>,
    fixed: &mut std::collections::HashMap<String, String>,
) {
    if file.receiver {
        hard.insert(super::RECEIVER_KEY.to_owned(), "Y".to_owned());
    }
    for (key, value) in [
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, file.server.trim().to_owned()),
        (keys::OPTION_KEY, file.key.trim().to_owned()),
        (keys::OPTION_API_SERVER, file.api_or_default()),
        (OPTION_CONSOLE, file.console_or_api()),
    ] {
        if !value.is_empty() && !fixed.contains_key(key) {
            fixed.insert(key.to_owned(), value);
        }
    }
}

/// The install-time file as this process has it.
pub fn install_file() -> Option<InstallFile> {
    FILE.lock().unwrap().clone()
}

/// The fields the registration carries from the install-time file: the
/// token with the group, or the admission. Empty once the server answered.
pub fn enrollment_fields() -> Vec<(&'static str, String)> {
    install_file()
        .map(|file| file.enrollment_fields())
        .unwrap_or_default()
}

/// The server answered a registration that carried the install-time file's
/// token or admission: the file is written again without them.
pub fn enrollment_answered(status: &str) {
    if status.is_empty() {
        return;
    }
    let mut file = FILE.lock().unwrap();
    let Some(current) = file.as_ref().filter(|f| f.has_secrets()) else {
        return;
    };
    let kept = current.without_secrets();
    #[cfg(windows)]
    match crate::platform::windows::write_receiver_install_file(&kept.render()) {
        Ok(()) => log::info!("The enrollment token left the install-time file"),
        Err(err) => log::warn!("The install-time file kept its token: {err}"),
    }
    *file = Some(kept);
}

/// True in a process of the installed receiver: the receiver runs from the
/// folder it was installed to.
pub fn installed() -> bool {
    #[cfg(windows)]
    {
        static INSTALLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
        *INSTALLED.get_or_init(|| {
            super::is_receiver() && crate::platform::windows::is_cur_exe_the_installed()
        })
    }
    #[cfg(not(windows))]
    false
}

/// True in the installed receiver's window and tray: the service's process
/// runs the support sessions and keeps the device token.
pub fn forwards_to_service() -> bool {
    !super::is_quick_support() && installed() && !Config::holds_secrets()
}

/// Whether a support link of the console at `host` belongs to the server
/// this receiver was installed for.
pub fn takes_link_of(host: &str) -> bool {
    install_file().map_or(false, |file| file.takes_link_of(host))
}

/// The support link of `text` when the installed receiver runs its session
/// itself: a support link or a bare code of its own server.
pub fn own_support_link(text: &str) -> Option<String> {
    let invite = link::parse(text).ok()?;
    if invite.kind == Some(Kind::Join) {
        return None;
    }
    let console = invite.console.clone().or_else(super::known_console)?;
    if !takes_link_of(&console.host_port()) {
        return None;
    }
    Some(format!("{}/s/{}", console.base(), invite.code))
}

/// Sends a request to the service's process and returns its answer.
pub async fn ask_service_async(request: Value) -> Option<Value> {
    let mut conn = crate::ipc::connect(1_000, "").await.ok()?;
    conn.send(&crate::ipc::Data::NdSupport(request.to_string()))
        .await
        .ok()?;
    match conn.next_timeout(3_000).await {
        Ok(Some(crate::ipc::Data::NdSupport(answer))) => serde_json::from_str(&answer).ok(),
        _ => None,
    }
}

/// [`ask_service_async`] for a caller outside any async runtime.
pub fn ask_service(request: Value) -> Option<Value> {
    super::block_on(ask_service_async(request)).flatten()
}

/// Answers a request of the receiver's window or tray in the service's
/// process (ipc.rs, `Data::NdSupport`).
pub fn service_request(request: &str) -> String {
    let request: Value = serde_json::from_str(request).unwrap_or(Value::Null);
    let flag = |name: &str| request.get(name).and_then(Value::as_bool) == Some(true);
    let ok = |ok: bool| json!({ "ok": ok }).to_string();
    if !super::is_receiver() || super::is_quick_support() || !Config::holds_secrets() {
        return ok(false);
    }
    match request.get("do").and_then(Value::as_str) {
        Some("start") => ok(start_in_service(
            request.get("link").and_then(Value::as_str).unwrap_or(""),
        )),
        Some("state") => super::local_state_json(),
        Some("consent") => {
            super::consent(
                flag("allow"),
                Grants {
                    clipboard: flag("clipboard"),
                    file_transfer: flag("file_transfer"),
                },
            );
            ok(true)
        }
        Some("end") => {
            super::end_support();
            ok(true)
        }
        Some("feedback") => {
            super::send_feedback(
                request
                    .get("answers")
                    .and_then(Value::as_str)
                    .unwrap_or("{}")
                    .to_owned(),
            );
            ok(true)
        }
        Some("dismiss") => {
            super::dismiss_support();
            ok(true)
        }
        _ => ok(false),
    }
}

/// Starts the session of a support link of this receiver's server in the
/// service's process. A link while a session runs changes nothing.
fn start_in_service(link: &str) -> bool {
    let Ok(invite) = link::parse(link) else {
        return false;
    };
    if invite.kind != Some(Kind::Support) {
        return false;
    }
    let Some(console) = invite.console.clone().or_else(super::known_console) else {
        return false;
    };
    if !takes_link_of(&console.host_port()) {
        log::info!("A support link of another server is not the receiver's");
        return false;
    }
    if SUPPORT.lock().unwrap().is_some() {
        return true;
    }
    STATE.update(|s| {
        *s = super::State::default();
        s.server = Some(console.host.clone());
        s.link = Some(link.to_owned());
    });
    log::info!("The receiver runs a support session with its own ID");
    super::start_support(console, invite.code);
    true
}

/// The receiver in its service's process, as quick support sees it: the
/// server and the enrolled ID stay, the session's password and grants
/// apply while it runs.
pub(super) struct ServiceHost;

impl support::SupportHost for ServiceHost {
    fn device(&self) -> DeviceIdentity {
        DeviceIdentity::of_this_device(Config::get_id())
    }

    fn apply_server(&self, _server: &ServerSettings) {
        // The server stays the receiver's; only the way in changes for the
        // session: the one-time password that goes to the supporter
        let options = super::quick_support_options();
        let mut saved = SAVED_OPTIONS.lock().unwrap();
        if saved.is_none() {
            *saved = Some(
                options
                    .iter()
                    .map(|(key, _)| (key.to_string(), Config::get_option(key)))
                    .collect(),
            );
        }
        for (key, value) in options {
            Config::set_option(key.to_owned(), value.to_owned());
        }
        password_security::update_temporary_password();
    }

    fn set_grants(&self, grants: Grants) {
        *GRANTS.lock().unwrap() = grants;
    }

    fn password(&self) -> String {
        password_security::temporary_password()
    }

    fn in_session(&self) -> bool {
        !crate::server::AUTHED_CONNS.lock().unwrap().is_empty()
    }

    fn asking(&self) -> Option<String> {
        REQUESTS.newest()
    }

    fn caller_channel(&self, channel: Option<caller::Channel>) {
        match channel {
            Some(channel) => caller::open(channel),
            None => caller::close(),
        }
    }

    fn shut_down(&self) {
        caller::close();
        if let Some(saved) = SAVED_OPTIONS.lock().unwrap().take() {
            for (key, value) in saved {
                Config::set_option(key, value);
            }
        }
        crate::hbbs_http::sync::disconnect(crate::Connection::alive_conns());
        password_security::update_temporary_password();
    }
}

/// Keeps the access policy of a sealed heartbeat answer (`access_policy`,
/// None when the answer had none), with every field of the contract.
pub fn note_access_policy(policy: Option<&Value>) {
    POLICY.lock().unwrap().access = Some(policy.map(unattended::access_policy_of));
}

/// The policy the unattended access rule takes.
pub fn unattended_policy() -> unattended::Policy {
    POLICY.lock().unwrap().clone()
}

/// Applies the answer of GET /api/nd/device-policy: session approval (the
/// organization's mode and allowed operators for the unattended access
/// rule), and whether the app may be removed.
pub fn apply_policy(answer: &Value) {
    let mode = answer
        .pointer("/policies/connection/mode")
        .and_then(Value::as_str)
        .map(|m| m.trim().to_owned());
    let operators = unattended::names_of(answer.pointer("/policies/security/allowed_operators"));
    let org = unattended::OrgPolicy { mode, operators };
    let resolved = receiver_policy::resolve(
        answer
            .pointer("/policies/security/allow_uninstall")
            .and_then(Value::as_bool),
    );
    let before = POLICY.lock().unwrap().org.replace(org.clone());
    let applied_before = APPLIED.lock().unwrap().replace(resolved);
    if before.as_ref() != Some(&org) || applied_before != Some(resolved) {
        log::info!(
            "Receiver policy: session approval {}, {} allowed operators, removing allowed {}",
            org.mode.as_deref().unwrap_or("not set"),
            org.operators.len(),
            resolved.allow_uninstall
        );
    }
    // A session sets its own way in and puts these back when it ends
    if !SESSION.load(Ordering::Relaxed) {
        for (key, value) in receiver_policy::connection_options() {
            if Config::get_option(key) != value {
                Config::set_option(key.to_owned(), value.to_owned());
            }
        }
    }
    let mut uninstall = UNINSTALL_APPLIED.lock().unwrap();
    if *uninstall != Some(resolved.allow_uninstall) {
        #[cfg(windows)]
        match crate::platform::windows::set_receiver_uninstall_allowed(resolved.allow_uninstall) {
            Ok(()) => *uninstall = Some(resolved.allow_uninstall),
            Err(err) => log::warn!("The app's uninstall entry was not changed: {err}"),
        }
        #[cfg(not(windows))]
        {
            *uninstall = Some(resolved.allow_uninstall);
        }
    }
}

/// The policy applied last, for tests.
#[cfg(test)]
pub fn applied() -> Option<receiver_policy::Resolved> {
    *APPLIED.lock().unwrap()
}

/// The pipe a quick support file started in this Windows session hands its
/// link to: the installed receiver's tray listens on it.
pub fn handoff_postfix(session: u32) -> String {
    format!("_qs_handoff_{session}")
}

/// The answers on the hand-off pipe.
const TAKEN: &str = "taken";
const DECLINED: &str = "declined";

/// Serves the hand-off pipe `postfix`: each link goes to `take`, and the
/// sender hears whether it was taken.
pub async fn serve_handoffs(
    postfix: String,
    take: std::sync::Arc<dyn Fn(String) -> bool + Send + Sync>,
) {
    #[allow(unused_imports)]
    use hbb_common::futures::StreamExt as _;
    let mut incoming = match crate::ipc::new_listener(&postfix).await {
        Ok(incoming) => incoming,
        Err(err) => {
            log::error!("The receiver takes no support links from other apps: {err}");
            return;
        }
    };
    while let Some(conn) = incoming.next().await {
        let Ok(conn) = conn else {
            continue;
        };
        let take = take.clone();
        hbb_common::tokio::spawn(async move {
            let mut conn = crate::ipc::Connection::new(conn);
            if let Ok(Some(crate::ipc::Data::UrlLink(link))) = conn.next_timeout(2_000).await {
                let taken = hbb_common::tokio::task::spawn_blocking(move || take(link))
                    .await
                    .unwrap_or(false);
                let answer = if taken { TAKEN } else { DECLINED };
                conn.send(&crate::ipc::Data::UrlLink(answer.to_owned()))
                    .await
                    .ok();
            }
        });
    }
}

/// Hands `link` to the app serving the hand-off pipe `postfix`; true when
/// it took it.
pub async fn send_handoff(postfix: &str, link: &str) -> bool {
    let Ok(mut conn) = crate::ipc::connect_unnamespaced(1_000, postfix).await else {
        return false;
    };
    if conn
        .send(&crate::ipc::Data::UrlLink(link.to_owned()))
        .await
        .is_err()
    {
        return false;
    }
    matches!(
        conn.next_timeout(5_000).await,
        Ok(Some(crate::ipc::Data::UrlLink(answer))) if answer == TAKEN
    )
}

/// In a quick support app: hands `link` to the installed receiver of this
/// Windows session, which runs the session with the computer's own ID.
/// True when it took it.
pub fn hand_to_receiver(link: &str) -> bool {
    #[cfg(windows)]
    {
        let Some(session) = crate::platform::windows::get_current_process_session_id() else {
            return false;
        };
        let postfix = handoff_postfix(session);
        let link = link.to_owned();
        let taken = super::block_on(async move { send_handoff(&postfix, &link).await })
            .unwrap_or(false);
        if taken {
            log::info!("The installed receiver took the support link");
        }
        taken
    }
    #[cfg(not(windows))]
    {
        let _ = link;
        false
    }
}

/// In the installed receiver's tray: takes the support links quick support
/// files started in this session hand over, for links of its own server.
pub fn listen_for_handoffs() {
    #[cfg(windows)]
    {
        if !installed() {
            return;
        }
        let Some(session) = crate::platform::windows::get_current_process_session_id() else {
            return;
        };
        std::thread::spawn(move || {
            let take: std::sync::Arc<dyn Fn(String) -> bool + Send + Sync> =
                std::sync::Arc::new(|link: String| take_link(&link));
            super::block_on(serve_handoffs(handoff_postfix(session), take));
        });
    }
}

/// Runs the session of a handed-over link in the service's process and
/// brings up the receiver's window, which shows it.
fn take_link(link: &str) -> bool {
    let Some(link) = own_support_link(link) else {
        return false;
    };
    let started = ask_service(json!({ "do": "start", "link": link }))
        .and_then(|answer| answer.get("ok").and_then(Value::as_bool))
        == Some(true);
    if started {
        open_window();
    }
    started
}

/// Starts the receiver's window unless one runs; a running one comes up by
/// itself when the session asks the person.
pub fn open_window() {
    if !crate::check_process("", true) {
        if let Err(err) = crate::run_me::<&str>(vec![]) {
            log::warn!("The receiver's window did not start: {err}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_install_file_makes_the_receiver_of_its_server() {
        let file = InstallFile::parse(
            "receiver=Y
server=rcv-test.example.com:21116
key=a2V5
token=tok-1
group=4
",
        );
        let (mut hard, mut fixed) = (Default::default(), Default::default());
        // The signed config's key wins
        let mut signed = std::collections::HashMap::new();
        signed.insert(keys::OPTION_KEY.to_owned(), "c2lnbmVk".to_owned());
        apply_to(&file, &mut hard, &mut signed);
        assert_eq!(signed.get(keys::OPTION_KEY).map(String::as_str), Some("c2lnbmVk"));
        apply_to(&file, &mut hard, &mut fixed);
        let get = |key: &str| fixed.get(key).map(String::as_str);
        assert_eq!(hard.get("receiver").map(String::as_str), Some("Y"));
        assert_eq!(
            get(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER),
            Some("rcv-test.example.com:21116")
        );
        assert_eq!(get(keys::OPTION_KEY), Some("a2V5"));
        assert_eq!(get(keys::OPTION_API_SERVER), Some("https://rcv-test.example.com"));
        assert_eq!(get(OPTION_CONSOLE), Some("https://rcv-test.example.com"));
        // Without receiver=Y the app stays what it was
        let (mut hard, mut fixed) = (Default::default(), Default::default());
        apply_to(&InstallFile::parse("server=x"), &mut hard, &mut fixed);
        assert!(hard.is_empty());
    }

    #[test]
    fn the_registration_carries_the_token_once() {
        let file = InstallFile::parse(
            "receiver=Y
server=rcv-test.example.com:21116
key=a2V5
token=tok-1
group=4
",
        );
        *FILE.lock().unwrap() = Some(file);
        assert!(takes_link_of("rcv-test.example.com"));
        assert!(!takes_link_of("other.example.com"));
        let mut body = json!({"device_id": "123456789"});
        crate::hbbs_http::neodesk::add_enrollment_fields(&mut body, &enrollment_fields());
        assert_eq!(body["token"], "tok-1");
        assert_eq!(body["group"], "4");
        assert!(body.get("admission").is_none());
        enrollment_answered("");
        assert_eq!(enrollment_fields().len(), 2, "no answer, no change");
        enrollment_answered("pending");
        assert!(enrollment_fields().is_empty());
        let mut body = json!({"device_id": "123456789"});
        crate::hbbs_http::neodesk::add_enrollment_fields(&mut body, &enrollment_fields());
        assert!(body.get("token").is_none(), "the token went again: {body}");
        let kept = install_file().unwrap();
        assert!(kept.receiver);
        assert_eq!(kept.server, "rcv-test.example.com:21116");
        assert_eq!(kept.token, "");

        // The offer after quick support enrolls with the admission
        *FILE.lock().unwrap() = Some(InstallFile::parse("receiver=Y
server=x
admission=3f9c"));
        let mut body = json!({});
        crate::hbbs_http::neodesk::add_enrollment_fields(&mut body, &enrollment_fields());
        assert_eq!(body["admission"], "3f9c");
        *FILE.lock().unwrap() = None;
    }

    #[test]
    fn the_policy_sets_the_way_in() {
        note_access_policy(None);
        apply_policy(&json!({"policies": {"connection": {"mode": "ask_always"}, "security": {"allow_uninstall": false}}}));
        assert_eq!(applied(), Some(receiver_policy::Resolved { allow_uninstall: false }));
        assert_eq!(Config::get_option("approve-mode"), "click");
        // Unattended for the organization: still the click, and no password;
        // a vouched caller skips the click in the connection itself
        note_access_policy(Some(&json!({"unattended_enabled": true, "schedule_enabled": true,
            "schedule_days": ["mon"], "schedule_start": "08:00", "schedule_end": "18:00",
            "schedule_timezone": "Europe/Berlin", "allowed_operators": ["anna"]})));
        apply_policy(&json!({"policies": {"connection": {"mode": "unattended"},
            "security": {"allow_uninstall": true, "allowed_operators": ["anna", "bert"]}}}));
        assert_eq!(applied(), Some(receiver_policy::Resolved { allow_uninstall: true }));
        assert_eq!(Config::get_option("approve-mode"), "click");
        assert_eq!(Config::get_option("verification-method"), "use-temporary-password");
        // The rule gets the whole policy
        let policy = unattended_policy();
        let org = policy.org.unwrap();
        assert_eq!(org.mode.as_deref(), Some("unattended"));
        assert_eq!(org.operators, ["anna", "bert"]);
        let access = policy.access.unwrap().unwrap();
        assert_eq!(access.schedule_timezone, "Europe/Berlin");
        assert_eq!(access.allowed_operators, ["anna"]);
        note_access_policy(None);
        assert_eq!(unattended_policy().access, Some(None));
    }

    #[test]
    fn a_handed_link_reaches_the_running_receiver() {
        let postfix = format!("_qs_handoff_test_{}", std::process::id());
        let seen: std::sync::Arc<Mutex<Vec<String>>> = Default::default();
        let take: std::sync::Arc<dyn Fn(String) -> bool + Send + Sync> = {
            let seen = seen.clone();
            std::sync::Arc::new(move |link: String| {
                let ours = link.contains("support.example.com");
                seen.lock().unwrap().push(link);
                ours
            })
        };
        let runtime = hbb_common::tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        runtime.spawn(serve_handoffs(postfix.clone(), take));
        let link = "neodesk://support/support.example.com/K7Q2M9XD";
        let taken = runtime.block_on(async {
            for _ in 0..50 {
                if send_handoff(&postfix, link).await {
                    return true;
                }
                hbb_common::tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            }
            false
        });
        assert!(taken, "the receiver did not take its own server's link");
        assert_eq!(seen.lock().unwrap().as_slice(), [link.to_owned()]);
        // Another server's link is declined: the quick support app goes on
        let other = "neodesk://support/other.example.com/K7Q2M9XD";
        assert!(!runtime.block_on(send_handoff(&postfix, other)));
        assert_eq!(seen.lock().unwrap().len(), 2);
        // Nobody listening: nothing is taken
        assert!(!runtime.block_on(send_handoff("_qs_handoff_nobody_listens", link)));
        runtime.shutdown_background();
    }
}
