//! The receiver's tickets: the person opens, reads and answers the tickets
//! of this computer from the home window (My tickets), through the device
//! routes of the console under /api/tickets/nd
//! (neodesk-server/console/routes/tickets/device.go). They are reached on the
//! API port, where the chat is.
//!
//! As with the chat (nd_chat.rs) the device token stays in the process that
//! keeps it. The window's process sends each request over IPC
//! (`NdChat::Api`); that process adds the token, asks the server and hands
//! the answer back. It also keeps the number of tickets with something
//! unread for the tray: from the list it fetches when the chat socket says
//! a ticket changed (`ticket.updated`) or opens, after the person wrote or
//! read something, and from `tickets_unread` of the sealed heartbeat
//! (hbbs_http/sync.rs) while the socket is down.

use crate::ipc::{Connection, Data};
use crate::nd_chat::NdChat;
use hbb_common::{bytes::Bytes, log, tokio};
use std::{
    sync::atomic::{AtomicBool, AtomicI64, Ordering},
    time::Duration,
};

/// The routes of the computer's tickets.
pub const BASE: &str = "/api/tickets/nd";

/// The largest request: 25 MB of files as base64, and the text.
pub const MAX_BODY: u64 = 36 << 20;
/// The largest answer: a file of the ticket.
const MAX_ANSWER: u64 = 50 << 20;
const TIMEOUT: Duration = Duration::from_secs(300);

/// Whether the window may send `method` to `path`: the list and a new
/// ticket, one ticket, a reply to it, marking it read, and one of its files.
/// Anything else, a query or an odd segment included, is refused before it
/// reaches the server.
pub fn allowed(method: &str, path: &str) -> bool {
    let Some(rest) = path.strip_prefix(BASE) else {
        return false;
    };
    let parts: Vec<&str> = if rest.is_empty() {
        Vec::new()
    } else {
        match rest.strip_prefix('/') {
            Some(rest) => rest.split('/').collect(),
            None => return false,
        }
    };
    let number = |s: &str| !s.is_empty() && s.len() <= 18 && s.bytes().all(|b| b.is_ascii_digit());
    match (method, parts.as_slice()) {
        ("GET" | "POST", []) => true,
        ("GET", [ticket]) => number(ticket),
        ("POST", [ticket, "comments" | "read"]) => number(ticket),
        ("GET", [ticket, "attachments", file]) => number(ticket) && number(file),
        _ => false,
    }
}

// ------------------------------------------------- the process with the token

/// Answers one `NdChat::Api` request of the window's process: reads its
/// body, asks the server with the device token and sends the status and
/// the answer back.
pub async fn serve(stream: &mut Connection, method: &str, path: &str, size: u64) {
    let body = if size > 0 {
        match tokio::time::timeout(TIMEOUT, stream.next_raw()).await {
            Ok(Ok(bytes)) if bytes.len() as u64 == size => bytes.to_vec(),
            _ => return answer(stream, 0, None).await,
        }
    } else {
        Vec::new()
    };
    if size > MAX_BODY {
        return answer(stream, 413, None).await;
    }
    if !allowed(method, path) {
        return answer(stream, 404, None).await;
    }
    let (status, bytes) = request(method, path, body).await;
    if method == "POST" && (200..300).contains(&status) {
        refresh_unread();
    }
    answer(stream, status, bytes).await;
}

async fn answer(stream: &mut Connection, status: u16, bytes: Option<Bytes>) {
    let size = bytes.as_ref().map_or(0, |b| b.len() as u64);
    if stream
        .send(&Data::NdChat(NdChat::ApiAnswer { status, size }))
        .await
        .is_err()
    {
        return;
    }
    if let Some(bytes) = bytes.filter(|b| !b.is_empty()) {
        stream.send_raw(bytes).await.ok();
    }
}

/// Sends the request with the device token: the status (0 when nobody
/// answered, nd_chat's NO_TOKEN without a token) and the answer.
async fn request(method: &str, path: &str, body: Vec<u8>) -> (u16, Option<Bytes>) {
    let Some(access) = crate::nd_chat::access() else {
        return (crate::nd_chat::NO_TOKEN, None);
    };
    let url = format!("{}{path}", access.api);
    let client = crate::hbbs_http::create_http_client_async_with_url(&url).await;
    let builder = if method == "POST" {
        let body = if body.is_empty() { b"{}".to_vec() } else { body };
        client
            .post(&url)
            .header("Content-Type", "application/json")
            .body(body)
    } else {
        client.get(&url)
    };
    let response = match builder
        .bearer_auth(&access.token)
        .timeout(TIMEOUT)
        .send()
        .await
    {
        Ok(response) => response,
        Err(err) => {
            log::debug!("tickets: request failed: {err}");
            return (0, None);
        }
    };
    let status = response.status().as_u16();
    if response.content_length().unwrap_or(0) > MAX_ANSWER {
        return (413, None);
    }
    match response.bytes().await {
        Ok(bytes) if bytes.len() as u64 <= MAX_ANSWER => (status, Some(bytes)),
        Ok(_) => (413, None),
        Err(_) => (0, None),
    }
}

/// Tickets of this computer with something unread; -1 until known.
static UNREAD: AtomicI64 = AtomicI64::new(-1);
static REFRESHING: AtomicBool = AtomicBool::new(false);
static AGAIN: AtomicBool = AtomicBool::new(false);

/// The number of tickets with something unread, None until a list or a
/// heartbeat told it.
pub fn unread() -> Option<u32> {
    u32::try_from(UNREAD.load(Ordering::SeqCst)).ok()
}

/// `tickets_unread` of a sealed heartbeat answer.
pub fn set_unread(count: u64) {
    UNREAD.store(count.min(u32::MAX as u64) as i64, Ordering::SeqCst);
}

/// The tickets of a list answer with something unread.
pub fn count_unread(list: &str) -> Option<u32> {
    let v: serde_json::Value = serde_json::from_str(list).ok()?;
    let tickets = v["tickets"].as_array()?;
    Some(tickets.iter().filter(|t| t["unread"] == true).count() as u32)
}

/// Fetches the list once more for [`unread`], on a thread of its own; a
/// call while one runs makes it fetch again after.
pub fn refresh_unread() {
    AGAIN.store(true, Ordering::SeqCst);
    if REFRESHING.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(|| {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build();
        if let Ok(runtime) = runtime {
            while AGAIN.swap(false, Ordering::SeqCst) {
                let (status, bytes) = runtime.block_on(request("GET", BASE, Vec::new()));
                if status != 200 {
                    continue;
                }
                let text = bytes.map(|b| String::from_utf8_lossy(&b).into_owned());
                if let Some(count) = text.as_deref().and_then(count_unread) {
                    set_unread(count as u64);
                }
            }
        }
        REFRESHING.store(false, Ordering::SeqCst);
    });
}

// --------------------------------------------------------- the window's side

/// The receiver window's side: Flutter calls these through
/// `main_get_common` with keys starting "nd-tickets-"
/// (flutter/lib/receiver/tickets_model.dart).
#[cfg(feature = "flutter")]
pub mod window {
    use super::*;

    /// Answers `main_get_common` for a key starting "nd-tickets-":
    /// - "nd-tickets-request:{method, path, body?}": {"status", "body"},
    ///   the answer as text.
    /// - "nd-tickets-download:{path, to}": {"status"}; on 200 the file is
    ///   saved at `to`.
    /// - "nd-tickets-about": {"reporter", "os"}, the signed-in person's
    ///   name and the system, which go with a new ticket.
    pub fn get(key: &str) -> String {
        if let Some(request) = key.strip_prefix("nd-tickets-request:") {
            request_json(request)
        } else if let Some(request) = key.strip_prefix("nd-tickets-download:") {
            download_json(request)
        } else if key == "nd-tickets-about" {
            serde_json::json!({"reporter": reporter(), "os": os()}).to_string()
        } else {
            String::new()
        }
    }

    fn request_json(request: &str) -> String {
        let answer = |status: u16, body: String| {
            serde_json::json!({"status": status, "body": body}).to_string()
        };
        let Ok(request) = serde_json::from_str::<serde_json::Value>(request) else {
            return answer(0, String::new());
        };
        let method = request["method"].as_str().unwrap_or("GET").to_owned();
        let path = request["path"].as_str().unwrap_or_default().to_owned();
        if !allowed(&method, &path) {
            return answer(404, String::new());
        }
        let body = match &request["body"] {
            serde_json::Value::Null => Vec::new(),
            serde_json::Value::String(text) => text.as_bytes().to_vec(),
            other => other.to_string().into_bytes(),
        };
        match block_on(ask(&method, &path, body)).flatten() {
            Some((status, bytes)) => answer(
                status,
                bytes
                    .map(|b| String::from_utf8_lossy(&b).into_owned())
                    .unwrap_or_default(),
            ),
            None => answer(0, String::new()),
        }
    }

    fn download_json(request: &str) -> String {
        let answer = |status: u16| serde_json::json!({ "status": status }).to_string();
        let Ok(request) = serde_json::from_str::<serde_json::Value>(request) else {
            return answer(0);
        };
        let path = request["path"].as_str().unwrap_or_default().to_owned();
        let Some(to) = request["to"].as_str().filter(|p| !p.is_empty()) else {
            return answer(0);
        };
        if !allowed("GET", &path) || !path.contains("/attachments/") {
            return answer(404);
        }
        let Some((status, bytes)) = block_on(ask("GET", &path, Vec::new())).flatten() else {
            return answer(0);
        };
        if status == 200 {
            let to = std::path::Path::new(to);
            if let Some(dir) = to.parent() {
                std::fs::create_dir_all(dir).ok();
            }
            if let Err(err) = std::fs::write(to, bytes.unwrap_or_default()) {
                log::warn!("tickets: could not save a file: {err}");
                return answer(0);
            }
        }
        answer(status)
    }

    async fn ask(method: &str, path: &str, body: Vec<u8>) -> Option<(u16, Option<Bytes>)> {
        let mut c = crate::ipc::connect(1000, "").await.ok()?;
        let size = body.len() as u64;
        c.send(&Data::NdChat(NdChat::Api {
            method: method.to_owned(),
            path: path.to_owned(),
            size,
        }))
        .await
        .ok()?;
        if size > 0 {
            c.send_raw(Bytes::from(body)).await.ok()?;
        }
        let answer = tokio::time::timeout(TIMEOUT, c.next()).await.ok()?.ok()??;
        let Data::NdChat(NdChat::ApiAnswer { status, size }) = answer else {
            return None;
        };
        if size == 0 {
            return Some((status, None));
        }
        let bytes = tokio::time::timeout(TIMEOUT, c.next_raw()).await.ok()?.ok()?;
        if bytes.len() as u64 != size {
            return None;
        }
        Some((status, Some(bytes.freeze())))
    }

    fn block_on<F: std::future::Future>(future: F) -> Option<F::Output> {
        match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => Some(runtime.block_on(future)),
            Err(err) => {
                log::error!("tickets: no runtime: {err}");
                None
            }
        }
    }

    /// The signed-in person's full name, else their account name.
    fn reporter() -> String {
        let name = hbb_common::whoami::realname();
        let name = name.trim_end_matches('\0').trim();
        let name = if name.is_empty() {
            crate::common::username()
        } else {
            name.to_owned()
        };
        name.chars().take(200).collect()
    }

    /// The system as people name it, with its version: "Windows 11 Pro
    /// 24H2 (26100)".
    fn os() -> String {
        use hbb_common::sysinfo::System;
        let system = System::new();
        let long = system.long_os_version().unwrap_or_default();
        let version = system.os_version().unwrap_or_default();
        let os = match (long.trim().is_empty(), version.trim().is_empty()) {
            (false, false) => format!("{} ({})", long.trim(), version.trim()),
            (false, true) => long.trim().to_owned(),
            (true, _) => std::env::consts::OS.to_owned(),
        };
        os.chars().take(200).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_computers_ticket_routes_go_through() {
        for (method, path) in [
            ("GET", "/api/tickets/nd"),
            ("POST", "/api/tickets/nd"),
            ("GET", "/api/tickets/nd/24"),
            ("POST", "/api/tickets/nd/24/comments"),
            ("POST", "/api/tickets/nd/24/read"),
            ("GET", "/api/tickets/nd/24/attachments/16"),
        ] {
            assert!(allowed(method, path), "{method} {path}");
        }
        for (method, path) in [
            ("GET", "/api/tickets"),
            ("GET", "/api/tickets/nd/"),
            ("GET", "/api/tickets/ndx"),
            ("DELETE", "/api/tickets/nd/24"),
            ("POST", "/api/tickets/nd/24"),
            ("GET", "/api/tickets/nd/24/comments"),
            ("GET", "/api/tickets/nd/24/read"),
            ("GET", "/api/tickets/nd/../../devices"),
            ("GET", "/api/tickets/nd/24?all=1"),
            ("GET", "/api/tickets/nd/24/attachments/16/x"),
            ("GET", "/api/tickets/nd/24/attachments/"),
            ("GET", "/api/tickets/nd/%32%34"),
            ("GET", "/api/chat/device/files"),
            ("GET", "https://evil.example/api/tickets/nd"),
        ] {
            assert!(!allowed(method, path), "{method} {path}");
        }
    }

    #[test]
    fn the_unread_count_is_the_tickets_with_unread_set() {
        let list = serde_json::json!({"tickets": [
            {"id": 1, "unread": true},
            {"id": 2, "unread": false},
            {"id": 3, "unread": true},
            {"id": 4},
        ], "total": 4})
        .to_string();
        assert_eq!(count_unread(&list), Some(2));
        assert_eq!(count_unread(r#"{"tickets": []}"#), Some(0));
        assert_eq!(count_unread(r#"{"error": "Ticket not found"}"#), None);
        assert_eq!(count_unread("not json"), None);
    }
}
