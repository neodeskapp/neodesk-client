//! Saved sign-in at a lock or sign-in screen (L469), wire format 1.
//!
//! The device tells the viewer where its console is: `logon_state` in
//! PeerInfo.platform_additions at login, and a Misc.plugin_request
//! `nd.logon_state` whenever it changes during the session. A client that
//! can type a sign-in adds `nd_signin: 1` there too.
//!
//! The viewer forwards a packet the NeoDesk server sealed (libsodium
//! crypto_box_seal) to the X25519 form of the device's Ed25519 key, as
//! Misc.plugin_request `nd.signin`. Only the process that holds the
//! device's secret key opens it: on Windows the service's server process,
//! which also types. The packet holds JSON:
//!
//! - `v`: 1
//! - `device_id`: the device's ID
//! - `session`: the relay session UUID of the connection it is for
//! - `username`, `password`
//! - `form`: `password` (password, Return) or `name_password` (account
//!   name, Tab, password, Return)
//! - `not_after`: Unix seconds
//! - `nonce`: 16 random bytes, base64url without padding
//!
//! The answer is a Misc.plugin_request `nd.signin_result` with
//! `{"result": ..., "nonce": ...}`. Nothing here logs or keeps the account
//! name or the password, and both are wiped once typed or refused.
//!
//! Keep the wire format in this file, so a change to it stays in one place.

// Only Windows types a sign-in so far
#![cfg_attr(not(windows), allow(dead_code))]

use hbb_common::{
    base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _},
    log,
    sodiumoxide::{
        crypto::{box_, sealedbox, sign},
        utils::memzero,
    },
};
use serde_derive::Deserialize;
use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
};

/// platform_additions key: the sealed sign-in format this client opens
pub const CAPABILITY_KEY: &str = "nd_signin";
/// The sealed sign-in format this client opens
pub const FORMAT: u64 = 1;
/// platform_additions key and JSON key of the console's state
pub const LOGON_STATE_KEY: &str = "logon_state";
/// Misc.plugin_request ids
pub const ID_LOGON_STATE: &str = "nd.logon_state";
pub const ID_SIGNIN: &str = "nd.signin";
pub const ID_SIGNIN_RESULT: &str = "nd.signin_result";

/// How long the sign-in screen takes to come up after Ctrl+Alt+Del
pub const SAS_WAIT_MS: u64 = 1500;
/// The pause after Tab, before the password field takes the text
pub const TAB_WAIT_MS: u64 = 200;
/// Refused packets a connection may send before it gets no more tries
pub const MAX_REFUSALS_PER_CONNECTION: u32 = 5;
/// A packet that claims to be valid for longer than this is refused; it
/// also bounds how long a nonce stays in the book
pub const MAX_LIFETIME_SECS: i64 = 3600;
/// Nonces the book keeps at most
pub const NONCE_BOOK_CAPACITY: usize = 1024;
/// A larger packet is refused without opening it
pub const MAX_PACKET_LEN: usize = 8192;

/// Where the console is
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogonState {
    /// Nobody is signed in at the console
    Prelogin,
    /// A signed-in session is locked
    Locked,
    /// The sign-in UI runs in the active session, neither of the above
    LogonUi,
    /// An open desktop
    Desktop,
}

impl LogonState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Prelogin => "prelogin",
            Self::Locked => "locked",
            Self::LogonUi => "logon_ui",
            Self::Desktop => "desktop",
        }
    }

    /// Whether a sign-in may be typed here: only while nobody is signed in
    /// or the session is locked. The sign-in UI of an open session (the
    /// Ctrl+Alt+Del screen) counts as an open desktop.
    pub fn at_sign_in_screen(self) -> bool {
        matches!(self, Self::Prelogin | Self::Locked)
    }
}

/// The console's state from the platform's checks, in this order:
/// prelogin, locked, logon_ui, desktop. logon_ui is None when the check
/// failed, and then the state is unknown.
pub fn logon_state_of(prelogin: bool, locked: bool, logon_ui: Option<bool>) -> Option<LogonState> {
    if prelogin {
        Some(LogonState::Prelogin)
    } else if locked {
        Some(LogonState::Locked)
    } else {
        logon_ui.map(|ui| {
            if ui {
                LogonState::LogonUi
            } else {
                LogonState::Desktop
            }
        })
    }
}

/// The content of an `nd.logon_state` request
pub fn logon_state_content(state: LogonState) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({ LOGON_STATE_KEY: state.as_str() })).unwrap_or_default()
}

/// The answer to a sign-in request
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Typed,
    NotAtLockScreen,
    Expired,
    BadBlob,
}

impl Outcome {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Typed => "typed",
            Self::NotAtLockScreen => "not_at_lock_screen",
            Self::Expired => "expired",
            Self::BadBlob => "bad_blob",
        }
    }
}

/// The content of an `nd.signin_result` request
pub fn result_content(outcome: Outcome, nonce: &str) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({ "result": outcome.as_str(), "nonce": nonce }))
        .unwrap_or_default()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Form {
    Password,
    NamePassword,
}

/// An opened and checked sign-in request. The account name and the
/// password are wiped when it is dropped.
pub struct Request {
    username: Vec<u8>,
    password: Vec<u8>,
    form: Form,
    nonce: String,
}

impl Request {
    pub fn nonce(&self) -> &str {
        &self.nonce
    }
}

impl Drop for Request {
    fn drop(&mut self) {
        memzero(&mut self.username);
        memzero(&mut self.password);
    }
}

impl std::fmt::Debug for Request {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Request")
            .field("form", &self.form)
            .field("nonce", &self.nonce)
            .finish_non_exhaustive()
    }
}

/// A refused request: what to answer
#[derive(Debug, PartialEq, Eq)]
pub struct Refusal {
    pub outcome: Outcome,
    /// The request's nonce, "" when the packet did not open
    pub nonce: String,
}

/// The X25519 form of the device's key pair
pub struct DeviceKeys {
    pk: box_::PublicKey,
    sk: box_::SecretKey,
}

impl DeviceKeys {
    /// From the device's Ed25519 public key (32 bytes) and secret key (64
    /// bytes), as Config::get_key_pair keeps them. The caller wipes sk.
    pub fn from_ed25519(pk: &[u8], sk: &[u8]) -> Option<Self> {
        let pk = sign::PublicKey::from_slice(pk)?;
        // sodiumoxide wipes its secret keys when they are dropped
        let sk = sign::SecretKey::from_slice(sk)?;
        Some(Self {
            pk: sign::to_curve25519_pk(&pk).ok()?,
            sk: sign::to_curve25519_sk(&sk).ok()?,
        })
    }
}

/// What the request has to name: this device and this connection
pub struct Expect<'a> {
    pub device_id: &'a str,
    /// The relay session of this connection; None for a direct connection
    pub relay_uuid: Option<&'a str>,
}

/// The nonces this device took, each until its not_after
#[derive(Default)]
pub struct NonceBook {
    seen: HashMap<String, i64>,
}

impl NonceBook {
    /// Forgets the nonces past their not_after
    fn prune(&mut self, now: i64) {
        self.seen.retain(|_, not_after| *not_after >= now);
    }
}

/// The device's nonce book, for all its connections
pub fn nonce_book() -> &'static Mutex<NonceBook> {
    static BOOK: OnceLock<Mutex<NonceBook>> = OnceLock::new();
    BOOK.get_or_init(Default::default)
}

/// Held while a sign-in is typed, so two never mix
pub fn typing_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(Default::default)
}

/// One connection's tries: a connection signs in once, and gets no more
/// tries after a few refused packets
#[derive(Default)]
pub struct ConnGate {
    refusals: u32,
    used: bool,
}

/// The plaintext as it comes; every field may be missing, so a refusal can
/// still name the nonce
#[derive(Deserialize)]
struct Wire {
    v: Option<u64>,
    device_id: Option<String>,
    session: Option<String>,
    #[serde(default)]
    username: String,
    #[serde(default)]
    password: String,
    form: Option<String>,
    not_after: Option<i64>,
    nonce: Option<String>,
}

impl Drop for Wire {
    fn drop(&mut self) {
        wipe(&mut self.username);
        wipe(&mut self.password);
    }
}

fn wipe(s: &mut String) {
    // Zero bytes are valid UTF-8
    unsafe { memzero(s.as_bytes_mut()) }
}

/// 16 bytes in base64url without padding
fn valid_nonce(nonce: &&str) -> bool {
    nonce.len() == 22
        && URL_SAFE_NO_PAD
            .decode(nonce)
            .map_or(false, |bytes| bytes.len() == 16)
}

fn has_control(text: &[u8]) -> bool {
    std::str::from_utf8(text).map_or(true, |s| s.chars().any(char::is_control))
}

type Refused = (Outcome, String, &'static str);

/// Opens and checks a sign-in packet for this device and connection, at
/// time now (Unix seconds) with the console in state. Checks in this
/// order and refuses with the first failure: the packet opens, holds JSON
/// of format 1 for this device and this connection's relay session (else
/// bad_blob), its nonce is new (bad_blob), now is not past not_after
/// (expired), nobody is signed in or the session is locked
/// (not_at_lock_screen). A request that gets past the nonce check uses up
/// its nonce, and one accepted request uses up the connection.
pub fn accept(
    packet: &[u8],
    keys: &DeviceKeys,
    expect: &Expect,
    gate: &mut ConnGate,
    book: &mut NonceBook,
    now: i64,
    state: Option<LogonState>,
) -> Result<Request, Refusal> {
    match check(packet, keys, expect, gate, book, now, state) {
        Ok(request) => {
            gate.used = true;
            Ok(request)
        }
        Err((outcome, nonce, why)) => {
            gate.refusals = gate.refusals.saturating_add(1);
            // Only the reason, never a value from the packet
            log::info!("saved sign-in refused ({}): {}", outcome.as_str(), why);
            Err(Refusal { outcome, nonce })
        }
    }
}

fn check(
    packet: &[u8],
    keys: &DeviceKeys,
    expect: &Expect,
    gate: &ConnGate,
    book: &mut NonceBook,
    now: i64,
    state: Option<LogonState>,
) -> Result<Request, Refused> {
    let unopened = |why| Err((Outcome::BadBlob, String::new(), why));
    if gate.used {
        return unopened("this connection signed in already");
    }
    if gate.refusals >= MAX_REFUSALS_PER_CONNECTION {
        return unopened("too many refused packets on this connection");
    }
    if packet.len() > MAX_PACKET_LEN {
        return unopened("packet too large");
    }
    let Ok(mut plain) = sealedbox::open(packet, &keys.pk, &keys.sk) else {
        return unopened("packet does not open");
    };
    let parsed = serde_json::from_slice::<Wire>(&plain);
    memzero(&mut plain);
    let Ok(mut wire) = parsed else {
        return unopened("not the JSON of a sign-in");
    };

    let nonce = wire.nonce.as_deref().filter(valid_nonce).map(str::to_owned);
    let echo = nonce.clone().unwrap_or_default();
    let bad = |why| Err((Outcome::BadBlob, echo.clone(), why));
    if wire.v != Some(FORMAT) {
        return bad("not format 1");
    }
    if wire.device_id.as_deref() != Some(expect.device_id) {
        return bad("for another device");
    }
    let Some(relay_uuid) = expect.relay_uuid else {
        return bad("not a relayed connection");
    };
    if wire.session.as_deref() != Some(relay_uuid) {
        return bad("for another session");
    }
    let Some(nonce) = nonce else {
        return bad("no nonce");
    };
    let form = match wire.form.as_deref() {
        Some("password") => Form::Password,
        Some("name_password") => Form::NamePassword,
        _ => return bad("unknown form"),
    };
    let Some(not_after) = wire.not_after else {
        return bad("no not_after");
    };
    // From here the details are in the request, which wipes them when dropped
    let request = Request {
        username: std::mem::take(&mut wire.username).into_bytes(),
        password: std::mem::take(&mut wire.password).into_bytes(),
        form,
        nonce: nonce.clone(),
    };
    drop(wire);
    if request.password.is_empty() {
        return bad("no password");
    }
    if form == Form::NamePassword && request.username.is_empty() {
        return bad("no account name");
    }
    if has_control(&request.username) || has_control(&request.password) {
        return bad("control characters");
    }
    if not_after > now.saturating_add(MAX_LIFETIME_SECS) {
        return bad("valid for too long");
    }

    book.prune(now);
    if book.seen.contains_key(&nonce) {
        return bad("nonce used before");
    }
    if now > not_after {
        return Err((Outcome::Expired, echo.clone(), "past not_after"));
    }
    if book.seen.len() >= NONCE_BOOK_CAPACITY {
        return bad("nonce book full");
    }
    book.seen.insert(nonce, not_after);

    if !state.map_or(false, LogonState::at_sign_in_screen) {
        return Err((Outcome::NotAtLockScreen, echo.clone(), "not at a sign-in screen"));
    }
    Ok(request)
}

/// The keyboard and the console, as the typing sees them
pub trait SigninKeys {
    fn logon_state(&mut self) -> Option<LogonState>;
    /// Ctrl+Alt+Del
    fn sas(&mut self);
    fn sleep(&mut self, ms: u64);
    /// The text as Unicode characters, whatever the keyboard layout
    fn text(&mut self, text: &str);
    fn tab(&mut self);
    fn enter(&mut self);
}

/// Types an accepted request, once: Ctrl+Alt+Del, then the text, Tab and
/// Return per form. It checks the console again before each part and stops
/// when nobody-signed-in or locked no longer holds. The request is wiped
/// when this returns.
pub fn type_signin(request: Request, keys: &mut dyn SigninKeys) -> Outcome {
    fn still_there(keys: &mut dyn SigninKeys) -> bool {
        keys.logon_state()
            .map_or(false, LogonState::at_sign_in_screen)
    }
    if !still_there(keys) {
        log::info!("saved sign-in not typed: no longer at a sign-in screen");
        return Outcome::NotAtLockScreen;
    }
    keys.sas();
    keys.sleep(SAS_WAIT_MS);
    if !still_there(keys) {
        log::info!("saved sign-in not typed: left the sign-in screen after Ctrl+Alt+Del");
        return Outcome::NotAtLockScreen;
    }
    if request.form == Form::NamePassword {
        keys.text(std::str::from_utf8(&request.username).unwrap_or_default());
        keys.tab();
        keys.sleep(TAB_WAIT_MS);
        if !still_there(keys) {
            log::info!("saved sign-in stopped after the account name: left the sign-in screen");
            return Outcome::NotAtLockScreen;
        }
    }
    keys.text(std::str::from_utf8(&request.password).unwrap_or_default());
    keys.enter();
    log::info!("saved sign-in typed");
    Outcome::Typed
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, Once};

    // Made up for these tests; no real device or account
    const DEVICE: &str = "123456789";
    const SESSION: &str = "5b0e3f4c-7d61-4a8e-9a43-0c2f7b1d9e55";
    const USER: &str = "TESTLAB\\made-up-user";
    const PASSWORD: &str = "Made-up pässwörd 7!";
    const NONCE: &str = "AAECAwQFBgcICQoLDA0ODw";
    const NOW: i64 = 1_790_000_000;

    fn device_keys() -> (sign::PublicKey, sign::SecretKey) {
        sign::keypair_from_seed(&sign::Seed([7u8; 32]))
    }

    fn keys() -> DeviceKeys {
        let (pk, sk) = device_keys();
        DeviceKeys::from_ed25519(&pk.0, &sk.0).expect("made-up keys convert")
    }

    fn body() -> serde_json::Value {
        serde_json::json!({
            "v": 1,
            "device_id": DEVICE,
            "session": SESSION,
            "username": USER,
            "password": PASSWORD,
            "form": "password",
            "not_after": NOW + 60,
            "nonce": NONCE,
        })
    }

    fn seal_json(v: &serde_json::Value) -> Vec<u8> {
        seal_bytes(&serde_json::to_vec(v).unwrap())
    }

    fn seal_bytes(plain: &[u8]) -> Vec<u8> {
        let (pk, _) = device_keys();
        let x = sign::to_curve25519_pk(&pk).unwrap();
        sealedbox::seal(plain, &x)
    }

    fn expect() -> Expect<'static> {
        Expect {
            device_id: DEVICE,
            relay_uuid: Some(SESSION),
        }
    }

    fn try_packet(packet: &[u8], state: Option<LogonState>) -> Result<Request, Refusal> {
        accept(
            packet,
            &keys(),
            &expect(),
            &mut ConnGate::default(),
            &mut NonceBook::default(),
            NOW,
            state,
        )
    }

    fn refusal(outcome: Outcome, nonce: &str) -> Refusal {
        Refusal {
            outcome,
            nonce: nonce.to_owned(),
        }
    }

    #[test]
    fn logon_state_follows_prelogin_then_locked_then_logon_ui() {
        use LogonState::*;
        assert_eq!(logon_state_of(true, false, Some(false)), Some(Prelogin));
        assert_eq!(logon_state_of(true, true, Some(true)), Some(Prelogin));
        assert_eq!(logon_state_of(false, true, Some(true)), Some(Locked));
        assert_eq!(logon_state_of(false, true, None), Some(Locked));
        assert_eq!(logon_state_of(false, false, Some(true)), Some(LogonUi));
        assert_eq!(logon_state_of(false, false, Some(false)), Some(Desktop));
        assert_eq!(logon_state_of(false, false, None), None);
        let names: Vec<_> = [Prelogin, Locked, LogonUi, Desktop]
            .iter()
            .map(|s| s.as_str())
            .collect();
        assert_eq!(names, ["prelogin", "locked", "logon_ui", "desktop"]);
        assert!(Prelogin.at_sign_in_screen());
        assert!(Locked.at_sign_in_screen());
        assert!(!LogonUi.at_sign_in_screen());
        assert!(!Desktop.at_sign_in_screen());
    }

    #[test]
    fn the_wire_contents_are_the_agreed_json() {
        assert_eq!(
            logon_state_content(LogonState::LogonUi),
            br#"{"logon_state":"logon_ui"}"#.to_vec()
        );
        let v: serde_json::Value =
            serde_json::from_slice(&result_content(Outcome::NotAtLockScreen, NONCE)).unwrap();
        assert_eq!(
            v,
            serde_json::json!({"result": "not_at_lock_screen", "nonce": NONCE})
        );
        let names: Vec<_> = [
            Outcome::Typed,
            Outcome::NotAtLockScreen,
            Outcome::Expired,
            Outcome::BadBlob,
        ]
        .iter()
        .map(|o| o.as_str())
        .collect();
        assert_eq!(names, ["typed", "not_at_lock_screen", "expired", "bad_blob"]);
    }

    #[test]
    fn a_packet_for_this_device_and_session_opens_at_the_lock_screen() {
        let req = try_packet(&seal_json(&body()), Some(LogonState::Locked)).unwrap();
        assert_eq!(req.form, Form::Password);
        assert_eq!(req.nonce(), NONCE);
        assert_eq!(req.username, USER.as_bytes());
        assert_eq!(req.password, PASSWORD.as_bytes());
        let mut b = body();
        b["form"] = "name_password".into();
        b["extra"] = "ignored".into();
        let req = try_packet(&seal_json(&b), Some(LogonState::Prelogin)).unwrap();
        assert_eq!(req.form, Form::NamePassword);
    }

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    /// The server's test vector (neodesk-server/crypto/devicevault on the
    /// server branch nd-signin), made-up keys and values
    #[test]
    fn the_servers_sealed_packet_opens_with_the_device_key() {
        use hbb_common::base64::engine::general_purpose::STANDARD;
        let v: serde_json::Value =
            serde_json::from_str(include_str!("testdata/sealed-signin-v1.json")).unwrap();
        let field = |k: &str| v[k].as_str().unwrap().to_owned();
        let seed = sign::Seed::from_slice(&hex(&field("ed25519_seed_hex"))).unwrap();
        let (pk, sk) = sign::keypair_from_seed(&seed);
        assert_eq!(pk.0.to_vec(), hex(&field("ed25519_public_hex")));
        let keys = DeviceKeys::from_ed25519(&pk.0, &sk.0).unwrap();
        assert_eq!(keys.pk.0.to_vec(), hex(&field("x25519_public_hex")));
        assert_eq!(keys.sk.0.to_vec(), hex(&field("x25519_secret_hex")));

        let plain: serde_json::Value = serde_json::from_str(&field("plaintext")).unwrap();
        let text = |k: &str| plain[k].as_str().unwrap().to_owned();
        let packet = STANDARD.decode(field("packet_base64")).unwrap();
        let session = text("session");
        let not_after = plain["not_after"].as_i64().unwrap();
        let req = accept(
            &packet,
            &keys,
            &Expect {
                device_id: &text("device_id"),
                relay_uuid: Some(&session),
            },
            &mut ConnGate::default(),
            &mut NonceBook::default(),
            not_after - 30,
            Some(LogonState::Locked),
        )
        .unwrap();
        assert_eq!(req.form, Form::NamePassword);
        assert_eq!(req.nonce(), text("nonce"));
        assert_eq!(req.username, br"LAB\lab-admin");
        assert_eq!(req.password, "Made-Up-Vector-Pass-ä€@\\<&>".as_bytes());
    }

    #[test]
    fn packets_that_do_not_open_are_bad_blobs_without_a_nonce() {
        let none = refusal(Outcome::BadBlob, "");
        let state = Some(LogonState::Locked);
        assert_eq!(try_packet(b"", state).unwrap_err(), none);
        assert_eq!(try_packet(&[0u8; 120], state).unwrap_err(), none);
        // Sealed to another device's key
        let (other, _) = sign::keypair_from_seed(&sign::Seed([9u8; 32]));
        let other = sign::to_curve25519_pk(&other).unwrap();
        let packet = sealedbox::seal(&serde_json::to_vec(&body()).unwrap(), &other);
        assert_eq!(try_packet(&packet, state).unwrap_err(), none);
        // A flipped byte
        let mut packet = seal_json(&body());
        let last = packet.len() - 1;
        packet[last] ^= 1;
        assert_eq!(try_packet(&packet, state).unwrap_err(), none);
        // Not JSON, or JSON of the wrong shape
        assert_eq!(try_packet(&seal_bytes(b"not json"), state).unwrap_err(), none);
        assert_eq!(try_packet(&seal_bytes(b"[1,2]"), state).unwrap_err(), none);
        let mut b = body();
        b["v"] = "1".into();
        assert_eq!(try_packet(&seal_json(&b), state).unwrap_err(), none);
        // Too large to open
        let mut b = body();
        b["password"] = "x".repeat(MAX_PACKET_LEN).into();
        assert_eq!(try_packet(&seal_json(&b), state).unwrap_err(), none);
    }

    #[test]
    fn a_packet_for_another_device_session_or_format_is_a_bad_blob() {
        let bad = refusal(Outcome::BadBlob, NONCE);
        let state = Some(LogonState::Locked);
        for (key, value) in [
            ("v", serde_json::json!(2)),
            ("device_id", serde_json::json!("987654321")),
            ("session", serde_json::json!("00000000-0000-0000-0000-000000000000")),
            ("session", serde_json::json!("")),
            ("form", serde_json::json!("pin")),
            ("password", serde_json::json!("")),
            ("password", serde_json::json!("line\nbreak")),
            ("username", serde_json::json!("tab\tin name")),
            ("not_after", serde_json::json!(NOW + MAX_LIFETIME_SECS + 1)),
        ] {
            let mut b = body();
            b[key] = value.clone();
            assert_eq!(
                try_packet(&seal_json(&b), state).unwrap_err(),
                bad,
                "{key} = {value}"
            );
        }
        for key in ["v", "device_id", "session", "password", "form", "not_after"] {
            let mut b = body();
            b.as_object_mut().unwrap().remove(key);
            assert_eq!(try_packet(&seal_json(&b), state).unwrap_err(), bad, "no {key}");
        }
        // The account name may be left out of the password form only
        let mut b = body();
        b["form"] = "name_password".into();
        b["username"] = "".into();
        assert_eq!(try_packet(&seal_json(&b), state).unwrap_err(), bad);
        // A nonce that is not 16 bytes in base64url is not echoed
        for nonce in ["", "short", "AAECAwQFBgcICQoLDA0ODw==", "AAECAwQFBgcICQoLDA0OD+"] {
            let mut b = body();
            b["nonce"] = nonce.into();
            assert_eq!(
                try_packet(&seal_json(&b), state).unwrap_err(),
                refusal(Outcome::BadBlob, ""),
                "nonce {nonce:?}"
            );
        }
    }

    #[test]
    fn a_direct_connection_has_no_relay_session_and_gets_a_bad_blob() {
        let packet = seal_json(&body());
        let got = accept(
            &packet,
            &keys(),
            &Expect {
                device_id: DEVICE,
                relay_uuid: None,
            },
            &mut ConnGate::default(),
            &mut NonceBook::default(),
            NOW,
            Some(LogonState::Locked),
        );
        assert_eq!(got.unwrap_err(), refusal(Outcome::BadBlob, NONCE));
    }

    #[test]
    fn an_expired_packet_is_refused_and_a_replayed_nonce_is_a_bad_blob() {
        let packet = seal_json(&body());
        let mut book = NonceBook::default();
        let run = |now: i64, book: &mut NonceBook| {
            accept(
                &packet,
                &keys(),
                &expect(),
                &mut ConnGate::default(),
                book,
                now,
                Some(LogonState::Locked),
            )
        };
        assert_eq!(
            run(NOW + 61, &mut book).unwrap_err(),
            refusal(Outcome::Expired, NONCE)
        );
        // The expired try did not take the nonce
        assert!(run(NOW, &mut book).is_ok());
        // Seen within its not_after, on another connection too
        assert_eq!(
            run(NOW + 1, &mut book).unwrap_err(),
            refusal(Outcome::BadBlob, NONCE)
        );
        // Replay is checked before expiry
        assert_eq!(
            run(NOW + 60, &mut book).unwrap_err(),
            refusal(Outcome::BadBlob, NONCE)
        );
        // Past its not_after the book forgets it, and the clock refuses it
        assert_eq!(
            run(NOW + 61, &mut book).unwrap_err(),
            refusal(Outcome::Expired, NONCE)
        );
    }

    #[test]
    fn a_packet_is_typed_only_at_a_lock_or_sign_in_screen() {
        let packet = seal_json(&body());
        for state in [Some(LogonState::Desktop), Some(LogonState::LogonUi), None] {
            assert_eq!(
                try_packet(&packet, state).unwrap_err(),
                refusal(Outcome::NotAtLockScreen, NONCE),
                "{state:?}"
            );
        }
        // Expiry is checked before the screen
        let mut b = body();
        b["not_after"] = (NOW - 1).into();
        assert_eq!(
            try_packet(&seal_json(&b), Some(LogonState::Desktop)).unwrap_err(),
            refusal(Outcome::Expired, NONCE)
        );
        // Refused at the desktop, the nonce is used up
        let mut book = NonceBook::default();
        let mut run = |state| {
            accept(
                &packet,
                &keys(),
                &expect(),
                &mut ConnGate::default(),
                &mut book,
                NOW,
                state,
            )
        };
        assert!(run(Some(LogonState::Desktop)).is_err());
        assert_eq!(
            run(Some(LogonState::Locked)).unwrap_err(),
            refusal(Outcome::BadBlob, NONCE)
        );
    }

    #[test]
    fn a_connection_signs_in_once_and_stops_after_five_refused_packets() {
        let mut book = NonceBook::default();
        let mut gate = ConnGate::default();
        let mut send = |b: &serde_json::Value, gate: &mut ConnGate| {
            accept(
                &seal_json(b),
                &keys(),
                &expect(),
                gate,
                &mut book,
                NOW,
                Some(LogonState::Locked),
            )
        };
        assert!(send(&body(), &mut gate).is_ok());
        let mut b = body();
        b["nonce"] = "AQECAwQFBgcICQoLDA0ODw".into();
        assert_eq!(
            send(&b, &mut gate).unwrap_err(),
            refusal(Outcome::BadBlob, "")
        );

        let mut gate = ConnGate::default();
        for i in 0..MAX_REFUSALS_PER_CONNECTION {
            let mut b = body();
            b["device_id"] = format!("other{i}").into();
            assert!(send(&b, &mut gate).is_err());
        }
        let mut b = body();
        b["nonce"] = "AgECAwQFBgcICQoLDA0ODw".into();
        assert_eq!(
            send(&b, &mut gate).unwrap_err(),
            refusal(Outcome::BadBlob, "")
        );
    }

    #[test]
    fn the_nonce_book_is_bounded() {
        let mut book = NonceBook::default();
        let mut gate;
        for i in 0..NONCE_BOOK_CAPACITY {
            let mut b = body();
            b["nonce"] = URL_SAFE_NO_PAD.encode((i as u128).to_le_bytes()).into();
            gate = ConnGate::default();
            accept(
                &seal_json(&b),
                &keys(),
                &expect(),
                &mut gate,
                &mut book,
                NOW,
                Some(LogonState::Locked),
            )
            .unwrap();
        }
        let mut b = body();
        b["nonce"] = URL_SAFE_NO_PAD.encode(u128::MAX.to_le_bytes()).into();
        let packet = seal_json(&b);
        let mut run = |now| {
            accept(
                &packet,
                &keys(),
                &expect(),
                &mut ConnGate::default(),
                &mut book,
                now,
                Some(LogonState::Locked),
            )
        };
        assert_eq!(
            run(NOW).unwrap_err(),
            refusal(Outcome::BadBlob, &URL_SAFE_NO_PAD.encode(u128::MAX.to_le_bytes()))
        );
        // Once the others are past their not_after there is room again
        let mut b = body();
        b["nonce"] = URL_SAFE_NO_PAD.encode(u128::MAX.to_le_bytes()).into();
        b["not_after"] = (NOW + 200).into();
        let packet = seal_json(&b);
        assert!(accept(
            &packet,
            &keys(),
            &expect(),
            &mut ConnGate::default(),
            &mut book,
            NOW + 61,
            Some(LogonState::Locked),
        )
        .is_ok());
    }

    #[derive(Debug, PartialEq)]
    enum Step {
        State,
        Sas,
        Sleep(u64),
        Text(String),
        Tab,
        Enter,
    }

    struct FakeKeys {
        states: Vec<Option<LogonState>>,
        steps: Vec<Step>,
    }

    impl FakeKeys {
        fn new(states: &[Option<LogonState>]) -> Self {
            Self {
                states: states.iter().rev().cloned().collect(),
                steps: vec![],
            }
        }
    }

    impl SigninKeys for FakeKeys {
        fn logon_state(&mut self) -> Option<LogonState> {
            self.steps.push(Step::State);
            if self.states.len() > 1 {
                self.states.pop().unwrap()
            } else {
                self.states[0]
            }
        }
        fn sas(&mut self) {
            self.steps.push(Step::Sas);
        }
        fn sleep(&mut self, ms: u64) {
            self.steps.push(Step::Sleep(ms));
        }
        fn text(&mut self, text: &str) {
            self.steps.push(Step::Text(text.to_owned()));
        }
        fn tab(&mut self) {
            self.steps.push(Step::Tab);
        }
        fn enter(&mut self) {
            self.steps.push(Step::Enter);
        }
    }

    fn accepted(form: &str, state: LogonState) -> Request {
        let mut b = body();
        b["form"] = form.into();
        try_packet(&seal_json(&b), Some(state)).unwrap()
    }

    #[test]
    fn the_password_form_is_typed_once_after_ctrl_alt_del() {
        use LogonState::*;
        let mut keys = FakeKeys::new(&[Some(Locked)]);
        assert_eq!(
            type_signin(accepted("password", Locked), &mut keys),
            Outcome::Typed
        );
        assert_eq!(
            keys.steps,
            [
                Step::State,
                Step::Sas,
                Step::Sleep(SAS_WAIT_MS),
                Step::State,
                Step::Text(PASSWORD.into()),
                Step::Enter,
            ]
        );
    }

    #[test]
    fn the_name_and_password_form_is_typed_once_with_tab() {
        use LogonState::*;
        let mut keys = FakeKeys::new(&[Some(Prelogin)]);
        assert_eq!(
            type_signin(accepted("name_password", Prelogin), &mut keys),
            Outcome::Typed
        );
        assert_eq!(
            keys.steps,
            [
                Step::State,
                Step::Sas,
                Step::Sleep(SAS_WAIT_MS),
                Step::State,
                Step::Text(USER.into()),
                Step::Tab,
                Step::Sleep(TAB_WAIT_MS),
                Step::State,
                Step::Text(PASSWORD.into()),
                Step::Enter,
            ]
        );
    }

    #[test]
    fn the_sign_in_ui_of_an_open_session_is_not_typed_into() {
        use LogonState::*;
        // The Ctrl+Alt+Del screen of a signed-in session
        let mut keys = FakeKeys::new(&[Some(LogonUi)]);
        assert_eq!(
            type_signin(accepted("password", Locked), &mut keys),
            Outcome::NotAtLockScreen
        );
        assert_eq!(keys.steps, [Step::State]);
        // Or the session left the lock screen for it after Ctrl+Alt+Del
        let mut keys = FakeKeys::new(&[Some(Locked), Some(LogonUi)]);
        assert_eq!(
            type_signin(accepted("password", Locked), &mut keys),
            Outcome::NotAtLockScreen
        );
        assert_eq!(
            keys.steps,
            [Step::State, Step::Sas, Step::Sleep(SAS_WAIT_MS), Step::State]
        );
    }

    #[test]
    fn nothing_more_is_typed_once_the_console_left_the_sign_in_screen() {
        use LogonState::*;
        // Someone signed in at the computer meanwhile
        let mut keys = FakeKeys::new(&[Some(Desktop)]);
        assert_eq!(
            type_signin(accepted("password", Locked), &mut keys),
            Outcome::NotAtLockScreen
        );
        assert_eq!(keys.steps, [Step::State]);

        let mut keys = FakeKeys::new(&[Some(Locked), Some(Desktop)]);
        assert_eq!(
            type_signin(accepted("password", Locked), &mut keys),
            Outcome::NotAtLockScreen
        );
        assert_eq!(
            keys.steps,
            [Step::State, Step::Sas, Step::Sleep(SAS_WAIT_MS), Step::State]
        );

        let mut keys = FakeKeys::new(&[Some(Locked), Some(Locked), None]);
        assert_eq!(
            type_signin(accepted("name_password", Locked), &mut keys),
            Outcome::NotAtLockScreen
        );
        assert!(!keys.steps.contains(&Step::Text(PASSWORD.into())));
        assert!(!keys.steps.contains(&Step::Enter));
    }

    struct Capture(Mutex<Vec<String>>);

    impl log::Log for Capture {
        fn enabled(&self, _: &log::Metadata) -> bool {
            true
        }
        fn log(&self, record: &log::Record) {
            self.0
                .lock()
                .unwrap()
                .push(format!("{} {}", record.target(), record.args()));
        }
        fn flush(&self) {}
    }

    static CAPTURE: Capture = Capture(Mutex::new(Vec::new()));
    static CAPTURE_ONCE: Once = Once::new();

    #[test]
    fn neither_the_account_name_nor_the_password_reaches_the_log() {
        CAPTURE_ONCE.call_once(|| {
            log::set_logger(&CAPTURE).expect("no other logger in the tests");
            log::set_max_level(log::LevelFilter::Trace);
        });
        let mut b = body();
        b["form"] = "name_password".into();
        let packet = seal_json(&b);
        let mut book = NonceBook::default();
        for (now, state) in [
            (NOW, Some(LogonState::Desktop)),
            (NOW + 61, Some(LogonState::Locked)),
            (NOW, Some(LogonState::Locked)),
        ] {
            let got = accept(
                &packet,
                &keys(),
                &expect(),
                &mut ConnGate::default(),
                &mut book,
                now,
                state,
            );
            let _ = format!("{got:?}");
            if let Ok(req) = got {
                type_signin(req, &mut FakeKeys::new(&[Some(LogonState::Locked)]));
            }
        }
        let mut b = body();
        b["device_id"] = "987654321".into();
        let _ = try_packet(&seal_json(&b), Some(LogonState::Locked));
        let lines = CAPTURE.0.lock().unwrap().clone();
        assert!(
            lines.iter().any(|l| l.contains("saved sign-in")),
            "the refusals are logged: {lines:?}"
        );
        for line in &lines {
            assert!(!line.contains("made-up-user"), "{line}");
            assert!(!line.contains("pässwörd"), "{line}");
        }
        let req = accepted("name_password", LogonState::Locked);
        let shown = format!("{req:?}");
        assert!(!shown.contains("made-up-user") && !shown.contains("pässwörd"), "{shown}");
    }
}
