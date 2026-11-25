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
    grants::Grants,
    http::{Http, OnboardError},
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
