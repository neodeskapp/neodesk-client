//! Quick support kept on the computer (Windows).
//!
//! After a session the person can keep the quick support app: the file they
//! downloaded copies itself to their own programs folder under a name
//! without a code ([`FILE_NAME`]), opens `neodesk://support/...` links from
//! then on, starts at sign-in with only a tray icon, and shows up in Apps &
//! installed apps. Everything goes under the person's own account (HKCU and
//! `%LOCALAPPDATA%`), so keeping it asks for no administrator. A kept app
//! still asks before every session and never joins the server.
//!
//! One quick support app runs per Windows session: a second start hands its
//! link (or its Open, or its Remove) to the one that runs ([`Handoff`]) and
//! quits.
//!
//! The paths, the registry entries and the decisions are plain functions
//! here, so they are tested on every platform; [`win`] applies them.

use std::path::{Path, PathBuf};

use hbb_common::config;
use serde_json::{json, Value};

/// The folder under `%LOCALAPPDATA%\Programs`.
pub const FOLDER: &str = "NeoDesk Quick Support";
/// The kept app's file name. It carries no code, so the kept app starts
/// without a session and waits for a link.
pub const FILE_NAME: &str = "NeoDesk-QuickSupport.exe";
/// Starts the kept app at sign-in with only its tray icon.
pub const BACKGROUND_ARG: &str = "--quick-support-background";
/// Remove in Apps & installed apps.
pub const REMOVE_ARG: &str = "--quick-support-remove";
/// The packer passes the full path of the file the person started; the
/// name alone is in `RUSTDESK_APPNAME`.
pub const PACKED_PATH_ENV: &str = "NEODESK_PACKED_PATH";
pub const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
pub const RUN_VALUE: &str = "NeoDesk Quick Support";
pub const UNINSTALL_KEY: &str =
    r"Software\Microsoft\Windows\CurrentVersion\Uninstall\NeoDesk Quick Support";
/// The name in Apps & installed apps.
pub const DISPLAY_NAME: &str = "NeoDesk Quick Support";
const PUBLISHER: &str = "NeoDesk";
/// The IPC name a running quick support app takes handoffs on.
const HANDOFF_IPC: &str = "_qs_handoff";

/// `HKCU\Software\Classes\neodesk`.
pub fn scheme_key() -> String {
    format!(r"Software\Classes\{}", config::URI_SCHEME)
}

pub fn scheme_command_key() -> String {
    format!(r"{}\shell\open\command", scheme_key())
}

/// The kept app's folder.
pub fn folder(local_app_data: &Path) -> PathBuf {
    local_app_data.join("Programs").join(FOLDER)
}

/// The kept app.
pub fn exe(local_app_data: &Path) -> PathBuf {
    folder(local_app_data).join(FILE_NAME)
}

/// True for the kept app's file name, with or without a folder.
pub fn is_kept_file(path: &str) -> bool {
    path.rsplit(['/', '\\'])
        .next()
        .map_or(false, |name| name.trim().eq_ignore_ascii_case(FILE_NAME))
}

/// The IPC name of the quick support app in the Windows session `session`,
/// so two people signed in at once each have their own.
pub fn handoff_ipc(session: Option<u32>) -> String {
    match session {
        Some(session) => format!("{HANDOFF_IPC}_{session}"),
        None => HANDOFF_IPC.to_owned(),
    }
}

fn quoted(path: &Path) -> String {
    format!("\"{}\"", path.display())
}

/// Registry data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Data {
    Text(String),
    Number(u32),
}

/// A value under HKCU: the key, the value's name ("" for the default) and
/// its data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub key: String,
    pub name: String,
    pub data: Data,
}

impl Entry {
    fn text(key: &str, name: &str, text: impl Into<String>) -> Self {
        Self {
            key: key.to_owned(),
            name: name.to_owned(),
            data: Data::Text(text.into()),
        }
    }

    fn number(key: &str, name: &str, number: u32) -> Self {
        Self {
            key: key.to_owned(),
            name: name.to_owned(),
            data: Data::Number(number),
        }
    }
}

/// What keeping writes under HKCU for the kept app at `exe`: autostart in
/// the background, the entry in Apps & installed apps, and neodesk:// when
/// `scheme`. Without a full NeoDesk on the computer `scheme` is true; with
/// one its machine-wide neodesk:// stays in charge, which an entry under
/// HKCU would override.
pub fn entries(exe: &Path, version: &str, size_kb: u32, scheme: bool) -> Vec<Entry> {
    let program = quoted(exe);
    let folder = exe.parent().map(|dir| dir.display().to_string()).unwrap_or_default();
    let mut entries = Vec::new();
    if scheme {
        let key = scheme_key();
        entries.push(Entry::text(&key, "", format!("URL:{} Protocol", config::URI_SCHEME)));
        entries.push(Entry::text(&key, "URL Protocol", ""));
        entries.push(Entry::text(&format!(r"{key}\DefaultIcon"), "", format!("{program},0")));
        entries.push(Entry::text(&scheme_command_key(), "", format!("{program} \"%1\"")));
    }
    entries.push(Entry::text(RUN_KEY, RUN_VALUE, format!("{program} {BACKGROUND_ARG}")));
    let remove = format!("{program} {REMOVE_ARG}");
    entries.extend([
        Entry::text(UNINSTALL_KEY, "DisplayName", DISPLAY_NAME),
        Entry::text(UNINSTALL_KEY, "DisplayIcon", format!("{program},0")),
        Entry::text(UNINSTALL_KEY, "DisplayVersion", version),
        Entry::text(UNINSTALL_KEY, "Publisher", PUBLISHER),
        Entry::text(UNINSTALL_KEY, "InstallLocation", folder),
        Entry::text(UNINSTALL_KEY, "UninstallString", remove.clone()),
        Entry::text(UNINSTALL_KEY, "QuietUninstallString", remove),
        Entry::number(UNINSTALL_KEY, "NoModify", 1),
        Entry::number(UNINSTALL_KEY, "NoRepair", 1),
        Entry::number(UNINSTALL_KEY, "EstimatedSize", size_kb),
    ]);
    entries
}

/// The program a registry command starts, without quotes and arguments.
fn program_of(command: &str) -> &str {
    let command = command.trim();
    match command.strip_prefix('"') {
        Some(rest) => rest.split('"').next().unwrap_or_default(),
        None => command.split(' ').next().unwrap_or_default(),
    }
}

/// True when the open command `command` starts the kept app at `exe`.
pub fn opens(command: &str, exe: &Path) -> bool {
    let program = program_of(command).replace('/', "\\");
    let exe = exe.display().to_string().replace('/', "\\");
    !program.is_empty() && program.eq_ignore_ascii_case(&exe)
}

/// What removing deletes under HKCU.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Removal {
    /// Keys deleted with everything under them.
    pub keys: Vec<String>,
    /// Single values: key and name.
    pub values: Vec<(String, String)>,
}

/// What removing the kept app at `exe` deletes under HKCU: the uninstall
/// entry, the autostart, and neodesk:// when its open command
/// (`scheme_command`, if there is one) starts the kept app. A neodesk:// of
/// a full NeoDesk stays.
pub fn removal(exe: &Path, scheme_command: Option<&str>) -> Removal {
    let mut keys = vec![UNINSTALL_KEY.to_owned()];
    if scheme_command.map_or(false, |command| opens(command, exe)) {
        keys.push(scheme_key());
    }
    Removal {
        keys,
        values: vec![(RUN_KEY.to_owned(), RUN_VALUE.to_owned())],
    }
}

/// How a quick support app was started, as far as one that runs already
/// takes over.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Launch {
    /// At sign-in: only the tray icon.
    Background,
    /// The kept app started by hand: its window.
    Open,
    /// Remove in Apps & installed apps.
    Remove,
    /// A support link, from a downloaded file's name or from the command line.
    Link(String),
}

/// How a quick support process with the arguments `args` (without the
/// program) was started. `pending` is the support link of its file name or
/// arguments; `kept` is true for the kept app. None for the processes a
/// quick support app starts itself (connection manager and the like), which
/// inherit the file name and so the link, but have arguments of their own.
pub fn launch_of(args: &[String], pending: Option<&str>, kept: bool) -> Option<Launch> {
    let link = || pending.map(|link| Launch::Link(link.to_owned()));
    match args {
        [arg] if kept && arg == REMOVE_ARG => Some(Launch::Remove),
        [arg] if kept && arg == BACKGROUND_ARG => Some(Launch::Background),
        [] => link().or(kept.then_some(Launch::Open)),
        [arg] if crate::common::is_supported_uni_link(arg) => link(),
        [flag, _] if flag == "--join" => link(),
        _ => None,
    }
}

/// What a quick support app hands to the one that runs, which then does it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Handoff {
    /// Only asks whether one runs (a second start at sign-in).
    Ping,
    /// Show the window.
    Show,
    /// Remove the kept app and quit.
    Remove,
    /// Start a session for `link`. `file` is the downloaded file it came
    /// from, which a kept app deletes: it opens the next links itself.
    Open { link: String, file: Option<String> },
}

impl Handoff {
    /// The handoff for a start, with the file it was started from.
    pub fn of(launch: &Launch, file: Option<&str>) -> Self {
        match launch {
            Launch::Background => Handoff::Ping,
            Launch::Open => Handoff::Show,
            Launch::Remove => Handoff::Remove,
            Launch::Link(link) => Handoff::Open {
                link: link.clone(),
                file: file.filter(|f| !f.trim().is_empty()).map(str::to_owned),
            },
        }
    }

    pub fn encode(&self) -> String {
        match self {
            Handoff::Ping => json!({ "do": "ping" }),
            Handoff::Show => json!({ "do": "show" }),
            Handoff::Remove => json!({ "do": "remove" }),
            Handoff::Open { link, file } => json!({ "do": "open", "link": link, "file": file }),
        }
        .to_string()
    }

    pub fn decode(text: &str) -> Option<Self> {
        let value: Value = serde_json::from_str(text).ok()?;
        match value.get("do")?.as_str()? {
            "ping" => Some(Handoff::Ping),
            "show" => Some(Handoff::Show),
            "remove" => Some(Handoff::Remove),
            "open" => Some(Handoff::Open {
                link: value.get("link")?.as_str()?.to_owned(),
                file: value.get("file").and_then(Value::as_str).map(str::to_owned),
            }),
            _ => None,
        }
    }
}

/// What a kept app does when it starts without a link: it removes itself
/// once a full NeoDesk is on the computer, which is for team members and
/// opens support links itself.
pub fn stays(full_client_installed: bool) -> bool {
    !full_client_installed
}

/// Whether a downloaded file handed over with a link may be deleted by the
/// kept app: only a quick support file, never the kept app itself.
pub fn deletes_handed_file(file: &str) -> bool {
    !is_kept_file(file)
        && super::link::parse_file_name(file)
            .map_or(false, |invite| invite.kind == Some(super::link::Kind::Support))
}

/// The Windows side: the files, the registry and the handoff pipe.
#[cfg(windows)]
pub mod win {
    use std::{
        os::windows::process::CommandExt,
        path::{Path, PathBuf},
    };

    use hbb_common::{config, log};
    use winreg::{enums::*, RegKey};

    use super::{Data, Removal};

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    pub fn local_app_data() -> Option<PathBuf> {
        std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .filter(|dir| dir.is_dir())
    }

    /// The kept app's path.
    pub fn exe() -> Option<PathBuf> {
        local_app_data().map(|dir| super::exe(&dir))
    }

    /// The file the person started: the packed exe, as the packer passes it.
    pub fn started_file() -> Option<PathBuf> {
        std::env::var_os(super::PACKED_PATH_ENV)
            .map(PathBuf::from)
            .filter(|path| path.is_file())
    }

    /// The pipe name of this Windows session.
    pub fn handoff_ipc() -> String {
        super::handoff_ipc(crate::platform::windows::get_current_process_session_id())
    }

    /// True when a full NeoDesk named `app_name` is installed for the whole
    /// computer: its uninstall entry points to a folder with the client, or
    /// the machine-wide neodesk:// starts a program that is not the kept app.
    pub fn full_client_installed(app_name: &str) -> bool {
        let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
        let exe_name = format!("{}.exe", config::EXE_NAME);
        let uninstall = [
            format!(r"Software\{app_name}\InstallState\{app_name}"),
            format!(r"Software\Microsoft\Windows\CurrentVersion\Uninstall\{app_name}"),
            format!(r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{app_name}"),
        ];
        for key in uninstall {
            let location = hklm
                .open_subkey(&key)
                .and_then(|key| key.get_value::<String, _>("InstallLocation"))
                .unwrap_or_default();
            let location = location.trim().trim_matches('"').trim_end_matches('\\');
            if !location.is_empty() && Path::new(location).join(&exe_name).is_file() {
                return true;
            }
        }
        let command = hklm
            .open_subkey(super::scheme_command_key())
            .and_then(|key| key.get_value::<String, _>(""))
            .unwrap_or_default();
        let program = super::program_of(&command);
        !program.is_empty() && !super::is_kept_file(program) && Path::new(program).is_file()
    }

    /// Copies the file the person started to the kept app's place and
    /// writes the registry. With the kept app's path, and the downloaded
    /// file when it is another one (the caller deletes it).
    pub fn keep(full_client: bool) -> Result<(PathBuf, Option<PathBuf>), String> {
        let source = started_file().ok_or("the started file is not known")?;
        let target = exe().ok_or("no LOCALAPPDATA")?;
        let dir = target.parent().ok_or("no folder")?;
        std::fs::create_dir_all(dir).map_err(|err| format!("{}: {err}", dir.display()))?;
        let same = same_file(&source, &target);
        if !same {
            std::fs::copy(&source, &target)
                .map_err(|err| format!("copy to {}: {err}", target.display()))?;
            // The copy is an installed program now, not a download.
            std::fs::remove_file(format!("{}:Zone.Identifier", target.display())).ok();
        }
        let size_kb = std::fs::metadata(&target)
            .map(|m| (m.len() / 1024).min(u32::MAX as u64) as u32)
            .unwrap_or(0);
        let entries = super::entries(&target, crate::VERSION, size_kb, super::stays(full_client));
        write(&entries)?;
        Ok((target, (!same).then_some(source)))
    }

    fn same_file(a: &Path, b: &Path) -> bool {
        match (a.canonicalize(), b.canonicalize()) {
            (Ok(a), Ok(b)) => a == b,
            _ => false,
        }
    }

    fn write(entries: &[super::Entry]) -> Result<(), String> {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        for entry in entries {
            let (key, _) = hkcu
                .create_subkey(&entry.key)
                .map_err(|err| format!("{}: {err}", entry.key))?;
            let set = match &entry.data {
                Data::Text(text) => key.set_value(&entry.name, text),
                Data::Number(number) => key.set_value(&entry.name, number),
            };
            set.map_err(|err| format!("{}\\{}: {err}", entry.key, entry.name))?;
        }
        Ok(())
    }

    /// True when the kept app is in its place.
    pub fn is_kept() -> bool {
        exe().map_or(false, |exe| exe.is_file())
    }

    /// Removes the kept app's registry entries and its folder. The folder
    /// goes once this process has quit when it can't go now.
    pub fn remove_kept() {
        let Some(exe) = exe() else {
            return;
        };
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let command = hkcu
            .open_subkey(super::scheme_command_key())
            .and_then(|key| key.get_value::<String, _>(""))
            .ok();
        let Removal { keys, values } = super::removal(&exe, command.as_deref());
        for key in keys {
            if let Err(err) = hkcu.delete_subkey_all(&key) {
                if err.kind() != std::io::ErrorKind::NotFound {
                    log::warn!("Quick support: {key} stays: {err}");
                }
            }
        }
        for (key, name) in values {
            if let Ok(key) = hkcu.open_subkey_with_flags(&key, KEY_SET_VALUE) {
                key.delete_value(&name).ok();
            }
        }
        if let Some(dir) = exe.parent() {
            if dir.exists() && std::fs::remove_dir_all(dir).is_err() {
                delete_later(dir);
            }
        }
        log::info!("Quick support removed from this computer");
    }

    /// A newer quick support file opened while the kept app runs: it
    /// replaces the kept app, which starts from it next time. The running
    /// app goes on as it is.
    pub fn adopt(file: &Path) {
        let Some(target) = exe() else {
            return;
        };
        if same_file(file, &target) {
            return;
        }
        let differs = match (std::fs::read(file), std::fs::read(&target)) {
            (Ok(new), Ok(old)) => new != old,
            _ => false,
        };
        if differs {
            match std::fs::copy(file, &target) {
                Ok(_) => {
                    std::fs::remove_file(format!("{}:Zone.Identifier", target.display())).ok();
                    log::info!("Quick support: the kept app is now {}", file.display());
                }
                Err(err) => log::warn!("Quick support: the kept app stays as it was: {err}"),
            }
        }
    }

    /// Deletes the file `path` now, or once this process has quit.
    pub fn delete_file(path: &Path) {
        if path.is_file() && std::fs::remove_file(path).is_err() {
            delete_later(path);
        }
    }

    /// Deletes `path` (a file or a folder) a few seconds from now, from a
    /// command prompt without a window, after this process has quit.
    fn delete_later(path: &Path) {
        let path = path.display().to_string();
        let delete = if Path::new(&path).is_dir() {
            format!("rmdir /s /q \"{path}\"")
        } else {
            format!("del /f /q \"{path}\"")
        };
        let script = format!("ping -n 4 127.0.0.1 > nul & {delete}");
        if let Err(err) = std::process::Command::new("cmd.exe")
            .arg("/c")
            .raw_arg(&script)
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
        {
            log::warn!("Quick support could not delete {path}: {err}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    fn local() -> PathBuf {
        PathBuf::from(r"C:\Users\ana\AppData\Local")
    }

    #[test]
    fn the_kept_app_lives_in_the_persons_programs_folder() {
        let exe = exe(&local());
        assert_eq!(exe.file_name().unwrap(), FILE_NAME);
        assert_eq!(exe.parent().unwrap().file_name().unwrap(), FOLDER);
        assert_eq!(
            exe.parent().unwrap().parent().unwrap().file_name().unwrap(),
            "Programs"
        );
        assert!(exe.starts_with(local()));
    }

    #[test]
    fn the_kept_name_is_quick_support_without_a_code() {
        assert!(is_kept_file("NeoDesk-QuickSupport.exe"));
        assert!(is_kept_file(r"C:\x\neodesk-quicksupport.EXE"));
        assert!(is_kept_file("/tmp/NeoDesk-QuickSupport.exe"));
        assert!(!is_kept_file("NeoDesk-QuickSupport-desk.example.com-ABCDEF23.exe"));
        assert!(!is_kept_file("NeoDesk.exe"));
        // Still read as quick support, and without an invite
        assert!(super::super::link::parse_file_name(FILE_NAME).is_none());
    }

    #[test]
    fn keeping_registers_the_link_only_without_a_full_neodesk() {
        let exe = exe(&local());
        let with = entries(&exe, "3.6.20", 9000, true);
        let without = entries(&exe, "3.6.20", 9000, false);
        let command = format!(r#""{}" "%1""#, exe.display());
        assert!(with.contains(&Entry::text(&scheme_command_key(), "", command.clone())));
        assert!(with.contains(&Entry::text(&scheme_key(), "URL Protocol", "")));
        assert!(without.iter().all(|e| !e.key.starts_with(&scheme_key())));
        assert_eq!(scheme_key(), r"Software\Classes\neodesk");
        for entries in [&with, &without] {
            assert!(entries.contains(&Entry::text(
                RUN_KEY,
                RUN_VALUE,
                format!(r#""{}" --quick-support-background"#, exe.display())
            )));
            assert!(entries.contains(&Entry::text(
                UNINSTALL_KEY,
                "UninstallString",
                format!(r#""{}" --quick-support-remove"#, exe.display())
            )));
            assert!(entries.contains(&Entry::text(UNINSTALL_KEY, "DisplayName", DISPLAY_NAME)));
            assert!(entries.contains(&Entry::number(UNINSTALL_KEY, "EstimatedSize", 9000)));
            // Everything goes under the person's own account
            assert!(entries.iter().all(|e| e.key.starts_with(r"Software\")));
        }
    }

    #[test]
    fn removing_leaves_a_full_neodesks_link_alone() {
        let exe = exe(&local());
        let ours = format!(r#""{}" "%1""#, exe.display());
        let theirs = r#""C:\Program Files\NeoDesk\neodesk.exe" "%1""#;
        assert!(removal(&exe, Some(&ours)).keys.contains(&scheme_key()));
        assert!(!removal(&exe, Some(theirs)).keys.contains(&scheme_key()));
        assert!(!removal(&exe, None).keys.contains(&scheme_key()));
        let removal = removal(&exe, None);
        assert!(removal.keys.contains(&UNINSTALL_KEY.to_owned()));
        assert_eq!(removal.values, vec![(RUN_KEY.to_owned(), RUN_VALUE.to_owned())]);
    }

    #[test]
    fn an_open_command_names_its_program() {
        let exe = exe(&local());
        assert!(opens(&format!(r#""{}" "%1""#, exe.display()), &exe));
        assert!(opens(
            &format!(r#""{}" "%1""#, exe.display().to_string().to_uppercase()),
            &exe
        ));
        assert!(!opens(r#""C:\Program Files\NeoDesk\neodesk.exe" "%1""#, &exe));
        assert!(!opens("", &exe));
    }

    #[test]
    fn each_start_says_what_the_running_app_does() {
        let link = "neodesk://support/desk.example.com/ABCDEF23";
        assert_eq!(launch_of(&args(&[REMOVE_ARG]), None, true), Some(Launch::Remove));
        assert_eq!(
            launch_of(&args(&[BACKGROUND_ARG]), None, true),
            Some(Launch::Background)
        );
        // A downloaded file carries its link in its name
        assert_eq!(
            launch_of(&[], Some(link), false),
            Some(Launch::Link(link.to_owned()))
        );
        // The kept app started by hand
        assert_eq!(launch_of(&[], None, true), Some(Launch::Open));
        // A link from the browser, and from an installed NeoDesk
        assert_eq!(
            launch_of(&args(&[link]), Some(link), true),
            Some(Launch::Link(link.to_owned()))
        );
        assert_eq!(
            launch_of(&args(&["--join", link]), Some(link), false),
            Some(Launch::Link(link.to_owned()))
        );
        // The connection manager and the other helpers of a session carry
        // the downloaded file's name, and so its link, too
        assert_eq!(launch_of(&args(&["--cm"]), Some(link), false), None);
        assert_eq!(launch_of(&args(&["--cm-no-ui"]), None, true), None);
        assert_eq!(
            launch_of(&args(&["--portable-service-shmem-name=x"]), Some(link), false),
            None
        );
        assert_eq!(launch_of(&[], None, false), None);
        // Only the kept app has the background and the remove start
        assert_eq!(launch_of(&args(&[BACKGROUND_ARG]), Some(link), false), None);
        assert_eq!(launch_of(&args(&[REMOVE_ARG]), Some(link), false), None);
    }

    #[test]
    fn handoffs_reach_the_running_app_as_sent() {
        let link = "neodesk://support/desk.example.com/ABCDEF23";
        let file = r"C:\Users\ana\Downloads\NeoDesk-QuickSupport-desk.example.com-ABCDEF23.exe";
        for handoff in [
            Handoff::Ping,
            Handoff::Show,
            Handoff::Remove,
            Handoff::of(&Launch::Link(link.into()), Some(file)),
            Handoff::of(&Launch::Link(link.into()), None),
        ] {
            assert_eq!(Handoff::decode(&handoff.encode()), Some(handoff));
        }
        assert_eq!(
            Handoff::of(&Launch::Link(link.into()), Some(file)),
            Handoff::Open {
                link: link.into(),
                file: Some(file.into())
            }
        );
        assert_eq!(Handoff::of(&Launch::Background, None), Handoff::Ping);
        assert_eq!(Handoff::of(&Launch::Open, None), Handoff::Show);
        assert_eq!(Handoff::decode("{\"do\":\"format c:\"}"), None);
        assert_eq!(Handoff::decode("open"), None);
        assert_eq!(Handoff::decode("{\"do\":\"open\"}"), None);
    }

    #[test]
    fn each_windows_session_has_its_own_handoff() {
        assert_ne!(handoff_ipc(Some(1)), handoff_ipc(Some(2)));
        assert_eq!(handoff_ipc(None), "_qs_handoff");
    }

    #[test]
    fn a_kept_app_goes_once_a_full_neodesk_is_installed() {
        assert!(stays(false));
        assert!(!stays(true));
    }

    #[test]
    fn only_a_downloaded_quick_support_file_is_deleted_on_handoff() {
        assert!(deletes_handed_file(
            r"C:\Users\ana\Downloads\NeoDesk-QuickSupport-desk.example.com-ABCDEF23.exe"
        ));
        assert!(!deletes_handed_file(&exe(&local()).display().to_string()));
        assert!(!deletes_handed_file(r"C:\Users\ana\Downloads\setup.exe"));
        assert!(!deletes_handed_file(
            r"C:\Users\ana\Downloads\NeoDesk-Setup-desk.example.com-ABCDEF23.exe"
        ));
    }
}
