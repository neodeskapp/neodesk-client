//! The tray menu: its entries, their labels and which of them can be
//! clicked, for what the service last reported about this computer.
//!
//! The first line says the same as the status line on Home
//! (flutter/lib/desktop/pages/home/home_status.dart), shorter: both follow
//! the cases in flutter/test/nd/home_status_cases.txt, and both tests read
//! that file.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/tray_model.rs`.

/// The service's online state, as Home's SvcStatus.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Online {
    NotReady,
    Connecting,
    Ready,
}

impl Online {
    /// The status number of the IPC OnlineStatus answer, after the UI's
    /// rule: a server that answers but has not taken the key is not ready.
    pub fn of(status: i64, key_confirmed: bool) -> Self {
        if status > 0 && key_confirmed {
            Online::Ready
        } else if status == 0 {
            Online::Connecting
        } else {
            Online::NotReady
        }
    }
}

/// The option neodesk-device-standing: what the server last said about
/// this computer.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Standing {
    pub banned: bool,
    pub enrollment: String,
    pub reason: String,
    pub signal: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Facts {
    /// The server's host, as people know it.
    pub server: String,
    pub online: Online,
    /// The status reason (deployment_required, ipc_disconnected, ...).
    pub reason: String,
    pub standing: Standing,
    /// Connections to this computer are turned off.
    pub service_stopped: bool,
    /// No server is set up.
    pub no_server: bool,
    /// The chat with support: None while this computer has none (not
    /// approved, chat off, no chat on the server), else its new messages.
    pub chat: Option<u32>,
    /// The receiver's tickets with something unread (nd_tickets.rs).
    pub tickets: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Off,
    NoServer,
    Banned,
    Removed,
    KeyRefused,
    Ready,
    Approval,
    NoService,
    Connecting,
    Offline,
}

/// The state for `facts`, in the order of Home's homeStatusOf. A computer
/// the signal server took is ready, even while an older answer of the
/// enrollment API still says it waits.
pub fn state_of(facts: &Facts) -> State {
    let standing = &facts.standing;
    if facts.service_stopped {
        return State::Off;
    }
    if facts.no_server {
        return State::NoServer;
    }
    if standing.banned {
        return State::Banned;
    }
    if standing.enrollment == "rejected" {
        return State::Removed;
    }
    if standing.signal == "refused" {
        return State::KeyRefused;
    }
    if facts.online == Online::Ready {
        return State::Ready;
    }
    if standing.enrollment == "pending"
        || standing.signal == "pending"
        || facts.reason == "deployment_required"
    {
        return State::Approval;
    }
    if facts.reason == "ipc_disconnected" {
        return State::NoService;
    }
    if facts.online == Online::Connecting {
        return State::Connecting;
    }
    State::Offline
}

impl State {
    /// Its name in home_status_cases.txt.
    #[cfg(test)]
    pub fn name(self) -> &'static str {
        match self {
            State::Off => "off",
            State::NoServer => "no-server",
            State::Banned => "banned",
            State::Removed => "removed",
            State::KeyRefused => "key-refused",
            State::Ready => "ready",
            State::Approval => "approval",
            State::NoService => "no-service",
            State::Connecting => "connecting",
            State::Offline => "offline",
        }
    }

    /// The tray's line: a translation key, and whether its {} is the
    /// server. Ready and connecting read as on Home.
    fn line(self) -> (&'static str, bool) {
        match self {
            State::Off => ("nd-tray-status-paused", false),
            State::NoServer => ("nd-tray-status-no-server", false),
            State::Banned => ("nd-tray-status-banned", true),
            State::Removed => ("nd-tray-status-removed", true),
            State::KeyRefused => ("nd-tray-status-key-refused", false),
            State::Ready => ("nd-home-status-ready", true),
            State::Approval => ("nd-tray-status-approval", false),
            State::NoService => ("nd-tray-status-no-service", false),
            State::Connecting => ("nd-home-status-connecting", true),
            State::Offline => ("nd-tray-status-offline", true),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    /// The state line; it does nothing.
    Status,
    /// Copies this computer's ID.
    CopyId,
    Open,
    Settings,
    /// Pauses connections to this computer; the service keeps running.
    StopService,
    /// Accepts connections again after a pause.
    AcceptConnections,
    /// Opens Settings at About.
    About,
    /// Opens the chat with support in the main window; the receiver's
    /// Messages.
    Chat,
    /// The receiver: opens Get help in the home window.
    GetHelp,
    /// The receiver: opens My tickets in the home window.
    Tickets,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Item {
    /// A translation key, the text for its {} (empty if it has none), and
    /// whether the entry can be clicked.
    Entry {
        action: Action,
        key: &'static str,
        arg: String,
        enabled: bool,
    },
    Separator,
}

impl Item {
    fn entry(action: Action, key: &'static str, arg: &str) -> Self {
        Item::Entry {
            action,
            key,
            arg: arg.to_owned(),
            enabled: action != Action::Status,
        }
    }

    /// The action, or None for a separator.
    #[cfg(test)]
    pub fn action(&self) -> Option<Action> {
        match self {
            Item::Entry { action, .. } => Some(*action),
            Item::Separator => None,
        }
    }
}

/// What this build and platform let the menu offer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Offers {
    /// Settings and About open in the main window (not with settings
    /// turned off or in an incoming-only build).
    pub settings: bool,
    /// Turning connections off (not with hide-stop-service).
    pub stop_service: bool,
    /// The receiver (onboard::is_receiver): its own short menu.
    pub receiver: bool,
}

/// The menu, top to bottom: the state line, the ID, Open, the chat with
/// support while this computer has one, Settings; then
/// pausing connections, or accepting them again while paused, neither while
/// the service isn't running; then About. The ID is left out until the
/// service has told it.
pub fn menu(facts: &Facts, id: &str, version: &str, offers: Offers) -> Vec<Item> {
    if offers.receiver {
        return receiver_menu(facts);
    }
    let state = state_of(facts);
    let (key, names_server) = state.line();
    let mut first = vec![Item::entry(
        Action::Status,
        key,
        if names_server { &facts.server } else { "" },
    )];
    if !id.is_empty() {
        first.push(Item::entry(Action::CopyId, "nd-tray-id", &format_id(id)));
    }
    first.push(Item::entry(Action::Open, "nd-tray-open", ""));
    match facts.chat {
        Some(0) => first.push(Item::entry(Action::Chat, "nd-tray-chat", "")),
        Some(n) => first.push(Item::entry(Action::Chat, "nd-tray-chat-new", &n.to_string())),
        None => {}
    }
    if offers.settings {
        first.push(Item::entry(Action::Settings, "Settings", ""));
    }
    let mut groups = vec![first];
    if state == State::Off {
        groups.push(vec![Item::entry(
            Action::AcceptConnections,
            "nd-tray-accept",
            "",
        )]);
    } else if offers.stop_service && state != State::NoService {
        groups.push(vec![Item::entry(Action::StopService, "nd-tray-stop", "")]);
    }
    if offers.settings {
        groups.push(vec![Item::entry(Action::About, "nd-tray-about", version)]);
    }
    let mut items = Vec::new();
    for group in groups {
        if !items.is_empty() {
            items.push(Item::Separator);
        }
        items.extend(group);
    }
    items
}

/// The receiver's menu: the home window and its three areas, Messages and
/// My tickets with what is new. Nothing opens settings or connects to
/// another computer.
fn receiver_menu(facts: &Facts) -> Vec<Item> {
    let messages = match facts.chat {
        Some(n) if n > 0 => Item::entry(Action::Chat, "nd-rcv-tray-messages-new", &n.to_string()),
        _ => Item::entry(Action::Chat, "nd-rcv-tray-messages", ""),
    };
    let tickets = match facts.tickets {
        0 => Item::entry(Action::Tickets, "nd-rcv-tray-tickets", ""),
        n => Item::entry(Action::Tickets, "nd-rcv-tray-tickets-new", &n.to_string()),
    };
    vec![
        Item::entry(Action::Open, "nd-tray-open", ""),
        Item::Separator,
        Item::entry(Action::GetHelp, "nd-rcv-tray-help", ""),
        messages,
        tickets,
    ]
}

/// The tray's first line, the same as the menu's state line: a translation
/// key and the text for its {}.
pub fn status_line(facts: &Facts) -> (&'static str, String) {
    let (key, names_server) = state_of(facts).line();
    (key, if names_server { facts.server.clone() } else { String::new() })
}

/// The number on the tray icon: new messages and tickets with something
/// unread. The icon gets a dot while it isn't 0.
pub fn badge(facts: &Facts) -> u32 {
    facts.chat.unwrap_or(0).saturating_add(facts.tickets)
}

/// The tooltip's line about the tickets of the receiver: a translation key
/// and its count, when some have something unread.
pub fn tickets_tooltip(tickets: u32) -> Option<(&'static str, String)> {
    (tickets > 0).then(|| ("nd-rcv-tray-tickets-tooltip", tickets.to_string()))
}

/// `rgba` (`width` x `height`) with a dot in the lower right corner, a
/// third of the icon wide, in `color`, with a ring of `ring` around it.
pub fn with_dot(rgba: &[u8], width: u32, height: u32, color: [u8; 4], ring: [u8; 4]) -> Vec<u8> {
    let mut out = rgba.to_vec();
    let size = width.min(height) as f32;
    let r = size / 6.0;
    let edge = r * 0.35;
    let (cx, cy) = (width as f32 - r - edge, height as f32 - r - edge);
    for y in 0..height {
        for x in 0..width {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            let d = (dx * dx + dy * dy).sqrt();
            let paint = if d <= r {
                color
            } else if d <= r + edge {
                ring
            } else {
                continue;
            };
            let i = ((y * width + x) * 4) as usize;
            if i + 4 <= out.len() {
                out[i..i + 4].copy_from_slice(&paint);
            }
        }
    }
    out
}

/// The tooltip's line about the chat: a translation key and its count, when
/// there are new messages.
pub fn chat_tooltip(chat: Option<u32>) -> Option<(&'static str, String)> {
    match chat {
        Some(n) if n > 0 => Some(("nd-tray-chat-tooltip", n.to_string())),
        _ => None,
    }
}

/// An ID in groups of three from the right, as Home shows it (formatID).
pub fn format_id(id: &str) -> String {
    let id2: String = id.chars().filter(|c| *c != ' ').collect();
    if id2.is_empty() || !id2.chars().all(|c| c.is_ascii_digit()) {
        return id.to_owned();
    }
    if id2.len() <= 3 {
        return id2;
    }
    let first = match id2.len() % 3 {
        0 => 3,
        n => n,
    };
    let mut out = id2[..first].to_owned();
    let mut i = first;
    while i < id2.len() {
        out.push(' ');
        out.push_str(&id2[i..i + 3]);
        i += 3;
    }
    out
}

/// The server this computer reports to, as people know it: the ID server,
/// else the API server, without scheme, path or port (Home's serverName).
pub fn server_name(custom_rendezvous_server: &str, api_server: &str) -> String {
    let mut host = custom_rendezvous_server.trim();
    if host.is_empty() {
        host = api_server.trim();
    }
    if let Some(at) = host.find("://") {
        if at > 0 && host[..at].chars().all(|c| c.is_ascii_lowercase()) {
            host = &host[at + 3..];
        }
    }
    if let Some(slash) = host.find('/') {
        if slash > 0 {
            host = &host[..slash];
        }
    }
    if let Some(colon) = host.rfind(':') {
        if colon > 0 && !host.contains(']') {
            host = &host[..colon];
        }
    }
    host.to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    const CASES: &str = include_str!("../flutter/test/nd/home_status_cases.txt");
    const EN: &str = include_str!("lang/en.rs");
    const DE: &str = include_str!("lang/de.rs");
    const TEMPLATE: &str = include_str!("lang/template.rs");

    const ON: Offers = Offers {
        settings: true,
        stop_service: true,
        receiver: false,
    };

    const RECEIVER: Offers = Offers {
        settings: true,
        stop_service: true,
        receiver: true,
    };

    fn facts(online: Online, reason: &str, standing: Standing) -> Facts {
        Facts {
            server: "10.10.10.74".to_owned(),
            online,
            reason: reason.to_owned(),
            standing,
            service_stopped: false,
            no_server: false,
            chat: None,
            tickets: 0,
        }
    }

    fn ready() -> Facts {
        facts(Online::Ready, "ready", Standing::default())
    }

    /// The menu as lines: "-" for a separator, a disabled entry in
    /// brackets.
    fn lines(items: &[Item]) -> Vec<String> {
        items
            .iter()
            .map(|item| match item {
                Item::Separator => "-".to_owned(),
                Item::Entry {
                    key, arg, enabled, ..
                } => {
                    let text = if arg.is_empty() {
                        key.to_string()
                    } else {
                        format!("{key} {arg}")
                    };
                    if *enabled {
                        text
                    } else {
                        format!("[{text}]")
                    }
                }
            })
            .collect()
    }

    #[test]
    fn the_state_follows_the_same_cases_as_home() {
        let mut count = 0;
        for line in CASES.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (given, want) = line.split_once("=>").expect(line);
            let mut f = facts(Online::NotReady, "", Standing::default());
            for token in given.split_whitespace() {
                let (name, value) = token.split_once('=').expect(token);
                match name {
                    "status" => {
                        f.online = match value {
                            "ready" => Online::Ready,
                            "connecting" => Online::Connecting,
                            "notReady" => Online::NotReady,
                            _ => panic!("{line}"),
                        }
                    }
                    "reason" => f.reason = value.to_owned(),
                    "banned" => f.standing.banned = value == "1",
                    "enrollment" => f.standing.enrollment = value.to_owned(),
                    "signal" => f.standing.signal = value.to_owned(),
                    "said" => f.standing.reason = value.to_owned(),
                    "stopped" => f.service_stopped = value == "1",
                    "noserver" => f.no_server = value == "1",
                    _ => panic!("unknown fact in {line}"),
                }
            }
            assert_eq!(state_of(&f).name(), want.trim(), "{line}");
            count += 1;
        }
        assert!(count >= 10, "only {count} cases");
    }

    #[test]
    fn a_ready_computer_shows_its_server_id_and_every_entry() {
        assert_eq!(
            lines(&menu(&ready(), "123456789", "1.5.0", ON)),
            [
                "[nd-home-status-ready 10.10.10.74]",
                "nd-tray-id 123 456 789",
                "nd-tray-open",
                "Settings",
                "-",
                "nd-tray-stop",
                "-",
                "nd-tray-about 1.5.0",
            ]
        );
    }

    #[test]
    fn the_chat_entry_follows_open_with_the_count_of_new_messages() {
        let mut f = ready();
        f.chat = Some(0);
        assert_eq!(
            lines(&menu(&f, "123456789", "1.5.0", ON))[..4],
            [
                "[nd-home-status-ready 10.10.10.74]",
                "nd-tray-id 123 456 789",
                "nd-tray-open",
                "nd-tray-chat",
            ]
        );
        f.chat = Some(3);
        assert_eq!(lines(&menu(&f, "123456789", "1.5.0", ON))[3], "nd-tray-chat-new 3");
        let chat = menu(&f, "1", "1", ON)
            .into_iter()
            .find(|i| i.action() == Some(Action::Chat));
        assert!(matches!(chat, Some(Item::Entry { enabled: true, .. })));
        assert_eq!(chat_tooltip(Some(3)), Some(("nd-tray-chat-tooltip", "3".to_owned())));
        assert_eq!(chat_tooltip(Some(0)), None);
        assert_eq!(chat_tooltip(None), None);
    }

    #[test]
    fn a_computer_without_chat_has_no_chat_entry() {
        let f = ready();
        assert!(menu(&f, "123456789", "1.5.0", ON)
            .iter()
            .all(|i| i.action() != Some(Action::Chat)));
    }

    #[test]
    fn each_state_changes_only_the_first_line() {
        let standing = |signal: &str, enrollment: &str| Standing {
            signal: signal.to_owned(),
            enrollment: enrollment.to_owned(),
            ..Standing::default()
        };
        let mut no_server = facts(Online::NotReady, "no_rendezvous_server", Standing::default());
        no_server.no_server = true;
        no_server.server.clear();
        for (f, first) in [
            (no_server, "[nd-tray-status-no-server]"),
            (
                facts(Online::NotReady, "offline", standing("pending", "")),
                "[nd-tray-status-approval]",
            ),
            (
                facts(Online::NotReady, "offline", standing("", "pending")),
                "[nd-tray-status-approval]",
            ),
            (
                facts(Online::NotReady, "offline", standing("refused", "")),
                "[nd-tray-status-key-refused]",
            ),
            (
                facts(Online::NotReady, "offline", Standing::default()),
                "[nd-tray-status-offline 10.10.10.74]",
            ),
            (
                facts(Online::Connecting, "connecting", Standing::default()),
                "[nd-home-status-connecting 10.10.10.74]",
            ),
        ] {
            let menu = lines(&menu(&f, "123456789", "1.5.0", ON));
            assert_eq!(menu[0], first, "{f:?}");
            assert_eq!(menu[1..], lines(&super::menu(&ready(), "123456789", "1.5.0", ON))[1..]);
        }
    }

    // Nothing pauses connections while the service isn't running (L486)
    #[test]
    fn a_service_that_is_not_running_offers_no_pause() {
        let down = facts(Online::NotReady, "ipc_disconnected", Standing::default());
        let items = menu(&down, "123456789", "1.5.0", ON);
        assert_eq!(
            lines(&items),
            [
                "[nd-tray-status-no-service]",
                "nd-tray-id 123 456 789",
                "nd-tray-open",
                "Settings",
                "-",
                "nd-tray-about 1.5.0",
            ]
        );
        assert!(items
            .iter()
            .all(|i| i.action() != Some(Action::StopService)));
    }

    #[test]
    fn paused_connections_say_so_and_can_be_accepted_again() {
        let mut off = ready();
        off.service_stopped = true;
        let items = menu(&off, "123456789", "1.5.0", ON);
        assert_eq!(
            lines(&items),
            [
                "[nd-tray-status-paused]",
                "nd-tray-id 123 456 789",
                "nd-tray-open",
                "Settings",
                "-",
                "nd-tray-accept",
                "-",
                "nd-tray-about 1.5.0",
            ]
        );
        assert!(items.iter().all(|i| i.action() != Some(Action::StopService)));
    }

    #[test]
    fn what_the_build_does_not_offer_leaves_no_entry_and_no_stray_separator() {
        let none = Offers {
            settings: false,
            stop_service: false,
            receiver: false,
        };
        assert_eq!(
            lines(&menu(&ready(), "123456789", "1.5.0", none)),
            [
                "[nd-home-status-ready 10.10.10.74]",
                "nd-tray-id 123 456 789",
                "nd-tray-open",
            ]
        );
        let stop_only = Offers {
            settings: false,
            stop_service: true,
            receiver: false,
        };
        assert_eq!(
            lines(&menu(&ready(), "", "1.5.0", stop_only)),
            [
                "[nd-home-status-ready 10.10.10.74]",
                "nd-tray-open",
                "-",
                "nd-tray-stop",
            ]
        );
    }

    /// The receiver's tray: Open, Get help, Messages, My tickets, and
    /// nothing that opens settings or connects to another computer, in every
    /// state, even where the build would offer settings.
    #[test]
    fn the_receiver_menu_has_its_home_and_three_areas_and_nothing_else() {
        let mut f = ready();
        assert_eq!(
            lines(&menu(&f, "123456789", "1.5.0", RECEIVER)),
            [
                "nd-tray-open",
                "-",
                "nd-rcv-tray-help",
                "nd-rcv-tray-messages",
                "nd-rcv-tray-tickets",
            ]
        );
        f.chat = Some(2);
        f.tickets = 1;
        assert_eq!(
            lines(&menu(&f, "123456789", "1.5.0", RECEIVER))[2..],
            [
                "nd-rcv-tray-help",
                "nd-rcv-tray-messages-new 2",
                "nd-rcv-tray-tickets-new 1",
            ]
        );
        let mut off = ready();
        off.service_stopped = true;
        let down = facts(Online::NotReady, "ipc_disconnected", Standing::default());
        for f in [ready(), off, down] {
            let actions: Vec<_> = menu(&f, "123456789", "1.5.0", RECEIVER)
                .iter()
                .filter_map(Item::action)
                .collect();
            assert_eq!(
                actions,
                [Action::Open, Action::GetHelp, Action::Chat, Action::Tickets],
                "{f:?}"
            );
        }
    }

    #[test]
    fn the_badge_counts_new_messages_and_unread_tickets() {
        let mut f = ready();
        assert_eq!(badge(&f), 0);
        f.chat = Some(2);
        assert_eq!(badge(&f), 2);
        f.tickets = 3;
        assert_eq!(badge(&f), 5);
        f.chat = None;
        assert_eq!(badge(&f), 3, "tickets count without chat");
        assert_eq!(tickets_tooltip(3), Some(("nd-rcv-tray-tickets-tooltip", "3".to_owned())));
        assert_eq!(tickets_tooltip(0), None);
    }

    #[test]
    fn the_dot_sits_in_the_lower_right_corner_and_leaves_the_rest() {
        let (w, h) = (32u32, 32u32);
        let icon = vec![10u8; (w * h * 4) as usize];
        let dotted = with_dot(&icon, w, h, [200, 0, 0, 255], [255, 255, 255, 255]);
        let px = |x: u32, y: u32| {
            let i = ((y * w + x) * 4) as usize;
            dotted[i..i + 4].to_vec()
        };
        assert_eq!(px(26, 26), [200, 0, 0, 255], "the dot");
        assert_eq!(px(2, 2), [10, 10, 10, 10], "the icon");
        assert_eq!(px(26, 2), [10, 10, 10, 10]);
        assert_eq!(px(2, 26), [10, 10, 10, 10]);
    }

    #[test]
    fn only_the_state_line_is_disabled() {
        for item in menu(&ready(), "123456789", "1.5.0", ON) {
            if let Item::Entry {
                action, enabled, ..
            } = item
            {
                assert_eq!(enabled, action != Action::Status, "{action:?}");
            }
        }
    }

    #[test]
    fn the_id_reads_in_groups_of_three_as_on_home() {
        assert_eq!(format_id("123456789"), "123 456 789");
        assert_eq!(format_id("1234567890"), "1 234 567 890");
        assert_eq!(format_id("12 34 56"), "123 456");
        assert_eq!(format_id("123"), "123");
        assert_eq!(format_id("my-pc"), "my-pc");
    }

    #[test]
    fn the_server_reads_as_people_know_it() {
        assert_eq!(server_name("10.10.10.74", ""), "10.10.10.74");
        assert_eq!(server_name(" lab.example:21116 ", ""), "lab.example");
        assert_eq!(server_name("", "https://lab.example:21114/api"), "lab.example");
        assert_eq!(server_name("[::1]", ""), "[::1]");
        assert_eq!(server_name("", ""), "");
    }

    /// Every text the menu can show is in English and German, and in the
    /// template; other languages fall back to English.
    #[test]
    fn every_label_is_translated() {
        let mut keys = vec![
            "nd-tray-id",
            "nd-tray-open",
            "nd-tray-stop",
            "nd-tray-accept",
            "nd-tray-about",
            "nd-tray-chat",
            "nd-tray-chat-new",
            "nd-tray-chat-tooltip",
            "nd-rcv-tray-help",
            "nd-rcv-tray-messages",
            "nd-rcv-tray-messages-new",
            "nd-rcv-tray-tickets",
            "nd-rcv-tray-tickets-new",
            "nd-rcv-tray-tickets-tooltip",
        ];
        for state in [
            State::Off,
            State::NoServer,
            State::Banned,
            State::Removed,
            State::KeyRefused,
            State::Ready,
            State::Approval,
            State::NoService,
            State::Connecting,
            State::Offline,
        ] {
            keys.push(state.line().0);
        }
        keys.push("nd-tray-id-copied");
        let has = |file: &str, key: &str, filled: bool| {
            file.lines().any(|l| {
                let l = l.trim();
                l.starts_with(&format!("(\"{key}\", \"")) && (!filled || !l.ends_with("\"\"),"))
            })
        };
        for key in keys {
            assert!(has(EN, key, true), "en.rs: {key}");
            assert!(has(DE, key, true), "de.rs: {key}");
            assert!(has(TEMPLATE, key, false), "template.rs: {key}");
        }
        // "Settings" is RustDesk's own key, translated everywhere.
        assert!(has(DE, "Settings", true));
    }
}
