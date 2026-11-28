//! The receiver's install-time file: what the installer was told about the
//! server, written next to the app as key=value lines.
//!
//! The receiver MSI writes it from its properties SERVER, KEY, API, TOKEN
//! and GROUP (res/msi, lead/receiver-app/MSI-CONTRACT.md), and the offer
//! after quick support writes it with the server of the session and the
//! session's admission. The app reads it only from its own folder under
//! Program Files and only while nobody but the system and administrators
//! can change the file or the folder ([`only_admins_can_write`]); then it
//! is the receiver, takes the server from it and enrolls with the token,
//! the group or the admission. After the server answered the enrollment the
//! app writes the file again without them ([`InstallFile::without_secrets`]).
//!
//! ```text
//! receiver=Y
//! server=support.example.com:21116
//! key=<the server's public key>
//! api=https://support.example.com
//! token=<enrollment token>
//! group=12
//! ```
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/install_file.rs`.

/// The file's name in the app's folder.
#[allow(dead_code)]
pub const FILE_NAME: &str = "neodesk-install.txt";

/// What the file says. Empty strings are values the installer was not given.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct InstallFile {
    /// `receiver=Y`: the app is the receiver.
    pub receiver: bool,
    /// The ID server, host[:port] (SERVER).
    pub server: String,
    /// The server's public key (KEY).
    pub key: String,
    /// The API address (API).
    pub api: String,
    /// The web console where a bare support code goes; the offer after
    /// quick support knows it, the MSI does not.
    pub console: String,
    /// The enrollment token (TOKEN).
    pub token: String,
    /// The folder, by id or name (GROUP).
    pub group: String,
    /// The one-time admission of a quick support session.
    pub admission: String,
}

/// The longest value taken; anything longer is left out.
const VALUE_MAX: usize = 2048;

impl InstallFile {
    /// Reads the file's text. Keys are taken in any case, blank lines and
    /// lines starting with # are skipped, unknown keys are ignored, and a
    /// value with a control character is left out.
    pub fn parse(text: &str) -> Self {
        let mut file = Self::default();
        let text = text.strip_prefix('\u{feff}').unwrap_or(text);
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let value = value.trim();
            if value.len() > VALUE_MAX || value.chars().any(char::is_control) {
                continue;
            }
            let value = value.to_owned();
            match key.trim().to_ascii_lowercase().as_str() {
                "receiver" => file.receiver = yes(&value),
                "server" => file.server = value,
                "key" => file.key = value,
                "api" => file.api = value,
                "console" => file.console = value,
                "token" => file.token = value,
                "group" => file.group = value,
                "admission" => file.admission = value,
                _ => {}
            }
        }
        file
    }

    /// The file's text: one line per value that is set, in a fixed order.
    pub fn render(&self) -> String {
        let mut out = String::new();
        if self.receiver {
            out.push_str("receiver=Y\n");
        }
        for (name, value) in [
            ("server", &self.server),
            ("key", &self.key),
            ("api", &self.api),
            ("console", &self.console),
            ("token", &self.token),
            ("group", &self.group),
            ("admission", &self.admission),
        ] {
            let value = value.trim();
            if !value.is_empty() && !value.chars().any(char::is_control) {
                out.push_str(name);
                out.push('=');
                out.push_str(value);
                out.push('\n');
            }
        }
        out
    }

    /// Whether the file still holds what admits the computer once.
    pub fn has_secrets(&self) -> bool {
        !self.token.is_empty() || !self.admission.is_empty()
    }

    /// The file once the server has seen the token and the admission: the
    /// same without them. The group goes with the token it belongs to.
    pub fn without_secrets(&self) -> Self {
        Self {
            token: String::new(),
            group: String::new(),
            admission: String::new(),
            ..self.clone()
        }
    }

    /// The API address: API, else https:// and the host of SERVER
    /// (MSI-CONTRACT.md). Empty without both.
    pub fn api_or_default(&self) -> String {
        let api = self.api.trim().trim_end_matches('/');
        if !api.is_empty() {
            return api.to_owned();
        }
        let host = host_of(&self.server);
        if host.is_empty() {
            return String::new();
        }
        if host.contains(':') {
            return format!("https://[{host}]");
        }
        format!("https://{host}")
    }

    /// Where a bare support code goes: the console when the file names one,
    /// else the API address.
    pub fn console_or_api(&self) -> String {
        let console = self.console.trim().trim_end_matches('/');
        if !console.is_empty() {
            return console.to_owned();
        }
        self.api_or_default()
    }

    /// The fields the first registration carries besides the device's own:
    /// `token`, `group` (only next to a token, the only place the server
    /// reads it) and `admission`.
    pub fn enrollment_fields(&self) -> Vec<(&'static str, String)> {
        let mut out = Vec::new();
        if !self.token.is_empty() {
            out.push(("token", self.token.clone()));
            if !self.group.is_empty() {
                out.push(("group", self.group.clone()));
            }
        }
        if !self.admission.is_empty() {
            out.push(("admission", self.admission.clone()));
        }
        out
    }

    /// The hosts this computer's server answers on: SERVER's, the API's and
    /// the console's, lower case.
    pub fn hosts(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for host in [
            host_of(&self.server).to_owned(),
            url_host(&self.api_or_default()),
            url_host(&self.console),
        ] {
            let host = host.to_ascii_lowercase();
            if !host.is_empty() && !out.contains(&host) {
                out.push(host);
            }
        }
        out
    }

    /// Whether a support link of the console at `link_host` (host[:port])
    /// belongs to this computer's server, so the installed app runs its
    /// session with its own ID. A link of another server is not taken.
    pub fn takes_link_of(&self, link_host: &str) -> bool {
        let host = host_of(link_host).to_ascii_lowercase();
        !host.is_empty() && self.hosts().contains(&host)
    }
}

/// The install-time file the offer after quick support asks the installer
/// for (`--install-receiver`): the receiver of a server with its key, and
/// at most the session's admission; a token or a group never comes this
/// way. None for anything else.
pub fn offer_request(text: &str) -> Option<InstallFile> {
    let file = InstallFile::parse(text);
    if !file.receiver || file.server.is_empty() || file.key.is_empty() {
        return None;
    }
    Some(InstallFile {
        token: String::new(),
        group: String::new(),
        ..file
    })
}

fn yes(value: &str) -> bool {
    value.eq_ignore_ascii_case("y") || value.eq_ignore_ascii_case("yes") || value == "1"
}

/// The host of `host[:port]` or `[v6]:port`, without brackets.
pub fn host_of(server: &str) -> &str {
    let server = server.trim();
    if let Some(rest) = server.strip_prefix('[') {
        return rest.split(']').next().unwrap_or("");
    }
    match server.matches(':').count() {
        0 => server,
        1 => server.split(':').next().unwrap_or(""),
        // A bare IPv6 address has no port
        _ => server,
    }
}

/// The host of an http(s) address, without the port.
pub fn url_host(url: &str) -> String {
    let url = url.trim();
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .unwrap_or(url);
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let authority = authority.rsplit('@').next().unwrap_or("");
    host_of(authority).to_owned()
}

/// Whether the app's folder `dir` is a folder below one of the Program
/// Files folders `program_files` (C:\Program Files, C:\Program Files
/// (x86)): only an administrator writes there. Case does not matter; a path
/// with `..` or one that is the Program Files folder itself is refused.
pub fn in_program_files(dir: &str, program_files: &[String]) -> bool {
    let normal = |p: &str| p.replace('/', "\\").trim_end_matches('\\').to_lowercase();
    let dir = normal(dir);
    if dir.is_empty() || dir.split('\\').any(|part| part == ".." || part == ".") {
        return false;
    }
    let dir = dir.strip_prefix(r"\\?\").unwrap_or(&dir);
    program_files.iter().any(|root| {
        let root = normal(root);
        let root = root.strip_prefix(r"\\?\").unwrap_or(&root).to_owned();
        !root.is_empty()
            && dir.len() > root.len() + 1
            && dir.starts_with(&root)
            && dir.as_bytes()[root.len()] == b'\\'
    })
}

/// One entry of a file's or folder's access list, as the app reads it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ace {
    /// The account or group, as a SID string (S-1-5-32-544).
    pub sid: String,
    /// The access mask.
    pub mask: u32,
    /// An allow entry; a deny entry only takes rights away.
    pub allow: bool,
    /// The entry only passes to new files and folders below; it gives no
    /// right on the object itself.
    pub inherit_only: bool,
}

/// The accounts that may change the install-time file: the system,
/// administrators and TrustedInstaller.
pub const TRUSTED_SIDS: &[&str] = &[
    "S-1-5-18",
    "S-1-5-32-544",
    "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464",
];

/// The rights that change a file or what a folder holds: write and append
/// data (add a file, a folder), write attributes and extended attributes,
/// delete a child, delete, change the access list or the owner, and the
/// generic rights that include them.
pub const WRITE_RIGHTS: u32 = 0x0000_0002 // FILE_WRITE_DATA, FILE_ADD_FILE
    | 0x0000_0004 // FILE_APPEND_DATA, FILE_ADD_SUBDIRECTORY
    | 0x0000_0010 // FILE_WRITE_EA
    | 0x0000_0040 // FILE_DELETE_CHILD
    | 0x0000_0100 // FILE_WRITE_ATTRIBUTES
    | 0x0001_0000 // DELETE
    | 0x0004_0000 // WRITE_DAC
    | 0x0008_0000 // WRITE_OWNER
    | 0x0200_0000 // MAXIMUM_ALLOWED
    | 0x1000_0000 // GENERIC_ALL
    | 0x4000_0000; // GENERIC_WRITE

/// Whether only the system, administrators and TrustedInstaller can change
/// an object with this owner and access list. No access list (`None`) gives
/// everyone every right; an owner may always change the list.
pub fn only_admins_can_write(owner: Option<&str>, dacl: Option<&[Ace]>) -> bool {
    let trusted = |sid: &str| TRUSTED_SIDS.iter().any(|t| t.eq_ignore_ascii_case(sid));
    let Some(owner) = owner else {
        return false;
    };
    if !trusted(owner) {
        return false;
    }
    let Some(dacl) = dacl else {
        return false;
    };
    !dacl
        .iter()
        .any(|ace| ace.allow && !ace.inherit_only && ace.mask & WRITE_RIGHTS != 0 && !trusted(&ace.sid))
}

#[cfg(test)]
mod tests {
    use super::*;

    const MSI_FILE: &str = "\u{feff}receiver=Y\r\nserver=support.example.com:21116\r\nkey=a2V5PQ==\r\napi=https://support.example.com\r\ntoken=tok-123\r\ngroup=12\r\n";

    #[test]
    fn the_file_of_the_msi_reads_with_every_value() {
        let file = InstallFile::parse(MSI_FILE);
        assert!(file.receiver);
        assert_eq!(file.server, "support.example.com:21116");
        assert_eq!(file.key, "a2V5PQ==");
        assert_eq!(file.api, "https://support.example.com");
        assert_eq!(file.token, "tok-123");
        assert_eq!(file.group, "12");
        assert_eq!(file.admission, "");
        // What the app writes reads back the same
        assert_eq!(InstallFile::parse(&file.render()), file);
    }

    #[test]
    fn odd_lines_are_left_out() {
        let file = InstallFile::parse(
            "# written by the MSI\n\nRECEIVER = yes\nServer= desk.lan \nnonsense\nunknown=1\nkey=\ntoken=a\u{7}b\n",
        );
        assert!(file.receiver);
        assert_eq!(file.server, "desk.lan");
        assert_eq!(file.key, "");
        assert_eq!(file.token, "", "a value with a control character is left out");
        assert!(!InstallFile::parse("receiver=N\nserver=x").receiver);
        assert!(!InstallFile::parse("").receiver);
        let long = format!("token={}", "x".repeat(VALUE_MAX + 1));
        assert_eq!(InstallFile::parse(&long).token, "");
    }

    #[test]
    fn the_api_defaults_to_https_on_the_servers_host() {
        let mut file = InstallFile::parse("server=support.example.com:21116");
        assert_eq!(file.api_or_default(), "https://support.example.com");
        file.server = "[2001:db8::1]:21116".into();
        assert_eq!(file.api_or_default(), "https://[2001:db8::1]");
        file.api = "https://api.example.com:21121/".into();
        assert_eq!(file.api_or_default(), "https://api.example.com:21121");
        assert_eq!(InstallFile::default().api_or_default(), "");
        // A bare code goes to the console, else to the API
        assert_eq!(file.console_or_api(), "https://api.example.com:21121");
        file.console = "https://desk.example.com".into();
        assert_eq!(file.console_or_api(), "https://desk.example.com");
    }

    #[test]
    fn the_registration_carries_token_group_and_admission() {
        let file = InstallFile::parse(MSI_FILE);
        assert_eq!(
            file.enrollment_fields(),
            vec![("token", "tok-123".to_owned()), ("group", "12".to_owned())]
        );
        let offer = InstallFile::parse("receiver=Y\nserver=x\nadmission=3f9c\ngroup=7");
        assert_eq!(
            offer.enrollment_fields(),
            vec![("admission", "3f9c".to_owned())],
            "a group counts only next to a token"
        );
        assert!(InstallFile::parse("receiver=Y\nserver=x").enrollment_fields().is_empty());
    }

    #[test]
    fn the_token_goes_once_the_server_saw_it() {
        let file = InstallFile::parse(MSI_FILE);
        assert!(file.has_secrets());
        let kept = file.without_secrets();
        assert!(!kept.has_secrets());
        let text = kept.render();
        assert!(!text.contains("token"), "{text}");
        assert!(!text.contains("tok-123"), "{text}");
        assert!(!text.contains("group"), "{text}");
        // Everything else stays: the app is still the receiver of that server
        let again = InstallFile::parse(&text);
        assert!(again.receiver);
        assert_eq!(again.server, file.server);
        assert_eq!(again.key, file.key);
        assert_eq!(again.api, file.api);
        let offer = InstallFile::parse("receiver=Y\nadmission=3f9c").without_secrets();
        assert!(!offer.render().contains("admission"));
    }

    #[test]
    fn only_links_of_this_computers_server_are_taken() {
        let file = InstallFile::parse(MSI_FILE);
        assert!(file.takes_link_of("support.example.com"));
        assert!(file.takes_link_of("SUPPORT.example.com:443"));
        assert!(!file.takes_link_of("other.example.com"));
        assert!(!file.takes_link_of(""));
        let mut api_only = InstallFile::parse("server=10.0.0.5\napi=https://desk.example.com:21121");
        assert!(api_only.takes_link_of("desk.example.com:3375"));
        assert!(api_only.takes_link_of("10.0.0.5"));
        api_only.console = "https://console.example.com".into();
        assert!(api_only.takes_link_of("console.example.com"));
    }

    #[test]
    fn the_offer_installs_a_receiver_with_its_admission_only() {
        let request = offer_request(
            "receiver=Y
server=desk.example.com
key=a2V5
api=https://desk.example.com:21121
console=https://desk.example.com
admission=3f9c
token=sneaked
group=9
",
        )
        .unwrap();
        assert_eq!(request.admission, "3f9c");
        assert_eq!(request.console, "https://desk.example.com");
        assert_eq!(request.token, "");
        assert_eq!(request.group, "");
        assert!(request.render().contains("admission=3f9c
"));
        assert!(offer_request("server=desk.example.com
key=a2V5").is_none());
        assert!(offer_request("receiver=Y
key=a2V5").is_none());
        assert!(offer_request("receiver=Y
server=desk.example.com").is_none());
    }

    #[test]
    fn hosts_and_urls() {
        assert_eq!(host_of("desk.lan:21116"), "desk.lan");
        assert_eq!(host_of("desk.lan"), "desk.lan");
        assert_eq!(host_of("[::1]:21116"), "::1");
        assert_eq!(host_of("2001:db8::1"), "2001:db8::1");
        assert_eq!(url_host("https://user@desk.lan:8443/x?y"), "desk.lan");
        assert_eq!(url_host("http://[::1]:5000/"), "::1");
        assert_eq!(url_host(""), "");
    }

    #[test]
    fn the_file_counts_only_in_a_folder_below_program_files() {
        let roots = vec![
            r"C:\Program Files".to_owned(),
            r"C:\Program Files (x86)".to_owned(),
        ];
        assert!(in_program_files(r"C:\Program Files\NeoDesk Support Agent", &roots));
        assert!(in_program_files(r"c:\program files\neodesk support agent\", &roots));
        assert!(in_program_files(r"\\?\C:\Program Files (x86)\NeoDesk", &roots));
        assert!(!in_program_files(r"C:\Program Files", &roots));
        assert!(!in_program_files(r"C:\Program Files\", &roots));
        assert!(!in_program_files(r"C:\Program FilesX\NeoDesk", &roots));
        assert!(!in_program_files(r"C:\Users\ana\Downloads", &roots));
        assert!(!in_program_files(r"C:\Program Files\..\Users\ana", &roots));
        assert!(!in_program_files(r"D:\Program Files\NeoDesk", &roots));
        assert!(!in_program_files("", &roots));
        assert!(!in_program_files(r"C:\Program Files\NeoDesk", &[]));
    }

    fn ace(sid: &str, mask: u32) -> Ace {
        Ace {
            sid: sid.to_owned(),
            mask,
            allow: true,
            inherit_only: false,
        }
    }

    const USERS: &str = "S-1-5-32-545";
    const AUTHENTICATED_USERS: &str = "S-1-5-11";
    const READ_EXECUTE: u32 = 0x0012_00a9;
    const FULL: u32 = 0x001f_01ff;

    /// The access list a file in a folder below Program Files inherits.
    fn program_files_acl() -> Vec<Ace> {
        vec![
            ace("S-1-5-18", FULL),
            ace("S-1-5-32-544", FULL),
            ace(USERS, READ_EXECUTE),
            ace("S-1-15-2-1", READ_EXECUTE),
        ]
    }

    #[test]
    fn a_file_only_administrators_can_change_is_taken() {
        assert!(only_admins_can_write(Some("S-1-5-32-544"), Some(&program_files_acl())));
        assert!(only_admins_can_write(Some("S-1-5-18"), Some(&program_files_acl())));
        // CREATOR OWNER's full control only passes to new files below
        let mut acl = program_files_acl();
        acl.push(Ace {
            inherit_only: true,
            ..ace("S-1-3-0", 0x1000_0000)
        });
        assert!(only_admins_can_write(Some("S-1-5-32-544"), Some(&acl)));
        // A deny entry takes rights away
        acl.push(Ace {
            allow: false,
            ..ace(USERS, FULL)
        });
        assert!(only_admins_can_write(Some("S-1-5-32-544"), Some(&acl)));
    }

    #[test]
    fn a_file_users_can_change_is_refused() {
        for (sid, mask) in [
            (USERS, 0x0000_0002),             // write data
            (USERS, 0x0000_0004),             // append, or add a folder
            (AUTHENTICATED_USERS, 0x0001_0000), // delete
            (USERS, 0x0004_0000),             // change the access list
            (USERS, 0x4000_0000),             // generic write
            (USERS, 0x0000_0040),             // delete a child, in a folder
            ("S-1-1-0", FULL),                // everyone
            ("S-1-5-21-1-2-3-1001", 0x0000_0002), // one person
        ] {
            let mut acl = program_files_acl();
            acl.push(ace(sid, mask));
            assert!(
                !only_admins_can_write(Some("S-1-5-32-544"), Some(&acl)),
                "{sid} with {mask:#x} can change it"
            );
        }
        // A file a person owns: the owner can change its access list
        assert!(!only_admins_can_write(Some("S-1-5-21-1-2-3-1001"), Some(&program_files_acl())));
        // No access list: everyone has every right
        assert!(!only_admins_can_write(Some("S-1-5-32-544"), None));
        assert!(!only_admins_can_write(None, Some(&program_files_acl())));
    }
}
