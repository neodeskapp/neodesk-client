//! JSON requests to the console for joins and quick support sessions.
//!
//! An HTTPS console is reached with certificate checks that cannot be
//! turned off (no fallback that accepts any certificate), and an answer that
//! came back over plain HTTP after a redirect is refused. A console on plain
//! HTTP is reached only when its link said so.

use std::time::Duration;

use hbb_common::tls::TlsType;
use serde_json::Value;

use super::link::Console;
use crate::hbbs_http::{create_http_client_async, create_http_client_async_with_url_strict};

/// A console that takes no connection ends a join with "Can't reach" within
/// about this long (L524).
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// Why a join or a quick support step did not work.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OnboardError {
    /// The text is neither a link nor a code.
    NotALink,
    /// A bare code and no console known to send it to.
    NeedsServer,
    /// The code is unknown, expired, used up or of the other kind.
    InvalidOrExpired,
    /// No answer from the console.
    Unreachable,
    /// The console's certificate is not valid for its name.
    Certificate,
    /// An HTTPS request ended on plain HTTP.
    Insecure,
    /// Too many codes from this address in a minute.
    RateLimited,
    /// The console does not admit this device, with its reason.
    Refused(String),
    /// The console did not accept the device's details.
    InvalidDevice(String),
    /// The session is not in the state the step needs.
    WrongState,
    /// The session ended or its token is no longer valid.
    SessionEnded,
    /// The device has no ID yet.
    NoDeviceId,
    /// Any other answer.
    Server(u16),
}

impl OnboardError {
    /// A stable name of the error for the UI.
    pub fn code(&self) -> &'static str {
        match self {
            OnboardError::NotALink => "not_a_link",
            OnboardError::NeedsServer => "needs_server",
            OnboardError::InvalidOrExpired => "invalid_or_expired",
            OnboardError::Unreachable => "unreachable",
            OnboardError::Certificate => "certificate",
            OnboardError::Insecure => "insecure",
            OnboardError::RateLimited => "rate_limited",
            OnboardError::Refused(_) => "refused",
            OnboardError::InvalidDevice(_) => "invalid_device",
            OnboardError::WrongState => "wrong_state",
            OnboardError::SessionEnded => "ended",
            OnboardError::NoDeviceId => "no_device_id",
            OnboardError::Server(_) => "server_error",
        }
    }

    /// The error in plain words, for the command line.
    pub fn message(&self, server: &str) -> String {
        match self {
            OnboardError::NotALink => {
                "This doesn't look like an invite link or code. A code looks like 7KQ4-M2XD."
                    .to_owned()
            }
            OnboardError::NeedsServer => {
                "A code alone needs the server. Use the whole invite link.".to_owned()
            }
            OnboardError::InvalidOrExpired => {
                "This link has expired or was already used. Ask the person who sent it for a new one."
                    .to_owned()
            }
            OnboardError::Unreachable => format!(
                "Can't reach {server}. Check your internet connection and try again."
            ),
            OnboardError::Certificate => format!(
                "The certificate of {server} is not valid, so the connection is not safe. Ask your IT support."
            ),
            OnboardError::Insecure => format!(
                "{server} sent the answer over an insecure connection. Ask your IT support."
            ),
            OnboardError::RateLimited => {
                "Too many tries. Wait a minute and try again.".to_owned()
            }
            OnboardError::Refused(reason) | OnboardError::InvalidDevice(reason) => {
                if reason.is_empty() {
                    format!("{server} did not accept this computer.")
                } else {
                    format!("{server} did not accept this computer: {reason}")
                }
            }
            OnboardError::WrongState => "The session is no longer waiting for this step.".to_owned(),
            OnboardError::SessionEnded => "The session has ended.".to_owned(),
            OnboardError::NoDeviceId => "This computer has no ID yet. Try again in a moment.".to_owned(),
            OnboardError::Server(status) => {
                format!("{server} could not finish the request (HTTP {status}). Try again later.")
            }
        }
    }
}

/// The reasons a console gives for a computer it refuses ("reason" of a
/// device_refused answer), with the language key of the client's own words.
const REFUSAL_KEYS: &[(&str, &str)] = &[
    ("device_revoked", "nd-refused-revoked"),
    ("device_blocked", "nd-refused-blocked"),
    ("device_banned", "nd-refused-banned"),
    ("device_removed", "nd-refused-removed"),
    ("device_rejected", "nd-refused-rejected"),
    ("other_machine", "nd-refused-other-machine"),
    ("key_changed", "nd-refused-key-changed"),
    ("join_proof", "nd-refused-join-proof"),
];

/// The words for a refusal in the app's language: the client's own for a
/// reason it knows, the server's message for any other.
pub fn refusal_words(reason: &str, message: &str) -> String {
    match REFUSAL_KEYS.iter().find(|(r, _)| *r == reason) {
        Some((_, key)) => crate::lang::translate((*key).to_owned()),
        None => message.to_owned(),
    }
}

/// refusal_words in a given language.
#[cfg(test)]
pub fn refusal_words_in(reason: &str, message: &str, locale: &str) -> String {
    match REFUSAL_KEYS.iter().find(|(r, _)| *r == reason) {
        Some((_, key)) => crate::lang::translate_locale((*key).to_owned(), locale),
        None => message.to_owned(),
    }
}

/// True when the error or one of its causes is about the certificate, as
/// rustls, OpenSSL, Schannel and the macOS security framework word it.
pub fn is_certificate_error(err: &(dyn std::error::Error + 'static)) -> bool {
    let mut current = Some(err);
    while let Some(err) = current {
        let text = err.to_string().to_ascii_lowercase();
        if text.contains("certificate")
            || text.contains("unknownissuer")
            || text.contains("self signed")
            || text.contains("self-signed")
            || text.contains("notvalidforname")
        {
            return true;
        }
        current = err.source();
    }
    false
}

fn transport_error(err: reqwest::Error) -> OnboardError {
    if is_certificate_error(&err) {
        OnboardError::Certificate
    } else {
        OnboardError::Unreachable
    }
}

/// An answer: the HTTP status and the JSON body (Null when it is none).
#[derive(Debug, Clone)]
pub struct Answer {
    pub status: u16,
    pub body: Value,
}

impl Answer {
    pub fn text(&self, key: &str) -> String {
        self.body
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("")
            .to_owned()
    }

    /// The errors every route answers the same way.
    pub fn common_error(&self) -> Option<OnboardError> {
        match self.status {
            200..=299 => None,
            404 => Some(OnboardError::InvalidOrExpired),
            429 => Some(OnboardError::RateLimited),
            403 => Some(OnboardError::Refused(refusal_words(
                &self.text("reason"),
                &self.text("message"),
            ))),
            400 if self.text("error") == "invalid_device" => {
                Some(OnboardError::InvalidDevice(self.text("message")))
            }
            401 => Some(OnboardError::SessionEnded),
            409 => Some(OnboardError::WrongState),
            status => Some(OnboardError::Server(status)),
        }
    }
}

/// Requests to one console. Each request gets a client of its own: the
/// session is polled every few seconds, and a pooled connection the console
/// closed in between would fail the next poll.
pub struct Http {
    console: Console,
}

impl Http {
    pub async fn new(console: Console) -> Result<Self, OnboardError> {
        let http = Self { console };
        // Learns how TLS works with this console once.
        http.client().await?;
        Ok(http)
    }

    async fn client(&self) -> Result<reqwest::Client, OnboardError> {
        if self.console.https {
            create_http_client_async_with_url_strict(&self.console.base())
                .await
                .map_err(|_| OnboardError::Unreachable)
        } else {
            Ok(create_http_client_async(TlsType::Plain, false))
        }
    }

    pub async fn get(&self, path: &str, bearer: Option<&str>) -> Result<Answer, OnboardError> {
        let url = format!("{}{path}", self.console.base());
        let client = self.client().await?;
        self.send(client.get(&url), bearer).await
    }

    pub async fn post(
        &self,
        path: &str,
        body: &Value,
        bearer: Option<&str>,
    ) -> Result<Answer, OnboardError> {
        self.post_with_headers(path, body, bearer, &[]).await
    }

    /// A POST that also carries `headers`, such as a key proof.
    pub async fn post_with_headers(
        &self,
        path: &str,
        body: &Value,
        bearer: Option<&str>,
        headers: &[(String, String)],
    ) -> Result<Answer, OnboardError> {
        let url = format!("{}{path}", self.console.base());
        let client = self.client().await?;
        let request = headers
            .iter()
            .fold(client.post(&url).json(body), |request, (name, value)| {
                request.header(name.as_str(), value.as_str())
            });
        self.send(request, bearer).await
    }

    async fn send(
        &self,
        request: reqwest::RequestBuilder,
        bearer: Option<&str>,
    ) -> Result<Answer, OnboardError> {
        let mut request = request
            .timeout(REQUEST_TIMEOUT)
            .header(reqwest::header::ACCEPT, "application/json");
        if let Some(token) = bearer {
            request = request.bearer_auth(token);
        }
        let response = request.send().await.map_err(transport_error)?;
        if self.console.https && response.url().scheme() != "https" {
            return Err(OnboardError::Insecure);
        }
        let status = response.status().as_u16();
        let text = response.text().await.map_err(transport_error)?;
        Ok(Answer {
            status,
            body: serde_json::from_str(&text).unwrap_or(Value::Null),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[derive(Debug)]
    struct Chain(&'static str, Option<Box<Chain>>);

    impl std::fmt::Display for Chain {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str(self.0)
        }
    }

    impl std::error::Error for Chain {
        fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
            self.1.as_deref().map(|e| e as _)
        }
    }

    #[test]
    fn certificate_problems_are_found_anywhere_in_the_chain() {
        let rustls = Chain(
            "error sending request",
            Some(Box::new(Chain(
                "client error (Connect)",
                Some(Box::new(Chain("invalid peer certificate: UnknownIssuer", None))),
            ))),
        );
        assert!(is_certificate_error(&rustls));
        let schannel = Chain(
            "The certificate chain was issued by an authority that is not trusted.",
            None,
        );
        assert!(is_certificate_error(&schannel));
        let refused = Chain(
            "error sending request",
            Some(Box::new(Chain("Connection refused (os error 111)", None))),
        );
        assert!(!is_certificate_error(&refused));
    }

    #[test]
    fn common_errors_map_from_the_status() {
        let answer = |status, body| Answer { status, body };
        assert_eq!(answer(200, json!({})).common_error(), None);
        assert_eq!(
            answer(404, json!({"success": false, "error": "invalid_or_expired"})).common_error(),
            Some(OnboardError::InvalidOrExpired)
        );
        assert_eq!(
            answer(429, Value::Null).common_error(),
            Some(OnboardError::RateLimited)
        );
        assert_eq!(
            answer(403, json!({"error": "device_refused", "message": "Device is banned"}))
                .common_error(),
            Some(OnboardError::Refused("Device is banned".to_owned()))
        );
        assert_eq!(
            answer(400, json!({"error": "invalid_device", "message": "hostname too long"}))
                .common_error(),
            Some(OnboardError::InvalidDevice("hostname too long".to_owned()))
        );
        assert_eq!(
            answer(400, json!({"error": "invalid_body"})).common_error(),
            Some(OnboardError::Server(400))
        );
        assert_eq!(
            answer(401, json!({"error": "invalid_session"})).common_error(),
            Some(OnboardError::SessionEnded)
        );
        assert_eq!(
            answer(502, Value::Null).common_error(),
            Some(OnboardError::Server(502))
        );
    }
}
