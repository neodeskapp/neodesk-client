//! Lines of the elevated install script that name the app. The app name is
//! the service name and the name of the install folder, the shortcuts and
//! the registry keys, and a custom client's name can hold spaces,
//! apostrophes, `&`, brackets and letters outside ASCII.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/platform/windows/install_commands.rs`.

/// Refuses a name the install can't use. Inside double quotes cmd.exe takes
/// every character literally except `"` and `%` (the script runs with
/// delayed expansion off), and the other characters here can't be in a
/// folder or shortcut name.
pub fn validate_app_name(name: &str) -> Result<(), String> {
    const REFUSED: &[char] = &['"', '%', '\\', '/', ':', '*', '?', '<', '>', '|'];
    if name.trim().is_empty() {
        return Err("The application name is empty.".to_owned());
    }
    if name.trim() != name || name.ends_with('.') {
        return Err(format!(
            "The application name \"{name}\" starts or ends with a space or ends with a dot, which Windows drops from folder names."
        ));
    }
    // The longest name a Windows service can have.
    if name.encode_utf16().count() > 256 {
        return Err("The application name is longer than 256 characters.".to_owned());
    }
    if let Some(c) = name.chars().find(|c| REFUSED.contains(c) || c.is_control()) {
        return Err(format!(
            "The application name {name:?} contains {c:?}, which Windows does not allow in a folder or shortcut name or which the installer cannot pass on."
        ));
    }
    Ok(())
}

/// `"value"`, one argument for cmd.exe and for the program it starts.
pub fn quoted(value: &str) -> String {
    format!("\"{value}\"")
}

/// A value inside `\"...\"` of a quoted argument stands outside cmd.exe's
/// quotes, so its `^` and `&` need a caret.
fn nested(value: &str) -> String {
    value.replace('^', "^^").replace('&', "^&")
}

pub fn stop_service(name: &str) -> String {
    format!("sc stop {}", quoted(name))
}

pub fn delete_service(name: &str) -> String {
    format!("sc delete {}", quoted(name))
}

pub fn start_service(name: &str) -> String {
    format!("sc start {}", quoted(name))
}

/// Creates the service `name` that runs `exe --service`, or points an
/// existing one at `exe`, and starts it. Two lines instead of an
/// `if (...) else (...)` block, which a `)` in the unquoted `exe` would end.
pub fn create_service(name: &str, exe: &str) -> String {
    let display = quoted(&format!("{name} Service"));
    let name = quoted(name);
    let exe = nested(exe);
    format!(
        "
sc query {name} >nul 2>&1 && sc config {name} binpath= \"\\\"{exe}\\\" --service\" start= auto
sc query {name} >nul 2>&1 || sc create {name} binpath= \"\\\"{exe}\\\" --service\" start= auto DisplayName= {display}
sc failure {name} reset= 86400 actions= restart/5000/restart/10000/restart/30000
sc failureflag {name} 1
sc start {name}
"
    )
}

/// Runs `exe --import-config config_path` once as the service `name`, which
/// copies the user's settings into the service's profile.
pub fn import_config_service(name: &str, exe: &str, config_path: &str) -> String {
    let display = quoted(&format!("{name} Service"));
    let name = quoted(name);
    let exe = nested(exe);
    let config_path = nested(config_path);
    format!(
        "
sc stop {name}
sc delete {name}
sc create {name} binpath= \"\\\"{exe}\\\" --import-config \\\"{config_path}\\\"\" start= auto DisplayName= {display}
sc start {name}
sc stop {name}
sc delete {name}
"
    )
}

/// Ends the processes of the client's executable `exe_name`.exe; `filter`
/// is empty or a taskkill ` /FI "..."` filter.
pub fn kill_processes(exe_name: &str, filter: &str) -> String {
    format!(
        "taskkill /F /IM {}{filter}",
        quoted(&format!("{exe_name}.exe"))
    )
}

/// `reg add` of the file class `.ext` and the link class `ext` that open
/// `exe`.
pub fn add_app_classes(ext: &str, exe: &str) -> String {
    let file_class = format!("HKEY_CLASSES_ROOT\\.{ext}");
    let link_class = format!("HKEY_CLASSES_ROOT\\{ext}");
    let key = |class: &str, sub: &str| quoted(&format!("{class}{sub}"));
    let (file, icon, file_shell, file_open, file_command) = (
        key(&file_class, ""),
        key(&file_class, "\\DefaultIcon"),
        key(&file_class, "\\shell"),
        key(&file_class, "\\shell\\open"),
        key(&file_class, "\\shell\\open\\command"),
    );
    let (link, link_shell, link_open, link_command) = (
        key(&link_class, ""),
        key(&link_class, "\\shell"),
        key(&link_class, "\\shell\\open"),
        key(&link_class, "\\shell\\open\\command"),
    );
    let exe = nested(exe);
    format!(
        "
reg add {file} /f
reg add {icon} /f
reg add {icon} /f /ve /t REG_SZ  /d \"\\\"{exe}\\\",0\"
reg add {file_shell} /f
reg add {file_open} /f
reg add {file_command} /f
reg add {file_command} /f /ve /t REG_SZ /d \"\\\"{exe}\\\" --play \\\"%%1\\\"\"
reg add {link} /f
reg add {link} /f /v \"URL Protocol\" /t REG_SZ /d \"\"
reg add {link_shell} /f
reg add {link_open} /f
reg add {link_command} /f
reg add {link_command} /f /ve /t REG_SZ /d \"\\\"{exe}\\\" \\\"%%1\\\"\"
"
    )
}

/// Stores the install option `option` = `value` in the file class `.ext`.
pub fn add_install_option(ext: &str, option: &str, value: &str) -> String {
    format!(
        "reg add {} /f /v {option} /t REG_SZ /d \"{value}\"",
        quoted(&format!("HKEY_CLASSES_ROOT\\.{ext}"))
    )
}

pub fn delete_app_classes(ext: &str) -> String {
    format!(
        "reg delete {} /f\nreg delete {} /f",
        quoted(&format!("HKEY_CLASSES_ROOT\\.{ext}")),
        quoted(&format!("HKEY_CLASSES_ROOT\\{ext}"))
    )
}

/// The marker font's file name in the Fonts folder. The console's support
/// page measures the font by its family name to tell that NeoDesk is
/// installed (res/marker-font).
pub const MARKER_FONT_FILE: &str = "NeoDeskMarker.ttf";
/// The font's registry value: its full name and the format.
pub const MARKER_FONT_VALUE: &str = "NeoDesk Marker Regular (TrueType)";
const FONTS_KEY: &str = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts";

/// Writes the marker font, `encoded` in base64, into the Fonts folder and
/// registers it. Any of these lines may fail (a font file in use, no
/// certutil) without stopping the install: none of them ends the script.
pub fn add_marker_font(encoded: &str) -> String {
    let staged = format!("%RUSTDESK_OUTPUT_DIR%\\{MARKER_FONT_FILE}");
    let installed = format!("%WINDIR%\\Fonts\\{MARKER_FONT_FILE}");
    format!(
        "
> \"%~f0.marker_font.b64\" echo {encoded}
certutil -f -decode \"%~f0.marker_font.b64\" \"{staged}\" >nul 2>&1
if exist \"{staged}\" copy /Y \"{staged}\" \"{installed}\" >nul 2>&1
if exist \"{installed}\" reg add {key} /f /v {value} /t REG_SZ /d {file} >nul 2>&1
if exist \"{staged}\" del /f /q \"{staged}\"
if exist \"%~f0.marker_font.b64\" del /f /q \"%~f0.marker_font.b64\"
",
        key = quoted(FONTS_KEY),
        value = quoted(MARKER_FONT_VALUE),
        file = quoted(MARKER_FONT_FILE),
    )
}

/// Unregisters the marker font and deletes its file. A font in use stays
/// until the next uninstall or a reinstall overwrites it.
pub fn remove_marker_font() -> String {
    let installed = format!("%WINDIR%\\Fonts\\{MARKER_FONT_FILE}");
    format!(
        "
reg delete {key} /f /v {value} >nul 2>&1
if exist \"{installed}\" del /f /q \"{installed}\" >nul 2>&1
",
        key = quoted(FONTS_KEY),
        value = quoted(MARKER_FONT_VALUE),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const NAMES: &[&str] = &[
        "NeoDesk Client",
        "NeoDesk Support Agent",
        "Müller & Söhne IT",
        "O'Brien (Support)!",
        "Caret^Desk",
        "远程协助",
    ];

    fn exe_of(name: &str) -> String {
        format!(r"C:\Program Files\{name}\neodesk.exe")
    }

    /// The commands cmd.exe runs for one batch file line, each as the
    /// argument list its program gets: `%%` made `%`, the line split at
    /// `&&`, `||`, `&` and `|` outside quotes, redirections dropped, carets
    /// outside quotes removed, then each command split by the C runtime's
    /// rules.
    fn commands(line: &str) -> Vec<Vec<String>> {
        let mut raw = vec![String::new()];
        let mut chars = line.chars().peekable();
        let mut in_quotes = false;
        while let Some(c) = chars.next() {
            if c == '%' {
                assert_eq!(chars.next(), Some('%'), "a single % expands in {line:?}");
                raw.last_mut().unwrap().push('%');
                continue;
            }
            if in_quotes {
                in_quotes = c != '"';
                raw.last_mut().unwrap().push(c);
                continue;
            }
            match c {
                '"' => {
                    in_quotes = true;
                    raw.last_mut().unwrap().push(c);
                }
                '^' => {
                    if let Some(next) = chars.next() {
                        raw.last_mut().unwrap().push(next);
                    }
                }
                '&' | '|' => {
                    if chars.peek() == Some(&c) {
                        chars.next();
                    }
                    raw.push(String::new());
                }
                '>' | '<' => {
                    let current = raw.last_mut().unwrap();
                    if current.ends_with(|d: char| d.is_ascii_digit()) {
                        current.pop();
                    }
                    if chars.peek() == Some(&'&') {
                        chars.next();
                    }
                    while chars.peek() == Some(&' ') {
                        chars.next();
                    }
                    while chars.peek().map_or(false, |d| !d.is_whitespace()) {
                        chars.next();
                    }
                }
                _ => raw.last_mut().unwrap().push(c),
            }
        }
        raw.iter()
            .map(|command| argv(command))
            .filter(|args| !args.is_empty())
            .collect()
    }

    /// Splits a command line like the C runtime of the program it starts.
    fn argv(command: &str) -> Vec<String> {
        let mut args = Vec::new();
        let mut current = String::new();
        let mut started = false;
        let mut in_quotes = false;
        let chars: Vec<char> = command.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            let c = chars[i];
            if c == '\\' {
                let start = i;
                while i < chars.len() && chars[i] == '\\' {
                    i += 1;
                }
                let count = i - start;
                if i < chars.len() && chars[i] == '"' {
                    current.push_str(&"\\".repeat(count / 2));
                    if count % 2 == 1 {
                        current.push('"');
                        i += 1;
                    }
                } else {
                    current.push_str(&"\\".repeat(count));
                }
                started = true;
                continue;
            }
            if c == '"' {
                if in_quotes && chars.get(i + 1) == Some(&'"') {
                    current.push('"');
                    i += 2;
                    continue;
                }
                in_quotes = !in_quotes;
                started = true;
            } else if c.is_whitespace() && !in_quotes {
                if started {
                    args.push(std::mem::take(&mut current));
                    started = false;
                }
            } else {
                current.push(c);
                started = true;
            }
            i += 1;
        }
        if started {
            args.push(current);
        }
        args
    }

    fn script_commands(script: &str) -> Vec<Vec<String>> {
        script.lines().flat_map(commands).collect()
    }

    fn find<'a>(commands: &'a [Vec<String>], start: &[&str]) -> &'a Vec<String> {
        commands
            .iter()
            .find(|args| args.len() >= start.len() && args[..start.len()] == *start)
            .unwrap_or_else(|| panic!("no command starts with {start:?} in {commands:?}"))
    }

    fn assert_only_programs(commands: &[Vec<String>], programs: &[&str]) {
        for args in commands {
            assert!(
                programs.contains(&args[0].as_str()),
                "unexpected command {args:?}"
            );
        }
    }

    #[test]
    fn names_windows_can_use_are_accepted() {
        for name in NAMES
            .iter()
            .chain(&["RustDesk", "RustDesk-Admin1", "RustDesk_Admin"])
        {
            assert_eq!(validate_app_name(name), Ok(()), "{name}");
        }
    }

    #[test]
    fn names_that_break_the_script_or_a_file_name_are_refused() {
        let long = "a".repeat(257);
        for name in [
            "",
            " ",
            "NeoDesk ",
            " NeoDesk",
            "NeoDesk.",
            "Neo\"Desk",
            "100% Desk",
            "Neo\\Desk",
            "Neo/Desk",
            "Neo:Desk",
            "Neo*Desk",
            "Neo?Desk",
            "Neo<Desk",
            "Neo>Desk",
            "Neo|Desk",
            "Neo\nDesk",
            "Neo\rDesk",
            "Neo\tDesk",
            "Neo\0Desk",
            long.as_str(),
        ] {
            assert!(validate_app_name(name).is_err(), "{name:?} was accepted");
        }
    }

    #[test]
    fn service_commands_get_the_whole_name() {
        for name in NAMES {
            for (script, verb) in [
                (stop_service(name), "stop"),
                (delete_service(name), "delete"),
                (start_service(name), "start"),
            ] {
                let commands = script_commands(&script);
                assert_eq!(
                    commands,
                    vec![vec!["sc".to_owned(), verb.to_owned(), name.to_string()]]
                );
            }
        }
    }

    #[test]
    fn the_service_is_created_under_the_whole_name() {
        for name in NAMES {
            let exe = exe_of(name);
            let commands = script_commands(&create_service(name, &exe));
            assert_only_programs(&commands, &["sc"]);
            let binpath = format!("\"{exe}\" --service");
            let display = format!("{name} Service");
            let create = find(&commands, &["sc", "create"]);
            assert_eq!(
                create[2..],
                [
                    name.to_string(),
                    "binpath=".to_owned(),
                    binpath.clone(),
                    "start=".to_owned(),
                    "auto".to_owned(),
                    "DisplayName=".to_owned(),
                    display,
                ],
                "{name}"
            );
            let config = find(&commands, &["sc", "config"]);
            assert_eq!(
                config[2..],
                [
                    name.to_string(),
                    "binpath=".to_owned(),
                    binpath,
                    "start=".to_owned(),
                    "auto".to_owned(),
                ]
            );
            for verb in ["query", "failure", "failureflag", "start"] {
                assert_eq!(find(&commands, &["sc", verb])[2], *name, "sc {verb}");
            }
        }
    }

    #[test]
    fn the_settings_import_runs_under_the_whole_name() {
        for name in NAMES {
            let exe = exe_of(name);
            let config = format!(r"C:\Users\Zoë\AppData\Roaming\{name}\config\{name}.toml");
            let commands = script_commands(&import_config_service(name, &exe, &config));
            assert_only_programs(&commands, &["sc"]);
            let create = find(&commands, &["sc", "create"]);
            assert_eq!(create[2], *name);
            assert_eq!(create[4], format!("\"{exe}\" --import-config \"{config}\""));
            assert_eq!(
                create[7..],
                [format!("DisplayName="), format!("{name} Service")]
            );
            for args in &commands {
                assert_eq!(args[2], *name, "{args:?}");
            }
        }
    }

    #[test]
    fn taskkill_names_the_executable() {
        let commands = script_commands(&kill_processes("neodesk", " /FI \"PID ne 42\""));
        assert_eq!(
            commands,
            vec![
                vec!["taskkill", "/F", "/IM", "neodesk.exe", "/FI", "PID ne 42"]
                    .into_iter()
                    .map(str::to_owned)
                    .collect::<Vec<_>>()
            ]
        );
    }

    #[test]
    fn app_classes_are_keyed_on_the_whole_name() {
        for name in NAMES {
            let ext = name.to_lowercase();
            let exe = exe_of(name);
            let commands = script_commands(&add_app_classes(&ext, &exe));
            assert_only_programs(&commands, &["reg"]);
            for args in &commands {
                let key = &args[2];
                assert!(
                    key.starts_with(&format!("HKEY_CLASSES_ROOT\\.{ext}"))
                        || key.starts_with(&format!("HKEY_CLASSES_ROOT\\{ext}")),
                    "{args:?}"
                );
            }
            let open = find(
                &commands,
                &[
                    "reg",
                    "add",
                    &format!("HKEY_CLASSES_ROOT\\{ext}\\shell\\open\\command"),
                    "/f",
                    "/ve",
                ],
            );
            assert_eq!(open.last().unwrap(), &format!("\"{exe}\" \"%1\""));
            let option = script_commands(&add_install_option(&ext, "PRINTER", "1"));
            assert_eq!(option[0][2], format!("HKEY_CLASSES_ROOT\\.{ext}"));
            assert_eq!(option[0].last().unwrap(), "1");
            let delete = script_commands(&delete_app_classes(&ext));
            let file_class = format!("HKEY_CLASSES_ROOT\\.{ext}");
            let link_class = format!("HKEY_CLASSES_ROOT\\{ext}");
            assert_eq!(delete[0][..3], ["reg", "delete", file_class.as_str()]);
            assert_eq!(delete[1][..3], ["reg", "delete", link_class.as_str()]);
        }
    }

    /// The script with the variables the elevated runner sets filled in.
    fn expand(script: &str) -> String {
        script
            .replace("%~f0", r"C:\Temp\install.bat")
            .replace("%RUSTDESK_OUTPUT_DIR%", r"C:\Temp\install.bat.dir")
            .replace("%WINDIR%", r"C:\Windows")
    }

    /// Each command with the file its `if exist` waits for.
    fn conditional_commands(script: &str) -> Vec<(Option<String>, Vec<String>)> {
        script_commands(&expand(script))
            .into_iter()
            .map(|args| {
                if args.len() > 3 && args[0] == "if" && args[1] == "exist" {
                    (Some(args[2].clone()), args[3..].to_vec())
                } else {
                    (None, args)
                }
            })
            .collect()
    }

    fn strings(args: &[&str]) -> Vec<String> {
        args.iter().map(|arg| arg.to_string()).collect()
    }

    const INSTALLED_FONT: &str = r"C:\Windows\Fonts\NeoDeskMarker.ttf";
    const STAGED_FONT: &str = r"C:\Temp\install.bat.dir\NeoDeskMarker.ttf";

    #[test]
    fn the_install_puts_the_marker_font_into_the_fonts_folder_and_registers_it() {
        let encoded = "AAEAAAAKAIAAAwAgT1MvMg==";
        let commands = conditional_commands(&add_marker_font(encoded));
        for (_, args) in &commands {
            assert!(
                ["echo", "certutil", "copy", "reg", "del"].contains(&args[0].as_str()),
                "unexpected command {args:?}, the font must not end the install"
            );
        }
        let encoded_file = r"C:\Temp\install.bat.marker_font.b64";
        assert!(
            commands.contains(&(None, strings(&["echo", encoded]))),
            "{commands:?}"
        );
        assert!(
            commands.contains(&(
                None,
                strings(&["certutil", "-f", "-decode", encoded_file, STAGED_FONT])
            )),
            "{commands:?}"
        );
        assert!(
            commands.contains(&(
                Some(STAGED_FONT.to_owned()),
                strings(&["copy", "/Y", STAGED_FONT, INSTALLED_FONT])
            )),
            "{commands:?}"
        );
        assert!(
            commands.contains(&(
                Some(INSTALLED_FONT.to_owned()),
                strings(&[
                    "reg",
                    "add",
                    r"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
                    "/f",
                    "/v",
                    "NeoDesk Marker Regular (TrueType)",
                    "/t",
                    "REG_SZ",
                    "/d",
                    "NeoDeskMarker.ttf",
                ])
            )),
            "{commands:?}"
        );
        let copy = commands.iter().position(|(_, args)| args[0] == "copy");
        let register = commands.iter().position(|(_, args)| args[0] == "reg");
        assert!(copy < register, "the font is registered before it is there");
    }

    #[test]
    fn the_uninstall_unregisters_the_marker_font_and_deletes_it() {
        let commands = conditional_commands(&remove_marker_font());
        assert_eq!(
            commands,
            vec![
                (
                    None,
                    strings(&[
                        "reg",
                        "delete",
                        r"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
                        "/f",
                        "/v",
                        "NeoDesk Marker Regular (TrueType)",
                    ])
                ),
                (
                    Some(INSTALLED_FONT.to_owned()),
                    strings(&["del", "/f", "/q", INSTALLED_FONT])
                ),
            ]
        );
    }
}
