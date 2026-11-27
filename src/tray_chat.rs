//! The chat with support, held by the tray from login on (L512). The tray
//! joins the chat socket the process with the device token keeps
//! (nd_chat.rs) for as long as it runs, so the console counts the computer
//! reachable without the main window, and it raises the notifications: for
//! a staff message the person hasn't read and wasn't told of yet, never
//! while the main window shows the chat in front. The window then leaves
//! the notifications to the tray.
//!
//! [`TrayChat`] is what the tray knows of the chat; [`watch`] runs it.

use std::collections::BTreeMap;
use std::time::Duration;

/// What the console's chat (PROTOCOL.md) needs a wait for before asking
/// again: no chat of version 2 on the server, or an older server.
const NO_CHAT_RECHECK: Duration = Duration::from_secs(600);
const NO_TOKEN_RECHECK: Duration = Duration::from_secs(120);
const CHAT_OFF_RECHECK: Duration = Duration::from_secs(600);
const TOO_MANY_WAIT: Duration = Duration::from_secs(30);
/// After 401 or 403: the service holds the refusal and asks the server
/// again only after a long wait, with a new token or after it starts again
/// (nd_chat.rs), so asking the service often costs the server nothing.
const REFUSED_RECHECK: Duration = Duration::from_secs(60);
/// After the socket dropped or couldn't connect, a refusal (401, 403, 404,
/// no token) likely comes from a server or a service that is starting:
/// this many short tries before the long wait.
const START_TRIES: u32 = 5;
const BACKOFF_MAX: Duration = Duration::from_secs(30);
/// The longest text of a notification.
const NOTE_CHARS: usize = 120;

/// The closing status for a socket whose first frame was not a welcome of
/// version 2 (an older server).
pub const NOT_CHAT: u16 = 3;

/// A notification to show: the staff member's name and the start of the
/// message, and the page a click opens. For a ticket of the receiver the
/// title and the body are translation keys ([`Note::keys`]).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub title: String,
    pub body: String,
    /// What a click opens: "chat", or "tickets/<id>" in the receiver.
    pub link: String,
    pub keys: bool,
}

impl Note {
    fn message(title: String, body: String) -> Self {
        Note {
            title,
            body,
            link: "chat".to_owned(),
            keys: false,
        }
    }

    /// The receiver's ticket `id` has news from staff.
    fn ticket(id: u64) -> Self {
        Note {
            title: "nd-rcv-note-ticket".to_owned(),
            body: "nd-rcv-note-ticket-body".to_owned(),
            link: format!("tickets/{id}"),
            keys: true,
        }
    }
}

/// A staff message the computer hasn't read.
#[derive(Clone, Debug)]
struct Unread {
    name: String,
    text: String,
    deleted: bool,
}

/// What the tray knows of the chat. Fed with the frames of the socket and
/// its end; answers what to notify, what the menu shows and when to try
/// again.
#[derive(Debug, Default)]
pub struct TrayChat {
    device_id: String,
    connected: bool,
    /// The server took the chat and hasn't refused it since.
    available: bool,
    /// Short tries left for a refusal after a drop ([`START_TRIES`]).
    start_tries: u32,
    attempt: u32,
    /// Staff messages after the computer's read mark, by id.
    unread: BTreeMap<u64, Unread>,
    read_mark: u64,
    /// The newest staff message the person was told of (or saw).
    notified: u64,
    /// The main window shows the chat in front.
    front: bool,
    /// The receiver: news about its tickets notifies too.
    pub receiver: bool,
}

fn id_of(v: &serde_json::Value) -> Option<u64> {
    match v {
        serde_json::Value::String(s) => s.parse().ok(),
        serde_json::Value::Number(n) => n.as_u64(),
        _ => None,
    }
}

fn shorten(text: &str) -> String {
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if text.chars().count() <= NOTE_CHARS {
        return text;
    }
    let mut short: String = text.chars().take(NOTE_CHARS - 1).collect();
    short.push('…');
    short
}

impl TrayChat {
    /// The menu's chat entry: None without chat, else the new messages.
    pub fn entry(&self) -> Option<u32> {
        if !self.available {
            return None;
        }
        Some(self.unread.values().filter(|m| !m.deleted).count() as u32)
    }

    /// Whether the main window shows the chat in front. Messages that came
    /// while it did count as told.
    pub fn set_front(&mut self, front: bool) {
        self.front = front;
        if front {
            if let Some(newest) = self.unread.keys().next_back() {
                self.notified = self.notified.max(*newest);
            }
        }
    }

    /// Takes a frame of the socket. Answers the notifications to show, or
    /// Err(()) when the socket's first frame shows a server without chat
    /// of version 2: the caller closes the socket and reports [`NOT_CHAT`].
    pub fn frame(&mut self, text: &str) -> Result<Vec<Note>, ()> {
        let v: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
        let kind = v["type"].as_str().unwrap_or_default();
        if !self.connected {
            if kind != "welcome" || v["v"].as_i64() != Some(2) {
                return Err(());
            }
            self.connected = true;
            self.available = true;
            self.attempt = 0;
            self.start_tries = 0;
            if let Some(id) = v["device_id"].as_str() {
                self.device_id = id.to_owned();
            }
            return Ok(vec![]);
        }
        match kind {
            "history" => {
                if let Some(reads) = v["reads"].as_array() {
                    for r in reads {
                        self.note_read(&r["reader"], &r["up_to"]);
                    }
                }
                if let Some(list) = v["messages"].as_array() {
                    for m in list {
                        self.put(m);
                    }
                }
                self.prune();
                Ok(self.tell())
            }
            "message.new" => {
                self.put(&v["message"]);
                self.prune();
                Ok(self.tell())
            }
            "message.updated" => {
                let m = &v["message"];
                if let Some(id) = id_of(&m["id"]) {
                    if self.unread.contains_key(&id) {
                        self.put(m);
                    }
                }
                Ok(vec![])
            }
            "read" => {
                self.note_read(&v["reader"], &v["up_to"]);
                self.prune();
                Ok(vec![])
            }
            // A ticket the person opened has an answer or a new status
            // (PROTOCOL.md, ticket.updated)
            "ticket.updated" if self.receiver && v["unread"] == true => {
                Ok(id_of(&v["ticket_id"]).map(Note::ticket).into_iter().collect())
            }
            _ => Ok(vec![]),
        }
    }

    fn note_read(&mut self, reader: &serde_json::Value, up_to: &serde_json::Value) {
        if reader["kind"].as_str() != Some("device") {
            return;
        }
        let id = reader["id"].as_str().unwrap_or_default();
        if !self.device_id.is_empty() && id != self.device_id {
            return;
        }
        if let Some(to) = id_of(up_to) {
            self.read_mark = self.read_mark.max(to);
        }
    }

    fn put(&mut self, m: &serde_json::Value) {
        if m["from"]["kind"].as_str() != Some("user") {
            return;
        }
        let Some(id) = id_of(&m["id"]) else {
            return;
        };
        if id <= self.read_mark {
            return;
        }
        let mut text = m["text"].as_str().unwrap_or_default().trim().to_owned();
        if text.is_empty() {
            if let Some(files) = m["attachments"].as_array() {
                text = files
                    .iter()
                    .filter_map(|f| f["name"].as_str())
                    .collect::<Vec<_>>()
                    .join(", ");
            }
        }
        self.unread.insert(
            id,
            Unread {
                name: m["from"]["name"].as_str().unwrap_or_default().to_owned(),
                text,
                deleted: m["deleted"].as_bool() == Some(true),
            },
        );
    }

    fn prune(&mut self) {
        let mark = self.read_mark;
        self.unread.retain(|id, _| *id > mark);
    }

    /// One notification for the newest unread staff message the person
    /// wasn't told of, none while the window shows the chat. A page of
    /// history (after a reconnect or at login) gives at most one as well.
    fn tell(&mut self) -> Vec<Note> {
        let floor = self.notified.max(self.read_mark);
        let newest = self
            .unread
            .iter()
            .filter(|(id, m)| **id > floor && !m.deleted)
            .next_back()
            .map(|(id, m)| (*id, m.clone()));
        let Some((id, m)) = newest else {
            return vec![];
        };
        self.notified = id;
        if self.front {
            return vec![];
        }
        vec![Note::message(m.name, shorten(&m.text))]
    }

    /// The socket ended with `status` (the HTTP status of a refused
    /// upgrade, 0 when it dropped, nd_chat's NO_TOKEN or CHAT_OFF, or
    /// [`NOT_CHAT`]) and, with chat off, the server's wait in seconds.
    /// `spread` is a number from 0 to 1 for the backoff. Answers when to
    /// try again.
    pub fn closed(&mut self, status: u16, retry_after: u32, spread: f64) -> Option<Duration> {
        self.connected = false;
        if status == 0 || status == 503 {
            self.start_tries = START_TRIES;
        }
        let refusal = matches!(status, 401 | 403 | 404 | crate::nd_chat::NO_TOKEN);
        if refusal && self.start_tries > 0 {
            // Something answers again: its start, not the old outage, sets
            // the pace.
            if self.start_tries == START_TRIES {
                self.attempt = 0;
            }
            self.start_tries -= 1;
            return Some(self.backoff(spread));
        }
        match status {
            401 | 403 => {
                self.available = false;
                Some(REFUSED_RECHECK)
            }
            404 | NOT_CHAT => {
                self.available = false;
                Some(NO_CHAT_RECHECK)
            }
            crate::nd_chat::NO_TOKEN => {
                self.available = false;
                Some(NO_TOKEN_RECHECK)
            }
            crate::nd_chat::CHAT_OFF => {
                self.available = false;
                Some(if retry_after > 0 {
                    Duration::from_secs(retry_after as u64)
                } else {
                    CHAT_OFF_RECHECK
                })
            }
            503 if retry_after > 0 => Some(Duration::from_secs(retry_after as u64)),
            429 => {
                let b = self.backoff(spread);
                Some(if b < TOO_MANY_WAIT { TOO_MANY_WAIT + b } else { b })
            }
            _ => Some(self.backoff(spread)),
        }
    }

    /// 1 s doubling to 30 s, each with up to a fifth more or less.
    fn backoff(&mut self, spread: f64) -> Duration {
        let max = BACKOFF_MAX.as_millis() as f64;
        let base = (1000.0 * 2f64.powi(self.attempt as i32)).min(max);
        self.attempt = (self.attempt + 1).min(10);
        let ms = (base * (0.8 + spread.clamp(0.0, 1.0) * 0.4)).min(max);
        Duration::from_millis(ms as u64)
    }
}

/// What the tray's chat tells the menu.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChatReport {
    /// [`TrayChat::entry`].
    pub entry: Option<u32>,
}

/// Holds the chat for the tray: joins the socket of the process with the
/// device token through its IPC, feeds [`TrayChat`], shows its
/// notifications and sends what the menu shows to `sender`. Runs until the
/// tray ends.
pub fn watch(sender: std::sync::mpsc::Sender<ChatReport>) {
    use hbb_common::tokio;
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(err) => {
            hbb_common::log::error!("tray chat: no runtime: {err}");
            return;
        }
    };
    runtime.block_on(async move {
        let mut chat = TrayChat {
            receiver: crate::onboard::is_receiver(),
            ..Default::default()
        };
        let mut last = None;
        let mut report = |chat: &TrayChat| {
            let now = ChatReport {
                entry: chat.entry(),
            };
            if last != Some(now) {
                sender.send(now).ok();
                last = Some(now);
            }
        };
        let mut notify = |note: Note| {
            let (title, body) = if note.keys {
                (
                    crate::client::translate(note.title),
                    crate::client::translate(note.body),
                )
            } else {
                (note.title, note.body)
            };
            let link = note.link;
            std::thread::spawn(move || {
                crate::nd_chat::show_notification(&title, &body, move || {
                    crate::tray_menu::open_link(&link)
                })
            });
        };
        loop {
            let (status, retry_after) =
                crate::nd_chat::hold("", &mut chat, &mut notify, &mut report).await;
            let Some(wait) = chat.closed(status, retry_after, hbb_common::rand::random::<f64>())
            else {
                report(&chat);
                return;
            };
            report(&chat);
            tokio::time::sleep(wait).await;
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const DEVICE: &str = "900100001";

    fn welcome() -> String {
        json!({"type": "welcome", "v": 2, "device_id": DEVICE}).to_string()
    }

    fn staff(id: u64, text: &str) -> serde_json::Value {
        json!({"id": id.to_string(), "from": {"kind": "user", "id": "7", "name": "Anna Weber"},
               "text": text, "attachments": [], "deleted": false})
    }

    fn own(id: u64) -> serde_json::Value {
        json!({"id": id.to_string(), "from": {"kind": "device", "id": DEVICE, "name": "pc"},
               "text": "mine", "attachments": [], "deleted": false})
    }

    fn history(messages: Vec<serde_json::Value>, read: u64) -> String {
        json!({"type": "history", "before": "0", "more": false, "messages": messages,
               "reads": [{"reader": {"kind": "device", "id": DEVICE}, "up_to": read.to_string()},
                         {"reader": {"kind": "user", "id": "7"}, "up_to": "999"}]})
        .to_string()
    }

    fn new(m: serde_json::Value) -> String {
        json!({"type": "message.new", "message": m}).to_string()
    }

    fn read(up_to: u64) -> String {
        json!({"type": "read", "reader": {"kind": "device", "id": DEVICE}, "up_to": up_to.to_string()})
            .to_string()
    }

    fn note(body: &str) -> Note {
        Note {
            title: "Anna Weber".to_owned(),
            body: body.to_owned(),
            link: "chat".to_owned(),
            keys: false,
        }
    }

    fn ticket_updated(id: u64, unread: bool) -> String {
        json!({"type": "ticket.updated", "ticket_id": id, "status": "in_progress", "unread": unread})
            .to_string()
    }

    fn connected() -> TrayChat {
        let mut chat = TrayChat::default();
        assert_eq!(chat.frame(&welcome()), Ok(vec![]));
        chat
    }

    #[test]
    fn the_entry_counts_staff_messages_after_the_read_mark_of_the_computer() {
        let mut chat = TrayChat::default();
        assert_eq!(chat.entry(), None, "no entry before the server took the chat");
        chat.frame(&welcome()).unwrap();
        assert_eq!(chat.entry(), Some(0));
        let mut deleted = staff(4, "gone");
        deleted["deleted"] = json!(true);
        chat.frame(&history(vec![staff(1, "a"), own(2), staff(3, "b"), deleted, staff(5, "c")], 1))
            .unwrap();
        assert_eq!(chat.entry(), Some(2));
        chat.frame(&read(3)).unwrap();
        assert_eq!(chat.entry(), Some(1));
        chat.frame(&read(2)).unwrap();
        assert_eq!(chat.entry(), Some(1), "a read mark never moves back");
        chat.frame(&read(5)).unwrap();
        assert_eq!(chat.entry(), Some(0));
    }

    #[test]
    fn a_new_staff_message_notifies_once_with_the_name_and_the_start_of_the_text() {
        let mut chat = connected();
        chat.frame(&history(vec![], 0)).unwrap();
        assert_eq!(
            chat.frame(&new(staff(1, "Hi, I am  looking\nat it now."))),
            Ok(vec![note("Hi, I am looking at it now.")])
        );
        assert_eq!(chat.frame(&new(own(2))), Ok(vec![]), "own messages never notify");
        let long = chat.frame(&new(staff(3, &"x".repeat(300)))).unwrap();
        assert_eq!(long[0].body.chars().count(), 120);
        let mut files = staff(4, "");
        files["attachments"] = json!([{"name": "error.png"}]);
        assert_eq!(chat.frame(&new(files)), Ok(vec![note("error.png")]));
    }

    #[test]
    fn nothing_notifies_while_the_window_shows_the_chat_in_front() {
        let mut chat = connected();
        chat.frame(&history(vec![], 0)).unwrap();
        chat.set_front(true);
        assert_eq!(chat.frame(&new(staff(1, "seen in the window"))), Ok(vec![]));
        chat.set_front(false);
        assert_eq!(chat.frame(&new(staff(2, "now"))), Ok(vec![note("now")]));
        chat.set_front(true);
        chat.frame(&new(staff(3, "while the window was open"))).unwrap();
        chat.set_front(false);
        let again = chat
            .frame(&history(vec![staff(2, "now"), staff(3, "while the window was open")], 0))
            .unwrap();
        assert_eq!(again, vec![], "what the window showed counts as told");
    }

    #[test]
    fn a_reconnect_tells_only_what_came_since_and_only_once() {
        let mut chat = connected();
        assert_eq!(
            chat.frame(&history(vec![staff(1, "a"), staff(2, "b"), staff(3, "c")], 1)),
            Ok(vec![note("c")]),
            "unread messages at login: one notification, for the newest"
        );
        chat.closed(0, 0, 0.5);
        chat.frame(&welcome()).unwrap();
        assert_eq!(
            chat.frame(&history(vec![staff(1, "a"), staff(2, "b"), staff(3, "c")], 1)),
            Ok(vec![]),
            "no storm after a reconnect"
        );
        chat.closed(0, 0, 0.5);
        chat.frame(&welcome()).unwrap();
        assert_eq!(
            chat.frame(&history(vec![staff(3, "c"), staff(4, "d"), staff(5, "e")], 1)),
            Ok(vec![note("e")]),
            "what came while away: one notification"
        );
        assert_eq!(chat.entry(), Some(4));
        assert_eq!(chat.frame(&new(staff(5, "e"))), Ok(vec![]), "a message is told once");
    }

    /// The receiver: staff answered a ticket of this computer or changed
    /// its status. The notification opens that ticket; a message's opens
    /// Messages.
    #[test]
    fn news_about_a_ticket_notifies_the_receiver_and_opens_that_ticket() {
        let mut chat = connected();
        chat.receiver = true;
        chat.frame(&history(vec![], 0)).unwrap();
        let notes = chat.frame(&ticket_updated(24, true)).unwrap();
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].link, "tickets/24");
        assert!(notes[0].keys, "the text comes from the language files");
        assert_eq!(chat.frame(&ticket_updated(24, false)), Ok(vec![]), "nothing unread");
        let message = chat.frame(&new(staff(1, "Hi"))).unwrap();
        assert_eq!(message[0].link, "chat");
        assert_eq!(chat.entry(), Some(1), "a ticket is not a chat message");
    }

    #[test]
    fn outside_the_receiver_news_about_tickets_says_nothing() {
        let mut chat = connected();
        chat.frame(&history(vec![], 0)).unwrap();
        assert_eq!(chat.frame(&ticket_updated(24, true)), Ok(vec![]));
    }

    #[test]
    fn read_messages_never_notify() {
        let mut chat = connected();
        assert_eq!(chat.frame(&history(vec![staff(1, "a"), staff(2, "b")], 2)), Ok(vec![]));
        assert_eq!(chat.entry(), Some(0));
    }

    #[test]
    fn a_server_without_chat_of_version_2_is_no_chat() {
        let mut chat = TrayChat::default();
        assert_eq!(chat.frame(&history(vec![staff(1, "a")], 0)), Err(()));
        let mut chat = TrayChat::default();
        assert_eq!(chat.frame(&json!({"type": "welcome", "v": 1}).to_string()), Err(()));
        assert_eq!(chat.frame("not json"), Err(()));
        assert_eq!(chat.closed(NOT_CHAT, 0, 0.5), Some(Duration::from_secs(600)));
        assert_eq!(chat.entry(), None);
    }

    #[test]
    fn the_waits_follow_the_window() {
        let secs = Duration::from_secs;
        let mut chat = connected();
        assert_eq!(chat.closed(404, 0, 0.5), Some(secs(600)));
        assert_eq!(chat.entry(), None);
        chat.frame(&welcome()).unwrap();
        assert_eq!(chat.entry(), Some(0));
        assert_eq!(chat.closed(crate::nd_chat::NO_TOKEN, 0, 0.5), Some(secs(120)));
        assert_eq!(chat.closed(crate::nd_chat::CHAT_OFF, 450, 0.5), Some(secs(450)));
        assert_eq!(chat.entry(), None, "no chat entry while chat is off");
        assert_eq!(chat.closed(crate::nd_chat::CHAT_OFF, 0, 0.5), Some(secs(600)));
        let too_many = chat.closed(429, 0, 0.5).unwrap();
        assert!(too_many >= secs(30), "{too_many:?}");
        for status in [401, 403] {
            let mut chat = connected();
            assert_eq!(
                chat.closed(status, 0, 0.5),
                Some(secs(60)),
                "{status}: the service holds the refusal, the tray asks it again"
            );
            assert_eq!(chat.entry(), None);
            assert_eq!(chat.closed(status, 0, 0.5), Some(secs(60)), "{status}: no growth");
            chat.frame(&welcome()).unwrap();
            assert_eq!(chat.entry(), Some(0), "{status}: a new token brings the chat back");
        }
    }

    #[test]
    fn a_refusal_right_after_a_drop_is_a_start_short_tries_keep_the_entry() {
        let ms = Duration::from_millis;
        for status in [404, crate::nd_chat::NO_TOKEN, 401, 403] {
            let mut chat = connected();
            for _ in 0..4 {
                chat.closed(0, 0, 0.5);
            }
            let waits: Vec<_> = (0..5).map(|_| chat.closed(status, 0, 0.5)).collect();
            assert_eq!(
                waits,
                [Some(ms(1000)), Some(ms(2000)), Some(ms(4000)), Some(ms(8000)), Some(ms(16000))],
                "{status}: the server or the service is starting"
            );
            assert_eq!(chat.entry(), Some(0), "{status}: the entry stays while it starts");
            let settled = chat.closed(status, 0, 0.5).unwrap();
            assert!(settled >= Duration::from_secs(60), "{status}: then the long wait, {settled:?}");
            assert_eq!(chat.entry(), None, "{status}");
        }
    }

    #[test]
    fn a_server_that_is_starting_is_asked_again_after_its_retry_after() {
        let mut chat = connected();
        assert_eq!(chat.closed(503, 5, 0.5), Some(Duration::from_secs(5)));
        assert_eq!(chat.entry(), Some(0), "the entry stays while the server starts");
        assert_eq!(
            chat.closed(404, 0, 0.5),
            Some(Duration::from_millis(1000)),
            "a 404 during the start is part of it"
        );
        assert_eq!(chat.entry(), Some(0));
    }

    #[test]
    fn a_refused_token_on_an_open_socket_waits_like_a_403() {
        let mut chat = connected();
        chat.closed(0, 0, 0.5);
        chat.frame(&welcome()).unwrap();
        assert_eq!(chat.closed(403, 0, 0.5), Some(Duration::from_secs(60)));
        assert_eq!(chat.entry(), None);
    }

    #[test]
    fn the_backoff_doubles_from_1_s_to_30_s_with_some_spread_and_resets_after_welcome() {
        let mut chat = connected();
        let mut waits = vec![];
        for _ in 0..7 {
            waits.push(chat.closed(0, 0, 0.5).unwrap().as_millis());
        }
        assert_eq!(waits, [1000, 2000, 4000, 8000, 16000, 30000, 30000]);
        assert_eq!(chat.entry(), Some(0), "a drop keeps the entry");
        chat.frame(&welcome()).unwrap();
        assert_eq!(chat.closed(0, 0, 0.0).unwrap().as_millis(), 800);
        assert_eq!(chat.closed(500, 0, 1.0).unwrap().as_millis(), 2400);
    }
}
