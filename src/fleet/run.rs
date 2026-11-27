//! fleet.run: one task of a fleet run, carried out on this computer.

use std::{
    io::{Read, Write},
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

use serde_json::{json, Value};

use super::{host, now_rfc3339, process};

pub const DEFAULT_TIMEOUT: u64 = 300;
pub const MIN_TIMEOUT: u64 = 10;
pub const MAX_TIMEOUT: u64 = 3600;
/// The largest script the client takes
const MAX_SCRIPT: usize = 256 * 1024;
/// The largest file file_deploy and install download
const MAX_DOWNLOAD: u64 = 2 * 1024 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Script,
    Restart,
    Update,
    Install,
    FileDeploy,
    Registry,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shell {
    PowerShell,
    Cmd,
    Sh,
    Bash,
}

#[derive(Clone, Debug)]
pub struct Task {
    pub run_id: i64,
    pub kind: Kind,
    pub script: String,
    pub shell: Shell,
    pub timeout: Duration,
}

/// Why a task does not start
#[derive(Debug, PartialEq, Eq)]
pub struct Refusal {
    pub status: &'static str,
    pub code: &'static str,
    pub message: String,
}

fn refuse(status: &'static str, code: &'static str, message: impl Into<String>) -> Refusal {
    Refusal {
        status,
        code,
        message: message.into(),
    }
}

pub fn run_id_of(args: &Value) -> Value {
    args.get("run_id").cloned().unwrap_or(Value::Null)
}

pub fn refusal_result(run_id: Value, refusal: &Refusal) -> Value {
    json!({
        "run_id": run_id,
        "exit_code": null,
        "code": refusal.code,
        "output": refusal.message,
        "started_at": now_rfc3339(),
        "finished_at": now_rfc3339(),
    })
}

/// The shell "auto" means on this platform
fn auto_shell() -> Shell {
    if cfg!(windows) {
        Shell::PowerShell
    } else {
        Shell::Sh
    }
}

fn parse_shell(value: Option<&str>) -> Result<Shell, Refusal> {
    let shell = match value
        .map(str::trim)
        .unwrap_or("auto")
        .to_ascii_lowercase()
        .as_str()
    {
        "" | "auto" => auto_shell(),
        "powershell" | "pwsh" | "ps" => Shell::PowerShell,
        "cmd" | "bat" | "batch" => Shell::Cmd,
        "sh" => Shell::Sh,
        "bash" => Shell::Bash,
        other => {
            return Err(refuse(
                "unsupported",
                "unsupported_shell",
                format!("The client has no shell \"{other}\"."),
            ))
        }
    };
    if shell == Shell::Cmd && !cfg!(windows) {
        return Err(refuse(
            "unsupported",
            "unsupported_shell",
            "cmd runs on Windows only.",
        ));
    }
    Ok(shell)
}

/// The time limit: `timeout` seconds, 10 to 3600, 300 when missing
pub fn parse_timeout(value: Option<&Value>) -> Duration {
    let seconds = match value {
        Some(Value::Number(n)) => n
            .as_u64()
            .or_else(|| {
                n.as_f64()
                    .filter(|f| f.is_finite() && *f > 0.0)
                    .map(|f| f as u64)
            })
            .unwrap_or(MIN_TIMEOUT),
        Some(Value::String(s)) => s.trim().parse().unwrap_or(DEFAULT_TIMEOUT),
        _ => DEFAULT_TIMEOUT,
    };
    Duration::from_secs(seconds.clamp(MIN_TIMEOUT, MAX_TIMEOUT))
}

pub fn parse(args: &Value) -> Result<Task, Refusal> {
    let run_id = match args.get("run_id").and_then(Value::as_i64) {
        Some(id) if id > 0 => id,
        _ => {
            return Err(refuse(
                "error",
                "run_id_required",
                "The task has no run id.",
            ))
        }
    };
    let kind = match args.get("type").and_then(Value::as_str).unwrap_or("") {
        "script" => Kind::Script,
        "restart" => Kind::Restart,
        "update" => Kind::Update,
        "install" => Kind::Install,
        "file_deploy" => Kind::FileDeploy,
        "registry" => Kind::Registry,
        other => {
            return Err(refuse(
                "unsupported",
                "unsupported_type",
                format!("The client does not know the task type \"{other}\"."),
            ))
        }
    };
    let script = args
        .get("script")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned();
    if script.len() > MAX_SCRIPT {
        return Err(refuse(
            "error",
            "script_too_large",
            "The script is larger than 256 KiB.",
        ));
    }
    let shell = if kind == Kind::Script {
        parse_shell(args.get("shell").and_then(Value::as_str))?
    } else {
        auto_shell()
    };
    let task = Task {
        run_id,
        kind,
        script,
        shell,
        timeout: parse_timeout(args.get("timeout")),
    };
    match kind {
        Kind::Script | Kind::Registry if task.script.trim().is_empty() => Err(refuse(
            "error",
            "script_required",
            "The task has no script.",
        )),
        Kind::Registry if !cfg!(windows) => Err(refuse(
            "unsupported",
            "unsupported_type",
            "Registry tasks run on Windows only.",
        )),
        Kind::Install => parse_install(&task.script).map(|_| task),
        Kind::FileDeploy => parse_file_deploy(&task.script).map(|_| task),
        _ => Ok(task),
    }
}

/// What install puts on the computer
#[derive(Debug, PartialEq, Eq)]
pub enum Install {
    Package(String),
    /// An installer from this https URL, with the arguments after it
    Url {
        url: String,
        args: String,
    },
}

pub fn parse_install(script: &str) -> Result<Install, Refusal> {
    let script = script.trim();
    if script.is_empty() {
        return Err(refuse(
            "error",
            "package_required",
            "The task names no package or installer.",
        ));
    }
    let (first, rest) = match script.split_once(char::is_whitespace) {
        Some((first, rest)) => (first, rest.trim()),
        None => (script, ""),
    };
    if first.contains("://") {
        let url = https_url(first)?;
        if rest.chars().any(|c| matches!(c, '\r' | '\n' | '\0')) {
            return Err(refuse(
                "error",
                "invalid_arguments",
                "Installer arguments take one line.",
            ));
        }
        return Ok(Install::Url {
            url,
            args: rest.to_owned(),
        });
    }
    let valid = !script.starts_with('-')
        && script.len() <= 200
        && script
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "._+-:@/".contains(c));
    if !valid {
        return Err(refuse(
            "error",
            "invalid_package",
            "A package name takes letters, digits and . _ + - : @ / only.",
        ));
    }
    Ok(Install::Package(script.to_owned()))
}

fn https_url(raw: &str) -> Result<String, Refusal> {
    let url = url::Url::parse(raw)
        .map_err(|_| refuse("error", "invalid_url", format!("\"{raw}\" is no URL.")))?;
    if url.scheme() != "https" {
        return Err(refuse(
            "error",
            "https_required",
            "The client downloads over https only.",
        ));
    }
    if url.host_str().unwrap_or("").is_empty() {
        return Err(refuse(
            "error",
            "invalid_url",
            format!("\"{raw}\" names no server."),
        ));
    }
    Ok(url.to_string())
}

#[derive(Debug, PartialEq, Eq)]
pub struct FileDeploy {
    pub url: String,
    pub path: PathBuf,
    pub sha256: Option<String>,
}

pub fn parse_file_deploy(script: &str) -> Result<FileDeploy, Refusal> {
    let spec: Value = serde_json::from_str(script).map_err(|_| {
        refuse(
            "error",
            "invalid_file_deploy",
            "A file deploy takes {\"url\": ..., \"path\": ..., \"sha256\": ...}.",
        )
    })?;
    let url = https_url(spec.get("url").and_then(Value::as_str).unwrap_or(""))?;
    let raw_path = spec
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let path = PathBuf::from(raw_path);
    if raw_path.is_empty() || !path.is_absolute() {
        return Err(refuse(
            "error",
            "absolute_path_required",
            "The target path must be absolute.",
        ));
    }
    if path
        .components()
        .any(|part| matches!(part, std::path::Component::ParentDir))
    {
        return Err(refuse(
            "error",
            "invalid_path",
            "The target path must not contain \"..\".",
        ));
    }
    if path.file_name().is_none() || raw_path.ends_with('/') || raw_path.ends_with('\\') {
        return Err(refuse(
            "error",
            "invalid_path",
            "The target path must name a file.",
        ));
    }
    let sha256 = match spec.get("sha256").and_then(Value::as_str).map(str::trim) {
        None | Some("") => None,
        Some(hash) if hash.len() == 64 && hash.chars().all(|c| c.is_ascii_hexdigit()) => {
            Some(hash.to_ascii_lowercase())
        }
        Some(_) => {
            return Err(refuse(
                "error",
                "invalid_sha256",
                "sha256 takes 64 hex digits.",
            ))
        }
    };
    Ok(FileDeploy { url, path, sha256 })
}

/// Carries out `task` and gives the status and the result for the server
pub fn execute(task: &Task) -> (String, Value) {
    let started_at = now_rfc3339();
    let (status, exit_code, output, code) = match carry_out(task) {
        Ok(done) => done,
        Err(refusal) => (
            refusal.status.to_owned(),
            None,
            refusal.message,
            Some(refusal.code),
        ),
    };
    let mut result = json!({
        "run_id": task.run_id,
        "exit_code": exit_code,
        "output": process::cap(&output),
        "started_at": started_at,
        "finished_at": now_rfc3339(),
    });
    if let Some(code) = code {
        result["code"] = json!(code);
    }
    (status, result)
}

type Done = (String, Option<i32>, String, Option<&'static str>);

fn carry_out(task: &Task) -> Result<Done, Refusal> {
    let needs_rights = !matches!(task.kind, Kind::Script);
    if needs_rights && !host::is_elevated() {
        return Err(refuse(
            "permission_denied",
            "not_elevated",
            "The NeoDesk service does not run with administrator rights on this computer.",
        ));
    }
    match task.kind {
        Kind::Script => run_script(&task.script, task.shell, task.timeout),
        Kind::Restart => restart(),
        Kind::Update => run_script(&update_script(), auto_shell(), task.timeout),
        Kind::Install => install(task),
        Kind::FileDeploy => file_deploy(&parse_file_deploy(&task.script)?, task.timeout),
        Kind::Registry => registry(&task.script, task.timeout),
    }
}

fn from_outcome(outcome: process::Outcome) -> Done {
    if outcome.timed_out {
        return ("timeout".to_owned(), None, outcome.output, None);
    }
    let status = if outcome.exit_code == Some(0) {
        "ok"
    } else {
        "error"
    };
    (status.to_owned(), outcome.exit_code, outcome.output, None)
}

/// A file in the temp folder that is deleted when it goes out of scope
pub struct TempFile(pub PathBuf);

impl TempFile {
    pub fn create(extension: &str, contents: &[u8]) -> std::io::Result<Self> {
        let path = std::env::temp_dir().join(format!(
            "neodesk-fleet-{}.{extension}",
            uuid::Uuid::new_v4().simple()
        ));
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)?;
        let file_guard = Self(path);
        file.write_all(contents)?;
        file.sync_all()?;
        Ok(file_guard)
    }

    pub fn empty(extension: &str) -> Self {
        Self(std::env::temp_dir().join(format!(
            "neodesk-fleet-{}.{extension}",
            uuid::Uuid::new_v4().simple()
        )))
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// The command that runs a script file with `shell`
fn shell_command(shell: Shell, file: &Path) -> Result<Command, Refusal> {
    let command = match shell {
        Shell::PowerShell => {
            let program = if cfg!(windows) {
                windows_powershell()
            } else if which("pwsh") {
                "pwsh".to_owned()
            } else {
                return Err(refuse(
                    "unsupported",
                    "unsupported_shell",
                    "PowerShell (pwsh) is not installed on this computer.",
                ));
            };
            let mut command = Command::new(program);
            command.args([
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
            ]);
            command.arg(file);
            command
        }
        Shell::Cmd => {
            let mut command = Command::new("cmd.exe");
            command.args(["/D", "/C"]);
            command.arg(file);
            command
        }
        Shell::Sh => {
            let mut command = Command::new("/bin/sh");
            command.arg(file);
            command
        }
        Shell::Bash => {
            if !which("bash") {
                return Err(refuse(
                    "unsupported",
                    "unsupported_shell",
                    "bash is not installed.",
                ));
            }
            let mut command = Command::new("bash");
            command.arg(file);
            command
        }
    };
    Ok(command)
}

pub fn windows_powershell() -> String {
    let root = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".to_owned());
    let path = format!("{root}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
    if Path::new(&path).exists() {
        path
    } else {
        "powershell.exe".to_owned()
    }
}

fn which(program: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|dir| dir.join(program).is_file()))
        .unwrap_or(false)
}

/// The bytes of the script file: PowerShell 5 reads a file without a BOM
/// in the ANSI code page and writes in the OEM one, so the file gets a BOM
/// and the script switches its output to UTF-8 first.
pub fn script_file_contents(shell: Shell, script: &str) -> (String, Vec<u8>) {
    match shell {
        Shell::PowerShell => {
            let mut bytes = vec![0xEF, 0xBB, 0xBF];
            bytes.extend_from_slice(
                b"try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); $OutputEncoding = [Console]::OutputEncoding } catch {}\r\n",
            );
            bytes.extend_from_slice(script.as_bytes());
            ("ps1".to_owned(), bytes)
        }
        Shell::Cmd => {
            let text = format!(
                "@chcp 65001 >nul\r\n{}",
                script.replace("\r\n", "\n").replace('\n', "\r\n")
            );
            ("cmd".to_owned(), text.into_bytes())
        }
        Shell::Sh | Shell::Bash => ("sh".to_owned(), script.replace("\r\n", "\n").into_bytes()),
    }
}

pub fn run_script(script: &str, shell: Shell, timeout: Duration) -> Result<Done, Refusal> {
    let (extension, contents) = script_file_contents(shell, script);
    let file = TempFile::create(&extension, &contents).map_err(|err| {
        refuse(
            "error",
            "temp_file_failed",
            format!("The script file could not be written: {err}"),
        )
    })?;
    let command = shell_command(shell, &file.0)?;
    let outcome = process::run(command, timeout).map_err(|err| {
        refuse(
            "error",
            "start_failed",
            format!("The shell could not start: {err}"),
        )
    })?;
    drop(file);
    Ok(from_outcome(outcome))
}

fn restart() -> Result<Done, Refusal> {
    let (program, args): (&str, &[&str]) = if cfg!(windows) {
        (
            "shutdown.exe",
            &[
                "/r",
                "/t",
                "60",
                "/c",
                "NeoDesk: restart requested by the administrator",
            ],
        )
    } else {
        (
            "shutdown",
            &[
                "-r",
                "+1",
                "NeoDesk: restart requested by the administrator",
            ],
        )
    };
    match process::quick(program, args, Duration::from_secs(30)) {
        Ok(output) => Ok((
            "ok".to_owned(),
            Some(0),
            format!("The computer restarts in 60 seconds.\n{output}")
                .trim()
                .to_owned(),
            None,
        )),
        Err(message) => Ok(("error".to_owned(), None, message, None)),
    }
}

/// The script that installs the operating system's updates
pub fn update_script() -> String {
    if cfg!(windows) {
        r#"$ErrorActionPreference = 'Continue'
if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
    Import-Module PSWindowsUpdate
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Confirm:$false -Verbose 4>&1 | Out-String -Width 200
    exit 0
}
$uso = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
if (-not (Test-Path $uso)) { Write-Output 'Neither PSWindowsUpdate nor UsoClient is available.'; exit 1 }
& $uso StartScan
& $uso StartDownload
& $uso StartInstall
Write-Output 'Windows Update was told to scan, download and install. It goes on in the background.'
exit 0
"#
        .to_owned()
    } else if cfg!(target_os = "macos") {
        "softwareupdate -ia 2>&1\n".to_owned()
    } else {
        r#"export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade
elif command -v dnf >/dev/null 2>&1; then
    dnf -y upgrade --refresh
elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive refresh && zypper --non-interactive update
elif command -v yum >/dev/null 2>&1; then
    yum -y update
else
    echo "No supported package manager (apt-get, dnf, zypper, yum) found." >&2
    exit 1
fi
"#
        .to_owned()
    }
}

/// The script that installs package `name` with the platform's manager
pub fn package_script(name: &str) -> String {
    if cfg!(windows) {
        format!(
            r#"$ErrorActionPreference = 'Stop'
$winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
if (-not $winget) {{
    $winget = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
}}
if (-not $winget) {{ Write-Output 'winget is not installed on this computer.'; exit 1 }}
& $winget install --exact --id {id} --silent --disable-interactivity --accept-package-agreements --accept-source-agreements --scope machine
if ($LASTEXITCODE -ne 0) {{
    & $winget install --exact --id {id} --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
}}
exit $LASTEXITCODE
"#,
            id = host::ps_quote(name)
        )
    } else if cfg!(target_os = "macos") {
        format!(
            r#"brew=""
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && brew="$b" && break; done
if [ -z "$brew" ]; then echo "Homebrew is not installed on this computer." >&2; exit 1; fi
owner=$(stat -f %Su "$brew")
if [ "$(id -u)" = 0 ] && [ "$owner" != root ]; then
    exec sudo -u "$owner" -H env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install {name}
fi
exec env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install {name}
"#,
            name = host::sh_quote(name)
        )
    } else {
        format!(
            r#"export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y {name}
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y {name}
elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install {name}
elif command -v yum >/dev/null 2>&1; then
    yum install -y {name}
else
    echo "No supported package manager (apt-get, dnf, zypper, yum) found." >&2
    exit 1
fi
"#,
            name = host::sh_quote(name)
        )
    }
}

/// The file name of the download at `url`, from its path
fn download_name(url: &str) -> String {
    let name = url::Url::parse(url)
        .ok()
        .and_then(|url| {
            url.path_segments()
                .and_then(|mut parts| parts.next_back().map(str::to_owned))
        })
        .unwrap_or_default();
    let name: String = name
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || "._-".contains(*c))
        .collect();
    if name.trim_matches('.').is_empty() {
        "installer".to_owned()
    } else {
        name
    }
}

fn extension_of(name: &str) -> String {
    Path::new(name)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
}

/// The script that runs the installer at `file`
pub fn installer_script(file: &Path, args: &str) -> Result<(Shell, String), Refusal> {
    let name = file.to_string_lossy().to_string();
    let extension = extension_of(&name);
    if cfg!(windows) {
        let file = host::ps_quote(&name);
        let args = host::ps_quote(args);
        let script = match extension.as_str() {
            "msi" => format!(
                "$p = Start-Process -FilePath msiexec.exe -ArgumentList ('/i \"' + {file} + '\" /qn /norestart ' + {args}) -Wait -PassThru\r\nexit $p.ExitCode\r\n"
            ),
            "exe" => format!(
                "$a = {args}\r\nif ($a) {{ $p = Start-Process -FilePath {file} -ArgumentList $a -Wait -PassThru }} else {{ $p = Start-Process -FilePath {file} -Wait -PassThru }}\r\nexit $p.ExitCode\r\n"
            ),
            "msix" | "appx" | "msixbundle" | "appxbundle" => format!(
                "Add-AppxProvisionedPackage -Online -PackagePath {file} -SkipLicense | Out-String\r\nexit 0\r\n"
            ),
            "ps1" => format!(
                "$a = @(({args}) -split ' ' | Where-Object {{ $_ }})\r\n& {file} @a\r\nexit $LASTEXITCODE\r\n"
            ),
            _ => {
                return Err(refuse(
                    "unsupported",
                    "unsupported_installer",
                    "Windows installers are .msi, .exe, .msix or .ps1 files.",
                ))
            }
        };
        return Ok((Shell::PowerShell, script));
    }
    let file = host::sh_quote(&name);
    let script = if cfg!(target_os = "macos") {
        match extension.as_str() {
            "pkg" => format!("installer -pkg {file} -target / {args}\n"),
            "dmg" => format!(
                r#"mnt=$(mktemp -d /tmp/neodesk-dmg.XXXXXX)
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" {file} || exit 1
rc=0
pkg=$(find "$mnt" -maxdepth 1 -name '*.pkg' | head -n 1)
app=$(find "$mnt" -maxdepth 1 -name '*.app' | head -n 1)
if [ -n "$pkg" ]; then installer -pkg "$pkg" -target / || rc=$?
elif [ -n "$app" ]; then rm -rf "/Applications/$(basename "$app")"; cp -R "$app" /Applications/ || rc=$?
else echo "The disk image holds no .pkg or .app." >&2; rc=1; fi
hdiutil detach "$mnt" -quiet || true
rmdir "$mnt" 2>/dev/null
exit $rc
"#
            ),
            "sh" => format!("/bin/sh {file} {args}\n"),
            _ => {
                return Err(refuse(
                    "unsupported",
                    "unsupported_installer",
                    "macOS installers are .pkg, .dmg or .sh files.",
                ))
            }
        }
    } else {
        match extension.as_str() {
            "deb" => format!(
                "export DEBIAN_FRONTEND=noninteractive\nif command -v apt-get >/dev/null 2>&1; then apt-get install -y {file}; else dpkg -i {file}; fi\n"
            ),
            "rpm" => format!(
                "if command -v dnf >/dev/null 2>&1; then dnf install -y {file}\nelif command -v zypper >/dev/null 2>&1; then zypper --non-interactive install --allow-unsigned-rpm {file}\nelse rpm -U {file}; fi\n"
            ),
            "sh" | "run" => format!("/bin/sh {file} {args}\n"),
            _ => {
                return Err(refuse(
                    "unsupported",
                    "unsupported_installer",
                    "Linux installers are .deb, .rpm or .sh files.",
                ))
            }
        }
    };
    Ok((Shell::Sh, script))
}

fn install(task: &Task) -> Result<Done, Refusal> {
    match parse_install(&task.script)? {
        Install::Package(name) => run_script(&package_script(&name), auto_shell(), task.timeout),
        Install::Url { url, args } => {
            if !args.is_empty()
                && !cfg!(windows)
                && args.chars().any(|c| "`$;&|<>(){}\\\"'".contains(c))
            {
                return Err(refuse(
                    "error",
                    "invalid_arguments",
                    "Installer arguments take no shell characters.",
                ));
            }
            let name = download_name(&url);
            let extension = extension_of(&name);
            let file = TempFile::empty(if extension.is_empty() {
                "bin"
            } else {
                &extension
            });
            let started = std::time::Instant::now();
            let (size, hash) = download(&url, &file.0, task.timeout)?;
            let left = task
                .timeout
                .saturating_sub(started.elapsed())
                .max(Duration::from_secs(MIN_TIMEOUT));
            let (shell, script) = installer_script(&file.0, &args)?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&file.0, std::fs::Permissions::from_mode(0o700));
            }
            let mut done = run_script(&script, shell, left)?;
            done.2 = format!(
                "Downloaded {name} ({size} bytes, sha256 {hash}).\n{}",
                done.2
            );
            drop(file);
            Ok(done)
        }
    }
}

/// Downloads `url` to `target` over https and gives its size and sha256
fn download(url: &str, target: &Path, timeout: Duration) -> Result<(u64, String), Refusal> {
    use sha2::{Digest, Sha256};
    let client = crate::hbbs_http::create_http_client_with_url_strict(url)
        .map_err(|err| refuse("error", "download_failed", format!("{err}")))?;
    let mut response = client
        .get(url)
        .timeout(timeout)
        .send()
        .and_then(|response| response.error_for_status())
        .map_err(|err| {
            refuse(
                "error",
                "download_failed",
                format!("The download failed: {err}"),
            )
        })?;
    if !response.url().as_str().starts_with("https://") {
        return Err(refuse(
            "error",
            "https_required",
            "The download was redirected away from https.",
        ));
    }
    if response
        .content_length()
        .map_or(false, |len| len > MAX_DOWNLOAD)
    {
        return Err(refuse(
            "error",
            "download_too_large",
            "The file is larger than 2 GiB.",
        ));
    }
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(target)
        .map_err(|err| {
            refuse(
                "error",
                "write_failed",
                format!("{}: {err}", target.display()),
            )
        })?;
    let mut hasher = Sha256::new();
    let mut size = 0_u64;
    let mut buffer = vec![0_u8; 64 * 1024];
    loop {
        let n = response.read(&mut buffer).map_err(|err| {
            refuse(
                "error",
                "download_failed",
                format!("The download broke off: {err}"),
            )
        })?;
        if n == 0 {
            break;
        }
        size += n as u64;
        if size > MAX_DOWNLOAD {
            return Err(refuse(
                "error",
                "download_too_large",
                "The file is larger than 2 GiB.",
            ));
        }
        hasher.update(&buffer[..n]);
        file.write_all(&buffer[..n]).map_err(|err| {
            refuse(
                "error",
                "write_failed",
                format!("{}: {err}", target.display()),
            )
        })?;
    }
    file.sync_all().map_err(|err| {
        refuse(
            "error",
            "write_failed",
            format!("{}: {err}", target.display()),
        )
    })?;
    Ok((size, hex::encode(hasher.finalize())))
}

fn file_deploy(spec: &FileDeploy, timeout: Duration) -> Result<Done, Refusal> {
    let parent = spec
        .path
        .parent()
        .ok_or_else(|| refuse("error", "invalid_path", "The target path has no folder."))?;
    std::fs::create_dir_all(parent).map_err(|err| {
        refuse(
            "error",
            "write_failed",
            format!("{}: {err}", parent.display()),
        )
    })?;
    let partial = parent.join(format!(
        ".{}.neodesk-{}",
        spec.path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("file"),
        uuid::Uuid::new_v4().simple()
    ));
    let result = download(&spec.url, &partial, timeout).and_then(|(size, hash)| {
        if let Some(expected) = &spec.sha256 {
            if *expected != hash {
                return Err(refuse(
                    "error",
                    "sha256_mismatch",
                    format!("The file's sha256 is {hash}, not {expected}. It was not written."),
                ));
            }
        }
        replace_file(&partial, &spec.path).map_err(|err| {
            refuse(
                "error",
                "write_failed",
                format!("{}: {err}", spec.path.display()),
            )
        })?;
        Ok((size, hash))
    });
    if result.is_err() {
        let _ = std::fs::remove_file(&partial);
    }
    let (size, hash) = result?;
    Ok((
        "ok".to_owned(),
        Some(0),
        format!(
            "Wrote {} ({size} bytes, sha256 {hash}).",
            spec.path.display()
        ),
        None,
    ))
}

fn replace_file(from: &Path, to: &Path) -> std::io::Result<()> {
    match std::fs::rename(from, to) {
        Ok(()) => Ok(()),
        Err(_) if to.exists() => {
            // Windows renames over a file only when nothing holds it open
            std::fs::remove_file(to)?;
            std::fs::rename(from, to)
        }
        Err(err) => Err(err),
    }
}

fn registry(script: &str, timeout: Duration) -> Result<Done, Refusal> {
    // reg import reads UTF-16 with a BOM, and needs the header line
    let mut text = script.replace("\r\n", "\n").replace('\n', "\r\n");
    let first = text.trim_start_matches('\u{feff}').trim_start().to_owned();
    if !first.starts_with("Windows Registry Editor Version 5.00") && !first.starts_with("REGEDIT4")
    {
        text = format!("Windows Registry Editor Version 5.00\r\n\r\n{first}");
    } else {
        text = first;
    }
    let mut bytes = vec![0xFF, 0xFE];
    for unit in text.encode_utf16() {
        bytes.extend_from_slice(&unit.to_le_bytes());
    }
    let file = TempFile::create("reg", &bytes).map_err(|err| {
        refuse(
            "error",
            "temp_file_failed",
            format!("The .reg file could not be written: {err}"),
        )
    })?;
    let mut command = Command::new("reg.exe");
    command.arg("import").arg(&file.0);
    let outcome = process::run(command, timeout).map_err(|err| {
        refuse(
            "error",
            "start_failed",
            format!("reg could not start: {err}"),
        )
    })?;
    drop(file);
    Ok(from_outcome(outcome))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(kind: &str, script: &str) -> Value {
        json!({"run_id": 5, "task_id": 2, "type": kind, "script": script, "shell": "auto", "timeout": 60})
    }

    #[test]
    fn a_script_task_parses() {
        let task = parse(&args("script", "echo hi")).unwrap();
        assert_eq!(task.run_id, 5);
        assert_eq!(task.kind, Kind::Script);
        assert_eq!(task.timeout, Duration::from_secs(60));
        assert_eq!(
            task.shell,
            if cfg!(windows) {
                Shell::PowerShell
            } else {
                Shell::Sh
            }
        );
    }

    #[test]
    fn the_timeout_stays_between_10_seconds_and_an_hour() {
        assert_eq!(parse_timeout(None), Duration::from_secs(300));
        assert_eq!(parse_timeout(Some(&json!(1))), Duration::from_secs(10));
        assert_eq!(parse_timeout(Some(&json!(0))), Duration::from_secs(10));
        assert_eq!(parse_timeout(Some(&json!(-5))), Duration::from_secs(10));
        assert_eq!(
            parse_timeout(Some(&json!(99999))),
            Duration::from_secs(3600)
        );
        assert_eq!(parse_timeout(Some(&json!(45))), Duration::from_secs(45));
        assert_eq!(parse_timeout(Some(&json!(45.7))), Duration::from_secs(45));
        assert_eq!(parse_timeout(Some(&json!("120"))), Duration::from_secs(120));
        assert_eq!(
            parse_timeout(Some(&json!("soon"))),
            Duration::from_secs(300)
        );
    }

    #[test]
    fn bad_arguments_are_refused() {
        let missing_run = json!({"type": "script", "script": "x"});
        assert_eq!(parse(&missing_run).unwrap_err().code, "run_id_required");
        assert_eq!(
            parse(&json!({"run_id": 0, "type": "script", "script": "x"}))
                .unwrap_err()
                .code,
            "run_id_required"
        );
        let unknown = parse(&args("format_disk", "x")).unwrap_err();
        assert_eq!(
            (unknown.status, unknown.code),
            ("unsupported", "unsupported_type")
        );
        assert_eq!(
            parse(&args("script", "  ")).unwrap_err().code,
            "script_required"
        );
        let mut shell = args("script", "x");
        shell["shell"] = json!("fish");
        assert_eq!(parse(&shell).unwrap_err().code, "unsupported_shell");
        let big = "x".repeat(MAX_SCRIPT + 1);
        assert_eq!(
            parse(&args("script", &big)).unwrap_err().code,
            "script_too_large"
        );
        if !cfg!(windows) {
            let registry = parse(&args("registry", "[HKEY_LOCAL_MACHINE\\x]")).unwrap_err();
            assert_eq!(registry.status, "unsupported");
            shell["shell"] = json!("cmd");
            assert_eq!(parse(&shell).unwrap_err().code, "unsupported_shell");
        }
        // A restart needs no script
        assert!(parse(&args("restart", "")).is_ok());
    }

    #[test]
    fn install_takes_a_package_name_or_an_https_installer() {
        assert_eq!(
            parse_install("Mozilla.Firefox").unwrap(),
            Install::Package("Mozilla.Firefox".into())
        );
        assert_eq!(
            parse_install(" htop ").unwrap(),
            Install::Package("htop".into())
        );
        assert_eq!(
            parse_install("https://example.com/setup.exe /S /D=C:\\x").unwrap(),
            Install::Url {
                url: "https://example.com/setup.exe".into(),
                args: "/S /D=C:\\x".into()
            }
        );
        assert_eq!(
            parse_install("http://example.com/a.msi").unwrap_err().code,
            "https_required"
        );
        assert_eq!(
            parse_install("ftp://example.com/a.msi").unwrap_err().code,
            "https_required"
        );
        assert_eq!(
            parse_install("htop; rm -rf /").unwrap_err().code,
            "invalid_package"
        );
        assert_eq!(
            parse_install("--version").unwrap_err().code,
            "invalid_package"
        );
        assert_eq!(parse_install("$(id)").unwrap_err().code, "invalid_package");
        assert_eq!(parse_install("").unwrap_err().code, "package_required");
        assert_eq!(
            parse(&args("install", "http://x/a.deb")).unwrap_err().code,
            "https_required"
        );
    }

    #[test]
    fn file_deploy_takes_https_an_absolute_path_and_an_optional_hash() {
        let target = if cfg!(windows) {
            "C:\\ProgramData\\x\\a.txt"
        } else {
            "/etc/x/a.txt"
        };
        let spec =
            json!({"url": "https://example.com/a.txt", "path": target, "sha256": "AB".repeat(32)})
                .to_string();
        let deploy = parse_file_deploy(&spec).unwrap();
        assert_eq!(deploy.path, PathBuf::from(target));
        assert_eq!(deploy.sha256.as_deref(), Some("ab".repeat(32).as_str()));

        let no_hash = json!({"url": "https://example.com/a.txt", "path": target}).to_string();
        assert_eq!(parse_file_deploy(&no_hash).unwrap().sha256, None);

        let plain = json!({"url": "http://example.com/a.txt", "path": target}).to_string();
        assert_eq!(
            parse_file_deploy(&plain).unwrap_err().code,
            "https_required"
        );
        let relative = json!({"url": "https://example.com/a.txt", "path": "x/a.txt"}).to_string();
        assert_eq!(
            parse_file_deploy(&relative).unwrap_err().code,
            "absolute_path_required"
        );
        let dotdot = if cfg!(windows) {
            "C:\\x\\..\\a.txt"
        } else {
            "/x/../a.txt"
        };
        let escape = json!({"url": "https://example.com/a", "path": dotdot}).to_string();
        assert_eq!(parse_file_deploy(&escape).unwrap_err().code, "invalid_path");
        let short =
            json!({"url": "https://example.com/a", "path": target, "sha256": "abc"}).to_string();
        assert_eq!(
            parse_file_deploy(&short).unwrap_err().code,
            "invalid_sha256"
        );
        assert_eq!(
            parse_file_deploy("not json").unwrap_err().code,
            "invalid_file_deploy"
        );
        assert_eq!(
            parse(&args("file_deploy", &plain)).unwrap_err().code,
            "https_required"
        );
    }

    #[test]
    fn the_result_has_the_contract_fields() {
        let task = parse(&args(
            "script",
            if cfg!(windows) {
                "Write-Output 'hello'; exit 4"
            } else {
                "echo hello; exit 4"
            },
        ))
        .unwrap();
        let (status, result) = execute(&task);
        assert_eq!(status, "error");
        assert_eq!(result["run_id"], 5);
        assert_eq!(result["exit_code"], 4);
        assert!(
            result["output"].as_str().unwrap().contains("hello"),
            "{result}"
        );
        for key in ["started_at", "finished_at"] {
            let at = result[key].as_str().unwrap();
            assert!(
                chrono::DateTime::parse_from_rfc3339(at).is_ok(),
                "{key}: {at}"
            );
        }
        let task = parse(&args(
            "script",
            if cfg!(windows) { "exit 0" } else { "true" },
        ))
        .unwrap();
        assert_eq!(execute(&task).0, "ok");
    }

    #[cfg(unix)]
    #[test]
    fn a_script_that_runs_too_long_times_out() {
        let task = Task {
            run_id: 9,
            kind: Kind::Script,
            script: "echo begun; sleep 30; echo never".to_owned(),
            shell: Shell::Sh,
            timeout: Duration::from_millis(700),
        };
        let begun = std::time::Instant::now();
        let (status, result) = execute(&task);
        assert_eq!(status, "timeout");
        assert_eq!(result["exit_code"], Value::Null);
        let output = result["output"].as_str().unwrap();
        assert!(
            output.contains("begun") && !output.contains("never"),
            "{output}"
        );
        assert!(begun.elapsed() < Duration::from_secs(10));
    }

    #[test]
    fn the_script_file_is_deleted_afterwards() {
        let before: Vec<_> = temp_scripts();
        let task = parse(&args(
            "script",
            if cfg!(windows) { "exit 0" } else { "true" },
        ))
        .unwrap();
        execute(&task);
        let after: Vec<_> = temp_scripts();
        assert!(
            after.iter().all(|path| before.contains(path)),
            "left behind: {after:?}"
        );
    }

    fn temp_scripts() -> Vec<PathBuf> {
        std::fs::read_dir(std::env::temp_dir())
            .map(|entries| {
                entries
                    .flatten()
                    .map(|entry| entry.path())
                    .filter(|path| {
                        let name = path.file_name().unwrap().to_string_lossy().to_string();
                        name.starts_with("neodesk-fleet-")
                            && (name.ends_with(".sh") || name.ends_with(".ps1"))
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    #[test]
    fn long_output_keeps_its_last_64_kib() {
        let script = if cfg!(windows) {
            "1..20000 | ForEach-Object { 'line {0:D6}' -f $_ }; Write-Output 'LAST'"
        } else {
            "i=0; while [ $i -lt 20000 ]; do echo \"line $i\"; i=$((i+1)); done; echo LAST"
        };
        let task = parse(&args("script", script)).unwrap();
        let (status, result) = execute(&task);
        assert_eq!(status, "ok", "{result}");
        let output = result["output"].as_str().unwrap();
        assert!(output.len() <= process::MAX_OUTPUT);
        assert!(output.len() > process::MAX_OUTPUT - 100);
        assert!(output.trim_end().ends_with("LAST"));
        assert!(!output.contains("line 0\n") && !output.contains("line 000001"));
    }

    #[test]
    fn tasks_that_change_the_computer_need_full_rights() {
        if host::is_elevated() {
            return;
        }
        for kind in ["restart", "update", "install"] {
            let task = parse(&args(kind, "htop")).unwrap();
            let (status, result) = execute(&task);
            assert_eq!(status, "permission_denied", "{kind}");
            assert_eq!(result["code"], "not_elevated");
        }
    }

    #[test]
    fn installer_scripts_quote_the_file() {
        if cfg!(windows) {
            let (_, script) = installer_script(Path::new("C:\\T\\it's.msi"), "ALLUSERS=1").unwrap();
            assert!(script.contains("'C:\\T\\it''s.msi'"), "{script}");
            assert!(script.contains("/qn"));
        } else if cfg!(target_os = "linux") {
            let (_, script) = installer_script(Path::new("/tmp/it's.deb"), "").unwrap();
            assert!(script.contains("'/tmp/it'\\''s.deb'"), "{script}");
            assert_eq!(
                installer_script(Path::new("/tmp/a.zip"), "")
                    .unwrap_err()
                    .code,
                "unsupported_installer"
            );
        }
        assert_eq!(
            download_name("https://x.example/dl/Setup%20(1).exe?x=1"),
            "Setup201.exe"
        );
        assert_eq!(download_name("https://x.example/"), "installer");
    }

    #[test]
    fn package_scripts_quote_the_name() {
        let script = package_script("vim");
        if cfg!(windows) {
            assert!(script.contains("--id 'vim'"));
        } else {
            assert!(script.contains(" 'vim'"));
        }
    }
}
