//! fleet.compliance: security checks and the installed software.
//!
//! Each platform reports the checks it can answer; one it cannot answer is
//! left out rather than counted as failed.

use std::{sync::Mutex, time::Duration};

use serde_json::{json, Value};

use super::host;
#[cfg(not(windows))]
use super::process;

/// The software list stays under this many bytes of JSON, so the result
/// fits the server's limit for one command result
const MAX_SOFTWARE_BYTES: usize = 160 * 1024;

lazy_static::lazy_static! {
    static ref SCAN_LOCK: Mutex<()> = Mutex::new(());
}

#[derive(Clone, Debug, PartialEq)]
pub struct Check {
    pub key: &'static str,
    pub ok: bool,
    pub detail: String,
    pub fixable: bool,
}

impl Check {
    fn new(key: &'static str, ok: bool, detail: impl Into<String>, fixable: bool) -> Self {
        Self {
            key,
            ok,
            detail: detail.into(),
            fixable: fixable && !ok,
        }
    }

    fn to_json(&self) -> Value {
        json!({"key": self.key, "ok": self.ok, "detail": self.detail, "fixable": self.fixable})
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Software {
    pub name: String,
    pub version: String,
    pub publisher: String,
}

pub fn remediate_requested(args: &Value) -> bool {
    match args.get("remediate") {
        Some(Value::Bool(value)) => *value,
        Some(Value::String(value)) => matches!(value.as_str(), "true" | "1" | "yes"),
        _ => false,
    }
}

/// Sorted, without duplicates, and cut to the size limit
pub fn software_json(mut software: Vec<Software>) -> (Value, bool) {
    software.retain(|item| !item.name.trim().is_empty());
    for item in software.iter_mut() {
        item.name = item.name.trim().chars().take(200).collect();
        item.version = item.version.trim().chars().take(100).collect();
        item.publisher = item.publisher.trim().chars().take(120).collect();
    }
    software.sort_by(|a, b| {
        a.name
            .to_lowercase()
            .cmp(&b.name.to_lowercase())
            .then(a.version.cmp(&b.version))
    });
    software.dedup_by(|a, b| a.name.eq_ignore_ascii_case(&b.name) && a.version == b.version);
    let mut used = 2;
    let mut list = Vec::new();
    let mut truncated = false;
    for item in software {
        let value =
            json!({"name": item.name, "version": item.version, "publisher": item.publisher});
        let size = value.to_string().len() + 1;
        if used + size > MAX_SOFTWARE_BYTES {
            truncated = true;
            break;
        }
        used += size;
        list.push(value);
    }
    (Value::Array(list), truncated)
}

/// The result as the server reads it
pub fn result_json(checks: &[Check], software: Vec<Software>, remediated: &[String]) -> Value {
    let (software, truncated) = software_json(software);
    let mut result = json!({
        "software": software,
        "checks": checks.iter().map(Check::to_json).collect::<Vec<_>>(),
        "collected_at": super::now_rfc3339(),
    });
    if truncated {
        result["software_truncated"] = json!(true);
    }
    if !remediated.is_empty() {
        result["remediated"] = json!(remediated);
    }
    result
}

/// fleet.compliance on this computer
pub fn collect(remediate: bool) -> (String, Value) {
    let _lock = SCAN_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    let mut remediated = Vec::new();
    let mut checks = platform::checks();
    if remediate {
        if !host::is_elevated() {
            let mut result = result_json(&checks, platform::software(), &[]);
            result["code"] = json!("not_elevated");
            return ("permission_denied".to_owned(), result);
        }
        for check in checks.iter().filter(|check| !check.ok && check.fixable) {
            match platform::fix(check.key) {
                Ok(()) => remediated.push(check.key.to_owned()),
                Err(message) => {
                    hbb_common::log::warn!("fleet compliance: {} not fixed: {message}", check.key)
                }
            }
        }
        if !remediated.is_empty() {
            checks = platform::checks();
        }
    }
    (
        "ok".to_owned(),
        result_json(&checks, platform::software(), &remediated),
    )
}

#[cfg(not(windows))]
fn quick(program: &str, args: &[&str]) -> Result<String, String> {
    process::quick(program, args, Duration::from_secs(120))
}

/// Reads "name<TAB>version<TAB>publisher" lines, as dpkg-query and rpm
/// print them. A publisher's mail address is left out.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn parse_package_lines(text: &str) -> Vec<Software> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            let name = fields.next()?.trim();
            if name.is_empty() || name == "(none)" {
                return None;
            }
            let version = fields.next().unwrap_or("").trim();
            let publisher = fields.next().unwrap_or("").trim();
            let publisher = publisher.split('<').next().unwrap_or("").trim();
            let publisher = if publisher == "(none)" { "" } else { publisher };
            Some(Software {
                name: name.to_owned(),
                version: version.to_owned(),
                publisher: publisher.to_owned(),
            })
        })
        .collect()
}

/// Reads the checks a PowerShell script prints as JSON
#[cfg_attr(not(windows), allow(dead_code))]
pub fn parse_checks(text: &str, keys: &[&'static str]) -> Vec<Check> {
    let start = text.find(|c| c == '[' || c == '{').unwrap_or(0);
    let value: Value = serde_json::from_str(text[start..].trim()).unwrap_or(Value::Null);
    let rows = match value {
        Value::Array(rows) => rows,
        Value::Object(_) => vec![value],
        _ => Vec::new(),
    };
    rows.iter()
        .filter_map(|row| {
            let key = row.get("key").and_then(Value::as_str)?;
            let key = keys.iter().copied().find(|known| *known == key)?;
            Some(Check::new(
                key,
                row.get("ok").and_then(Value::as_bool).unwrap_or(false),
                row.get("detail").and_then(Value::as_str).unwrap_or(""),
                row.get("fixable").and_then(Value::as_bool).unwrap_or(false),
            ))
        })
        .collect()
}

#[cfg_attr(not(windows), allow(dead_code))]
pub const KEYS: [&str; 5] = [
    "firewall",
    "disk_encryption",
    "os_updates",
    "antivirus",
    "screen_lock",
];

#[cfg(windows)]
mod platform {
    use super::*;
    use crate::fleet::win;

    const CHECKS: &str = r#"$ErrorActionPreference = 'SilentlyContinue'
$checks = @()

$profiles = @(Get-NetFirewallProfile)
if ($profiles.Count -gt 0) {
    $off = @($profiles | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
    $detail = if ($off.Count -eq 0) { 'Windows Firewall is on for all profiles.' } else { 'Windows Firewall is off for: ' + ($off -join ', ') }
    $checks += [pscustomobject]@{ key = 'firewall'; ok = ($off.Count -eq 0); detail = $detail; fixable = $true }
}

$volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
if ($volume) {
    $on = "$($volume.ProtectionStatus)" -eq 'On'
    $checks += [pscustomobject]@{ key = 'disk_encryption'; ok = $on; detail = "BitLocker on ${env:SystemDrive}: $($volume.ProtectionStatus), $($volume.VolumeStatus)"; fixable = $false }
} else {
    $checks += [pscustomobject]@{ key = 'disk_encryption'; ok = $false; detail = "BitLocker is not available or not set up on ${env:SystemDrive}."; fixable = $false }
}

$pending = $null
try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $pending = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'").Updates.Count
} catch {}
if ($pending -ne $null) {
    $detail = if ($pending -eq 0) { 'No updates are waiting.' } else { "$pending updates are waiting to be installed." }
    $checks += [pscustomobject]@{ key = 'os_updates'; ok = ($pending -eq 0); detail = $detail; fixable = $true }
} else {
    $last = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($last) {
        $days = [int]((Get-Date) - $last.InstalledOn).TotalDays
        $checks += [pscustomobject]@{ key = 'os_updates'; ok = ($days -le 45); detail = "The last update was installed $days days ago."; fixable = $true }
    }
}

$av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct)
if ($av.Count -gt 0) {
    $active = @($av | Where-Object { (($_.productState -shr 12) -band 0xF) -eq 1 })
    $names = ($av | ForEach-Object { $_.displayName }) -join ', '
    $detail = if ($active.Count -gt 0) { 'Active: ' + (($active | ForEach-Object { $_.displayName }) -join ', ') } else { "Installed but not active: $names" }
    $checks += [pscustomobject]@{ key = 'antivirus'; ok = ($active.Count -gt 0); detail = $detail; fixable = $false }
} else {
    $mp = Get-MpComputerStatus
    if ($mp) {
        $on = $mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled
        $checks += [pscustomobject]@{ key = 'antivirus'; ok = $on; detail = "Microsoft Defender: real-time protection $(if ($mp.RealTimeProtectionEnabled) { 'on' } else { 'off' })"; fixable = $false }
    } else {
        $checks += [pscustomobject]@{ key = 'antivirus'; ok = $false; detail = 'No antivirus product is registered.'; fixable = $false }
    }
}

$limit = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name InactivityTimeoutSecs).InactivityTimeoutSecs
if ($limit -and $limit -gt 0 -and $limit -le 900) {
    $checks += [pscustomobject]@{ key = 'screen_lock'; ok = $true; detail = "The computer locks after $limit seconds without input."; fixable = $true }
} else {
    $users = @(Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' })
    $locked = @($users | Where-Object {
        $d = Get-ItemProperty -Path "Registry::HKEY_USERS\$($_.PSChildName)\Control Panel\Desktop"
        $d.ScreenSaveActive -eq '1' -and $d.ScreenSaverIsSecure -eq '1' -and [int]$d.ScreenSaveTimeOut -gt 0 -and [int]$d.ScreenSaveTimeOut -le 900
    })
    if ($users.Count -gt 0 -and $locked.Count -eq $users.Count) {
        $checks += [pscustomobject]@{ key = 'screen_lock'; ok = $true; detail = 'The screen saver locks within 15 minutes for the signed-in users.'; fixable = $true }
    } else {
        $checks += [pscustomobject]@{ key = 'screen_lock'; ok = $false; detail = 'No lock after at most 15 minutes without input is set.'; fixable = $true }
    }
}

ConvertTo-Json -InputObject @($checks) -Compress
"#;

    pub fn checks() -> Vec<Check> {
        match win::powershell(CHECKS, Duration::from_secs(600)) {
            Ok(outcome) => parse_checks(&outcome.output, &KEYS),
            Err(err) => {
                hbb_common::log::warn!("fleet compliance checks did not run: {err}");
                Vec::new()
            }
        }
    }

    pub fn fix(key: &str) -> Result<(), String> {
        let script = match key {
            "firewall" => "Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop",
            "screen_lock" => {
                "New-Item -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Force | Out-Null\nSet-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name InactivityTimeoutSecs -Value 900 -Type DWord -ErrorAction Stop"
            }
            "os_updates" => {
                "$uso = Join-Path $env:SystemRoot 'System32\\UsoClient.exe'\nif (-not (Test-Path $uso)) { throw 'UsoClient is not available.' }\n& $uso StartScan\n& $uso StartDownload"
            }
            _ => return Err("Not fixable.".to_owned()),
        };
        win::ps(script).map(|_| ())
    }

    pub fn software() -> Vec<Software> {
        use winreg::{enums::*, RegKey};
        const UNINSTALL: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
        const UNINSTALL_32: &str =
            "Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
        let mut roots: Vec<(RegKey, String)> = vec![
            (RegKey::predef(HKEY_LOCAL_MACHINE), UNINSTALL.to_owned()),
            (RegKey::predef(HKEY_LOCAL_MACHINE), UNINSTALL_32.to_owned()),
        ];
        let users = RegKey::predef(HKEY_USERS);
        for sid in users.enum_keys().flatten() {
            if sid.starts_with("S-1-5-21-") && !sid.ends_with("_Classes") {
                roots.push((RegKey::predef(HKEY_USERS), format!("{sid}\\{UNINSTALL}")));
            }
        }
        let mut software = Vec::new();
        for (root, path) in roots {
            let Ok(key) = root.open_subkey_with_flags(&path, KEY_READ) else {
                continue;
            };
            for name in key.enum_keys().flatten() {
                let Ok(entry) = key.open_subkey_with_flags(&name, KEY_READ) else {
                    continue;
                };
                let display: String = entry.get_value("DisplayName").unwrap_or_default();
                if display.trim().is_empty() {
                    continue;
                }
                let system: u32 = entry.get_value("SystemComponent").unwrap_or(0);
                let parent: String = entry.get_value("ParentKeyName").unwrap_or_default();
                if system == 1 || !parent.is_empty() {
                    continue;
                }
                software.push(Software {
                    name: display,
                    version: entry.get_value("DisplayVersion").unwrap_or_default(),
                    publisher: entry.get_value("Publisher").unwrap_or_default(),
                });
            }
        }
        software
    }
}

#[cfg(target_os = "linux")]
mod platform {
    use super::*;

    fn sh(script: &str) -> Result<String, String> {
        quick("/bin/sh", &["-c", script])
    }

    fn has(program: &str) -> bool {
        sh(&format!("command -v {program} >/dev/null 2>&1")).is_ok()
    }

    fn firewall() -> Option<Check> {
        if has("ufw") {
            let status = sh("ufw status 2>&1").unwrap_or_else(|err| err);
            let on = status.contains("Status: active");
            return Some(Check::new(
                "firewall",
                on,
                format!("ufw: {}", status.lines().next().unwrap_or("").trim()),
                true,
            ));
        }
        if has("firewall-cmd") {
            let on = sh("firewall-cmd --state 2>&1")
                .map(|s| s.trim() == "running")
                .unwrap_or(false);
            return Some(Check::new(
                "firewall",
                on,
                if on {
                    "firewalld is running."
                } else {
                    "firewalld is not running."
                },
                true,
            ));
        }
        if has("nft") {
            let rules =
                sh("nft list ruleset 2>/dev/null | grep -c 'hook input'").unwrap_or_default();
            let on = rules.trim().parse::<u32>().unwrap_or(0) > 0;
            return Some(Check::new(
                "firewall",
                on,
                if on {
                    "nftables filters incoming traffic."
                } else {
                    "No firewall (ufw, firewalld, nftables) filters incoming traffic."
                },
                false,
            ));
        }
        Some(Check::new(
            "firewall",
            false,
            "No firewall (ufw, firewalld, nftables) found.",
            false,
        ))
    }

    fn disk_encryption() -> Option<Check> {
        let source = sh("findmnt -no SOURCE /").ok()?;
        let source = source.trim();
        if source.is_empty() {
            return None;
        }
        let types = sh(&format!(
            "lsblk -nso TYPE {} 2>/dev/null",
            host::sh_quote(source)
        ))
        .unwrap_or_default();
        let on = types.lines().any(|line| line.trim() == "crypt");
        Some(Check::new(
            "disk_encryption",
            on,
            if on {
                format!("The root file system ({source}) is encrypted.")
            } else {
                format!("The root file system ({source}) is not encrypted.")
            },
            false,
        ))
    }

    fn os_updates() -> Option<Check> {
        let count = if has("apt-get") {
            sh("apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null | grep -c '^Inst '")
                .ok()
                .or(Some("0".to_owned()))
        } else if has("dnf") {
            sh("dnf -q check-update 2>/dev/null | grep -c '^[[:alnum:]]'; true").ok()
        } else if has("zypper") {
            sh("zypper -q --non-interactive list-updates 2>/dev/null | grep -c '^v '; true").ok()
        } else {
            None
        }?;
        let count = count
            .trim()
            .lines()
            .next()
            .unwrap_or("0")
            .trim()
            .parse::<u32>()
            .unwrap_or(0);
        Some(Check::new(
            "os_updates",
            count == 0,
            if count == 0 {
                "No updates are waiting.".to_owned()
            } else {
                format!("{count} updates are waiting to be installed.")
            },
            true,
        ))
    }

    fn screen_lock() -> Option<Check> {
        let (uid, user) = crate::platform::linux::get_active_user_id_name();
        if uid.is_empty() || user.is_empty() || !has("gsettings") {
            return None;
        }
        let get = |schema: &str, key: &str| {
            sh(&format!(
                "runuser -u {user} -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus gsettings get {schema} {key}",
                user = host::sh_quote(&user),
                uid = uid.trim(),
            ))
            .ok()
            .map(|value| value.trim().to_owned())
        };
        let lock = get("org.gnome.desktop.screensaver", "lock-enabled")?;
        let idle = get("org.gnome.desktop.session", "idle-delay")?;
        let idle = idle
            .split_whitespace()
            .last()
            .unwrap_or("0")
            .parse::<u32>()
            .unwrap_or(0);
        let ok = lock == "true" && idle > 0 && idle <= 900;
        Some(Check::new(
            "screen_lock",
            ok,
            format!("GNOME for {user}: lock {lock}, idle after {idle} seconds."),
            true,
        ))
    }

    pub fn checks() -> Vec<Check> {
        [firewall(), disk_encryption(), os_updates(), screen_lock()]
            .into_iter()
            .flatten()
            .collect()
    }

    pub fn fix(key: &str) -> Result<(), String> {
        match key {
            "firewall" if has("ufw") => {
                // Keep SSH reachable when the computer runs it
                sh("if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then ufw allow 22/tcp; fi; ufw --force enable").map(|_| ())
            }
            "firewall" if has("firewall-cmd") => sh("systemctl enable --now firewalld").map(|_| ()),
            "os_updates" => sh(
                "export DEBIAN_FRONTEND=noninteractive; if command -v apt-get >/dev/null; then apt-get update && apt-get -y -d dist-upgrade; elif command -v dnf >/dev/null; then dnf -y upgrade --downloadonly; elif command -v zypper >/dev/null; then zypper --non-interactive update --download-only; fi",
            )
            .map(|_| ()),
            "screen_lock" => {
                let (uid, user) = crate::platform::linux::get_active_user_id_name();
                let set = |schema: &str, key: &str, value: &str| {
                    sh(&format!(
                        "runuser -u {user} -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus gsettings set {schema} {key} {value}",
                        user = host::sh_quote(&user),
                        uid = uid.trim(),
                    ))
                };
                set("org.gnome.desktop.screensaver", "lock-enabled", "true")?;
                set("org.gnome.desktop.session", "idle-delay", "'uint32 900'").map(|_| ())
            }
            _ => Err("Not fixable here.".to_owned()),
        }
    }

    pub fn software() -> Vec<Software> {
        if let Ok(text) = quick(
            "dpkg-query",
            &["-W", "-f", "${Package}\t${Version}\t${Maintainer}\n"],
        ) {
            return parse_package_lines(&text);
        }
        if let Ok(text) = quick(
            "rpm",
            &["-qa", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\t%{VENDOR}\n"],
        ) {
            return parse_package_lines(&text);
        }
        Vec::new()
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use super::*;

    pub fn checks() -> Vec<Check> {
        let mut checks = Vec::new();
        if let Ok(state) = quick(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            &["--getglobalstate"],
        ) {
            let on = state.contains("enabled")
                || state.contains("State = 1")
                || state.contains("State = 2");
            checks.push(Check::new("firewall", on, state.trim(), true));
        }
        if let Ok(state) = quick("fdesetup", &["status"]) {
            checks.push(Check::new(
                "disk_encryption",
                state.contains("FileVault is On"),
                state.trim(),
                false,
            ));
        }
        if let Ok(list) = quick("softwareupdate", &["-l"]) {
            let waiting = list
                .lines()
                .filter(|line| line.trim_start().starts_with("* "))
                .count();
            checks.push(Check::new(
                "os_updates",
                waiting == 0,
                if waiting == 0 {
                    "No updates are waiting.".to_owned()
                } else {
                    format!("{waiting} updates are waiting to be installed.")
                },
                true,
            ));
        }
        let gatekeeper = quick("spctl", &["--status"]).unwrap_or_else(|err| err);
        let on = gatekeeper.contains("assessments enabled");
        checks.push(Check::new(
            "antivirus",
            on,
            if on {
                "Gatekeeper and XProtect are on."
            } else {
                "Gatekeeper is off."
            },
            false,
        ));
        if let Ok(state) = quick("sysadminctl", &["-screenLock", "status"]) {
            let text = state.to_lowercase();
            let ok = text.contains("immediate")
                || text
                    .split_whitespace()
                    .filter_map(|word| word.parse::<u32>().ok())
                    .next()
                    .map_or(false, |seconds| seconds <= 900)
                    && !text.contains("is off");
            checks.push(Check::new("screen_lock", ok, state.trim(), false));
        }
        checks
    }

    pub fn fix(key: &str) -> Result<(), String> {
        match key {
            "firewall" => quick(
                "/usr/libexec/ApplicationFirewall/socketfilterfw",
                &["--setglobalstate", "on"],
            )
            .map(|_| ()),
            "os_updates" => quick("softwareupdate", &["-d", "-a"]).map(|_| ()),
            _ => Err("Not fixable here.".to_owned()),
        }
    }

    pub fn software() -> Vec<Software> {
        let mut software = Vec::new();
        for folder in ["/Applications", "/Applications/Utilities"] {
            let Ok(entries) = std::fs::read_dir(folder) else {
                continue;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) != Some("app") {
                    continue;
                }
                let name = path
                    .file_stem()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();
                let plist = path.join("Contents/Info.plist");
                let plist = plist.to_string_lossy().to_string();
                let read = |key: &str| {
                    quick(
                        "/usr/bin/plutil",
                        &["-extract", key, "raw", "-o", "-", &plist],
                    )
                    .map(|value| value.trim().to_owned())
                    .unwrap_or_default()
                };
                software.push(Software {
                    name,
                    version: read("CFBundleShortVersionString"),
                    publisher: String::new(),
                });
            }
        }
        software
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remediate_is_off_unless_asked() {
        assert!(!remediate_requested(&json!({})));
        assert!(!remediate_requested(&json!({"remediate": false})));
        assert!(!remediate_requested(&json!({"remediate": "no"})));
        assert!(remediate_requested(&json!({"remediate": true})));
    }

    #[test]
    fn package_lines_become_software() {
        let text = "bash\t5.2-1\tUbuntu Developers <ubuntu-devel@lists.ubuntu.com>\nvim\t9.0\t(none)\n\n(none)\t1\tx\nlone\n";
        let software = parse_package_lines(text);
        assert_eq!(
            software,
            vec![
                Software {
                    name: "bash".into(),
                    version: "5.2-1".into(),
                    publisher: "Ubuntu Developers".into()
                },
                Software {
                    name: "vim".into(),
                    version: "9.0".into(),
                    publisher: "".into()
                },
                Software {
                    name: "lone".into(),
                    version: "".into(),
                    publisher: "".into()
                },
            ]
        );
    }

    #[test]
    fn checks_come_from_the_script_json() {
        let text = "WARNING: noise\n[{\"key\":\"firewall\",\"ok\":true,\"detail\":\"on\",\"fixable\":true},{\"key\":\"made_up\",\"ok\":true},{\"key\":\"screen_lock\",\"ok\":false,\"detail\":\"none\",\"fixable\":true}]";
        let checks = parse_checks(text, &KEYS);
        assert_eq!(checks.len(), 2);
        assert_eq!(
            checks[0],
            Check {
                key: "firewall",
                ok: true,
                detail: "on".into(),
                fixable: false
            }
        );
        assert_eq!(
            checks[1],
            Check {
                key: "screen_lock",
                ok: false,
                detail: "none".into(),
                fixable: true
            }
        );
        // PowerShell 5 prints a single object without the array
        let one = parse_checks("{\"key\":\"antivirus\",\"ok\":false}", &KEYS);
        assert_eq!(one.len(), 1);
        assert!(parse_checks("garbage", &KEYS).is_empty());
    }

    #[test]
    fn the_result_has_software_and_checks() {
        let checks = vec![Check::new("firewall", false, "off", true)];
        let software = vec![
            Software {
                name: "Zed".into(),
                version: "1".into(),
                publisher: "Z".into(),
            },
            Software {
                name: "app".into(),
                version: "2".into(),
                publisher: "".into(),
            },
            Software {
                name: "App".into(),
                version: "2".into(),
                publisher: "".into(),
            },
            Software {
                name: " ".into(),
                version: "2".into(),
                publisher: "".into(),
            },
        ];
        let result = result_json(&checks, software, &["firewall".to_owned()]);
        assert_eq!(
            result["checks"][0],
            json!({"key": "firewall", "ok": false, "detail": "off", "fixable": true})
        );
        let names: Vec<&str> = result["software"]
            .as_array()
            .unwrap()
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["app", "Zed"]);
        assert_eq!(result["software"][0]["publisher"], "");
        assert_eq!(result["remediated"], json!(["firewall"]));
        assert!(result.get("software_truncated").is_none());
    }

    #[test]
    fn a_huge_software_list_is_cut_to_fit() {
        let software = (0..10_000)
            .map(|i| Software {
                name: format!("package-{i:05}"),
                version: "1.0.0-1ubuntu1".into(),
                publisher: "Some Publisher".into(),
            })
            .collect();
        let (list, truncated) = software_json(software);
        assert!(truncated);
        assert!(list.to_string().len() <= MAX_SOFTWARE_BYTES);
        assert!(list.as_array().unwrap().len() > 1000);
    }

    #[test]
    fn a_scan_reports_the_shape_the_server_reads() {
        let (status, result) = collect(false);
        assert_eq!(status, "ok");
        assert!(result["software"].is_array());
        let checks = result["checks"].as_array().unwrap();
        for check in checks {
            assert!(KEYS.contains(&check["key"].as_str().unwrap()), "{check}");
            assert!(
                check["ok"].is_boolean()
                    && check["fixable"].is_boolean()
                    && check["detail"].is_string()
            );
        }
        assert!(result.to_string().len() < 256 * 1024);
    }
}
