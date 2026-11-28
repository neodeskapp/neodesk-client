//! The join and quick support flows against a small fake console.

use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    time::{Duration, Instant},
};

use serde_json::{json, Value};

use super::{
    caller,
    grants::Grants,
    http::{self, Http, OnboardError},
    join::{redeem_join, DeviceIdentity, ServerSettings},
    link::Console,
    support::{self, Command, SupportHost, Timing},
    Phase, SharedState, State,
};

#[derive(Debug, Clone)]
struct Request {
    method: String,
    path: String,
    headers: HashMap<String, String>,
    body: Value,
}

impl Request {
    fn bearer(&self) -> Option<&str> {
        self.headers
            .get("authorization")
            .and_then(|value| value.strip_prefix("Bearer "))
    }
}

type Handler = dyn Fn(&Request) -> (u16, Value) + Send + Sync;

/// An HTTP server on 127.0.0.1 that answers each request with `handler`
/// and keeps every request it could read.
struct FakeConsole {
    port: u16,
    requests: Arc<Mutex<Vec<Request>>>,
}

impl FakeConsole {
    fn start(handler: impl Fn(&Request) -> (u16, Value) + Send + Sync + 'static) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let handler: Arc<Handler> = Arc::new(handler);
        let kept = requests.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(stream) = stream else { continue };
                let (handler, kept) = (handler.clone(), kept.clone());
                std::thread::spawn(move || serve(stream, &*handler, &kept));
            }
        });
        Self { port, requests }
    }

    fn console(&self) -> Console {
        Console {
            https: false,
            host: "127.0.0.1".to_owned(),
            port: Some(self.port),
        }
    }

    fn requests(&self) -> Vec<Request> {
        self.requests.lock().unwrap().clone()
    }

    fn requests_to(&self, path: &str) -> Vec<Request> {
        self.requests()
            .into_iter()
            .filter(|r| r.path == path)
            .collect()
    }
}

fn serve(stream: TcpStream, handler: &Handler, kept: &Mutex<Vec<Request>>) {
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .ok();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    // A TLS handshake starts with 0x16; this console speaks plain HTTP only.
    match reader.fill_buf() {
        Ok(bytes) if bytes.first() != Some(&0x16) => {}
        _ => return,
    }
    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return;
    }
    let mut parts = line.split_whitespace();
    let (Some(method), Some(path), Some(version)) = (parts.next(), parts.next(), parts.next())
    else {
        return;
    };
    if !version.starts_with("HTTP/") {
        return;
    }
    let (method, path) = (method.to_owned(), path.to_owned());
    let mut headers = HashMap::new();
    loop {
        let mut header = String::new();
        if reader.read_line(&mut header).is_err() {
            return;
        }
        let header = header.trim_end();
        if header.is_empty() {
            break;
        }
        if let Some((name, value)) = header.split_once(':') {
            headers.insert(name.trim().to_ascii_lowercase(), value.trim().to_owned());
        }
    }
    let length = headers
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(0);
    let mut body = vec![0; length];
    if reader.read_exact(&mut body).is_err() {
        return;
    }
    let request = Request {
        method,
        path,
        headers,
        body: serde_json::from_slice(&body).unwrap_or(Value::Null),
    };
    let (status, answer) = handler(&request);
    kept.lock().unwrap().push(request);
    let answer = answer.to_string();
    let mut stream = stream;
    write!(
        stream,
        "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{answer}",
        answer.len()
    )
    .ok();
    stream.flush().ok();
}

fn block_on<F: std::future::Future>(future: F) -> F::Output {
    hbb_common::tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(future)
}

fn device() -> DeviceIdentity {
    DeviceIdentity {
        device_id: "123456789".to_owned(),
        uuid: "uuid-1".to_owned(),
        hostname: "reception".to_owned(),
        platform: "windows".to_owned(),
        version: "1.4.6".to_owned(),
        public_key: Some("cHVibGlj".to_owned()),
    }
}

fn server_answer() -> Value {
    json!({
        "id_server": "desk.example.com",
        "relay_server": "desk.example.com:21117",
        "api_server": "https://desk.example.com:21121",
        "key": "c2VydmVyLWtleQ==",
    })
}

fn wait_for(what: &str, mut done: impl FnMut() -> bool) {
    let start = Instant::now();
    while !done() {
        assert!(start.elapsed() < Duration::from_secs(10), "timed out: {what}");
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn join_sends_the_device_and_reads_the_answer() {
    let console = FakeConsole::start(|request| match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/onboard/join") if request.body["code"] == "ABCDEF23" => (
            200,
            json!({
                "success": true,
                "server": server_answer(),
                "device_token": "ab".repeat(32),
                "device": {"id": "123456789", "name": "Reception PC", "folder_id": 7},
                "console": "http://127.0.0.1",
            }),
        ),
        ("POST", "/api/onboard/join") => (404, json!({"success": false, "error": "invalid_or_expired"})),
        _ => (405, Value::Null),
    });

    let joined = block_on(async {
        let http = Http::new(console.console()).await?;
        redeem_join(&http, "ABCDEF23", &device(), &[]).await
    })
    .unwrap();
    assert_eq!(joined.server.id_server, "desk.example.com");
    assert_eq!(joined.server.key, "c2VydmVyLWtleQ==");
    assert_eq!(joined.device_token, "ab".repeat(32));
    assert_eq!(joined.device_name, "Reception PC");

    let sent = console.requests_to("/api/onboard/join");
    assert_eq!(sent.len(), 1);
    assert_eq!(
        sent[0].body,
        json!({
            "code": "ABCDEF23",
            "device_id": "123456789",
            "uuid": "uuid-1",
            "hostname": "reception",
            "platform": "windows",
            "version": "1.4.6",
            "public_key": "cHVibGlj",
        })
    );
    assert_eq!(sent[0].bearer(), None);

    let wrong = block_on(async {
        let http = Http::new(console.console()).await?;
        redeem_join(&http, "ZZZZZZZZ", &device(), &[]).await
    });
    assert_eq!(wrong, Err(OnboardError::InvalidOrExpired));
}

#[test]
fn a_join_refused_for_its_key_keeps_the_servers_words_and_the_invite() {
    const REASON: &str = "This computer's ID is already enrolled with another key. Ask your administrator to approve the new key or to delete the device in the console.";
    let console = FakeConsole::start(|_| {
        (
            403,
            json!({"success": false, "error": "device_refused", "message": REASON}),
        )
    });
    let err = block_on(async {
        let http = Http::new(console.console()).await?;
        redeem_join(&http, "ABCDEF23", &device(), &[]).await
    })
    .unwrap_err();

    let link = "http://127.0.0.1/join/ABCDEF23";
    let mut state = State {
        phase: Phase::JoinFailed,
        server: Some("127.0.0.1".to_owned()),
        link: Some(link.to_owned()),
        ..State::default()
    };
    state.fail(&err);
    assert_eq!(state.error.as_deref(), Some("refused"));
    assert_eq!(state.error_reason.as_deref(), Some(REASON));
    assert_eq!(state.link.as_deref(), Some(link));
    let value = serde_json::to_value(&state).unwrap();
    assert_eq!(value["errorReason"], REASON);
    assert_eq!(value["link"], link);

    state.fail(&OnboardError::Unreachable);
    assert_eq!(state.error_reason, None);
    state.fail(&err);
    state.clear_error();
    assert_eq!(state.error_reason, None);
}

/// L508: a bare code whose console (from an earlier join) no longer answers
/// on its old port is tried on the same host on the console port of 3.6.0.
/// A console without a port of its own, or already on that port, is not
/// tried elsewhere.
#[test]
fn a_known_console_on_an_old_port_is_tried_on_the_console_port() {
    let at = |https: bool, port: Option<u16>| Console {
        https,
        host: "10.10.10.74".to_owned(),
        port,
    };
    assert_eq!(
        super::moved_console(&at(false, Some(5000))),
        Some(at(false, Some(3375)))
    );
    assert_eq!(
        super::moved_console(&at(true, Some(8443))),
        Some(at(true, Some(3375)))
    );
    assert_eq!(super::moved_console(&at(false, Some(3375))), None);
    assert_eq!(super::moved_console(&at(true, None)), None);
}

/// L525: a code retried where the console moved reports the console that
/// answered, and `--join` prints that one, not the old port.
#[test]
fn a_join_on_the_moved_console_names_the_console_that_answered() {
    let old = Console {
        https: false,
        host: "10.10.10.74".to_owned(),
        port: Some(5000),
    };
    let joined = super::join::Joined {
        server: ServerSettings::default(),
        device_token: "token".to_owned(),
        device_name: String::new(),
        folder_id: None,
        console: String::new(),
    };
    let mut asked = Vec::new();
    let (got, answered) = super::redeem_at(old.clone(), false, |console| {
        asked.push(console.port);
        if console.port == Some(5000) {
            Err(OnboardError::Unreachable)
        } else {
            Ok(joined.clone())
        }
    })
    .unwrap();
    assert_eq!(asked, vec![Some(5000), Some(3375)]);
    assert_eq!(answered.port, Some(3375));
    assert_eq!(got.console, "http://10.10.10.74:3375");
    assert_eq!(
        super::joined_line(&answered, "", "525129550"),
        "This computer joined 10.10.10.74:3375. ID: 525129550"
    );

    // A console the invite named is not tried elsewhere
    let mut asked = Vec::new();
    let refused = super::redeem_at(old.clone(), true, |console| {
        asked.push(console.port);
        Err(OnboardError::Unreachable)
    });
    assert_eq!(refused.unwrap_err(), OnboardError::Unreachable);
    assert_eq!(asked, vec![Some(5000)]);

    // A console that answers is the one named
    let (_, answered) = super::redeem_at(old.clone(), false, |_| Ok(joined.clone())).unwrap();
    assert_eq!(answered, old);
    assert_eq!(
        super::joined_line(&answered, "Front desk", "1"),
        "This computer joined 10.10.10.74:5000 as Front desk. ID: 1"
    );
}

/// L524: after a join, the same code typed again with another address
/// (here one that does not answer) left the screen on "Connecting" for
/// ever: the code stayed taken and the join was refused without a word.
/// A code is taken only while its join runs.
#[test]
fn a_code_is_free_again_once_its_join_ended() {
    let first = super::JoinRun::start("L524AAAA").expect("free at first");
    assert!(
        super::JoinRun::start("L524AAAA").is_none(),
        "the same code twice at once"
    );
    // The join ended (joined): the same code may be joined again
    drop(first);
    let again = super::JoinRun::start("L524AAAA").expect("free after the join ended");
    drop(again);
}

/// L524: a console that takes the connection but never answers ends the
/// join with "Can't reach" within about 15 seconds.
#[test]
fn a_console_that_never_answers_is_unreachable_within_15_seconds() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let console = Console {
        https: false,
        host: "127.0.0.1".to_owned(),
        port: Some(listener.local_addr().unwrap().port()),
    };
    let started = Instant::now();
    let result = block_on(async {
        let http = Http::new(console).await?;
        redeem_join(&http, "ABCDEF23", &device(), &[]).await
    });
    assert_eq!(result, Err(OnboardError::Unreachable));
    assert!(
        started.elapsed() < Duration::from_secs(17),
        "{:?}",
        started.elapsed()
    );
    drop(listener);
}

#[test]
fn a_console_that_does_not_answer_is_unreachable() {
    let port = {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.local_addr().unwrap().port()
    };
    let console = Console {
        https: false,
        host: "127.0.0.1".to_owned(),
        port: Some(port),
    };
    let result = block_on(async {
        let http = Http::new(console).await?;
        redeem_join(&http, "ABCDEF23", &device(), &[]).await
    });
    assert_eq!(result, Err(OnboardError::Unreachable));
}

#[test]
fn a_link_without_http_1_never_talks_plain_http() {
    let console = FakeConsole::start(|_| (200, json!({"success": true})));
    let invite = super::link::parse(&format!(
        "neodesk://join/127.0.0.1:{}/ABCDEF23",
        console.port
    ))
    .unwrap();
    let https = invite.console.unwrap();
    assert!(https.https);
    let result = block_on(async {
        let http = Http::new(https).await?;
        redeem_join(&http, "ABCDEF23", &device(), &[]).await
    });
    assert!(result.is_err(), "{result:?}");
    // The fake console speaks plain HTTP only; it must not have seen one
    // readable request.
    assert!(console.requests().is_empty(), "{:?}", console.requests());

    let plain = super::link::parse(&format!(
        "neodesk://join/127.0.0.1:{}/ABCDEF23?http=1",
        console.port
    ))
    .unwrap();
    assert!(!plain.console.unwrap().https);
}

/// A quick support app with a password the test sets and a switch for
/// "the supporter is connected".
#[derive(Default)]
struct FakeHost {
    applied: Mutex<Vec<ServerSettings>>,
    grants: Mutex<Option<Grants>>,
    password: Mutex<String>,
    in_session: AtomicBool,
    shut_down: AtomicBool,
    asking: Mutex<Option<String>>,
    /// The caller channel as the run set it last, and every change
    channel: Mutex<Option<caller::Channel>>,
    channel_changes: Mutex<Vec<bool>>,
}

impl SupportHost for FakeHost {
    fn device(&self) -> DeviceIdentity {
        DeviceIdentity {
            public_key: None,
            ..device()
        }
    }

    fn apply_server(&self, server: &ServerSettings) {
        self.applied.lock().unwrap().push(server.clone());
    }

    fn set_grants(&self, grants: Grants) {
        *self.grants.lock().unwrap() = Some(grants);
    }

    fn password(&self) -> String {
        self.password.lock().unwrap().clone()
    }

    fn in_session(&self) -> bool {
        self.in_session.load(Ordering::SeqCst)
    }

    fn asking(&self) -> Option<String> {
        self.asking.lock().unwrap().clone()
    }

    fn caller_channel(&self, channel: Option<caller::Channel>) {
        self.channel_changes.lock().unwrap().push(channel.is_some());
        *self.channel.lock().unwrap() = channel;
    }

    fn shut_down(&self) {
        self.shut_down.store(true, Ordering::SeqCst);
    }
}

/// The session routes of a console with one support code, ABCDEF23.
struct SupportConsole {
    fake: FakeConsole,
    ended: Arc<AtomicBool>,
}

fn support_console(device_answer: (u16, Value)) -> SupportConsole {
    support_console_with(device_answer, Duration::ZERO)
}

/// The same console, slow to answer `/end` by `end_delay`.
fn support_console_with(device_answer: (u16, Value), end_delay: Duration) -> SupportConsole {
    let ended = Arc::new(AtomicBool::new(false));
    let status = Arc::new(Mutex::new("opened".to_owned()));
    let over = ended.clone();
    let fake = FakeConsole::start(move |request| {
        let session = |status: &str| json!({"success": true, "session": {"id": "s1", "status": status}});
        if request.path == "/api/support/session/end" {
            std::thread::sleep(end_delay);
        }
        if request.path == "/api/support/redeem" {
            return if request.body["code"] == "ABCDEF23" {
                (
                    200,
                    json!({
                        "success": true,
                        "session_token": "tok",
                        "session": {"id": "s1", "status": "opened", "expires_at": "", "device_id": ""},
                        "supporter": "Mara Jensen",
                        "company": "Fernhill IT",
                        "server": server_answer(),
                        "console": "http://127.0.0.1",
                    }),
                )
            } else {
                (404, json!({"success": false, "error": "invalid_or_expired"}))
            };
        }
        // The feedback routes take the token after the end too
        if request.path == super::feedback::PATH && request.bearer() == Some("tok") {
            return match request.method.as_str() {
                "GET" => (200, feedback_form()),
                _ => (200, json!({"success": true})),
            };
        }
        if request.bearer() != Some("tok") || over.load(Ordering::SeqCst) {
            return (401, json!({"success": false, "error": "invalid_session"}));
        }
        let mut status = status.lock().unwrap();
        match request.path.as_str() {
            "/api/support/session/device" => {
                if device_answer.0 == 200 {
                    *status = "asking".to_owned();
                }
                (device_answer.0, device_answer.1.clone())
            }
            "/api/support/session/consent" => {
                *status = if request.body["allowed"] == true {
                    "allowed"
                } else {
                    "declined"
                }
                .to_owned();
                (200, session(&status))
            }
            "/api/support/session/password" => (200, json!({"success": true})),
            "/api/support/session" => (200, session(&status)),
            "/api/support/session/end" => {
                over.store(true, Ordering::SeqCst);
                (200, json!({"success": true}))
            }
            _ => (404, Value::Null),
        }
    });
    SupportConsole { fake, ended }
}

struct Running {
    state: SharedState,
    host: Arc<FakeHost>,
    commands: mpsc::Sender<Command>,
    thread: std::thread::JoinHandle<()>,
}

fn run_support(console: &SupportConsole, code: &str) -> Running {
    let state = SharedState::default();
    let host = Arc::new(FakeHost::default());
    *host.password.lock().unwrap() = "pw-1".to_owned();
    let (commands, rx) = mpsc::channel();
    let thread = std::thread::spawn({
        let (state, host, console, code) = (
            state.clone(),
            host.clone(),
            console.fake.console(),
            code.to_owned(),
        );
        move || {
            let timing = Timing {
                poll: Duration::from_millis(50),
                tick: Duration::from_millis(10),
            };
            support::run(console, code, &*host, &state, &rx, timing);
        }
    });
    Running {
        state,
        host,
        commands,
        thread,
    }
}

fn passwords(console: &SupportConsole) -> Vec<Value> {
    console
        .fake
        .requests_to("/api/support/session/password")
        .into_iter()
        .map(|r| r.body["password"].clone())
        .collect()
}

#[test]
fn quick_support_reports_the_device_waits_for_consent_and_hands_over_the_password() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");

    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    let state = run.state.get();
    assert_eq!(state.supporter_name.as_deref(), Some("Mara Jensen"));
    assert_eq!(state.company.as_deref(), Some("Fernhill IT"));
    assert_eq!(state.server.as_deref(), Some("127.0.0.1"));
    // The device is reported before the app reaches the ID server.
    let device = console.fake.requests_to("/api/support/session/device");
    assert_eq!(device.len(), 1);
    assert_eq!(device[0].body["device_id"], "123456789");
    assert_eq!(device[0].body.get("public_key"), None);
    assert_eq!(run.host.applied.lock().unwrap()[0].id_server, "desk.example.com");
    // The session waits for the person: no answer and no password go out
    // on their own.
    std::thread::sleep(Duration::from_millis(200));
    assert_eq!(run.state.get().phase, Phase::SupportConsent);
    assert!(console.fake.requests_to("/api/support/session/consent").is_empty());
    assert!(passwords(&console).is_empty());

    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("password", || passwords(&console) == vec![json!("pw-1")]);
    assert_eq!(run.state.get().phase, Phase::SupportWaiting);
    let consent = console.fake.requests_to("/api/support/session/consent");
    assert_eq!(consent[0].body, json!({"allowed": true, "grants": []}));
    assert_eq!(*run.host.grants.lock().unwrap(), Some(Grants::default()));

    // The same password goes over once; a new one goes again.
    std::thread::sleep(Duration::from_millis(150));
    assert_eq!(passwords(&console).len(), 1);
    *run.host.password.lock().unwrap() = "pw-2".to_owned();
    wait_for("new password", || passwords(&console).len() == 2);
    assert_eq!(passwords(&console)[1], json!("pw-2"));

    run.host.in_session.store(true, Ordering::SeqCst);
    wait_for("in session", || run.state.get().phase == Phase::SupportInSession);
    assert!(!console.fake.requests_to("/api/support/session").is_empty());

    // The supporter ends the session in the console: the next poll gets 401.
    console.ended.store(true, Ordering::SeqCst);
    run.thread.join().unwrap();
    assert_eq!(run.state.get().phase, Phase::SupportEnded);
    assert_eq!(run.state.get().error, None);
    assert!(run.host.shut_down.load(Ordering::SeqCst));
    assert!(console.fake.requests_to("/api/support/session/end").is_empty());
}

/// The console's feedback form as the fake console sends it.
fn feedback_form() -> Value {
    json!({"success": true, "given": false, "form": {"questions": [
        {"id": "q1", "kind": "rating", "label": "How was the help?", "required": true},
        {"id": "q2", "kind": "text", "label": "Anything else?", "required": false, "long": true},
    ]}})
}

/// When the supporter's session on this computer ends (Stop session in the
/// connection manager, or the supporter leaves), quick support ends with
/// it: the window shows the end, not "waiting" again, the console hears of
/// it, and the end screen gets the console's feedback questions.
#[test]
fn quick_support_ends_with_the_session_and_asks_for_feedback() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("waiting", || run.state.get().phase == Phase::SupportWaiting);
    assert_eq!(run.state.get().session_started, None);

    run.host.in_session.store(true, Ordering::SeqCst);
    wait_for("in session", || run.state.get().phase == Phase::SupportInSession);
    assert!(run.state.get().session_started.is_some());
    // No feedback is asked for while the session runs
    assert!(console.fake.requests_to(super::feedback::PATH).is_empty());

    run.host.in_session.store(false, Ordering::SeqCst);
    wait_for("ended", || run.state.get().phase == Phase::SupportEnded);
    run.thread.join().unwrap();
    let state = run.state.get();
    assert_eq!(state.phase, Phase::SupportEnded);
    assert!(run.host.shut_down.load(Ordering::SeqCst));
    assert_eq!(console.fake.requests_to("/api/support/session/end").len(), 1);
    assert!(state.session_ended >= state.session_started);
    let asked = console.fake.requests_to(super::feedback::PATH);
    assert_eq!(asked.len(), 1);
    assert_eq!(asked[0].method, "GET");
    assert_eq!(asked[0].bearer(), Some("tok"));
    let ids: Vec<_> = state.feedback.iter().map(|q| q["id"].clone()).collect();
    assert_eq!(ids, vec![json!("q1"), json!("q2")]);
}

/// Quick support that ends before any session took place asks for no
/// feedback: there was nothing to rate.
#[test]
fn quick_support_without_a_session_asks_for_no_feedback() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("waiting", || run.state.get().phase == Phase::SupportWaiting);
    run.commands.send(Command::End).unwrap();
    run.thread.join().unwrap();
    assert_eq!(run.state.get().phase, Phase::SupportEnded);
    assert!(run.state.get().feedback.is_empty());
    assert!(console.fake.requests_to(super::feedback::PATH).is_empty());
}

/// The end screen shows only questions it can show, at most ten, and none
/// when the console has feedback off or already has the answers.
#[test]
fn feedback_questions_are_taken_only_from_a_good_answer() {
    use super::feedback;
    let answer = |status: u16, body: Value| http::Answer { status, body };
    let form = |questions: Value| json!({"success": true, "form": {"questions": questions}});
    let got = feedback::questions(&answer(200, form(json!([
        {"id": "a", "kind": "rating", "label": " How was it? ", "required": true},
        {"id": "b", "kind": "choice", "label": "Pick", "options": ["One", "Two", ""]},
        {"id": "c", "kind": "choice", "label": "One option only", "options": ["One"]},
        {"id": "d", "kind": "slider", "label": "Unknown kind"},
        {"id": "e", "kind": "text", "label": "   "},
        {"id": "a", "kind": "yesno", "label": "Same id again"},
        {"id": "f", "kind": "yesno", "label": "Line\u{7}break"},
    ]))));
    assert_eq!(
        got,
        vec![
            json!({"id": "a", "kind": "rating", "label": "How was it?", "required": true}),
            json!({"id": "b", "kind": "choice", "label": "Pick", "required": false, "options": ["One", "Two"]}),
            json!({"id": "f", "kind": "yesno", "label": "Linebreak", "required": false}),
        ]
    );
    let many: Vec<Value> = (0..15)
        .map(|i| json!({"id": format!("q{i}"), "kind": "yesno", "label": "x"}))
        .collect();
    assert_eq!(feedback::questions(&answer(200, form(json!(many)))).len(), 10);
    let one = json!([{"id": "a", "kind": "yesno", "label": "x"}]);
    assert!(feedback::questions(&answer(404, json!({"success": false, "error": "feedback_off"}))).is_empty());
    assert!(feedback::questions(&answer(401, form(one.clone()))).is_empty());
    let mut given = form(one);
    given["given"] = json!(true);
    assert!(feedback::questions(&answer(200, given)).is_empty());
}

/// The answers go out only for the console's questions and as their kind
/// needs; a required question without an answer sends nothing.
#[test]
fn feedback_answers_fit_the_questions() {
    use super::feedback;
    let questions = vec![
        json!({"id": "stars", "kind": "rating", "label": "x", "required": true}),
        json!({"id": "note", "kind": "text", "label": "x", "required": false, "long": true}),
        json!({"id": "pick", "kind": "choice", "label": "x", "required": false, "options": ["A", "B"]}),
        json!({"id": "again", "kind": "yesno", "label": "x", "required": false}),
    ];
    assert_eq!(
        feedback::body(&questions, &json!({"stars": 4, "note": "  thanks  ", "pick": "B", "again": true, "other": 1})),
        Some(json!({"answers": {"stars": 4, "note": "thanks", "pick": "B", "again": true}}))
    );
    // Answers that don't fit are left out
    assert_eq!(
        feedback::body(&questions, &json!({"stars": 5, "note": "", "pick": "C", "again": "yes"})),
        Some(json!({"answers": {"stars": 5}}))
    );
    let long = "x".repeat(3000);
    let sent = feedback::body(&questions, &json!({"stars": 1, "note": long})).unwrap();
    assert_eq!(sent["answers"]["note"].as_str().unwrap().len(), feedback::MAX_TEXT_CHARS);
    // The required rating is missing or out of range: nothing goes out
    assert_eq!(feedback::body(&questions, &json!({"note": "hi"})), None);
    assert_eq!(feedback::body(&questions, &json!({"stars": 6})), None);
    assert_eq!(feedback::body(&questions, &json!({"stars": 0})), None);

    let answer = |status: u16, body: Value| http::Answer { status, body };
    assert_eq!(feedback::sent_state(&answer(200, json!({"success": true}))), "sent");
    assert_eq!(feedback::sent_state(&answer(409, json!({"error": "already_given"}))), "sent");
    assert_eq!(feedback::sent_state(&answer(400, json!({"error": "invalid_answers"}))), "failed");
    assert_eq!(feedback::sent_state(&answer(409, json!({"error": "wrong_state"}))), "failed");
}

/// While a connection waits for the person's answer in the connection
/// manager, the quick support window says so instead of "has not connected
/// yet" (L553).
#[test]
fn quick_support_says_when_a_request_waits_in_the_other_window() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("waiting", || run.state.get().phase == Phase::SupportWaiting);
    assert_eq!(run.state.get().asking, None);

    *run.host.asking.lock().unwrap() = Some("Mara Jensen".to_owned());
    wait_for("asking", || run.state.get().asking.as_deref() == Some("Mara Jensen"));
    assert_eq!(run.state.get().phase, Phase::SupportWaiting);

    *run.host.asking.lock().unwrap() = None;
    run.host.in_session.store(true, Ordering::SeqCst);
    wait_for("in session", || run.state.get().phase == Phase::SupportInSession);
    assert_eq!(run.state.get().asking, None);
    run.commands.send(Command::End).unwrap();
    run.thread.join().unwrap();
}

/// Quick support opens a session with the one-time password only; the
/// approve mode never lets a caller in by click. Only a connection the
/// server vouches for gets Allow (A271), which the connection decides.
#[test]
fn quick_support_takes_only_the_password_unless_the_server_vouches() {
    let options = super::quick_support_options();
    let get = |key: &str| options.iter().find(|(k, _)| *k == key).map(|(_, v)| *v);
    assert_eq!(get("approve-mode"), Some("password"));
    assert_eq!(get("verification-method"), Some("use-temporary-password"));
    // In quick support Allow lets in only a vouched connection; elsewhere
    // the approve mode decides as before
    assert!(!caller::click_may_let_in(true, false));
    assert!(caller::click_may_let_in(true, true));
    assert!(caller::click_may_let_in(false, false));
}

/// An answer of the caller check, as the console sends it.
fn caller_answer(status: u16, body: Value) -> http::Answer {
    http::Answer { status, body }
}

fn vouched(device_id: &str, session: &str, helper: &str) -> Value {
    json!({"success": true, "vouched": true, "device_id": device_id, "session": session, "helper": helper})
}

/// The server's answer vouches for a caller only when it names this device,
/// the relay session the connection came through and a helper (A271). A
/// forged answer, one for another device or another connection, a refusal
/// (a replayed or a too old relay session) and an old server's 404 vouch
/// for nobody.
#[test]
fn the_caller_check_believes_only_an_answer_for_this_connection() {
    let (me, relay) = ("123456789", "6f1c2a9e-relay");
    // The good case: the helper's name comes from the server
    assert_eq!(
        caller::vouched_helper(&caller_answer(200, vouched(me, relay, "Olga Operator")), me, relay).as_deref(),
        Some("Olga Operator")
    );
    for (why, answer) in [
        ("another device", caller_answer(200, vouched("987654321", relay, "Olga Operator"))),
        ("another relay session", caller_answer(200, vouched(me, "other-relay", "Olga Operator"))),
        ("no helper", caller_answer(200, vouched(me, relay, "  "))),
        (
            "not vouched",
            caller_answer(200, json!({"success": true, "vouched": false, "device_id": me, "session": relay, "helper": "x"})),
        ),
        ("vouched as text", caller_answer(200, json!({"success": true, "vouched": "true", "device_id": me, "session": relay, "helper": "x"}))),
        ("a replayed relay session", caller_answer(409, json!({"success": false, "error": "not_vouched", "reason": "already_used"}))),
        ("a relay session over a minute old", caller_answer(409, json!({"success": false, "error": "not_vouched", "reason": "too_late"}))),
        ("a server without the route", caller_answer(404, Value::Null)),
        ("a 200 that is no JSON", caller_answer(200, Value::Null)),
        ("a 201 with a good body", caller_answer(201, vouched(me, relay, "Olga Operator"))),
    ] {
        assert_eq!(caller::vouched_helper(&answer, me, relay), None, "{why}");
    }
    // A connection that names no relay session or a device without an ID
    assert_eq!(caller::vouched_helper(&caller_answer(200, vouched(me, "", "x")), me, ""), None);
    assert_eq!(caller::vouched_helper(&caller_answer(200, vouched("", relay, "x")), "", relay), None);
    // The name is shown as text: no control characters, at most 128 of them
    let long = format!("Olga\u{7}\nOperator{}", "x".repeat(300));
    let shown = caller::vouched_helper(&caller_answer(200, vouched(me, relay, &long)), me, relay).unwrap();
    assert!(shown.starts_with("OlgaOperator"), "{shown}");
    assert_eq!(shown.chars().count(), 128);
}

/// The helper's picture comes with the server's answer: a PNG, JPEG or
/// WebP data URL of at most 64 KB. Anything else (an address the computer
/// would fetch, another type, a picture too large or not base64) is no
/// picture, and the helper is still vouched for.
#[test]
fn the_caller_check_takes_only_a_small_picture_from_the_server() {
    let (me, relay) = ("123456789", "6f1c2a9e-relay");
    let with = |avatar: Value| {
        let mut body = vouched(me, relay, "Olga Operator");
        body["helper_avatar"] = avatar;
        caller::vouched(&caller_answer(200, body), me, relay).unwrap()
    };
    let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
    assert_eq!(with(json!(png)), caller::Helper { name: "Olga Operator".to_owned(), avatar: Some(png.to_owned()) });
    assert!(with(json!("data:image/jpeg;base64,/9j/4AAQ")).avatar.is_some());
    for (why, avatar) in [
        ("an address", json!("https://example.com/olga.png")),
        ("another type", json!("data:image/svg+xml;base64,PHN2Zz4=")),
        ("not base64", json!("data:image/png;base64,<script>")),
        ("empty data", json!("data:image/png;base64,")),
        ("too large", json!(format!("data:image/png;base64,{}", "A".repeat(64 * 1024)))),
        ("no text", json!(42)),
    ] {
        assert_eq!(with(avatar).avatar, None, "{why}");
    }
    assert_eq!(caller::vouched(&caller_answer(200, vouched(me, relay, "Olga Operator")), me, relay).unwrap().avatar, None);
}

/// The check goes to the console's route with the session token and the
/// relay session, and takes the helper from the answer. A console that does
/// not know the route, or does not answer in time, vouches for nobody.
#[test]
fn the_caller_check_asks_the_console_with_the_session_token() {
    let (me, relay) = ("123456789", "6f1c2a9e-relay");
    let good = FakeConsole::start(move |request| {
        if request.path == caller::PATH
            && request.bearer() == Some("tok")
            && request.body["session"] == relay
            && request.body["secret"] == "s3cr3t"
        {
            (200, vouched(me, relay, "Olga Operator"))
        } else {
            (409, json!({"success": false, "error": "not_vouched", "reason": "session_not_open"}))
        }
    });
    let channel = |console: &FakeConsole, token: &str| caller::Channel {
        console: console.console(),
        token: token.to_owned(),
    };
    let wait = Duration::from_secs(5);
    assert_eq!(
        block_on(caller::ask(&channel(&good, "tok"), me, relay, "s3cr3t", wait)).map(|h| h.name).as_deref(),
        Some("Olga Operator")
    );
    let sent = good.requests_to(caller::PATH);
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].method, "POST");
    assert_eq!(sent[0].body, json!({"session": relay, "secret": "s3cr3t"}));
    // Another token or another relay session: not vouched
    assert_eq!(block_on(caller::ask(&channel(&good, "other"), me, relay, "s3cr3t", wait)), None);
    assert_eq!(block_on(caller::ask(&channel(&good, "tok"), me, "forged", "s3cr3t", wait)), None);
    assert_eq!(block_on(caller::ask(&channel(&good, "tok"), me, relay, "guessed", wait)), None);
    // No secret: the console is not asked at all
    let asked = good.requests_to(caller::PATH).len();
    assert_eq!(block_on(caller::ask(&channel(&good, "tok"), me, relay, "", wait)), None);
    assert_eq!(good.requests_to(caller::PATH).len(), asked);

    let old = FakeConsole::start(|_| (404, Value::Null));
    assert_eq!(block_on(caller::ask(&channel(&old, "tok"), me, relay, "s3cr3t", wait)), None);

    let slow = FakeConsole::start(move |_| {
        std::thread::sleep(Duration::from_millis(1500));
        (200, vouched(me, relay, "Olga Operator"))
    });
    let start = Instant::now();
    assert_eq!(block_on(caller::ask(&channel(&slow, "tok"), me, relay, "s3cr3t", Duration::from_millis(300))), None);
    assert!(start.elapsed() < Duration::from_millis(1200), "{:?}", start.elapsed());
}

/// A console on plain HTTP is never asked about a caller (A273): the
/// connection needs the password, and the console hears nothing.
#[test]
fn the_caller_check_never_asks_a_console_on_plain_http() {
    let (me, relay) = ("123456789", "6f1c2a9e-relay");
    let console = FakeConsole::start(move |_| (200, vouched(me, relay, "Olga Operator")));
    let plain = caller::Channel {
        console: console.console(),
        token: "tok".to_owned(),
    };
    assert!(!caller::may_ask(&plain));
    assert!(caller::may_ask(&caller::Channel {
        console: Console {
            https: true,
            ..console.console()
        },
        token: "tok".to_owned(),
    }));
    caller::open(plain);
    let check = caller::CallerCheck { session: relay.to_owned(), secret: "s3cr3t".to_owned() };
    assert_eq!(block_on(caller::vouched_caller(me, &check)), None);
    caller::close();
    assert!(console.requests_to(caller::PATH).is_empty());
}

/// The run lets connections ask about their caller only after the person
/// allowed quick support, with the session's console and token, and takes
/// that away once the session is over here.
#[test]
fn quick_support_opens_the_caller_check_only_after_allow() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(*run.host.channel.lock().unwrap(), None);
    assert!(run.host.channel_changes.lock().unwrap().is_empty());

    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("waiting", || run.state.get().phase == Phase::SupportWaiting);
    wait_for("channel", || run.host.channel.lock().unwrap().is_some());
    let channel = run.host.channel.lock().unwrap().clone().unwrap();
    assert_eq!(channel.token, "tok");
    assert_eq!(channel.console, console.fake.console());

    run.commands.send(Command::End).unwrap();
    run.thread.join().unwrap();
    assert_eq!(*run.host.channel.lock().unwrap(), None);
    assert_eq!(*run.host.channel_changes.lock().unwrap(), vec![true, false]);
}

/// A declined session never lets a connection ask.
#[test]
fn a_declined_quick_support_never_opens_the_caller_check() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(false, Grants::default())).unwrap();
    run.thread.join().unwrap();
    assert!(run.host.channel_changes.lock().unwrap().is_empty());
}

/// The connections that wait for the person to accept: one goes once it is
/// accepted or closed, and the window names the newest that still waits.
#[test]
fn waiting_requests_follow_the_connections() {
    let requests = super::Requests::default();
    assert_eq!(requests.newest(), None);
    requests.note(1, "admin", false);
    requests.note(2, "Mara Jensen", false);
    assert_eq!(requests.newest().as_deref(), Some("Mara Jensen"));
    requests.note(2, "Mara Jensen", true);
    assert_eq!(requests.newest().as_deref(), Some("admin"));
    requests.gone(1);
    assert_eq!(requests.newest(), None);
}

/// A computer the console refuses for a reason it names (a revoked or
/// blocked ID, L550) gets the client's own words for it, in the app's
/// language, and what to do; the server's English words are only the
/// fallback for a reason the client does not know.
#[test]
fn a_refusal_with_a_reason_is_said_in_the_clients_own_words() {
    let answer = |reason: &str| http::Answer {
        status: 403,
        body: json!({"success": false, "error": "device_refused", "reason": reason,
                     "message": "This computer's ID was revoked on this server."}),
    };
    match answer("device_revoked").common_error() {
        Some(OnboardError::Refused(words)) => {
            assert!(words.contains("revoked"), "{words}");
            assert!(words.contains("unblock"), "{words}");
            assert_ne!(words, "This computer's ID was revoked on this server.");
        }
        other => panic!("{other:?}"),
    }
    match answer("something_new").common_error() {
        Some(OnboardError::Refused(words)) => {
            assert_eq!(words, "This computer's ID was revoked on this server.")
        }
        other => panic!("{other:?}"),
    }
    for reason in [
        "device_revoked", "device_blocked", "device_banned", "device_removed",
        "device_rejected", "other_machine", "key_changed", "join_proof",
    ] {
        let de = http::refusal_words_in(reason, "x", "de");
        assert!(de != "x" && !de.starts_with("nd-"), "{reason}: {de}");
        assert_ne!(de, http::refusal_words_in(reason, "x", "en"), "{reason}");
    }
}

/// A computer refused for its join proof gets both ways out the server's
/// own text names: update NeoDesk, or have the old device deleted. The
/// join screen's next line ("When your administrator has done that, try
/// the same invite again") needs the second.
#[test]
fn a_refused_join_proof_names_the_administrator_too() {
    let en = http::refusal_words_in("join_proof", "x", "en");
    assert!(en.contains("Update NeoDesk"), "{en}");
    assert!(en.contains("delete the old device"), "{en}");
    let de = http::refusal_words_in("join_proof", "x", "de");
    assert!(de.contains("Aktualisiere NeoDesk"), "{de}");
    assert!(de.contains("das alte Gerät zu löschen"), "{de}");
}

#[test]
fn quick_support_declined_tells_the_console_and_hands_over_nothing() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(false, Grants::default())).unwrap();
    run.thread.join().unwrap();

    let state = run.state.get();
    assert_eq!(state.phase, Phase::SupportEnded);
    assert_eq!(state.error.as_deref(), Some("declined"));
    let consent = console.fake.requests_to("/api/support/session/consent");
    assert_eq!(consent.len(), 1);
    assert_eq!(consent[0].body, json!({"allowed": false}));
    assert!(passwords(&console).is_empty());
    assert!(run.host.shut_down.load(Ordering::SeqCst));
}

#[test]
fn quick_support_ended_by_the_person_calls_end() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands.send(Command::Consent(true, Grants::default())).unwrap();
    wait_for("password", || !passwords(&console).is_empty());
    run.commands.send(Command::End).unwrap();
    run.thread.join().unwrap();

    assert_eq!(run.state.get().phase, Phase::SupportEnded);
    let end = console.fake.requests_to("/api/support/session/end");
    assert_eq!(end.len(), 1);
    assert_eq!(end[0].bearer(), Some("tok"));
    assert!(run.host.shut_down.load(Ordering::SeqCst));
}

#[test]
fn quick_support_sends_what_the_person_ticked_and_the_app_keeps_to_it() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    let clipboard = Grants {
        clipboard: true,
        ..Grants::default()
    };
    run.commands.send(Command::Consent(true, clipboard)).unwrap();
    wait_for("password", || !passwords(&console).is_empty());

    let consent = console.fake.requests_to("/api/support/session/consent");
    assert_eq!(
        consent[0].body,
        json!({"allowed": true, "grants": ["clipboard"]})
    );
    assert_eq!(*run.host.grants.lock().unwrap(), Some(clipboard));
    run.commands.send(Command::End).unwrap();
    run.thread.join().unwrap();

    let both = Grants {
        clipboard: true,
        file_transfer: true,
    };
    assert_eq!(
        support::consent_body(true, both),
        json!({"allowed": true, "grants": ["clipboard", "file_transfer"]})
    );
    // A decline names nothing, whatever was ticked.
    assert_eq!(support::consent_body(false, both), json!({"allowed": false}));
}

#[test]
fn a_supporter_session_gets_only_what_the_person_allowed() {
    use hbb_common::config::keys;
    let none = Grants::default();
    assert!(none.allow(keys::OPTION_ENABLE_KEYBOARD));
    for option in [
        keys::OPTION_ENABLE_CLIPBOARD,
        keys::OPTION_ENABLE_FILE_TRANSFER,
        keys::OPTION_ENABLE_AUDIO,
        keys::OPTION_ENABLE_CAMERA,
        keys::OPTION_ENABLE_TERMINAL,
        keys::OPTION_ENABLE_TUNNEL,
        keys::OPTION_ENABLE_REMOTE_RESTART,
        keys::OPTION_ENABLE_RECORD_SESSION,
        keys::OPTION_ENABLE_BLOCK_INPUT,
        keys::OPTION_ENABLE_PRIVACY_MODE,
        keys::OPTION_ENABLE_REMOTE_PRINTER,
    ] {
        assert!(!none.allow(option), "{option}");
    }
    let both = Grants {
        clipboard: true,
        file_transfer: true,
    };
    assert!(both.allow(keys::OPTION_ENABLE_CLIPBOARD));
    assert!(both.allow(keys::OPTION_ENABLE_FILE_TRANSFER));
    assert!(!both.allow(keys::OPTION_ENABLE_AUDIO));
    // Outside quick support nothing changes.
    assert!(super::quick_support_allows(keys::OPTION_ENABLE_AUDIO));
}

#[test]
fn stop_cuts_the_supporter_off_before_the_console_hears_of_it() {
    let console = support_console_with(
        (200, json!({"success": true, "session": {"status": "asking"}})),
        Duration::from_secs(3),
    );
    let run = run_support(&console, "ABCDEF23");
    wait_for("consent screen", || run.state.get().phase == Phase::SupportConsent);
    run.commands
        .send(Command::Consent(true, Grants::default()))
        .unwrap();
    wait_for("password", || !passwords(&console).is_empty());
    run.host.in_session.store(true, Ordering::SeqCst);
    wait_for("in session", || run.state.get().phase == Phase::SupportInSession);

    let stopped = Instant::now();
    run.commands.send(Command::End).unwrap();
    while !run.host.shut_down.load(Ordering::SeqCst) {
        assert!(
            stopped.elapsed() < Duration::from_millis(1500),
            "Stop waited for the console"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(run.state.get().phase, Phase::SupportEnded);
    run.thread.join().unwrap();
    assert_eq!(console.fake.requests_to("/api/support/session/end").len(), 1);
}

#[test]
fn file_lines_name_the_file_or_count_them() {
    let one = super::FileLine::of(
        true,
        r"C:\Users\tester",
        &[("to-win.txt".to_owned(), 36)],
    );
    assert!(one.to_this_computer);
    assert_eq!((one.name.as_str(), one.count, one.size), ("to-win.txt", 1, 36));
    assert_eq!(one.path, r"C:\Users\tester");
    let file = super::FileLine::of(
        false,
        r"C:\Users\tester\Desktop\from-win.txt",
        &[(String::new(), 31)],
    );
    assert!(!file.to_this_computer);
    assert_eq!(file.name, "from-win.txt");
    let folder = super::FileLine::of(
        false,
        "/home/tester/Documents/",
        &[("a.txt".to_owned(), 10), ("b/c.txt".to_owned(), 20)],
    );
    assert_eq!((folder.name.as_str(), folder.count, folder.size), ("", 2, 30));

    let mut state = State::default();
    state.add_file(one);
    let value = serde_json::to_value(&state).unwrap();
    assert_eq!(value["files"][0]["toThisComputer"], true);
    assert_eq!(value["files"][0]["name"], "to-win.txt");
    assert_eq!(value["files"][0]["size"], 36);
}

#[test]
fn an_expired_support_code_changes_nothing() {
    let console = support_console((200, json!({"success": true, "session": {"status": "asking"}})));
    let run = run_support(&console, "ZZZZZZZZ");
    run.thread.join().unwrap();

    assert_eq!(run.state.get().phase, Phase::SupportExpired);
    assert_eq!(console.fake.requests().len(), 1);
    assert!(run.host.applied.lock().unwrap().is_empty());
    assert!(!run.host.shut_down.load(Ordering::SeqCst));
}

#[test]
fn a_refused_device_never_reaches_the_id_server() {
    let console = support_console((
        403,
        json!({"success": false, "error": "device_refused", "message": "Device is banned"}),
    ));
    let run = run_support(&console, "ABCDEF23");
    run.thread.join().unwrap();

    let state = run.state.get();
    assert_eq!(state.phase, Phase::SupportEnded);
    assert_eq!(state.error.as_deref(), Some("refused"));
    assert_eq!(
        state.error_text.as_deref(),
        Some("127.0.0.1 did not accept this computer: Device is banned")
    );
    assert!(run.host.applied.lock().unwrap().is_empty());
    assert_eq!(console.fake.requests_to("/api/support/session/end").len(), 1);
}

#[test]
fn the_state_has_the_ui_names() {
    let state = State {
        phase: Phase::SupportInSession,
        server: Some("desk.example.com".to_owned()),
        supporter_name: Some("Mara Jensen".to_owned()),
        ..State::default()
    };
    let value = serde_json::to_value(&state).unwrap();
    assert_eq!(value["phase"], "supportInSession");
    assert_eq!(value["supporterName"], "Mara Jensen");
    assert_eq!(value["server"], "desk.example.com");
    assert_eq!(value["error"], Value::Null);
    assert_eq!(serde_json::to_value(Phase::NotSetUp).unwrap(), "notSetUp");
    assert_eq!(serde_json::to_value(Phase::JoinFailed).unwrap(), "joinFailed");
}

#[test]
fn quick_support_uses_its_own_ipc_names() {
    assert_eq!(
        super::namespaced_ipc_path("/tmp/neodesk-1000/ipc"),
        "/tmp/neodesk-qs-1000/ipc"
    );
    assert_eq!(
        super::namespaced_ipc_path("/tmp/neodesk-service/ipc_service"),
        "/tmp/neodesk-qs-service/ipc_service"
    );
    assert_eq!(
        super::namespaced_ipc_path(r"\\.\pipe\neodesk\query_cm"),
        r"\\.\pipe\neodesk-qs\query_cm"
    );
}

#[test]
fn join_and_support_links_are_read_from_the_arguments() {
    let args = |values: &[&str]| values.iter().map(|v| v.to_string()).collect::<Vec<_>>();
    assert_eq!(
        super::invite_argument(&args(&["--join", "https://desk.example.com/join/ABCDEF23"])),
        Some("https://desk.example.com/join/ABCDEF23")
    );
    assert_eq!(
        super::invite_argument(&args(&["neodesk://support/desk.example.com/ABCDEF23"])),
        Some("neodesk://support/desk.example.com/ABCDEF23")
    );
    assert_eq!(super::invite_argument(&args(&["--join"])), None);
    assert_eq!(super::invite_argument(&args(&["--server"])), None);
    assert_eq!(
        super::invite_argument(&args(&["--connect", "123456789"])),
        None
    );
}

#[test]
fn a_handed_over_token_keeps_the_status_it_came_with() {
    let payload = |status: Option<&str>, device_id: &str| {
        let mut value = json!({
            "token": "t0ken",
            "device_id": device_id,
            "api": "http://desk.example.com:21114",
        });
        if let Some(status) = status {
            value["status"] = json!(status);
        }
        value.to_string()
    };
    let read = |payload: String| super::read_device_token(&payload, "123456789");

    let joined = read(payload(None, "123456789")).expect("a joined token was refused");
    assert_eq!(joined.status, "approved");
    assert_eq!(joined.token, "t0ken");
    assert_eq!(joined.api, "http://desk.example.com:21114");
    assert_eq!(
        read(payload(Some("pending"), "123456789")).map(|t| t.status),
        Some("pending")
    );
    assert_eq!(
        read(payload(Some("approved"), "123456789")).map(|t| t.status),
        Some("approved")
    );
    assert_eq!(read(payload(Some("rejected"), "123456789")), None);
    assert_eq!(read(payload(None, "987654321")), None);
}

/// The app's own state, which these steps share; one test runs them in turn.
#[test]
fn the_setup_screen_sees_each_join_and_can_leave_a_failed_one() {
    // A join failed; its screen is up, or the setup screen after Try another
    // code.
    super::STATE.update(|s| {
        s.phase = Phase::JoinFailed;
        s.fail(&OnboardError::Unreachable);
    });
    let closed = {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.local_addr().unwrap().port()
    };
    let link = format!("http://127.0.0.1:{closed}/join/ABCDEF23");
    super::redeem_join(link.clone());
    // The next join shows at once, so a quick second failure is a change the
    // screens see.
    let state = super::STATE.get();
    assert_eq!(state.phase, Phase::Joining);
    assert_eq!(state.error, None);
    assert_eq!(state.link.as_deref(), Some(link.as_str()));
    wait_for("second failure", || super::STATE.get().phase == Phase::JoinFailed);
    assert!(super::STATE.get().error.is_some());

    // Set up by hand leaves the failed join behind.
    super::dismiss_failed_join();
    let state = super::STATE.get();
    assert_eq!(state.phase, Phase::NotSetUp);
    assert_eq!(state.error, None);

    super::STATE.update(|s| s.phase = Phase::Joining);
    super::dismiss_failed_join();
    assert_eq!(super::STATE.get().phase, Phase::Joining);
    super::STATE.update(|s| *s = State::default());
}

#[test]
fn quick_support_chat_keeps_the_lines_of_both_sides() {
    let state = SharedState::default();
    let mut sent = Vec::new();
    super::chat_to_supporter(&state, "It is the printer".to_owned(), |text| {
        sent.push(text.to_owned());
        true
    });
    super::chat_to_supporter(&state, "  ".to_owned(), |_| panic!("an empty line went out"));
    super::chat_to_supporter(&state, "nobody gets this".to_owned(), |_| false);
    state.update(|s| s.add_chat(true, "Which one?".to_owned()));

    assert_eq!(sent, ["It is the printer"]);
    let lines: Vec<(bool, String)> = state
        .get()
        .messages
        .into_iter()
        .map(|line| (line.from_supporter, line.text))
        .collect();
    assert_eq!(
        lines,
        [
            (false, "It is the printer".to_owned()),
            (true, "Which one?".to_owned())
        ]
    );
    let value = serde_json::to_value(state.get()).unwrap();
    assert_eq!(value["messages"][1]["fromSupporter"], true);
    assert_eq!(value["messages"][1]["text"], "Which one?");
    assert!(value["messages"][1]["time"].as_i64().unwrap() > 0);

    for n in 0..super::CHAT_LINES_KEPT {
        state.update(|s| s.add_chat(true, n.to_string()));
    }
    let messages = state.get().messages;
    assert_eq!(messages.len(), super::CHAT_LINES_KEPT);
    assert_eq!(messages[0].text, "0");
}

#[test]
fn the_packed_exe_name_carries_the_invite() {
    let extracted = r"C:\Users\anna\AppData\Local\neodesk\neodesk.exe";
    let packed = "NeoDesk-Setup-desk.example.com-ABCDEF23 (1).exe";
    let started = super::started_file(Some(extracted), Some(packed));
    assert_eq!(started, Some(packed));
    let invite = super::link::parse_file_name(started.unwrap()).unwrap();
    assert_eq!(invite.kind, Some(super::Kind::Join));
    assert_eq!(invite.code, "ABCDEF23");

    assert_eq!(super::started_file(Some(extracted), None), Some(extracted));
    assert_eq!(super::started_file(Some(extracted), Some("")), Some(extracted));
}

const PROOF_HEADERS: [&str; 3] = [
    "x-nd-enrollment-timestamp",
    "x-nd-enrollment-nonce",
    "x-nd-enrollment-signature",
];

/// A console that lets every join in.
fn joining_console() -> FakeConsole {
    FakeConsole::start(|request| match (request.method.as_str(), request.path.as_str()) {
        ("POST", "/api/onboard/join") => (
            200,
            json!({
                "success": true,
                "server": server_answer(),
                "device_token": "ab".repeat(32),
                "device": {"id": "123456789", "name": "", "folder_id": null},
                "console": "http://127.0.0.1",
            }),
        ),
        _ => (405, Value::Null),
    })
}

/// Sends a join for `device` with `proof` to a console and returns the
/// request the console read.
fn sent_join(device: &DeviceIdentity, proof: &[(String, String)]) -> Request {
    let console = joining_console();
    block_on(async {
        let http = Http::new(console.console()).await?;
        redeem_join(&http, "ABCDEF23", device, proof).await
    })
    .unwrap();
    let mut sent = console.requests_to("/api/onboard/join");
    assert_eq!(sent.len(), 1);
    sent.remove(0)
}

/// Checks a join's key proof the way the console does: the signature
/// verifies with the body's public key over the nd-enrollment-v1 payload of
/// the request's method, path and the body's device ID.
fn proof_verifies(request: &Request) -> bool {
    use hbb_common::sodiumoxide::crypto::sign;
    let header = |name: &str| request.headers.get(name).cloned().unwrap_or_default();
    let body = |key: &str| request.body[key].as_str().unwrap_or("").to_owned();
    let Some(public_key) = crate::decode64(body("public_key"))
        .ok()
        .and_then(|key| sign::PublicKey::from_slice(&key))
    else {
        return false;
    };
    let Some(signature) = crate::decode64(header("x-nd-enrollment-signature"))
        .ok()
        .and_then(|bytes| sign::Signature::from_bytes(&bytes).ok())
    else {
        return false;
    };
    let payload = crate::hbbs_http::enrollment::proof_payload(
        &request.method,
        &request.path,
        &body("device_id"),
        &body("public_key"),
        &header("x-nd-enrollment-timestamp"),
        &header("x-nd-enrollment-nonce"),
    );
    sign::verify_detached(&signature, payload.as_bytes(), &public_key)
}

// The server refuses a join for a device ID it knows unless the request
// proves the key it holds for the ID (L483). The device's server process
// makes the proof; the join sends it with that process's key.
#[test]
fn a_join_proves_the_key_its_body_sends() {
    use hbb_common::sodiumoxide::crypto::sign;
    const TIMESTAMP: &str = "2026-11-25T10:00:00Z";
    const NONCE: &str = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
    let (public, secret) = sign::keypair_from_seed(&sign::Seed([7; 32]));
    let service_key = crate::encode64(public.0);
    let service_proof: Vec<(String, String)> = crate::hbbs_http::enrollment::proof_headers(
        "POST",
        "/api/onboard/join",
        "123456789",
        &public.0,
        &secret.0,
        TIMESTAMP,
        NONCE,
    )
    .unwrap()
    .into_iter()
    .map(|(name, value)| (name.to_owned(), value))
    .collect();

    let (device, proof) = DeviceIdentity::for_join(
        "123456789".to_owned(),
        Some((service_key.clone(), service_proof.clone())),
    );
    assert_eq!(device.device_id, "123456789");
    assert_eq!(
        device.public_key.as_deref(),
        Some(service_key.as_str()),
        "the join does not send the key the server process proved"
    );
    assert_eq!(proof, service_proof);

    let sent = sent_join(&device, &proof);
    for name in PROOF_HEADERS {
        assert!(sent.headers.contains_key(name), "the join went out without {name}");
    }
    assert_eq!(sent.headers["x-nd-enrollment-timestamp"], TIMESTAMP);
    assert_eq!(sent.headers["x-nd-enrollment-nonce"], NONCE);
    assert_eq!(sent.path, "/api/onboard/join");
    assert_eq!(sent.body["device_id"], "123456789");
    assert_eq!(sent.body["public_key"], json!(service_key));
    assert!(proof_verifies(&sent), "the join's proof does not verify");
}

// A client that runs its server in the window's process (not installed)
// holds the device's key and signs the join itself.
#[test]
fn a_join_without_a_server_process_is_signed_with_the_key_of_this_process() {
    use crate::ipc::device_key_tests::*;
    let _lock = DEVICE_KEY_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner());
    let _files = ConfigFilesGuard::new();
    let (_, public) = own_key_pair();

    // No server process answers in this test
    let (device, proof) = DeviceIdentity::for_join("123456789".to_owned(), None);
    assert_eq!(device.public_key, Some(crate::encode64(&public)));
    assert!(!proof.is_empty(), "the holder of the key sent its join unproved");

    let sent = sent_join(&device, &proof);
    for name in PROOF_HEADERS {
        assert!(sent.headers.contains_key(name), "the join went out without {name}");
    }
    assert_eq!(sent.body["public_key"], json!(crate::encode64(&public)));
    assert!(proof_verifies(&sent), "the join's proof does not verify");
}

// A window that got no proof from the service (none runs, it is an older
// one, or the main pipe's server is not the service) still sends its join,
// unsigned. For an ID the server knows, the server refuses it and the person
// sees why; the client does not hold the join back itself (L483).
#[test]
fn a_join_without_a_proof_from_the_service_goes_out_unsigned() {
    use crate::ipc::device_key_tests::*;
    const REASON: &str = "This computer's ID is already enrolled. The join has to prove its key.";
    let _lock = DEVICE_KEY_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner());
    let _files = ConfigFilesGuard::new();
    let _not_holder = NotSecretsHolder::new();
    let (_, service_public) = test_key_pair();
    hbb_common::config::Config::set_holder_public_key(service_public.clone());

    let (device, proof) = DeviceIdentity::for_join("123456789".to_owned(), None);
    assert!(proof.is_empty(), "the window signed the join");
    let console = FakeConsole::start(|request| {
        if request.headers.contains_key("x-nd-enrollment-signature") {
            (500, Value::Null)
        } else {
            (
                403,
                json!({"success": false, "error": "device_refused", "message": REASON}),
            )
        }
    });
    let result = block_on(async {
        let http = Http::new(console.console()).await?;
        redeem_join(&http, "ABCDEF23", &device, &proof).await
    });
    assert_eq!(result, Err(OnboardError::Refused(REASON.to_owned())));
    let sent = console.requests_to("/api/onboard/join");
    assert_eq!(sent.len(), 1, "the join did not go out");
    for name in PROOF_HEADERS {
        assert!(!sent[0].headers.contains_key(name), "the window sent {name}");
    }
    assert_eq!(sent[0].body["public_key"], json!(crate::encode64(&service_public)));
}

// The window of an installed client does not hold the device's secrets (L442).
// When no server process answers, its join sends the service's public key it
// learned earlier, or none: never a key of the window's own, which nobody
// signs with (L438), and never the copy an older version left in the profile.
// It sends no proof either; the server then refuses an ID it knows (L483).
#[test]
fn a_join_from_a_window_without_the_device_key_sends_no_key_of_its_own() {
    use crate::ipc::device_key_tests::*;
    let _lock = DEVICE_KEY_TEST_LOCK
        .lock()
        .unwrap_or_else(|err| err.into_inner());
    let _files = ConfigFilesGuard::new();
    let legacy = test_key_pair();
    write_key_pair_to_file(&legacy);
    let _not_holder = NotSecretsHolder::new();

    // No server process answers in this test
    let (device, proof) = DeviceIdentity::for_join("123456789".to_owned(), None);
    assert!(
        device.public_key.is_none(),
        "the join sent a key no server process signs with"
    );
    assert!(proof.is_empty(), "the window signed the join");
    let sent = sent_join(&device, &proof);
    for name in PROOF_HEADERS {
        assert!(!sent.headers.contains_key(name), "the window sent {name}");
    }
    assert!(sent.body.get("public_key").is_none());

    let (_, service_public) = test_key_pair();
    hbb_common::config::Config::set_holder_public_key(service_public.clone());
    let (device, proof) = DeviceIdentity::for_join("123456789".to_owned(), None);
    assert_eq!(device.public_key, Some(crate::encode64(&service_public)));
    assert!(proof.is_empty(), "the window signed the join");
    let sent = sent_join(&device, &proof);
    for name in PROOF_HEADERS {
        assert!(!sent.headers.contains_key(name), "the window sent {name}");
    }
    assert_eq!(sent.body["public_key"], json!(crate::encode64(&service_public)));
    assert!(
        reveals(&key_pair_of_file(), &legacy.0),
        "the join changed the key pair in the profile"
    );
}

/// Receiver mode comes from the signed config's `receiver=Y`, in a debug
/// build also from NEODESK_RECEIVER=1, and never in quick support.
#[test]
fn the_receiver_flag_comes_from_the_signed_config_and_debug_builds_only_take_the_variable() {
    use super::receiver_mode;
    assert!(receiver_mode(Some("Y"), None, false, false));
    assert!(receiver_mode(Some("y"), None, false, false));
    assert!(!receiver_mode(Some("N"), None, false, false));
    assert!(!receiver_mode(Some(""), None, false, false));
    assert!(!receiver_mode(None, None, true, false));
    assert!(receiver_mode(None, Some("1"), true, false), "debug build with the variable");
    assert!(
        !receiver_mode(None, Some("1"), false, false),
        "a release build ignores the variable"
    );
    assert!(!receiver_mode(None, Some("0"), true, false));
    assert!(
        !receiver_mode(Some("Y"), Some("1"), true, true),
        "Get help starts quick support, which is not the receiver"
    );
}

/// The offer to keep the app after quick support (A277): only when the
/// redeem answer allowed it, and its install carries the session's server
/// and the one-time admission.
#[test]
fn the_offer_installs_the_receiver_with_the_sessions_admission() {
    let admission = "3f9c0d".repeat(8);
    let answer = |offer: Value| http::Answer {
        status: 200,
        body: json!({
            "success": true,
            "session_token": "ab".repeat(32),
            "session": {"id": "0123456789abcdef", "status": "opened"},
            "supporter": "Mara Jensen",
            "company": "Fernhill IT",
            "server": {"id_server": "desk.example.com", "relay_server": "desk.example.com:21117",
                       "api_server": "https://desk.example.com:21121", "key": "a2V5"},
            "console": "https://desk.example.com",
            "receiver_offer": offer,
        }),
    };
    let console = Console::from_base("https://desk.example.com").unwrap();
    let redeemed = support::redeem_result(&answer(
        json!({"allowed": true, "admission": admission, "expires_at": "2026-11-28T14:05:00Z"}),
    ))
    .unwrap();
    super::AppHost.redeemed(&console, &redeemed);
    let file = super::OFFER.lock().unwrap().clone().expect("an offer");
    assert!(file.receiver);
    assert_eq!(file.server, "desk.example.com");
    assert_eq!(file.key, "a2V5");
    assert_eq!(file.api, "https://desk.example.com:21121");
    assert_eq!(file.console, "https://desk.example.com");
    assert_eq!(file.admission, admission);
    assert_eq!(file.token, "");
    // What the install gets: the same file, admission included
    let request = super::install_file::offer_request(&file.render()).unwrap();
    assert_eq!(request.admission, admission);
    assert_eq!(
        request.enrollment_fields(),
        vec![("admission", admission.clone())]
    );

    // Not allowed: nothing is offered
    let redeemed = support::redeem_result(&answer(
        json!({"allowed": false, "admission": null, "expires_at": null}),
    ))
    .unwrap();
    super::AppHost.redeemed(&console, &redeemed);
    assert!(super::OFFER.lock().unwrap().is_none());
}

// ------------------------------------------------ unattended access (A279)

use super::{
    receiver_policy::AccessPolicy,
    unattended::{self, Login, OrgPolicy, Policy},
};

const UA_ME: &str = "123456789";
const UA_RELAY: &str = "6f1c2a9e-relay";
const UA_SECRET: &str = "q3Jx_9vT-2mYc8LwPz0aRk5NdE7uFhGsVbI4oA1eWnU";
/// Monday 2026-11-16 09:00 UTC, 10:00 in Berlin.
const UA_MONDAY_MORNING: i64 = 1_794_819_600;

fn ua_login() -> Login<'static> {
    Login {
        receiver: true,
        support_session: false,
        relay_session: Some(UA_RELAY),
        secret: UA_SECRET,
        https: true,
        device_id: UA_ME,
    }
}

fn ua_vouched(device_id: &str, session: &str) -> http::Answer {
    caller_answer(
        200,
        json!({"success": true, "vouched": true, "device_id": device_id, "session": session,
               "helper": "Olga Operator", "helper_username": "olga", "via": "desktop"}),
    )
}

fn ua_policy(mode: &str, access: AccessPolicy) -> Policy {
    Policy {
        org: Some(OrgPolicy { mode: Some(mode.to_owned()), ..Default::default() }),
        access: Some(Some(access)),
    }
}

fn ua_office() -> AccessPolicy {
    AccessPolicy {
        unattended_enabled: true,
        schedule_enabled: true,
        schedule_days: ["mon", "tue", "wed", "thu", "fri"].map(String::from).to_vec(),
        schedule_start: "08:00".into(),
        schedule_end: "18:00".into(),
        schedule_timezone: "Europe/Berlin".into(),
        ..Default::default()
    }
}

/// The decision for one case, as the connection gets it.
fn ua_decide(login: &Login, answer: Option<&http::Answer>, policy: &Policy, now: i64) -> Result<String, &'static str> {
    unattended::unattended_may_let_in(login, answer, policy, now).map(|u| u.helper.name)
}

/// A vouched caller under the device's rule gets in without Allow, with
/// the server's name for the helper and how it vouched.
#[test]
fn unattended_access_lets_in_a_vouched_caller_the_rule_allows() {
    let policy = ua_policy("attended", ua_office());
    let answer = ua_vouched(UA_ME, UA_RELAY);
    let caller = unattended::unattended_may_let_in(&ua_login(), Some(&answer), &policy, UA_MONDAY_MORNING).unwrap();
    assert_eq!(caller.helper.name, "Olga Operator");
    assert_eq!(caller.username, "olga");
    assert_eq!(caller.via, "desktop");
}

/// Every caller the server does not vouch for, for this device and this
/// relay session, keeps the Allow prompt.
#[test]
fn unattended_access_needs_the_servers_proof_for_this_connection() {
    let policy = ua_policy("unattended", AccessPolicy::default());
    let now = UA_MONDAY_MORNING;
    let refused = |reason: &str| {
        caller_answer(409, json!({"success": false, "error": "not_vouched", "reason": reason}))
    };
    for (why, answer, want) in [
        ("no answer", None, "no_answer"),
        ("another device", Some(ua_vouched("987654321", UA_RELAY)), "not_for_this_connection"),
        ("another relay session", Some(ua_vouched(UA_ME, "other-relay")), "not_for_this_connection"),
        ("too late", Some(refused("too_late")), "too_late"),
        ("already used", Some(refused("already_used")), "already_used"),
        ("the server's rule", Some(refused("outside_schedule")), "outside_schedule"),
        ("an old server", Some(caller_answer(404, Value::Null)), "no_vouch"),
        ("a 401 for a banned device", Some(caller_answer(401, json!({"error": "unauthorized"}))), "no_vouch"),
        (
            "vouched as text",
            Some(caller_answer(200, json!({"success": true, "vouched": "true", "device_id": UA_ME,
                "session": UA_RELAY, "helper": "Olga Operator", "helper_username": "olga"}))),
            "not_for_this_connection",
        ),
    ] {
        assert_eq!(ua_decide(&ua_login(), answer.as_ref(), &policy, now), Err(want), "{why}");
    }
    assert!(ua_decide(&ua_login(), Some(&ua_vouched(UA_ME, UA_RELAY)), &policy, now).is_ok());
}

/// A vouched caller still needs the device's own rule: ask_always, the
/// schedule, the allowed operators and a policy it has not read yet each
/// keep the Allow prompt.
#[test]
fn unattended_access_needs_the_devices_own_rule_too() {
    let answer = ua_vouched(UA_ME, UA_RELAY);
    let decide = |policy: &Policy, now| ua_decide(&ua_login(), Some(&answer), policy, now);
    assert_eq!(decide(&ua_policy("ask_always", ua_office()), UA_MONDAY_MORNING), Err("ask_always"));
    assert_eq!(
        decide(&ua_policy("attended", AccessPolicy::default()), UA_MONDAY_MORNING),
        Err("not_enabled")
    );
    // Saturday, and Monday 18:30 in Berlin
    assert_eq!(
        decide(&ua_policy("attended", ua_office()), UA_MONDAY_MORNING + 5 * 86_400),
        Err("outside_schedule")
    );
    assert_eq!(
        decide(&ua_policy("unattended", ua_office()), UA_MONDAY_MORNING + 8 * 3600 + 1800),
        Err("outside_schedule")
    );
    let mut device_list = ua_office();
    device_list.allowed_operators = vec!["anna".into()];
    assert_eq!(decide(&ua_policy("attended", device_list), UA_MONDAY_MORNING), Err("operator_not_allowed"));
    let mut org_list = ua_policy("unattended", AccessPolicy::default());
    org_list.org.as_mut().unwrap().operators = vec!["anna".into()];
    assert_eq!(decide(&org_list, UA_MONDAY_MORNING), Err("operator_not_allowed"));
    org_list.org.as_mut().unwrap().operators = vec!["OLGA".into()];
    assert_eq!(decide(&org_list, UA_MONDAY_MORNING), Err("operator_not_allowed"), "no case folding");
    org_list.org.as_mut().unwrap().operators = vec![" olga ".into()];
    assert!(decide(&org_list, UA_MONDAY_MORNING).is_ok());
    // A policy of the wrong shape lets nobody in
    let mut bad_org = ua_policy("unattended", AccessPolicy::default());
    bad_org.org.as_mut().unwrap().malformed = true;
    assert_eq!(decide(&bad_org, UA_MONDAY_MORNING), Err("malformed_policy"));
    let bad_access = ua_policy("unattended", AccessPolicy { malformed: true, ..Default::default() });
    assert_eq!(decide(&bad_access, UA_MONDAY_MORNING), Err("malformed_policy"));
    // Nothing read yet from the server: no unattended access
    let unread = Policy { org: None, ..ua_policy("unattended", AccessPolicy::default()) };
    assert_eq!(decide(&unread, UA_MONDAY_MORNING), Err("no_policy"));
    let no_heartbeat = Policy { access: None, ..ua_policy("unattended", AccessPolicy::default()) };
    assert_eq!(decide(&no_heartbeat, UA_MONDAY_MORNING), Err("no_access_policy"));
}

/// Only the receiver outside a Get help session asks, for a relayed login
/// without a password, over HTTPS; anywhere else even a good proof lets
/// nobody in without Allow.
#[test]
fn unattended_access_is_only_for_the_receiver_on_https() {
    let policy = ua_policy("unattended", AccessPolicy::default());
    let answer = ua_vouched(UA_ME, UA_RELAY);
    assert!(unattended::may_ask(&ua_login()));
    for (why, login) in [
        ("plain HTTP", Login { https: false, ..ua_login() }),
        ("not a receiver", Login { receiver: false, ..ua_login() }),
        ("a Get help session", Login { support_session: true, ..ua_login() }),
        ("a direct connection", Login { relay_session: None, ..ua_login() }),
        ("an empty relay session", Login { relay_session: Some(""), ..ua_login() }),
        ("no caller secret", Login { secret: "", ..ua_login() }),
        ("no device ID", Login { device_id: "", ..ua_login() }),
    ] {
        assert!(!unattended::may_ask(&login), "{why}");
        assert_eq!(ua_decide(&login, Some(&answer), &policy, UA_MONDAY_MORNING), Err("not_asked"), "{why}");
    }
}

/// The check goes to the API address with the device token and the device
/// ID, and gives up after the wait.
#[test]
fn unattended_access_asks_with_the_device_token() {
    let console = FakeConsole::start(move |request| {
        if request.path == unattended::PATH
            && request.bearer() == Some("device-tok")
            && request.headers.get("x-device-id").map(String::as_str) == Some(UA_ME)
            && request.body == json!({"session": UA_RELAY, "secret": UA_SECRET})
        {
            (200, json!({"success": true, "vouched": true, "device_id": UA_ME, "session": UA_RELAY,
                         "helper": "Olga Operator", "helper_username": "olga", "via": "console"}))
        } else {
            (409, json!({"success": false, "error": "not_vouched", "reason": "session_not_open"}))
        }
    });
    let wait = Duration::from_secs(5);
    let answer = block_on(unattended::ask(&console.console(), "device-tok", UA_ME, UA_RELAY, UA_SECRET, wait)).unwrap();
    assert_eq!(answer.status, 200);
    let sent = console.requests_to(unattended::PATH);
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].method, "POST");
    let other = block_on(unattended::ask(&console.console(), "other-tok", UA_ME, UA_RELAY, UA_SECRET, wait)).unwrap();
    assert_eq!(other.status, 409);
    let guessed = block_on(unattended::ask(&console.console(), "device-tok", UA_ME, UA_RELAY, "guessed", wait)).unwrap();
    assert_eq!(guessed.status, 409);

    let slow = FakeConsole::start(|_| {
        std::thread::sleep(Duration::from_millis(1500));
        (200, Value::Null)
    });
    let start = Instant::now();
    assert!(block_on(unattended::ask(&slow.console(), "device-tok", UA_ME, UA_RELAY, UA_SECRET, Duration::from_millis(300))).is_none());
    assert!(start.elapsed() < Duration::from_millis(1200), "{:?}", start.elapsed());
}

/// The shared test vectors of the rule
/// (neodesk-server/policy/unattended/testdata/rule-vectors.json, copied
/// unchanged): the receiver decides each case as the server does.
#[test]
fn unattended_rule_matches_the_shared_vectors() {
    let text = include_str!("testdata/unattended-rule-vectors.json");
    let parsed: Value = serde_json::from_str(text).unwrap();
    let vectors = parsed
        .as_array()
        .or_else(|| parsed.get("vectors").and_then(Value::as_array))
        .expect("a list of vectors");
    assert!(vectors.len() >= 40, "{} vectors", vectors.len());
    let mut failed = Vec::new();
    for v in vectors {
        let name = v["name"].as_str().unwrap_or("?");
        let now = chrono::DateTime::parse_from_rfc3339(v["now"].as_str().unwrap())
            .unwrap_or_else(|err| panic!("{name}: {err}"))
            .timestamp();
        let access = match &v["access"] {
            Value::Null => None,
            access => Some(unattended::access_policy_of(access)),
        };
        let Some(org) = unattended::names_of(v.get("org_operators")) else {
            failed.push(format!("{name}: org_operators is not a list"));
            continue;
        };
        let got = super::receiver_policy::unattended_rule(
            v["mode"].as_str(),
            &org,
            access.as_ref(),
            v["caller"].as_str().unwrap_or(""),
            now,
            &unattended::offset_of,
        );
        let got = match got {
            Ok(()) => "allow",
            Err(refusal) => refusal.reason(),
        };
        if got != v["want"].as_str().unwrap_or("") {
            failed.push(format!("{name}: got {got}, want {}", v["want"]));
        }
    }
    assert!(failed.is_empty(), "{}", failed.join("\n"));
}

/// Which login the connection asks the server about (both the unattended
/// path and quick support's): only one without a password, through the
/// relay, with the caller secret signal gave the real caller. The relay
/// UUID alone travels in plain text, so a login without the secret, or
/// with a password, or a direct one, is never asked about, and the person
/// decides as before. This is the decision connection.rs takes.
#[test]
fn only_a_relayed_login_with_the_caller_secret_and_no_password_is_asked_about() {
    use hbb_common::message_proto::LoginRequest;
    let login = |password: &[u8], secret: &str| LoginRequest {
        password: password.to_vec().into(),
        nd_caller_secret: secret.to_owned(),
        ..Default::default()
    };
    let check = |lr: &LoginRequest, relay: Option<&str>, terminal: bool| {
        super::caller_check_of(&lr.password, &lr.nd_caller_secret, relay, terminal)
    };
    assert_eq!(
        check(&login(b"", UA_SECRET), Some(UA_RELAY), false),
        Some(super::CallerCheck { session: UA_RELAY.to_owned(), secret: UA_SECRET.to_owned() })
    );
    assert_eq!(check(&login(b"", &format!(" {UA_SECRET} ")), Some(UA_RELAY), false).unwrap().secret, UA_SECRET);
    for (why, lr, relay, terminal) in [
        ("a password", login(b"hashed-password", UA_SECRET), Some(UA_RELAY), false),
        ("no secret", login(b"", ""), Some(UA_RELAY), false),
        ("a blank secret", login(b"", "   "), Some(UA_RELAY), false),
        ("a secret that isn't base64url", login(b"", "a b\"c"), Some(UA_RELAY), false),
        ("a secret too long", login(b"", &"A".repeat(300)), Some(UA_RELAY), false),
        ("a direct connection", login(b"", UA_SECRET), None, false),
        ("an empty relay session", login(b"", UA_SECRET), Some(" "), false),
        ("a terminal's OS login", login(b"", UA_SECRET), Some(UA_RELAY), true),
    ] {
        assert_eq!(check(&lr, relay, terminal), None, "{why}");
    }
}
