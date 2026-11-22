//! The join flow against a small fake console.

use std::{
    collections::HashMap,
    io::{BufRead, BufReader, Read, Write},
    net::{TcpListener, TcpStream},
    sync::{Arc, Mutex},
    time::Duration,
};

use serde_json::{json, Value};

use super::{
    http::{Http, OnboardError},
    join::{redeem_join, DeviceIdentity},
    link::Console,
    Phase, State,
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
        redeem_join(&http, "ABCDEF23", &device()).await
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
        redeem_join(&http, "ZZZZZZZZ", &device()).await
    });
    assert_eq!(wrong, Err(OnboardError::InvalidOrExpired));
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
        redeem_join(&http, "ABCDEF23", &device()).await
    });
    assert_eq!(result, Err(OnboardError::Unreachable));
}

#[test]
fn a_link_without_http_1_never_talks_plain_http() {
    let console = FakeConsole::start(|_| (200, json!({"success": true})));
    let invite = super::link::parse(&format!(
        "betterdesk://join/127.0.0.1:{}/ABCDEF23",
        console.port
    ))
    .unwrap();
    let https = invite.console.unwrap();
    assert!(https.https);
    let result = block_on(async {
        let http = Http::new(https).await?;
        redeem_join(&http, "ABCDEF23", &device()).await
    });
    assert!(result.is_err(), "{result:?}");
    // The fake console speaks plain HTTP only; it must not have seen one
    // readable request.
    assert!(console.requests().is_empty(), "{:?}", console.requests());

    let plain = super::link::parse(&format!(
        "betterdesk://join/127.0.0.1:{}/ABCDEF23?http=1",
        console.port
    ))
    .unwrap();
    assert!(!plain.console.unwrap().https);
}

#[test]
fn the_state_has_the_ui_names() {
    let state = State {
        phase: Phase::Joining,
        server: Some("desk.example.com".to_owned()),
        join_step: 1,
        ..State::default()
    };
    let value = serde_json::to_value(&state).unwrap();
    assert_eq!(value["phase"], "joining");
    assert_eq!(value["joinStep"], 1);
    assert_eq!(value["server"], "desk.example.com");
    assert_eq!(value["error"], Value::Null);
    assert_eq!(serde_json::to_value(Phase::NotSetUp).unwrap(), "notSetUp");
    assert_eq!(serde_json::to_value(Phase::JoinFailed).unwrap(), "joinFailed");
}

#[test]
fn join_links_are_read_from_the_arguments() {
    let args = |values: &[&str]| values.iter().map(|v| v.to_string()).collect::<Vec<_>>();
    assert_eq!(
        super::invite_argument(&args(&["--join", "https://desk.example.com/join/ABCDEF23"])),
        Some("https://desk.example.com/join/ABCDEF23")
    );
    assert_eq!(super::invite_argument(&args(&["--join"])), None);
    assert_eq!(super::invite_argument(&args(&["--server"])), None);
    assert_eq!(
        super::invite_argument(&args(&["--connect", "123456789"])),
        None
    );
}
