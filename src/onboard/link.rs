//! Invites as people get them: a link, a `neodesk://` link, a code, or
//! the name of the file the invite page served.
//!
//! A code is 8 symbols of `23456789ABCDEFGHJKMNPQRSTVWXYZ`, shown as
//! `ABCD-EF23`; case, spaces and dashes do not matter. Links and file names
//! name the console the code belongs to:
//!
//! - `https://<host>[:port]/join/<CODE>` and `https://<host>[:port]/s/<CODE>`
//! - `neodesk://join/<host>[:port]/<CODE>` and
//!   `neodesk://support/<host>[:port]/<CODE>`, with `?http=1` for a
//!   console on plain HTTP. Without it the console is reached over HTTPS only.
//! - `NeoDesk-Setup-<filehost>-<CODE>.exe` and
//!   `NeoDesk-QuickSupport-<filehost>-<CODE>.exe`, where `<filehost>` is
//!   `host[_port][_http]`, left out for an IPv6 console. A browser's ` (1)`
//!   after the code is ignored.

use hbb_common::config;

const CODE_LENGTH: usize = 8;
const CODE_ALPHABET: &str = "23456789ABCDEFGHJKMNPQRSTVWXYZ";
const FILE_PREFIX_SETUP: &str = "neodesk-setup-";
const FILE_PREFIX_SUPPORT: &str = "neodesk-quicksupport-";

/// What a code is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// Add a computer: the client joins the server for good.
    Join,
    /// Quick support: one session, nothing installed.
    Support,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Join => "join",
            Kind::Support => "support",
        }
    }
}

/// The console's address as a link names it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Console {
    /// False for a console on plain HTTP.
    pub https: bool,
    /// Host name or address, lower case, IPv6 without brackets.
    pub host: String,
    /// The port, None for the scheme's own.
    pub port: Option<u16>,
}

impl Console {
    /// `https://host[:port]`, without a slash at the end.
    pub fn base(&self) -> String {
        let scheme = if self.https { "https" } else { "http" };
        format!("{scheme}://{}", self.host_port())
    }

    /// `host[:port]`, an IPv6 address in brackets.
    pub fn host_port(&self) -> String {
        let host = if self.host.contains(':') {
            format!("[{}]", self.host)
        } else {
            self.host.clone()
        };
        match self.port {
            Some(port) => format!("{host}:{port}"),
            None => host,
        }
    }

    /// Reads a base address such as `https://desk.example.com:8443`, the
    /// form the client keeps after a join.
    pub fn from_base(base: &str) -> Option<Self> {
        let url = url::Url::parse(base.trim()).ok()?;
        let https = match url.scheme() {
            "https" => true,
            "http" => false,
            _ => return None,
        };
        console_of_url(&url, https)
    }
}

/// An invite as the client read it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invite {
    /// None for a bare code, which can be either kind.
    pub kind: Option<Kind>,
    /// None for a bare code and for a file name without a host part.
    pub console: Option<Console>,
    /// The code without dash, upper case.
    pub code: String,
}

impl Invite {
    /// The `neodesk://` link of the invite, None without kind or console.
    pub fn deep_link(&self) -> Option<String> {
        let kind = self.kind?;
        let console = self.console.as_ref()?;
        let mut link = format!(
            "{}://{}/{}/{}",
            config::URI_SCHEME,
            kind.as_str(),
            console.host_port(),
            self.code
        );
        if !console.https {
            link.push_str("?http=1");
        }
        Some(link)
    }
}

/// Why a text is not an invite.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkError {
    /// Neither a link nor a code.
    NotALink,
}

/// Upper-cases the code and drops spaces and dashes, as the server does.
pub fn normalize_code(code: &str) -> String {
    code.chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .flat_map(char::to_uppercase)
        .collect()
}

/// The normalized code when it has the length and symbols of a code.
pub fn valid_code(code: &str) -> Option<String> {
    let code = normalize_code(code);
    (code.chars().count() == CODE_LENGTH && code.chars().all(|c| CODE_ALPHABET.contains(c)))
        .then_some(code)
}

fn valid_host(host: &str) -> bool {
    if host.parse::<std::net::IpAddr>().is_ok() {
        return true;
    }
    !host.is_empty()
        && host.len() <= 253
        && host.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        })
}

fn console_of_url(url: &url::Url, https: bool) -> Option<Console> {
    if !url.username().is_empty() || url.password().is_some() {
        return None;
    }
    let host = match url.host()? {
        url::Host::Domain(name) => name.to_ascii_lowercase(),
        url::Host::Ipv4(ip) => ip.to_string(),
        url::Host::Ipv6(ip) => ip.to_string(),
    };
    if !valid_host(&host) {
        return None;
    }
    Some(Console {
        https,
        host,
        port: url.port(),
    })
}

/// Reads what a person pasted or a link handed over: a join or support link
/// of the console, a `neodesk://` link, or a bare code.
pub fn parse(text: &str) -> Result<Invite, LinkError> {
    let text = text.trim();
    if let Some(invite) = parse_deep_link(text) {
        return invite;
    }
    let lower = text.to_ascii_lowercase();
    if lower.starts_with("https://") || lower.starts_with("http://") {
        return parse_web_link(text).ok_or(LinkError::NotALink);
    }
    valid_code(text)
        .map(|code| Invite {
            kind: None,
            console: None,
            code,
        })
        .ok_or(LinkError::NotALink)
}

fn parse_web_link(text: &str) -> Option<Invite> {
    let url = url::Url::parse(text).ok()?;
    let https = url.scheme() == "https";
    let console = console_of_url(&url, https)?;
    let mut segments: Vec<&str> = url.path_segments()?.collect();
    if segments.last() == Some(&"") {
        segments.pop();
    }
    let [verb, code] = segments.as_slice() else {
        return None;
    };
    let kind = match *verb {
        "join" => Kind::Join,
        "s" => Kind::Support,
        _ => return None,
    };
    Some(Invite {
        kind: Some(kind),
        console: Some(console),
        code: valid_code(code)?,
    })
}

/// `Some(Err)` for a `neodesk://` link that is not an invite, None for
/// any other text.
fn parse_deep_link(text: &str) -> Option<Result<Invite, LinkError>> {
    let prefix = format!("{}://", config::URI_SCHEME);
    if text.len() < prefix.len() || !text[..prefix.len()].eq_ignore_ascii_case(&prefix) {
        return None;
    }
    Some(parse_deep_link_rest(&text[prefix.len()..]).ok_or(LinkError::NotALink))
}

fn parse_deep_link_rest(rest: &str) -> Option<Invite> {
    // A link that went through a URL parser has its IPv6 brackets encoded.
    let rest = ["%5B", "%5b"]
        .iter()
        .fold(rest.to_owned(), |text, code| text.replace(code, "["));
    let rest = ["%5D", "%5d"]
        .iter()
        .fold(rest, |text, code| text.replace(code, "]"));
    let (path, query) = match rest.split_once('?') {
        Some((path, query)) => (path, Some(query)),
        None => (rest.as_str(), None),
    };
    let https = !query
        .unwrap_or("")
        .split('&')
        .any(|pair| pair.eq_ignore_ascii_case("http=1"));
    let mut segments: Vec<&str> = path.split('/').collect();
    if segments.last() == Some(&"") {
        segments.pop();
    }
    let [verb, host_port, code] = segments.as_slice() else {
        return None;
    };
    let kind = match verb.to_ascii_lowercase().as_str() {
        "join" => Kind::Join,
        "support" => Kind::Support,
        _ => return None,
    };
    let (host, port) = split_host_port(host_port)?;
    let host = host.to_ascii_lowercase();
    if !valid_host(&host) {
        return None;
    }
    Some(Invite {
        kind: Some(kind),
        console: Some(Console { https, host, port }),
        code: valid_code(code)?,
    })
}

fn split_host_port(text: &str) -> Option<(&str, Option<u16>)> {
    if let Some(rest) = text.strip_prefix('[') {
        let (host, after) = rest.split_once(']')?;
        host.parse::<std::net::Ipv6Addr>().ok()?;
        return match after {
            "" => Some((host, None)),
            port => Some((host, Some(parse_port(port.strip_prefix(':')?)?))),
        };
    }
    match text.split_once(':') {
        Some((host, port)) => Some((host, Some(parse_port(port)?))),
        None => Some((text, None)),
    }
}

fn parse_port(text: &str) -> Option<u16> {
    if text.is_empty() || !text.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    text.parse::<u16>().ok().filter(|port| *port > 0)
}

/// Reads the name of a file the invite page served (the file name only, or
/// a path). None for any other name.
pub fn parse_file_name(name: &str) -> Option<Invite> {
    let name = name.rsplit(['/', '\\']).next().unwrap_or(name);
    let lower = name.to_ascii_lowercase();
    let (kind, rest) = if lower.starts_with(FILE_PREFIX_SETUP) {
        (Kind::Join, &name[FILE_PREFIX_SETUP.len()..])
    } else if lower.starts_with(FILE_PREFIX_SUPPORT) {
        (Kind::Support, &name[FILE_PREFIX_SUPPORT.len()..])
    } else {
        return None;
    };
    let (file_host, tail) = match rest.rsplit_once('-') {
        Some((file_host, tail)) => (Some(file_host), tail),
        None => (None, rest),
    };
    let code = tail.split('.').next().unwrap_or(tail);
    let code = strip_copy_suffix(code);
    let code = valid_code_exact(code)?;
    let console = match file_host {
        Some(file_host) => Some(parse_file_host(file_host)?),
        None => None,
    };
    Some(Invite {
        kind: Some(kind),
        console,
        code,
    })
}

/// Like [`valid_code`], but without a dash or space inside: a file name
/// carries the code as one segment.
fn valid_code_exact(code: &str) -> Option<String> {
    if code.contains(|c: char| c.is_whitespace() || c == '-') {
        return None;
    }
    valid_code(code)
}

/// Drops the ` (1)` or `(1)` a browser adds to a second download.
fn strip_copy_suffix(text: &str) -> &str {
    let trimmed = text.trim_end();
    if let Some(open) = trimmed.rfind('(') {
        let inner = &trimmed[open + 1..];
        if let Some(number) = inner.strip_suffix(')') {
            if !number.is_empty() && number.chars().all(|c| c.is_ascii_digit()) {
                return trimmed[..open].trim_end();
            }
        }
    }
    trimmed
}

fn parse_file_host(text: &str) -> Option<Console> {
    let mut parts = text.split('_');
    let host = parts.next()?.to_ascii_lowercase();
    if !valid_host(&host) || host.contains(':') {
        return None;
    }
    let mut port = None;
    let mut https = true;
    for part in parts {
        if part.eq_ignore_ascii_case("http") && https {
            https = false;
        } else if port.is_none() && https {
            port = Some(parse_port(part)?);
        } else {
            return None;
        }
    }
    Some(Console { https, host, port })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn console(https: bool, host: &str, port: Option<u16>) -> Option<Console> {
        Some(Console {
            https,
            host: host.to_owned(),
            port,
        })
    }

    #[test]
    fn codes_ignore_case_spaces_and_dashes() {
        assert_eq!(valid_code("abcd-ef23").as_deref(), Some("ABCDEF23"));
        assert_eq!(valid_code(" ABCD EF23 ").as_deref(), Some("ABCDEF23"));
        // 0, 1, I, L, O and U are not in the alphabet.
        assert_eq!(valid_code("ABCD-EF01"), None);
        assert_eq!(valid_code("ABCDEFGI"), None);
        assert_eq!(valid_code("ABCDEF2"), None);
        assert_eq!(valid_code("ABCDEF234"), None);
    }

    #[test]
    fn web_links_name_the_console_and_the_kind() {
        let invite = parse("https://desk.example.com/join/ABCDEF23").unwrap();
        assert_eq!(invite.kind, Some(Kind::Join));
        assert_eq!(invite.console, console(true, "desk.example.com", None));
        assert_eq!(invite.code, "ABCDEF23");

        let invite = parse(" https://Desk.Example.com:8443/s/abcd-ef23/ ").unwrap();
        assert_eq!(invite.kind, Some(Kind::Support));
        assert_eq!(invite.console, console(true, "desk.example.com", Some(8443)));
        assert_eq!(invite.code, "ABCDEF23");

        let invite = parse("http://192.168.1.5:5000/join/ABCDEF23").unwrap();
        assert_eq!(invite.console, console(false, "192.168.1.5", Some(5000)));

        let invite = parse("https://[fd00::5]:8443/join/ABCDEF23").unwrap();
        assert_eq!(invite.console, console(true, "fd00::5", Some(8443)));
        assert_eq!(
            invite.console.unwrap().base(),
            "https://[fd00::5]:8443".to_owned()
        );
    }

    #[test]
    fn other_web_links_are_not_invites() {
        for text in [
            "https://desk.example.com/",
            "https://desk.example.com/join/",
            "https://desk.example.com/devices/ABCDEF23",
            "https://desk.example.com/join/ABCDEF23/extra",
            "https://desk.example.com/join/ABCDEF2",
            "https://user@desk.example.com/join/ABCDEF23",
            "ftp://desk.example.com/join/ABCDEF23",
        ] {
            assert_eq!(parse(text), Err(LinkError::NotALink), "{text}");
        }
    }

    #[test]
    fn deep_links_use_https_unless_they_say_http() {
        let invite = parse("neodesk://join/desk.example.com/ABCDEF23").unwrap();
        assert_eq!(invite.kind, Some(Kind::Join));
        assert_eq!(invite.console, console(true, "desk.example.com", None));

        let invite = parse("NeoDesk://support/desk.lan:5000/abcdef23?http=1").unwrap();
        assert_eq!(invite.kind, Some(Kind::Support));
        assert_eq!(invite.console, console(false, "desk.lan", Some(5000)));

        let invite = parse("neodesk://join/[fd00::5]:8443/ABCDEF23/").unwrap();
        assert_eq!(invite.console, console(true, "fd00::5", Some(8443)));
        let invite = parse("neodesk://join/%5Bfd00::5%5D:8443/ABCDEF23").unwrap();
        assert_eq!(invite.console, console(true, "fd00::5", Some(8443)));

        // Only http=1 turns HTTPS off.
        let invite = parse("neodesk://join/desk.lan/ABCDEF23?http=0").unwrap();
        assert!(invite.console.unwrap().https);
    }

    #[test]
    fn broken_deep_links_are_not_invites() {
        for text in [
            "neodesk://join/desk.example.com",
            "neodesk://join/ABCDEF23",
            "neodesk://connect/desk.example.com/ABCDEF23",
            "neodesk://join/desk.example.com:/ABCDEF23",
            "neodesk://join/desk.example.com:99999/ABCDEF23",
            "neodesk://join/desk_example.com/ABCDEF23",
            "neodesk://join/[nothost]/ABCDEF23",
            "neodesk://join/desk.example.com/ABCDEF2",
        ] {
            assert_eq!(parse(text), Err(LinkError::NotALink), "{text}");
        }
    }

    #[test]
    fn a_bare_code_has_no_kind_and_no_console() {
        let invite = parse(" 7kq4-m2xd ").unwrap();
        assert_eq!(
            invite,
            Invite {
                kind: None,
                console: None,
                code: "7KQ4M2XD".to_owned()
            }
        );
        assert_eq!(parse("hello"), Err(LinkError::NotALink));
        assert_eq!(parse(""), Err(LinkError::NotALink));
    }

    #[test]
    fn deep_link_round_trips() {
        let invite = parse("https://desk.example.com:8443/s/ABCDEF23").unwrap();
        assert_eq!(
            invite.deep_link().as_deref(),
            Some("neodesk://support/desk.example.com:8443/ABCDEF23")
        );
        let invite = parse_file_name("NeoDesk-Setup-192.168.1.5_5000_http-ABCDEF23.exe").unwrap();
        let link = invite.deep_link().unwrap();
        assert_eq!(link, "neodesk://join/192.168.1.5:5000/ABCDEF23?http=1");
        assert_eq!(parse(&link).unwrap(), invite);
        assert_eq!(parse("ABCDEF23").unwrap().deep_link(), None);
    }

    #[test]
    fn file_names_carry_kind_console_and_code() {
        let invite = parse_file_name("NeoDesk-Setup-desk.example.com-ABCDEF23.exe").unwrap();
        assert_eq!(invite.kind, Some(Kind::Join));
        assert_eq!(invite.console, console(true, "desk.example.com", None));
        assert_eq!(invite.code, "ABCDEF23");

        let invite =
            parse_file_name("NeoDesk-QuickSupport-desk.example.com_8443-ABCDEF23.exe").unwrap();
        assert_eq!(invite.kind, Some(Kind::Support));
        assert_eq!(invite.console, console(true, "desk.example.com", Some(8443)));

        let invite = parse_file_name("NeoDesk-Setup-192.168.1.5_5000_http-ABCDEF23.exe").unwrap();
        assert_eq!(invite.console, console(false, "192.168.1.5", Some(5000)));

        let invite = parse_file_name("neodesk-setup-desk.lan_http-abcdef23.EXE").unwrap();
        assert_eq!(invite.console, console(false, "desk.lan", None));
        assert_eq!(invite.code, "ABCDEF23");
    }

    #[test]
    fn host_names_with_dashes_and_browser_copies_still_parse() {
        let invite =
            parse_file_name("NeoDesk-Setup-my-desk.example.com-ABCDEF23 (1).exe").unwrap();
        assert_eq!(invite.console, console(true, "my-desk.example.com", None));
        assert_eq!(invite.code, "ABCDEF23");

        let invite = parse_file_name("NeoDesk-QuickSupport-desk.lan-ABCDEF23(12).exe").unwrap();
        assert_eq!(invite.code, "ABCDEF23");

        let invite =
            parse_file_name(r"C:\Users\anna\Downloads\NeoDesk-Setup-desk.lan-ABCDEF23.exe")
                .unwrap();
        assert_eq!(invite.console, console(true, "desk.lan", None));
    }

    #[test]
    fn a_file_name_without_host_has_no_console() {
        let invite = parse_file_name("NeoDesk-Setup-ABCDEF23.exe").unwrap();
        assert_eq!(invite.kind, Some(Kind::Join));
        assert_eq!(invite.console, None);
        assert_eq!(invite.code, "ABCDEF23");
    }

    #[test]
    fn other_file_names_are_not_invites() {
        for name in [
            "NeoDesk.exe",
            "neodesk-1.4.6-windows-x86_64.exe",
            "NeoDesk-Setup.exe",
            "NeoDesk-Setup-desk.example.com.exe",
            "NeoDesk-Setup-desk.example.com-ABCDEF2.exe",
            "NeoDesk-Setup-desk.example.com-ABCD-EF23.exe",
            "NeoDesk-Setup-desk.example.com_x-ABCDEF23.exe",
            "NeoDesk-Setup-desk.example.com_http_5000-ABCDEF23.exe",
            "NeoDesk-Setup-desk.example.com_5000_6000-ABCDEF23.exe",
            "NeoDesk-Setup-desk!.example.com-ABCDEF23.exe",
            "rustdesk-host=desk.example.com.exe",
        ] {
            assert_eq!(parse_file_name(name), None, "{name}");
        }
    }

    #[test]
    fn console_base_reads_back() {
        let base = Console::from_base("https://desk.example.com:8443").unwrap();
        assert_eq!(base, console(true, "desk.example.com", Some(8443)).unwrap());
        assert_eq!(base.base(), "https://desk.example.com:8443");
        assert_eq!(
            Console::from_base("http://desk.lan:5000/").unwrap().base(),
            "http://desk.lan:5000"
        );
        assert_eq!(
            Console::from_base("https://desk.example.com:443").unwrap().base(),
            "https://desk.example.com"
        );
        assert_eq!(Console::from_base("desk.example.com"), None);
    }
}
