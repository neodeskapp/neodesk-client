//! The computer's chat with the console's support staff (the console's
//! chat protocol, version 2: neodesk-server/console/routes/chat/PROTOCOL.md).
//!
//! The device token stays in the process that keeps it: the one that runs
//! the sync loop and the IPC server. The chat window's process asks that
//! process over IPC ([`NdChat`] in `Data::NdChat`) to open the chat socket
//! and pass the text frames both ways on that IPC connection, and to upload
//! and fetch the files of the chat. The window's process hands the frames to
//! Flutter as global events named "nd-chat" (see [`window`] and
//! flutter/lib/models/nd_chat_bridge.dart). The token is never put in a URL,
//! a log line or an IPC message.

use crate::hbbs_http::enrollment;
use crate::ipc::{Connection, Data};
use hbb_common::{
    bytes::Bytes,
    config::Config,
    futures::{SinkExt, StreamExt},
    log, tokio,
};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// What the chat window's process and the process holding the device token
/// tell each other on one IPC connection.
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(tag = "t", content = "c")]
pub enum NdChat {
    /// Window: open the chat socket and relay it on this connection.
    Open,
    /// A text frame of the chat socket, either way.
    Frame(String),
    /// The chat socket is gone: the HTTP status of a refused upgrade, 0 when
    /// it dropped or nobody answered, [`NO_TOKEN`] without a device token.
    Closed(u16),
    /// Window: upload a file; its bytes follow as the next raw frame.
    Upload { name: String, size: u64 },
    /// The upload's HTTP status and answer.
    Uploaded { status: u16, body: String },
    /// Window: fetch a file (`inline` for a picture to show).
    Download { id: String, inline: bool },
    /// The download's HTTP status; on 200 the bytes follow as a raw frame.
    Downloaded { status: u16, size: u64 },
    /// An admin turned "Chat with computers" off: ask again after these
    /// seconds.
    ChatOff(u32),
}

/// [`NdChat::Closed`] and [`NdChat::Uploaded`] when this computer holds no
/// device token for its server: no NeoDesk console, or not approved yet.
pub const NO_TOKEN: u16 = 1;

/// The window's closing status when chat with computers is off: the
/// upgrade answered 503 with `X-NeoDesk-Chat: chat_off`, or the open
/// socket was closed with 1008 `chat_off`.
pub const CHAT_OFF: u16 = 2;

/// How long to wait with chat off when the server named no time.
const CHAT_OFF_RETRY: u32 = 600;

/// The largest file of the chat (PROTOCOL.md section 6).
pub const MAX_FILE_BYTES: u64 = 50 << 20;

/// [`NdChat::Uploaded`] for a file over [`MAX_FILE_BYTES`].
const TOO_LARGE: u16 = 413;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const FILE_TIMEOUT: Duration = Duration::from_secs(300);

/// The server, device and token the chat uses.
struct Access {
    api: String,
    device_id: String,
    token: String,
}

/// The device token when it was issued for this device and server, as the
/// enrollment requests use it.
fn access() -> Option<Access> {
    let api = crate::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    let api = api.trim_end_matches('/').to_owned();
    if api.is_empty() || crate::is_public(&api) {
        return None;
    }
    let device_id = Config::get_id();
    let token = enrollment::StoredToken::load()
        .usable_for(&device_id, &api)?
        .to_owned();
    Some(Access {
        api,
        device_id,
        token,
    })
}

/// `{api}/ws/chat/<device id>?v=2` with ws for http and wss for https.
pub fn socket_url(api: &str, device_id: &str) -> Option<String> {
    let mut url = url::Url::parse(api).ok()?;
    let scheme = match url.scheme() {
        "https" => "wss",
        "http" => "ws",
        _ => return None,
    };
    url.set_scheme(scheme).ok()?;
    url.path_segments_mut()
        .ok()?
        .pop_if_empty()
        .extend(["ws", "chat", device_id]);
    url.set_query(Some("v=2"));
    Some(url.into())
}

/// `{api}/api/chat/device/files[/<id>][?inline=1]`.
pub fn files_url(api: &str, id: Option<&str>, inline: bool) -> Option<String> {
    let mut url = url::Url::parse(api).ok()?;
    if !matches!(url.scheme(), "http" | "https") {
        return None;
    }
    {
        let mut path = url.path_segments_mut().ok()?;
        path.pop_if_empty().extend(["api", "chat", "device", "files"]);
        if let Some(id) = id {
            path.push(id);
        }
    }
    if inline {
        url.set_query(Some("inline=1"));
    }
    Some(url.into())
}

/// A file id of the chat: 32 hex digits.
pub fn is_file_id(id: &str) -> bool {
    id.len() == 32 && id.bytes().all(|b| b.is_ascii_hexdigit())
}

/// The body of a multipart upload with one part, field "file".
pub fn multipart_body(boundary: &str, name: &str, bytes: &[u8]) -> Vec<u8> {
    let name: String = name
        .chars()
        .map(|c| match c {
            '"' | '\\' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect();
    let name = if name.trim().is_empty() {
        "file".to_owned()
    } else {
        name
    };
    let mut body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{name}\"\r\nContent-Type: application/octet-stream\r\n\r\n"
    )
    .into_bytes();
    body.extend_from_slice(bytes);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

// ------------------------------------------------- the process with the token

/// Answers one chat request of the window's process. [`NdChat::Open`] keeps
/// the IPC connection until the chat socket or the window goes away.
pub async fn serve(request: NdChat, stream: &mut Connection) {
    match request {
        NdChat::Open => relay(stream).await,
        NdChat::Upload { name, size } => {
            let answer = upload(stream, &name, size).await;
            stream.send(&Data::NdChat(answer)).await.ok();
        }
        NdChat::Download { id, inline } => download(stream, &id, inline).await,
        _ => {}
    }
}

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// The TLS settings the HTTP client settled on for the server: rustls, with
/// invalid certificates only where that client already accepts them.
fn connector(api: &str) -> Option<tokio_tungstenite::Connector> {
    if hbb_common::tls::is_plain(api) {
        return Some(tokio_tungstenite::Connector::Plain);
    }
    let accept_invalid = hbb_common::tls::get_cached_tls_accept_invalid_cert(api) == Some(true);
    hbb_common::verifier::client_config(accept_invalid)
        .ok()
        .map(|config| tokio_tungstenite::Connector::Rustls(std::sync::Arc::new(config)))
}

/// Why the chat socket isn't open: [`NdChat::Closed`] or [`NdChat::ChatOff`].
fn refusal(response: &tokio_tungstenite::tungstenite::handshake::client::Response) -> NdChat {
    let status = response.status().as_u16();
    let header = |name: &str| {
        response
            .headers()
            .get(name)
            .and_then(|v| v.to_str().ok())
            .map(str::trim)
            .unwrap_or_default()
    };
    if status == 503 && header("X-NeoDesk-Chat") == "chat_off" {
        let seconds = header("Retry-After")
            .parse::<u32>()
            .ok()
            .filter(|s| *s > 0)
            .unwrap_or(CHAT_OFF_RETRY);
        return NdChat::ChatOff(seconds);
    }
    NdChat::Closed(status)
}

/// Opens the chat socket with the token as a bearer header, or answers why
/// not: the refused upgrade's status (0 for no answer) or chat turned off.
async fn open_socket(access: &Access) -> Result<Socket, NdChat> {
    use tokio_tungstenite::tungstenite::{
        client::IntoClientRequest, http::HeaderValue, Error,
    };
    let url = socket_url(&access.api, &access.device_id).ok_or(NdChat::Closed(0))?;
    let mut request = url
        .as_str()
        .into_client_request()
        .map_err(|_| NdChat::Closed(0))?;
    let bearer = HeaderValue::from_str(&format!("Bearer {}", access.token))
        .map_err(|_| NdChat::Closed(0))?;
    request.headers_mut().insert("Authorization", bearer);
    let connecting = tokio_tungstenite::connect_async_tls_with_config(
        request,
        None,
        false,
        connector(&access.api),
    );
    match tokio::time::timeout(CONNECT_TIMEOUT, connecting).await {
        Ok(Ok((socket, _))) => Ok(socket),
        Ok(Err(Error::Http(response))) => {
            log::info!("chat socket refused: HTTP {}", response.status().as_u16());
            Err(refusal(&response))
        }
        Ok(Err(err)) => {
            log::debug!("chat socket failed: {err}");
            Err(NdChat::Closed(0))
        }
        Err(_) => Err(NdChat::Closed(0)),
    }
}

/// Passes text frames between the chat socket and the window's IPC
/// connection, and ends with [`NdChat::Closed`] when the socket goes.
async fn relay(stream: &mut Connection) {
    use tokio_tungstenite::tungstenite::Message;
    let Some(access) = access() else {
        stream.send(&Data::NdChat(NdChat::Closed(NO_TOKEN))).await.ok();
        return;
    };
    let mut socket = match open_socket(&access).await {
        Ok(socket) => socket,
        Err(why) => {
            stream.send(&Data::NdChat(why)).await.ok();
            return;
        }
    };
    loop {
        tokio::select! {
            frame = socket.next() => match frame {
                Some(Ok(Message::Text(text))) => {
                    let frame = Data::NdChat(NdChat::Frame(text.as_str().to_owned()));
                    if stream.send(&frame).await.is_err() {
                        break;
                    }
                }
                Some(Ok(Message::Close(Some(frame))))
                    if u16::from(frame.code) == 1008 && frame.reason.as_str() == "chat_off" =>
                {
                    stream.send(&Data::NdChat(NdChat::ChatOff(CHAT_OFF_RETRY))).await.ok();
                    break;
                }
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {
                    stream.send(&Data::NdChat(NdChat::Closed(0))).await.ok();
                    break;
                }
                Some(Ok(_)) => {}
            },
            data = stream.next() => match data {
                Ok(Some(Data::NdChat(NdChat::Frame(text)))) => {
                    if socket.send(Message::text(text)).await.is_err() {
                        stream.send(&Data::NdChat(NdChat::Closed(0))).await.ok();
                        break;
                    }
                }
                Ok(_) => {}
                Err(_) => break,
            },
        }
    }
    socket.close(None).await.ok();
}

async fn upload(stream: &mut Connection, name: &str, size: u64) -> NdChat {
    let failed = |status: u16| NdChat::Uploaded {
        status,
        body: String::new(),
    };
    let bytes = match tokio::time::timeout(FILE_TIMEOUT, stream.next_raw()).await {
        Ok(Ok(bytes)) => bytes,
        _ => return failed(0),
    };
    if bytes.len() as u64 != size {
        return failed(0);
    }
    if size > MAX_FILE_BYTES {
        return failed(TOO_LARGE);
    }
    let Some(access) = access() else {
        return failed(NO_TOKEN);
    };
    let Some(url) = files_url(&access.api, None, false) else {
        return failed(0);
    };
    let boundary = hex::encode(hbb_common::sodiumoxide::randombytes::randombytes(16));
    let body = multipart_body(&boundary, name, &bytes);
    let client = crate::hbbs_http::create_http_client_async_with_url(&url).await;
    let request = client
        .post(&url)
        .bearer_auth(&access.token)
        .header(
            "Content-Type",
            format!("multipart/form-data; boundary={boundary}"),
        )
        .body(body)
        .timeout(FILE_TIMEOUT);
    match request.send().await {
        Ok(response) => {
            let status = response.status().as_u16();
            NdChat::Uploaded {
                status,
                body: response.text().await.unwrap_or_default(),
            }
        }
        Err(err) => {
            log::debug!("chat upload failed: {err}");
            failed(0)
        }
    }
}

async fn download(stream: &mut Connection, id: &str, inline: bool) {
    let (status, bytes) = fetch(id, inline).await;
    let answer = NdChat::Downloaded {
        status,
        size: bytes.as_ref().map_or(0, |b| b.len() as u64),
    };
    if stream.send(&Data::NdChat(answer)).await.is_err() {
        return;
    }
    if let Some(bytes) = bytes {
        stream.send_raw(bytes).await.ok();
    }
}

async fn fetch(id: &str, inline: bool) -> (u16, Option<Bytes>) {
    if !is_file_id(id) {
        return (404, None);
    }
    let Some(access) = access() else {
        return (NO_TOKEN, None);
    };
    let Some(url) = files_url(&access.api, Some(id), inline) else {
        return (0, None);
    };
    let client = crate::hbbs_http::create_http_client_async_with_url(&url).await;
    let response = match client
        .get(&url)
        .bearer_auth(&access.token)
        .timeout(FILE_TIMEOUT)
        .send()
        .await
    {
        Ok(response) => response,
        Err(err) => {
            log::debug!("chat download failed: {err}");
            return (0, None);
        }
    };
    let status = response.status().as_u16();
    if status != 200 {
        return (status, None);
    }
    if response.content_length().unwrap_or(0) > MAX_FILE_BYTES {
        return (TOO_LARGE, None);
    }
    match response.bytes().await {
        Ok(bytes) if bytes.len() as u64 <= MAX_FILE_BYTES => (200, Some(bytes)),
        Ok(_) => (TOO_LARGE, None),
        Err(_) => (0, None),
    }
}

// --------------------------------------------------------- the window's side

/// The chat window's side: Flutter calls these through `main_get_common`
/// and `main_set_common` with keys starting "nd-chat-".
#[cfg(feature = "flutter")]
pub mod window {
    use super::*;
    use hbb_common::tokio::sync::mpsc;
    use std::sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    };

    lazy_static::lazy_static! {
        /// The open socket's number and the way to its relay; None sends
        /// nothing more and closes it.
        static ref SOCKET: Mutex<Option<(u64, mpsc::UnboundedSender<Option<String>>)>> =
            Mutex::new(None);
    }
    static NEXT: AtomicU64 = AtomicU64::new(0);

    /// Answers `main_get_common` for a key starting "nd-chat-".
    pub fn get(key: &str) -> String {
        if key == "nd-chat-open" {
            open("").to_string()
        } else if let Some(path) = key.strip_prefix("nd-chat-upload:") {
            upload_file("", path)
        } else if let Some(request) = key.strip_prefix("nd-chat-download:") {
            download_file("", request)
        } else {
            String::new()
        }
    }

    /// Runs `main_set_common` for a key starting "nd-chat-".
    pub fn set(key: &str, value: &str) {
        match key {
            "nd-chat-send" => send(value),
            "nd-chat-close" => close(),
            "nd-chat-notify" => notify(value),
            _ => {}
        }
    }

    fn push(event: serde_json::Value) {
        crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, event.to_string());
    }

    /// Opens a chat socket through the IPC server of `postfix` and answers
    /// its number. Its frames come as events {"name": "nd-chat", "socket":
    /// n, "frame": text} and its end as {"name": "nd-chat", "socket": n,
    /// "closed": status, "retry_after": seconds}. A socket opened before is
    /// closed.
    pub(super) fn open(postfix: &'static str) -> u64 {
        let n = NEXT.fetch_add(1, Ordering::SeqCst) + 1;
        let (sender, receiver) = mpsc::unbounded_channel();
        if let Some((_, old)) = SOCKET.lock().unwrap().replace((n, sender)) {
            old.send(None).ok();
        }
        std::thread::spawn(move || {
            let (status, retry_after) = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime.block_on(run(postfix, n, receiver, |frame| {
                    push(serde_json::json!({"name": "nd-chat", "socket": n, "frame": frame}))
                })),
                Err(err) => {
                    log::error!("chat: no runtime: {err}");
                    (0, 0)
                }
            };
            {
                let mut socket = SOCKET.lock().unwrap();
                if socket.as_ref().is_some_and(|(open, _)| *open == n) {
                    *socket = None;
                }
            }
            push(serde_json::json!({
                "name": "nd-chat",
                "socket": n,
                "closed": status,
                "retry_after": retry_after,
            }));
        });
        n
    }

    /// Relays one socket: frames from the IPC server go to `frame`, frames
    /// from `receiver` go to the IPC server. Answers the closing status and,
    /// with [`CHAT_OFF`], the seconds to wait before asking again.
    pub(super) async fn run(
        postfix: &str,
        n: u64,
        mut receiver: mpsc::UnboundedReceiver<Option<String>>,
        frame: impl Fn(String),
    ) -> (u16, u32) {
        let mut c = match crate::ipc::connect(1000, postfix).await {
            Ok(c) => c,
            Err(err) => {
                log::debug!("chat {n}: no IPC server: {err}");
                return (0, 0);
            }
        };
        if c.send(&Data::NdChat(NdChat::Open)).await.is_err() {
            return (0, 0);
        }
        loop {
            tokio::select! {
                data = c.next() => match data {
                    Ok(Some(Data::NdChat(NdChat::Frame(text)))) => frame(text),
                    Ok(Some(Data::NdChat(NdChat::Closed(status)))) => return (status, 0),
                    Ok(Some(Data::NdChat(NdChat::ChatOff(seconds)))) => return (CHAT_OFF, seconds),
                    Ok(_) => {}
                    Err(_) => return (0, 0),
                },
                out = receiver.recv() => match out {
                    Some(Some(text)) => {
                        if c.send(&Data::NdChat(NdChat::Frame(text))).await.is_err() {
                            return (0, 0);
                        }
                    }
                    _ => return (0, 0),
                },
            }
        }
    }

    fn send(frame: &str) {
        if let Some((_, sender)) = SOCKET.lock().unwrap().as_ref() {
            sender.send(Some(frame.to_owned())).ok();
        }
    }

    fn close() {
        if let Some((_, sender)) = SOCKET.lock().unwrap().take() {
            sender.send(None).ok();
        }
    }

    /// Uploads the file at `path` and answers {"status": ..., "file_id":
    /// ...}.
    pub(super) fn upload_file(postfix: &str, path: &str) -> String {
        let answer = |status: u16, file_id: Option<String>| {
            serde_json::json!({"status": status, "file_id": file_id}).to_string()
        };
        let path = std::path::Path::new(path);
        let size = std::fs::metadata(path).map(|m| m.len()).unwrap_or(0);
        if size > MAX_FILE_BYTES {
            return answer(TOO_LARGE, None);
        }
        let Ok(bytes) = std::fs::read(path) else {
            return answer(0, None);
        };
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let (status, body) = match block_on(ask_upload(postfix, name, bytes)).flatten() {
            Some(NdChat::Uploaded { status, body }) => (status, body),
            _ => (0, String::new()),
        };
        let file_id = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .filter(|v| v["success"] == true)
            .and_then(|v| v["file_id"].as_str().map(str::to_owned))
            .filter(|id| is_file_id(id));
        if status == 200 && file_id.is_none() {
            return answer(0, None);
        }
        answer(status, file_id)
    }

    async fn ask_upload(postfix: &str, name: String, bytes: Vec<u8>) -> Option<NdChat> {
        let mut c = crate::ipc::connect(1000, postfix).await.ok()?;
        let size = bytes.len() as u64;
        c.send(&Data::NdChat(NdChat::Upload { name, size })).await.ok()?;
        c.send_raw(Bytes::from(bytes)).await.ok()?;
        match tokio::time::timeout(FILE_TIMEOUT, c.next()).await {
            Ok(Ok(Some(Data::NdChat(answer)))) => Some(answer),
            _ => None,
        }
    }

    /// Fetches a file for the request {"id", "inline", "path"}, saves it at
    /// path and answers {"status": ...}.
    pub(super) fn download_file(postfix: &str, request: &str) -> String {
        let answer = |status: u16| serde_json::json!({ "status": status }).to_string();
        let Ok(request) = serde_json::from_str::<serde_json::Value>(request) else {
            return answer(0);
        };
        let id = request["id"].as_str().unwrap_or_default().to_owned();
        let inline = request["inline"].as_bool().unwrap_or(false);
        let Some(path) = request["path"].as_str().filter(|p| !p.is_empty()) else {
            return answer(0);
        };
        if !is_file_id(&id) {
            return answer(404);
        }
        let (status, bytes) = block_on(ask_download(postfix, id, inline))
            .flatten()
            .unwrap_or((0, None));
        if let Some(bytes) = bytes {
            let path = std::path::Path::new(path);
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir).ok();
            }
            if let Err(err) = std::fs::write(path, &bytes) {
                log::warn!("chat: could not save a file: {err}");
                return answer(0);
            }
        }
        answer(status)
    }

    async fn ask_download(
        postfix: &str,
        id: String,
        inline: bool,
    ) -> Option<(u16, Option<Bytes>)> {
        let mut c = crate::ipc::connect(1000, postfix).await.ok()?;
        c.send(&Data::NdChat(NdChat::Download { id, inline })).await.ok()?;
        let answer = tokio::time::timeout(FILE_TIMEOUT, c.next()).await.ok()?.ok()??;
        let Data::NdChat(NdChat::Downloaded { status, size }) = answer else {
            return None;
        };
        if status != 200 {
            return Some((status, None));
        }
        let bytes = tokio::time::timeout(FILE_TIMEOUT, c.next_raw()).await.ok()?.ok()?;
        if bytes.len() as u64 != size {
            return None;
        }
        Some((200, Some(bytes.freeze())))
    }

    fn block_on<F: std::future::Future>(future: F) -> Option<F::Output> {
        match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => Some(runtime.block_on(future)),
            Err(err) => {
                log::error!("chat: no runtime: {err}");
                None
            }
        }
    }

    /// Shows an OS notification for {"title", "body"}. Clicking it on
    /// Windows sends {"name": "nd-chat", "activated": true}.
    fn notify(request: &str) {
        let Ok(request) = serde_json::from_str::<serde_json::Value>(request) else {
            return;
        };
        let title = request["title"].as_str().unwrap_or_default().to_owned();
        let body = request["body"].as_str().unwrap_or_default().to_owned();
        std::thread::spawn(move || show_notification(&title, &body));
    }

    #[cfg(windows)]
    fn show_notification(title: &str, body: &str) {
        use tauri_winrt_notification::{Duration as ToastDuration, Sound, Toast};
        let app_id = format!("{}.Chat", crate::get_app_name().replace(' ', ""));
        if let Err(err) = crate::tray_menu::register_toast_sender(&app_id) {
            log::debug!("Failed to register {app_id} for notifications: {err}");
        }
        Toast::new(&app_id)
            .title(title)
            .text1(body)
            .sound(Some(Sound::Default))
            .duration(ToastDuration::Short)
            .on_activated(|| {
                push(serde_json::json!({"name": "nd-chat", "activated": true}));
                Ok(())
            })
            .show()
            .ok();
    }

    #[cfg(target_os = "linux")]
    fn show_notification(title: &str, body: &str) {
        use dbus::{arg::PropMap, blocking::Connection};
        let shown = (|| -> Result<(), dbus::Error> {
            let c = Connection::new_session()?;
            let proxy = c.with_proxy(
                "org.freedesktop.Notifications",
                "/org/freedesktop/Notifications",
                Duration::from_secs(3),
            );
            let _: (u32,) = proxy.method_call(
                "org.freedesktop.Notifications",
                "Notify",
                (
                    crate::get_app_name(),
                    0u32,
                    "",
                    title,
                    body,
                    Vec::<String>::new(),
                    PropMap::new(),
                    -1i32,
                ),
            )?;
            Ok(())
        })();
        if let Err(err) = shown {
            log::debug!("chat notification failed: {err}");
        }
    }

    #[cfg(not(any(windows, target_os = "linux")))]
    fn show_notification(_title: &str, _body: &str) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_socket_address_follows_the_api_server() {
        assert_eq!(
            socket_url("https://nd.example.com", "900100001").as_deref(),
            Some("wss://nd.example.com/ws/chat/900100001?v=2")
        );
        assert_eq!(
            socket_url("http://10.0.0.5:21114/", "900100001").as_deref(),
            Some("ws://10.0.0.5:21114/ws/chat/900100001?v=2")
        );
        assert_eq!(
            socket_url("https://nd.example.com/desk", "a b/c").as_deref(),
            Some("wss://nd.example.com/desk/ws/chat/a%20b%2Fc?v=2")
        );
        assert_eq!(socket_url("ftp://nd.example.com", "1"), None);
        assert_eq!(socket_url("", "1"), None);
    }

    #[test]
    fn the_file_addresses_follow_the_api_server() {
        let id = "4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5a";
        assert_eq!(
            files_url("https://nd.example.com", None, false).as_deref(),
            Some("https://nd.example.com/api/chat/device/files")
        );
        assert_eq!(
            files_url("http://10.0.0.5:21114/", Some(id), true).as_deref(),
            Some("http://10.0.0.5:21114/api/chat/device/files/4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5a?inline=1")
        );
        assert_eq!(files_url("ws://nd.example.com", Some(id), false), None);
    }

    #[test]
    fn only_ids_of_32_hex_digits_are_fetched() {
        assert!(is_file_id("4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5a"));
        assert!(!is_file_id("../../api/devices"));
        assert!(!is_file_id("4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5"));
        assert!(!is_file_id("4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5g"));
        assert!(!is_file_id(""));
    }

    #[test]
    fn the_upload_has_one_part_named_file_with_a_safe_file_name() {
        let body = multipart_body("b0undary", "error \"1\".png", b"\x89PNG");
        let mut expected = b"--b0undary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"error _1_.png\"\r\nContent-Type: application/octet-stream\r\n\r\n".to_vec();
        expected.extend_from_slice(b"\x89PNG\r\n--b0undary--\r\n");
        assert_eq!(body, expected);
        let broken = String::from_utf8_lossy(&multipart_body("b", "a\r\nX-Evil: 1", b""))
            .into_owned();
        assert!(broken.contains("filename=\"a__X-Evil: 1\""));
        assert!(String::from_utf8_lossy(&multipart_body("b", " ", b"")).contains("filename=\"file\""));
    }

    #[test]
    fn the_ipc_messages_keep_their_shape() {
        for message in [
            NdChat::Open,
            NdChat::Frame("{\"type\":\"read\"}".to_owned()),
            NdChat::Closed(403),
            NdChat::Upload {
                name: "a.png".to_owned(),
                size: 3,
            },
            NdChat::Uploaded {
                status: 200,
                body: "{}".to_owned(),
            },
            NdChat::Download {
                id: "4f0c2b8e9d1a4c6b8e2f7a9c0d1e3f5a".to_owned(),
                inline: true,
            },
            NdChat::Downloaded { status: 200, size: 3 },
            NdChat::ChatOff(600),
        ] {
            let data = Data::NdChat(message.clone());
            let text = serde_json::to_string(&data).unwrap();
            match serde_json::from_str::<Data>(&text).unwrap() {
                Data::NdChat(back) => assert_eq!(back, message),
                other => panic!("came back as {other:?}"),
            }
        }
    }

    /// The relay against a local chat server: the token goes as a bearer
    /// header and never in the address, frames pass both ways, a refused
    /// upgrade comes back with its status, chat turned off comes back as
    /// [`CHAT_OFF`] with the time to wait, and without a token nothing is
    /// opened.
    #[cfg(all(feature = "flutter", any(target_os = "linux", target_os = "macos")))]
    #[test]
    fn the_window_reaches_the_chat_socket_through_the_process_with_the_token() {
        use crate::ipc::device_key_tests::{
            start_test_listener, ConfigFilesGuard, DEVICE_KEY_TEST_LOCK,
        };
        use hbb_common::config::LocalConfig;
        use std::sync::{Arc, Mutex};
        use tokio_tungstenite::tungstenite::{
            handshake::server::{ErrorResponse, Request, Response},
            Message,
        };

        let _lock = DEVICE_KEY_TEST_LOCK
            .lock()
            .unwrap_or_else(|err| err.into_inner());
        let _files = ConfigFilesGuard::new();
        let kept: Vec<(String, String)> = [
            "neodesk-device-token",
            "neodesk-device-token-id",
            "neodesk-device-token-api",
        ]
        .iter()
        .map(|k| (k.to_string(), LocalConfig::get_option(k)))
        .collect();

        let seen: Arc<Mutex<Vec<(String, String)>>> = Arc::default();
        let got: Arc<Mutex<Vec<String>>> = Arc::default();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        {
            let seen = seen.clone();
            let got = got.clone();
            std::thread::spawn(move || {
                let runtime = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .unwrap();
                runtime.block_on(async move {
                    listener.set_nonblocking(true).unwrap();
                    let listener = tokio::net::TcpListener::from_std(listener).unwrap();
                    loop {
                        let (tcp, _) = listener.accept().await.unwrap();
                        let seen = seen.clone();
                        let got = got.clone();
                        tokio::spawn(async move {
                            let refuse = Arc::new(Mutex::new(false));
                            let refused = refuse.clone();
                            let callback = move |request: &Request, response: Response| {
                                let auth = request
                                    .headers()
                                    .get("Authorization")
                                    .and_then(|v| v.to_str().ok())
                                    .unwrap_or_default()
                                    .to_owned();
                                seen.lock().unwrap().push((request.uri().to_string(), auth.clone()));
                                if auth == "Bearer chat-off-token" {
                                    let mut off = ErrorResponse::new(Some(
                                        "{\"success\":false,\"code\":\"chat_off\"}".to_owned(),
                                    ));
                                    *off.status_mut() =
                                        tokio_tungstenite::tungstenite::http::StatusCode::SERVICE_UNAVAILABLE;
                                    off.headers_mut().insert("Retry-After", "450".parse().unwrap());
                                    off.headers_mut()
                                        .insert("X-NeoDesk-Chat", "chat_off".parse().unwrap());
                                    return Err(off);
                                }
                                if auth == "Bearer busy-token" {
                                    let mut busy = ErrorResponse::new(None);
                                    *busy.status_mut() =
                                        tokio_tungstenite::tungstenite::http::StatusCode::SERVICE_UNAVAILABLE;
                                    return Err(busy);
                                }
                                if auth == "Bearer closing-token" {
                                    *refused.lock().unwrap() = true;
                                    return Ok(response);
                                }
                                if auth != "Bearer chat-test-token" {
                                    *refused.lock().unwrap() = true;
                                    let mut no = ErrorResponse::new(None);
                                    *no.status_mut() =
                                        tokio_tungstenite::tungstenite::http::StatusCode::FORBIDDEN;
                                    return Err(no);
                                }
                                Ok(response)
                            };
                            let Ok(mut socket) =
                                tokio_tungstenite::accept_hdr_async(tcp, callback).await
                            else {
                                return;
                            };
                            if *refuse.lock().unwrap() {
                                use tokio_tungstenite::tungstenite::protocol::{
                                    frame::coding::CloseCode, CloseFrame,
                                };
                                socket
                                    .close(Some(CloseFrame {
                                        code: CloseCode::Policy,
                                        reason: "chat_off".into(),
                                    }))
                                    .await
                                    .ok();
                                while socket.next().await.is_some() {}
                                return;
                            }
                            socket
                                .send(Message::text("{\"type\":\"welcome\",\"v\":2}"))
                                .await
                                .unwrap();
                            while let Some(Ok(message)) = socket.next().await {
                                if let Message::Text(text) = message {
                                    got.lock().unwrap().push(text.as_str().to_owned());
                                    if text.as_str() == "{\"type\":\"bye\"}" {
                                        socket.close(None).await.ok();
                                        break;
                                    }
                                }
                            }
                        });
                    }
                });
            });
        }

        let api = format!("http://127.0.0.1:{port}");
        Config::set_option("api-server".to_owned(), api.clone());
        let device_id = Config::get_id();
        enrollment::store_token("chat-test-token", &device_id, &api);
        start_test_listener("_ndchat_test");

        let frames: Arc<Mutex<Vec<String>>> = Arc::default();
        let (sender, receiver) = tokio::sync::mpsc::unbounded_channel();
        sender.send(Some("{\"type\":\"read\"}".to_owned())).unwrap();
        let relay = {
            let frames = frames.clone();
            std::thread::spawn(move || {
                tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .unwrap()
                    .block_on(window::run("_ndchat_test", 1, receiver, move |f| {
                        frames.lock().unwrap().push(f)
                    }))
            })
        };
        for _ in 0..50 {
            if got.lock().unwrap().len() == 1 {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        sender.send(Some("{\"type\":\"bye\"}".to_owned())).ok();
        let status = relay.join().unwrap();
        assert_eq!(status, (0, 0), "the socket closed by the server ends with 0");
        assert_eq!(frames.lock().unwrap().as_slice(), ["{\"type\":\"welcome\",\"v\":2}"]);
        assert_eq!(
            got.lock().unwrap().as_slice(),
            ["{\"type\":\"read\"}", "{\"type\":\"bye\"}"]
        );
        {
            let seen = seen.lock().unwrap();
            assert_eq!(seen[0].0, format!("/ws/chat/{device_id}?v=2"));
            assert_eq!(seen[0].1, "Bearer chat-test-token");
        }

        enrollment::store_token("revoked-token", &device_id, &api);
        let (_sender, receiver) = tokio::sync::mpsc::unbounded_channel();
        let status = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(window::run("_ndchat_test", 2, receiver, |_| {}));
        assert_eq!(status, (403, 0));

        let run = |token: &str, n: u64| {
            enrollment::store_token(token, &device_id, &api);
            let (_sender, receiver) = tokio::sync::mpsc::unbounded_channel();
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap()
                .block_on(window::run("_ndchat_test", n, receiver, |_| {}))
        };
        assert_eq!(run("chat-off-token", 4), (CHAT_OFF, 450), "503 chat_off with Retry-After");
        assert_eq!(run("busy-token", 5), (503, 0), "a 503 without chat_off is no chat_off");
        assert_eq!(run("closing-token", 6), (CHAT_OFF, 600), "an open socket closed with 1008 chat_off");

        enrollment::clear_token();
        let (_sender, receiver) = tokio::sync::mpsc::unbounded_channel();
        let before = seen.lock().unwrap().len();
        let status = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(window::run("_ndchat_test", 3, receiver, |_| {}));
        assert_eq!(status, (NO_TOKEN, 0));
        assert_eq!(seen.lock().unwrap().len(), before, "no socket without a token");

        for (key, value) in kept {
            LocalConfig::set_option(key, value);
        }
    }
}
