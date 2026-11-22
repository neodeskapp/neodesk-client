//! Quick support: one session with a supporter, consent on this screen.
//!
//! The app redeems the support code (`POST /api/support/redeem`) and gets a
//! session token that opens only this session's routes. It reports the
//! device (`/api/support/session/device`) before it registers with the ID
//! server, so a server in managed mode admits it. The person allows or
//! declines (`/consent`); after Allow the app hands over the session
//! password once (`/password`, again only when the password changes) and
//! polls `GET /api/support/session` so the session stays open. A 401 means
//! the supporter ended it or it timed out. Closing the app ends it (`/end`).

use std::{
    sync::mpsc::{Receiver, RecvTimeoutError},
    time::{Duration, Instant},
};

use hbb_common::{log, tokio};
use serde_json::{json, Value};

use super::{
    http::{Answer, Http, OnboardError},
    join::{DeviceIdentity, ServerSettings},
    link::Console,
    Phase, SharedState,
};

/// What the UI asks of a running session.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Consent(bool),
    End,
}

/// What the session needs from the running app.
pub trait SupportHost {
    /// The device the session runs on.
    fn device(&self) -> DeviceIdentity;
    /// Makes the app reach the session's server.
    fn apply_server(&self, server: &ServerSettings);
    /// The session password the supporter connects with.
    fn password(&self) -> String;
    /// True while a supporter is connected.
    fn in_session(&self) -> bool;
    /// Ends local access: disconnects the supporter, changes the password and
    /// stops taking connections.
    fn shut_down(&self);
}

/// How often the session is polled and commands are looked at.
#[derive(Debug, Clone, Copy)]
pub struct Timing {
    pub poll: Duration,
    pub tick: Duration,
}

impl Default for Timing {
    fn default() -> Self {
        Self {
            poll: Duration::from_secs(5),
            tick: Duration::from_millis(250),
        }
    }
}

/// A redeemed support code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Redeemed {
    pub token: String,
    pub session_id: String,
    pub supporter: String,
    pub company: String,
    pub server: ServerSettings,
}

pub fn redeem_result(answer: &Answer) -> Result<Redeemed, OnboardError> {
    if let Some(err) = answer.common_error() {
        return Err(err);
    }
    let token = answer.text("session_token");
    if answer.body.get("success").and_then(Value::as_bool) != Some(true) || token.is_empty() {
        return Err(OnboardError::Server(answer.status));
    }
    let session = answer.body.get("session").unwrap_or(&Value::Null);
    Ok(Redeemed {
        token,
        session_id: session
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned(),
        supporter: answer.text("supporter"),
        company: answer.text("company"),
        server: ServerSettings::from_answer(answer.body.get("server").unwrap_or(&Value::Null)),
    })
}

/// The session's status from an answer of a session route. A session that
/// is over (401, or a final status) is [`OnboardError::SessionEnded`].
pub fn session_status(answer: &Answer) -> Result<String, OnboardError> {
    if let Some(err) = answer.common_error() {
        return Err(err);
    }
    let status = answer
        .body
        .get("session")
        .and_then(|session| session.get("status"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    match status.as_str() {
        "ended" | "expired" | "declined" => Err(OnboardError::SessionEnded),
        _ => Ok(status),
    }
}

fn success(answer: &Answer) -> Result<(), OnboardError> {
    match answer.common_error() {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

/// The session's routes for one token.
pub struct Session<'a> {
    http: &'a Http,
    token: String,
}

impl<'a> Session<'a> {
    pub async fn redeem(http: &'a Http, code: &str) -> Result<(Self, Redeemed), OnboardError> {
        let answer = http
            .post("/api/support/redeem", &json!({ "code": code }), None)
            .await?;
        let redeemed = redeem_result(&answer)?;
        Ok((
            Self {
                http,
                token: redeemed.token.clone(),
            },
            redeemed,
        ))
    }

    pub async fn report_device(&self, device: &DeviceIdentity) -> Result<String, OnboardError> {
        let mut body = device.to_json();
        if let Some(map) = body.as_object_mut() {
            map.remove("public_key");
        }
        let answer = self
            .http
            .post("/api/support/session/device", &body, Some(&self.token))
            .await?;
        session_status(&answer)
    }

    pub async fn consent(&self, allowed: bool) -> Result<String, OnboardError> {
        let answer = self
            .http
            .post(
                "/api/support/session/consent",
                &json!({ "allowed": allowed }),
                Some(&self.token),
            )
            .await?;
        if allowed {
            session_status(&answer)
        } else {
            success(&answer).map(|_| "declined".to_owned())
        }
    }

    pub async fn hand_over(&self, password: &str) -> Result<(), OnboardError> {
        let answer = self
            .http
            .post(
                "/api/support/session/password",
                &json!({ "password": password }),
                Some(&self.token),
            )
            .await?;
        success(&answer)
    }

    pub async fn poll(&self) -> Result<String, OnboardError> {
        let answer = self
            .http
            .get("/api/support/session", Some(&self.token))
            .await?;
        session_status(&answer)
    }

    pub async fn end(&self) -> Result<(), OnboardError> {
        let answer = self
            .http
            .post("/api/support/session/end", &json!({}), Some(&self.token))
            .await?;
        success(&answer)
    }
}

/// Runs one quick support session from the code to its end. Blocks; call it
/// on a thread of its own, outside any async runtime.
pub fn run(
    console: Console,
    code: String,
    host: &dyn SupportHost,
    state: &SharedState,
    commands: &Receiver<Command>,
    timing: Timing,
) {
    state.update(|s| {
        s.phase = Phase::SupportConnecting;
        s.server = Some(console.host.clone());
        s.clear_error();
    });
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(err) => {
            log::error!("Quick support could not start: {err}");
            state.update(|s| s.fail(&OnboardError::Server(0)));
            return;
        }
    };
    let fail = |err: &OnboardError| {
        log::warn!("Quick support stopped: {}", err.code());
        state.update(|s| s.fail(err));
    };
    let http = match runtime.block_on(Http::new(console)) {
        Ok(http) => http,
        Err(err) => return fail(&err),
    };
    let (session, redeemed) = match runtime.block_on(Session::redeem(&http, &code)) {
        Ok(redeemed) => redeemed,
        Err(OnboardError::InvalidOrExpired) => {
            state.update(|s| s.phase = Phase::SupportExpired);
            return;
        }
        Err(err) => return fail(&err),
    };
    log::info!("Quick support session {} opened", redeemed.session_id);
    state.update(|s| {
        s.supporter_name = Some(redeemed.supporter.clone());
        s.company = Some(redeemed.company.clone()).filter(|c| !c.is_empty());
    });
    let end_here = |reason: Option<&OnboardError>| {
        state.update(|s| {
            s.phase = Phase::SupportEnded;
            match reason {
                Some(err) => s.fail(err),
                None => s.clear_error(),
            }
        });
        host.shut_down();
    };

    if let Err(err) = runtime.block_on(session.report_device(&host.device())) {
        if err == OnboardError::SessionEnded {
            return end_here(None);
        }
        runtime.block_on(session.end()).ok();
        return end_here(Some(&err));
    }
    host.apply_server(&redeemed.server);
    state.update(|s| s.phase = Phase::SupportConsent);

    let mut last_poll = Instant::now();
    let poll_due = |last_poll: &mut Instant| {
        if last_poll.elapsed() < timing.poll {
            return false;
        }
        *last_poll = Instant::now();
        true
    };
    let allowed = loop {
        match commands.recv_timeout(timing.tick) {
            Ok(Command::Consent(allowed)) => break Some(allowed),
            Ok(Command::End) | Err(RecvTimeoutError::Disconnected) => break None,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if poll_due(&mut last_poll) {
            if let Err(OnboardError::SessionEnded) = runtime.block_on(session.poll()) {
                return end_here(None);
            }
        }
    };
    match allowed {
        None => {
            runtime.block_on(session.end()).ok();
            return end_here(None);
        }
        Some(false) => {
            runtime.block_on(session.consent(false)).ok();
            log::info!("Quick support declined");
            end_here(None);
            return state.update(|s| s.error = Some("declined".to_owned()));
        }
        Some(true) => {
            if let Err(err) = runtime.block_on(session.consent(true)) {
                if err != OnboardError::SessionEnded {
                    runtime.block_on(session.end()).ok();
                }
                return end_here(Some(&err));
            }
        }
    }
    log::info!("Quick support allowed");
    state.update(|s| s.phase = Phase::SupportWaiting);

    let mut handed_over = String::new();
    let mut next_try = Instant::now();
    loop {
        let password = host.password();
        if !password.is_empty() && password != handed_over && Instant::now() >= next_try {
            match runtime.block_on(session.hand_over(&password)) {
                Ok(()) => handed_over = password,
                Err(OnboardError::SessionEnded) => return end_here(None),
                Err(err) => {
                    log::warn!("Quick support password not handed over: {}", err.code());
                    next_try = Instant::now() + timing.poll;
                }
            }
        }
        let phase = if host.in_session() {
            Phase::SupportInSession
        } else {
            Phase::SupportWaiting
        };
        state.update(|s| s.phase = phase);
        match commands.recv_timeout(timing.tick) {
            Ok(Command::End) | Err(RecvTimeoutError::Disconnected) => {
                runtime.block_on(session.end()).ok();
                log::info!("Quick support ended here");
                return end_here(None);
            }
            Ok(Command::Consent(_)) | Err(RecvTimeoutError::Timeout) => {}
        }
        if poll_due(&mut last_poll) {
            match runtime.block_on(session.poll()) {
                Ok(_) => state.update(|s| s.clear_error()),
                Err(OnboardError::SessionEnded) => {
                    log::info!("Quick support ended by the supporter or timed out");
                    return end_here(None);
                }
                Err(err) => state.update(|s| s.fail(&err)),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer(status: u16, body: Value) -> Answer {
        Answer { status, body }
    }

    #[test]
    fn a_redeem_answer_has_token_supporter_and_server() {
        let redeemed = redeem_result(&answer(
            200,
            json!({
                "success": true,
                "session_token": "cd".repeat(32),
                "session": {"id": "0123456789abcdef", "status": "opened", "expires_at": "x", "device_id": ""},
                "supporter": "Mara Jensen",
                "company": "Fernhill IT",
                "server": {"id_server": "desk.example.com", "relay_server": "desk.example.com:21117",
                           "api_server": "https://desk.example.com:21121", "key": "a2V5"},
                "console": "https://desk.example.com",
            }),
        ))
        .unwrap();
        assert_eq!(redeemed.token, "cd".repeat(32));
        assert_eq!(redeemed.session_id, "0123456789abcdef");
        assert_eq!(redeemed.supporter, "Mara Jensen");
        assert_eq!(redeemed.company, "Fernhill IT");
        assert_eq!(redeemed.server.id_server, "desk.example.com");
        assert_eq!(redeemed.server.key, "a2V5");
        assert_eq!(
            redeem_result(&answer(200, json!({"success": true}))),
            Err(OnboardError::Server(200))
        );
        assert_eq!(
            redeem_result(&answer(404, json!({"error": "invalid_or_expired"}))),
            Err(OnboardError::InvalidOrExpired)
        );
    }

    #[test]
    fn final_statuses_and_401_end_the_session() {
        let status = |s: &str| answer(200, json!({"success": true, "session": {"status": s}}));
        assert_eq!(session_status(&status("asking")).as_deref(), Ok("asking"));
        assert_eq!(session_status(&status("allowed")).as_deref(), Ok("allowed"));
        for over in ["ended", "expired", "declined"] {
            assert_eq!(
                session_status(&status(over)),
                Err(OnboardError::SessionEnded)
            );
        }
        assert_eq!(
            session_status(&answer(401, json!({"error": "invalid_session"}))),
            Err(OnboardError::SessionEnded)
        );
        assert_eq!(
            session_status(&answer(409, json!({"error": "wrong_state"}))),
            Err(OnboardError::WrongState)
        );
    }
}
