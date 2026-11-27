//! fleet.resources: the printers, network drives, DNS servers, VPN
//! connections and proxy the server wants on this computer.
//!
//! The list is the whole desired state. What the client set up under an
//! earlier revision and the list no longer has is taken away again, so the
//! client remembers what it set up and the revision it came with.

use std::{net::IpAddr, sync::Mutex};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::host;

const STATE_OPTION: &str = "nd-fleet-resources";

lazy_static::lazy_static! {
    static ref APPLY_LOCK: Mutex<()> = Mutex::new(());
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Printer,
    NetworkDrive,
    Dns,
    Vpn,
    Proxy,
}

impl Kind {
    fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "printer" => Self::Printer,
            "network_drive" => Self::NetworkDrive,
            "dns" => Self::Dns,
            "vpn" => Self::Vpn,
            "proxy" => Self::Proxy,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Printer => "printer",
            Self::NetworkDrive => "network_drive",
            Self::Dns => "dns",
            Self::Vpn => "vpn",
            Self::Proxy => "proxy",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Resource {
    pub id: i64,
    pub kind: Kind,
    pub name: String,
    pub address: String,
}

/// Something the client set up, with what it needs to take it away
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Applied {
    pub id: i64,
    #[serde(rename = "type")]
    pub kind: String,
    pub name: String,
    pub address: String,
    /// Platform detail, such as the drive letter a network drive got
    #[serde(default)]
    pub handle: String,
}

impl Applied {
    fn same(&self, resource: &Resource) -> bool {
        self.id == resource.id
            && self.kind == resource.kind.name()
            && self.name == resource.name
            && self.address == resource.address
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Saved {
    #[serde(default)]
    pub revision: String,
    #[serde(default)]
    pub applied: Vec<Applied>,
}

#[derive(Debug, PartialEq, Eq)]
#[cfg_attr(windows, allow(dead_code))]
pub enum ItemError {
    Unsupported(String),
    Failed(String),
}

/// What sets things up on this platform
pub trait Backend {
    /// Sets up `resource`, `previous` being what an earlier revision set up
    /// for the same item. Gives the handle to remove it by.
    fn add(&mut self, resource: &Resource, previous: Option<&Applied>)
        -> Result<String, ItemError>;
    fn remove(&mut self, applied: &Applied) -> Result<(), String>;
    /// Puts these DNS servers on the active network adapters
    fn set_dns(&mut self, servers: &[IpAddr]) -> Result<String, ItemError>;
    /// Gives the adapters their own DNS servers back
    fn reset_dns(&mut self, handle: &str) -> Result<(), String>;
}

fn clean_text(value: &str, max: usize) -> Option<String> {
    let value = value.trim();
    if value.len() > max || value.chars().any(|c| c.is_control()) {
        return None;
    }
    Some(value.to_owned())
}

/// The DNS servers of a dns resource: addresses split by commas, semicolons
/// or spaces
pub fn dns_servers(address: &str) -> Result<Vec<IpAddr>, String> {
    let servers = address
        .split(|c: char| c == ',' || c == ';' || c.is_whitespace())
        .filter(|part| !part.is_empty())
        .map(|part| {
            part.parse::<IpAddr>()
                .map_err(|_| format!("\"{part}\" is no IP address."))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if servers.is_empty() {
        return Err("The DNS resource has no server address.".to_owned());
    }
    Ok(servers)
}

/// host and port of a proxy address: "host:port", "http://host:port/",
/// "[::1]:3128". The port is 8080 when missing.
pub fn proxy_endpoint(address: &str) -> Result<(String, u16), String> {
    let rest = address.trim();
    let rest = rest
        .strip_prefix("http://")
        .or_else(|| rest.strip_prefix("https://"))
        .unwrap_or(rest)
        .trim_end_matches('/');
    let (host, port) = if let Some(inner) = rest.strip_prefix('[') {
        let (host, after) = inner
            .split_once(']')
            .ok_or_else(|| format!("\"{address}\" is no proxy address."))?;
        (host.to_owned(), after.strip_prefix(':').unwrap_or(""))
    } else {
        match rest.rsplit_once(':') {
            Some((host, port)) if !host.contains(':') => (host.to_owned(), port),
            Some(_) => return Err(format!("\"{address}\": put an IPv6 address in brackets.")),
            None => (rest.to_owned(), ""),
        }
    };
    let valid_host = !host.is_empty()
        && host.len() <= 253
        && host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ".-:".contains(c));
    if !valid_host {
        return Err(format!("\"{address}\" is no proxy address."));
    }
    let port = if port.is_empty() {
        8080
    } else {
        match port.parse::<u16>() {
            Ok(port) if port > 0 => port,
            _ => return Err(format!("\"{port}\" is no port.")),
        }
    };
    Ok((host, port))
}

/// A Windows share: \\server\share with an optional path after it
pub fn unc_path(address: &str) -> Option<String> {
    let address = address.trim().replace('/', "\\");
    let rest = address.strip_prefix("\\\\")?;
    let mut parts = rest.split('\\');
    let server = parts.next()?;
    let share = parts.next()?;
    let valid = |part: &str| {
        !part.is_empty()
            && !part
                .chars()
                .any(|c| c.is_control() || "\"<>|*?".contains(c))
    };
    if !valid(server) || !valid(share) || address.len() > 260 {
        return None;
    }
    Some(address.trim_end_matches('\\').to_owned())
}

/// A host name or an IP address
pub fn host_name(address: &str) -> Option<String> {
    let address = address.trim();
    if address.parse::<IpAddr>().is_ok() {
        return Some(address.to_owned());
    }
    let valid = !address.is_empty()
        && address.len() <= 253
        && !address.starts_with('-')
        && address
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || ".-".contains(c));
    valid.then(|| address.to_owned())
}

/// The drive letter a network drive's name asks for: "Z:" or "Z"
#[cfg_attr(not(windows), allow(dead_code))]
pub fn drive_letter(name: &str) -> Option<char> {
    let name = name.trim();
    let name = name.strip_suffix(':').unwrap_or(name);
    let mut chars = name.chars();
    match (chars.next(), chars.next()) {
        (Some(letter), None) if letter.is_ascii_alphabetic() => Some(letter.to_ascii_uppercase()),
        _ => None,
    }
}

/// Reads one entry of the list; an error names what is wrong with it
pub fn parse_resource(value: &Value) -> Result<Resource, (i64, String)> {
    let id = value.get("id").and_then(Value::as_i64).unwrap_or(0);
    let kind_name = value.get("type").and_then(Value::as_str).unwrap_or("");
    let kind = Kind::parse(kind_name)
        .ok_or_else(|| (id, format!("Unknown resource type \"{kind_name}\".")))?;
    let name = clean_text(value.get("name").and_then(Value::as_str).unwrap_or(""), 128)
        .ok_or_else(|| {
            (
                id,
                "The name is too long or has control characters.".to_owned(),
            )
        })?;
    let address = clean_text(
        value.get("address").and_then(Value::as_str).unwrap_or(""),
        512,
    )
    .ok_or_else(|| {
        (
            id,
            "The address is too long or has control characters.".to_owned(),
        )
    })?;
    let resource = Resource {
        id,
        kind,
        name,
        address,
    };
    validate(&resource).map_err(|message| (id, message))?;
    Ok(resource)
}

fn validate(resource: &Resource) -> Result<(), String> {
    match resource.kind {
        Kind::Dns => dns_servers(&resource.address).map(|_| ()),
        Kind::Proxy => proxy_endpoint(&resource.address).map(|_| ()),
        Kind::NetworkDrive => unc_path(&resource.address).map(|_| ()).ok_or_else(|| {
            "A network drive's address is a share like \\\\server\\share.".to_owned()
        }),
        Kind::Printer => {
            if unc_path(&resource.address).is_some() || host_name(&resource.address).is_some() {
                Ok(())
            } else {
                Err("A printer's address is \\\\server\\printer or the printer's host name or IP address.".to_owned())
            }
        }
        Kind::Vpn => {
            if resource.name.is_empty() {
                Err("A VPN connection needs a name.".to_owned())
            } else if host_name(&resource.address).is_none() {
                Err("A VPN's address is the server's host name or IP address.".to_owned())
            } else {
                Ok(())
            }
        }
    }
}

fn item(id: i64, status: &str, message: impl Into<String>) -> Value {
    json!({"id": id, "status": status, "message": message.into()})
}

/// Applies `args` over `saved` with `backend`: the new saved state, the
/// overall status and the result for the server.
pub fn reconcile(args: &Value, saved: &Saved, backend: &mut dyn Backend) -> (Saved, String, Value) {
    let revision = args
        .get("revision")
        .and_then(Value::as_str)
        .unwrap_or("")
        .chars()
        .take(128)
        .collect::<String>();
    let listed = args
        .get("resources")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut items = Vec::new();
    let mut desired = Vec::new();
    for value in listed.iter().take(200) {
        match parse_resource(value) {
            Ok(resource) => desired.push(resource),
            Err((id, message)) => items.push(item(id, "error", message)),
        }
    }

    // Take away what is gone or changed. DNS is one setting for all dns
    // items together, handled below.
    let mut kept = Vec::new();
    let mut removed = Vec::new();
    let mut old_dns = None;
    for applied in &saved.applied {
        if applied.kind == Kind::Dns.name() {
            old_dns.get_or_insert_with(|| applied.handle.clone());
            continue;
        }
        if desired.iter().any(|resource| applied.same(resource)) {
            kept.push(applied.clone());
            continue;
        }
        match backend.remove(applied) {
            Ok(()) => removed.push(item(applied.id, "ok", "Removed.")),
            Err(message) => {
                removed.push(item(applied.id, "error", message));
                // Tried again with the next revision
                kept.push(applied.clone());
            }
        }
    }

    let mut applied_now: Vec<Applied> = kept
        .iter()
        .filter(|applied| !desired.iter().any(|resource| applied.same(resource)))
        .cloned()
        .collect();

    // DNS: the servers of all dns items in their order
    let dns_items: Vec<&Resource> = desired.iter().filter(|r| r.kind == Kind::Dns).collect();
    if dns_items.is_empty() {
        if let Some(handle) = old_dns {
            match backend.reset_dns(&handle) {
                Ok(()) => removed.push(item(0, "ok", "DNS servers reset.")),
                Err(message) => {
                    removed.push(item(0, "error", message));
                    applied_now.extend(
                        saved
                            .applied
                            .iter()
                            .filter(|a| a.kind == Kind::Dns.name())
                            .cloned(),
                    );
                }
            }
        }
    } else {
        let mut servers = Vec::new();
        for resource in &dns_items {
            for server in dns_servers(&resource.address).unwrap_or_default() {
                if !servers.contains(&server) {
                    servers.push(server);
                }
            }
        }
        let outcome = backend.set_dns(&servers);
        for resource in &dns_items {
            match &outcome {
                Ok(handle) => {
                    // The first handle is the one that knows the adapters'
                    // own settings
                    let handle = old_dns.clone().unwrap_or_else(|| handle.clone());
                    applied_now.push(applied_of(resource, handle));
                    items.push(item(resource.id, "ok", "DNS servers set."));
                }
                Err(ItemError::Unsupported(message)) => {
                    items.push(item(resource.id, "unsupported", message.clone()))
                }
                Err(ItemError::Failed(message)) => {
                    items.push(item(resource.id, "error", message.clone()))
                }
            }
        }
        if outcome.is_err() {
            if let Some(handle) = &old_dns {
                // Still in place from before
                applied_now.extend(
                    saved
                        .applied
                        .iter()
                        .filter(|a| a.kind == Kind::Dns.name())
                        .map(|a| Applied {
                            handle: handle.clone(),
                            ..a.clone()
                        }),
                );
            }
        }
    }

    let mut proxy_done = false;
    for resource in desired.iter().filter(|r| r.kind != Kind::Dns) {
        if resource.kind == Kind::Proxy {
            if proxy_done {
                items.push(item(
                    resource.id,
                    "error",
                    "Only one proxy applies; an earlier one in the list won.",
                ));
                continue;
            }
            proxy_done = true;
        }
        let previous = saved.applied.iter().find(|a| a.same(resource));
        match backend.add(resource, previous) {
            Ok(handle) => {
                applied_now.push(applied_of(resource, handle));
                items.push(item(resource.id, "ok", ""));
            }
            Err(ItemError::Unsupported(message)) => {
                items.push(item(resource.id, "unsupported", message))
            }
            Err(ItemError::Failed(message)) => {
                items.push(item(resource.id, "error", message));
                if let Some(previous) = previous {
                    // It was there before; it may still be
                    applied_now.push(previous.clone());
                }
            }
        }
    }

    let status = if items
        .iter()
        .chain(removed.iter())
        .any(|i| i["status"] == "error")
    {
        "error"
    } else {
        "ok"
    };
    let mut result = json!({"revision": revision, "items": items});
    if !removed.is_empty() {
        result["removed"] = Value::Array(removed);
    }
    (
        Saved {
            revision,
            applied: applied_now,
        },
        status.to_owned(),
        result,
    )
}

fn applied_of(resource: &Resource, handle: String) -> Applied {
    Applied {
        id: resource.id,
        kind: resource.kind.name().to_owned(),
        name: resource.name.clone(),
        address: resource.address.clone(),
        handle,
    }
}

pub fn load_saved() -> Saved {
    serde_json::from_str(&host::load(STATE_OPTION)).unwrap_or_default()
}

/// fleet.resources on this computer
pub fn apply(args: &Value) -> (String, Value) {
    let _lock = APPLY_LOCK.lock().unwrap_or_else(|err| err.into_inner());
    if !host::is_elevated() {
        let revision = args.get("revision").cloned().unwrap_or(Value::Null);
        return (
            "permission_denied".to_owned(),
            json!({"revision": revision, "items": [], "code": "not_elevated"}),
        );
    }
    let saved = load_saved();
    let mut backend = platform_backend();
    let (next, status, result) = reconcile(args, &saved, &mut *backend);
    host::store(
        STATE_OPTION,
        serde_json::to_string(&next).unwrap_or_default(),
    );
    (status, result)
}

fn platform_backend() -> Box<dyn Backend> {
    #[cfg(windows)]
    {
        Box::new(windows_backend::Windows)
    }
    #[cfg(not(windows))]
    {
        Box::new(unix_backend::Unix)
    }
}

#[cfg(windows)]
mod windows_backend {
    use super::*;
    use crate::fleet::win;

    pub struct Windows;

    fn q(value: &str) -> String {
        host::ps_quote(value)
    }

    /// A printer at a host name or IP address gets a TCP/IP port of its own
    fn port_name(address: &str) -> String {
        format!("NeoDesk_{address}")
    }

    impl Backend for Windows {
        fn add(
            &mut self,
            resource: &Resource,
            previous: Option<&Applied>,
        ) -> Result<String, ItemError> {
            let failed = ItemError::Failed;
            match resource.kind {
                Kind::Printer => {
                    if let Some(path) = unc_path(&resource.address) {
                        // For every user at logon, and right away for the
                        // one signed in
                        win::ps(&format!(
                            "$r = Start-Process -FilePath rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /ga /q /n\"' + {p} + '\"') -Wait -PassThru\nif ($r.ExitCode -ne 0) {{ throw ('printui failed: ' + $r.ExitCode) }}",
                            p = q(&path)
                        ))
                        .map_err(failed)?;
                        let now = win::ps_as_user(&format!(
                            "Add-Printer -ConnectionName {p} -ErrorAction Stop",
                            p = q(&path)
                        ));
                        if let Err(message) = now {
                            hbb_common::log::info!(
                                "printer connection for the signed-in user: {message}"
                            );
                        }
                        Ok(format!("unc:{path}"))
                    } else {
                        let address = host_name(&resource.address).unwrap_or_default();
                        let name = if resource.name.is_empty() {
                            address.clone()
                        } else {
                            resource.name.clone()
                        };
                        win::ps(&format!(
                            r#"$ErrorActionPreference = 'Stop'
$port = {port}; $name = {name}; $address = {address}
if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) {{ Add-PrinterPort -Name $port -PrinterHostAddress $address }}
$drivers = 'Microsoft IPP Class Driver', 'Microsoft PCL6 Class Driver', 'Microsoft PS Class Driver', 'Generic / Text Only'
$driver = $drivers | Where-Object {{ Get-PrinterDriver -Name $_ -ErrorAction SilentlyContinue }} | Select-Object -First 1
if (-not $driver) {{ Add-PrinterDriver -Name 'Microsoft IPP Class Driver'; $driver = 'Microsoft IPP Class Driver' }}
$printer = Get-Printer -Name $name -ErrorAction SilentlyContinue
if ($printer) {{ Set-Printer -Name $name -PortName $port }} else {{ Add-Printer -Name $name -PortName $port -DriverName $driver }}
"#,
                            port = q(&port_name(&address)),
                            name = q(&name),
                            address = q(&address)
                        ))
                        .map_err(failed)?;
                        Ok(format!("tcp:{name}"))
                    }
                }
                Kind::NetworkDrive => {
                    let path = unc_path(&resource.address).unwrap_or_default();
                    let wanted = drive_letter(&resource.name)
                        .or_else(|| previous.and_then(|p| drive_letter(&p.handle)))
                        .map(|letter| format!("{letter}:"))
                        .unwrap_or_default();
                    let label = if drive_letter(&resource.name).is_some() {
                        String::new()
                    } else {
                        resource.name.clone()
                    };
                    let output = win::ps_as_user(&format!(
                        r#"$ErrorActionPreference = 'Stop'
$path = {path}; $letter = {letter}; $label = {label}
$used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object {{ $_.Name.Substring(0, 2).ToUpper() }})
$mapped = @(Get-CimInstance -ClassName Win32_MappedLogicalDisk -ErrorAction SilentlyContinue | Where-Object {{ $_.ProviderName -eq $path }} | ForEach-Object {{ $_.DeviceID.ToUpper() }})
if (-not $letter) {{
    if ($mapped.Count -gt 0) {{ $letter = $mapped[0] }}
    else {{ $letter = 'ZYXWVUTSRQPONMLKJIHGFED'.ToCharArray() | ForEach-Object {{ "$($_):" }} | Where-Object {{ $used -notcontains $_ }} | Select-Object -First 1 }}
    if (-not $letter) {{ throw 'No free drive letter.' }}
}}
$local = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction SilentlyContinue
if ($local -and $local.DriveType -ne 4) {{ throw "$letter is a local drive." }}
& net.exe use $letter /delete /y 2>&1 | Out-Null
$out = & net.exe use $letter $path /persistent:yes 2>&1
if ($LASTEXITCODE -ne 0) {{ throw ($out | Out-String) }}
if ($label) {{ try {{ (New-Object -ComObject Shell.Application).NameSpace("$letter\").Self.Name = $label }} catch {{}} }}
Write-Output "LETTER=$letter"
"#,
                        path = q(&path),
                        letter = q(&wanted),
                        label = q(&label)
                    ))
                    .map_err(failed)?;
                    output
                        .lines()
                        .rev()
                        .find_map(|line| line.trim().strip_prefix("LETTER="))
                        .map(|letter| letter.trim().to_owned())
                        .ok_or_else(|| {
                            ItemError::Failed(format!(
                                "The drive was mapped, but its letter is unknown: {output}"
                            ))
                        })
                }
                Kind::Vpn => {
                    win::ps(&format!(
                        r#"$ErrorActionPreference = 'Stop'
$name = {name}; $server = {server}
if (Get-VpnConnection -AllUserConnection -Name $name -ErrorAction SilentlyContinue) {{
    Set-VpnConnection -AllUserConnection -Name $name -ServerAddress $server -Force
}} else {{
    Add-VpnConnection -AllUserConnection -Name $name -ServerAddress $server -TunnelType Automatic -Force
}}
"#,
                        name = q(&resource.name),
                        server = q(&host_name(&resource.address).unwrap_or_default())
                    ))
                    .map_err(failed)?;
                    Ok(resource.name.clone())
                }
                Kind::Proxy => {
                    let (host, port) = proxy_endpoint(&resource.address).map_err(failed)?;
                    let server = if host.contains(':') {
                        format!("[{host}]:{port}")
                    } else {
                        format!("{host}:{port}")
                    };
                    win::ps(&format!(
                        r#"$ErrorActionPreference = 'Stop'
$server = {server}
$out = & netsh.exe winhttp set proxy proxy-server="$server" bypass-list="<local>" 2>&1
if ($LASTEXITCODE -ne 0) {{ throw ($out | Out-String) }}
Get-ChildItem Registry::HKEY_USERS | Where-Object {{ $_.PSChildName -match '^S-1-5-21-[\d-]+$' }} | ForEach-Object {{
    $key = "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if (-not (Test-Path $key)) {{ New-Item -Path $key -Force | Out-Null }}
    Set-ItemProperty -Path $key -Name ProxyEnable -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name ProxyServer -Value $server -Type String
    Set-ItemProperty -Path $key -Name ProxyOverride -Value '<local>' -Type String
}}
"#,
                        server = q(&server)
                    ))
                    .map_err(failed)?;
                    Ok(server)
                }
                Kind::Dns => Err(ItemError::Failed("DNS goes through set_dns.".to_owned())),
            }
        }

        fn remove(&mut self, applied: &Applied) -> Result<(), String> {
            match Kind::parse(&applied.kind) {
                Some(Kind::Printer) => {
                    if let Some(path) = applied.handle.strip_prefix("unc:") {
                        win::ps(&format!(
                            "$r = Start-Process -FilePath rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /gd /q /n\"' + {p} + '\"') -Wait -PassThru",
                            p = q(path)
                        ))?;
                        let _ = win::ps_as_user(&format!(
                            "Remove-Printer -Name {p} -ErrorAction SilentlyContinue",
                            p = q(path)
                        ));
                        Ok(())
                    } else {
                        let name = applied.handle.strip_prefix("tcp:").unwrap_or(&applied.name);
                        let address = host_name(&applied.address).unwrap_or_default();
                        win::ps(&format!(
                            "Remove-Printer -Name {name} -ErrorAction SilentlyContinue\nRemove-PrinterPort -Name {port} -ErrorAction SilentlyContinue",
                            name = q(name),
                            port = q(&port_name(&address))
                        ))
                        .map(|_| ())
                    }
                }
                Some(Kind::NetworkDrive) => {
                    let Some(letter) = drive_letter(&applied.handle) else {
                        return Ok(());
                    };
                    win::ps_as_user(&format!(
                        "$out = & net.exe use {l} /delete /y 2>&1\nif ($LASTEXITCODE -ne 0 -and ($out | Out-String) -notmatch '2250') {{ throw ($out | Out-String) }}",
                        l = q(&format!("{letter}:"))
                    ))
                    .map(|_| ())
                }
                Some(Kind::Vpn) => win::ps(&format!(
                    "if (Get-VpnConnection -AllUserConnection -Name {n} -ErrorAction SilentlyContinue) {{ Remove-VpnConnection -AllUserConnection -Name {n} -Force -ErrorAction Stop }}",
                    n = q(&applied.handle)
                ))
                .map(|_| ()),
                Some(Kind::Proxy) => win::ps(
                    r#"$ErrorActionPreference = 'Stop'
& netsh.exe winhttp reset proxy | Out-Null
Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } | ForEach-Object {
    $key = "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if (Test-Path $key) {
        Set-ItemProperty -Path $key -Name ProxyEnable -Value 0 -Type DWord
        Remove-ItemProperty -Path $key -Name ProxyServer -ErrorAction SilentlyContinue
    }
}
"#,
                )
                .map(|_| ()),
                Some(Kind::Dns) | None => Ok(()),
            }
        }

        fn set_dns(&mut self, servers: &[IpAddr]) -> Result<String, ItemError> {
            let list = servers
                .iter()
                .map(|server| q(&server.to_string()))
                .collect::<Vec<_>>()
                .join(",");
            win::ps(&format!(
                r#"$ErrorActionPreference = 'Stop'
$adapters = @(Get-NetAdapter | Where-Object {{ $_.Status -eq 'Up' }})
if ($adapters.Count -eq 0) {{ throw 'No network adapter is up.' }}
foreach ($a in $adapters) {{ Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @({list}) }}
Clear-DnsClientCache
"#
            ))
            .map_err(ItemError::Failed)?;
            Ok("adapters".to_owned())
        }

        fn reset_dns(&mut self, _handle: &str) -> Result<(), String> {
            win::ps(
                "$ErrorActionPreference = 'Stop'\nGet-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses }\nClear-DnsClientCache",
            )
            .map(|_| ())
        }
    }
}

#[cfg(not(windows))]
mod unix_backend {
    use super::*;
    use crate::fleet::process;
    use std::time::Duration;

    pub struct Unix;

    fn sh(script: &str) -> Result<String, String> {
        process::quick("/bin/sh", &["-c", script], Duration::from_secs(120))
    }

    #[cfg(target_os = "linux")]
    const RESOLVED_DROP_IN: &str = "/etc/systemd/resolved.conf.d/neodesk-fleet.conf";
    #[cfg(target_os = "linux")]
    const RESOLV_BACKUP: &str = "/etc/resolv.conf.neodesk-backup";
    #[cfg(target_os = "linux")]
    const PROFILE_PROXY: &str = "/etc/profile.d/neodesk-proxy.sh";
    #[cfg(target_os = "linux")]
    const APT_PROXY: &str = "/etc/apt/apt.conf.d/95neodesk-proxy";

    #[cfg(target_os = "macos")]
    const SERVICES: &str = r#"networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*'"#;

    impl Backend for Unix {
        fn add(
            &mut self,
            resource: &Resource,
            _previous: Option<&Applied>,
        ) -> Result<String, ItemError> {
            match resource.kind {
                Kind::Proxy => {
                    let (host, port) =
                        proxy_endpoint(&resource.address).map_err(ItemError::Failed)?;
                    set_proxy(&host, port).map_err(ItemError::Failed)
                }
                Kind::Printer | Kind::NetworkDrive | Kind::Vpn => {
                    Err(ItemError::Unsupported(format!(
                        "{} resources are set up on Windows only.",
                        resource.kind.name()
                    )))
                }
                Kind::Dns => Err(ItemError::Failed("DNS goes through set_dns.".to_owned())),
            }
        }

        fn remove(&mut self, applied: &Applied) -> Result<(), String> {
            match Kind::parse(&applied.kind) {
                Some(Kind::Proxy) => reset_proxy(),
                _ => Ok(()),
            }
        }

        fn set_dns(&mut self, servers: &[IpAddr]) -> Result<String, ItemError> {
            let list = servers
                .iter()
                .map(|s| s.to_string())
                .collect::<Vec<_>>()
                .join(" ");
            set_dns(&list)
        }

        fn reset_dns(&mut self, handle: &str) -> Result<(), String> {
            reset_dns(handle)
        }
    }

    #[cfg(target_os = "linux")]
    fn set_dns(list: &str) -> Result<String, ItemError> {
        if std::path::Path::new("/run/systemd/resolve").is_dir() {
            let contents = format!(
                "# Set by NeoDesk fleet resources; removed when the server drops them\n[Resolve]\nDNS={list}\nDomains=~.\n"
            );
            std::fs::create_dir_all("/etc/systemd/resolved.conf.d")
                .and_then(|_| std::fs::write(RESOLVED_DROP_IN, contents))
                .map_err(|err| ItemError::Failed(format!("{RESOLVED_DROP_IN}: {err}")))?;
            sh("systemctl restart systemd-resolved").map_err(ItemError::Failed)?;
            return Ok("resolved".to_owned());
        }
        let resolv = std::path::Path::new("/etc/resolv.conf");
        let is_link = std::fs::symlink_metadata(resolv)
            .map(|meta| meta.file_type().is_symlink())
            .unwrap_or(false);
        if is_link {
            return Err(ItemError::Unsupported(
                "/etc/resolv.conf is managed by another service the client does not know."
                    .to_owned(),
            ));
        }
        if !std::path::Path::new(RESOLV_BACKUP).exists() {
            std::fs::copy(resolv, RESOLV_BACKUP)
                .map_err(|err| ItemError::Failed(format!("{RESOLV_BACKUP}: {err}")))?;
        }
        let contents = list
            .split(' ')
            .map(|server| format!("nameserver {server}\n"))
            .collect::<String>();
        std::fs::write(
            resolv,
            format!("# Set by NeoDesk fleet resources\n{contents}"),
        )
        .map_err(|err| ItemError::Failed(format!("/etc/resolv.conf: {err}")))?;
        Ok("resolv.conf".to_owned())
    }

    #[cfg(target_os = "linux")]
    fn reset_dns(_handle: &str) -> Result<(), String> {
        if std::path::Path::new(RESOLVED_DROP_IN).exists() {
            std::fs::remove_file(RESOLVED_DROP_IN)
                .map_err(|err| format!("{RESOLVED_DROP_IN}: {err}"))?;
            sh("systemctl restart systemd-resolved")?;
        }
        if std::path::Path::new(RESOLV_BACKUP).exists() {
            std::fs::copy(RESOLV_BACKUP, "/etc/resolv.conf")
                .map_err(|err| format!("/etc/resolv.conf: {err}"))?;
            let _ = std::fs::remove_file(RESOLV_BACKUP);
        }
        Ok(())
    }

    #[cfg(target_os = "linux")]
    fn set_proxy(host: &str, port: u16) -> Result<String, String> {
        let url = if host.contains(':') {
            format!("http://[{host}]:{port}")
        } else {
            format!("http://{host}:{port}")
        };
        let profile = format!(
            "# Set by NeoDesk fleet resources\nexport http_proxy={url} https_proxy={url} HTTP_PROXY={url} HTTPS_PROXY={url}\nexport no_proxy=localhost,127.0.0.1,::1 NO_PROXY=localhost,127.0.0.1,::1\n"
        );
        std::fs::write(PROFILE_PROXY, profile).map_err(|err| format!("{PROFILE_PROXY}: {err}"))?;
        if std::path::Path::new("/etc/apt/apt.conf.d").is_dir() {
            let apt =
                format!("Acquire::http::Proxy \"{url}\";\nAcquire::https::Proxy \"{url}\";\n");
            std::fs::write(APT_PROXY, apt).map_err(|err| format!("{APT_PROXY}: {err}"))?;
        }
        Ok(url)
    }

    #[cfg(target_os = "linux")]
    fn reset_proxy() -> Result<(), String> {
        for file in [PROFILE_PROXY, APT_PROXY] {
            if std::path::Path::new(file).exists() {
                std::fs::remove_file(file).map_err(|err| format!("{file}: {err}"))?;
            }
        }
        Ok(())
    }

    #[cfg(target_os = "macos")]
    fn set_dns(list: &str) -> Result<String, ItemError> {
        let servers = list
            .split(' ')
            .map(host::sh_quote)
            .collect::<Vec<_>>()
            .join(" ");
        sh(&format!(
            "{SERVICES} | while IFS= read -r svc; do networksetup -setdnsservers \"$svc\" {servers} || exit 1; done"
        ))
        .map_err(ItemError::Failed)?;
        Ok("networksetup".to_owned())
    }

    #[cfg(target_os = "macos")]
    fn reset_dns(_handle: &str) -> Result<(), String> {
        sh(&format!(
            "{SERVICES} | while IFS= read -r svc; do networksetup -setdnsservers \"$svc\" Empty; done"
        ))
        .map(|_| ())
    }

    #[cfg(target_os = "macos")]
    fn set_proxy(host: &str, port: u16) -> Result<String, String> {
        let host_q = host::sh_quote(host);
        sh(&format!(
            "{SERVICES} | while IFS= read -r svc; do networksetup -setwebproxy \"$svc\" {host_q} {port} && networksetup -setsecurewebproxy \"$svc\" {host_q} {port} || exit 1; done"
        ))?;
        Ok(format!("{host}:{port}"))
    }

    #[cfg(target_os = "macos")]
    fn reset_proxy() -> Result<(), String> {
        sh(&format!(
            "{SERVICES} | while IFS= read -r svc; do networksetup -setwebproxystate \"$svc\" off; networksetup -setsecurewebproxystate \"$svc\" off; done"
        ))
        .map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Fake {
        calls: Vec<String>,
        fail_add: Vec<i64>,
        fail_remove: Vec<i64>,
        unsupported: Vec<Kind>,
        dns_fails: bool,
    }

    impl Backend for Fake {
        fn add(
            &mut self,
            resource: &Resource,
            previous: Option<&Applied>,
        ) -> Result<String, ItemError> {
            self.calls.push(format!("add {}", resource.id));
            if self.unsupported.contains(&resource.kind) {
                return Err(ItemError::Unsupported("not here".into()));
            }
            if self.fail_add.contains(&resource.id) {
                return Err(ItemError::Failed("broken".into()));
            }
            Ok(previous
                .map(|p| p.handle.clone())
                .unwrap_or_else(|| format!("h{}", resource.id)))
        }

        fn remove(&mut self, applied: &Applied) -> Result<(), String> {
            self.calls.push(format!("remove {}", applied.id));
            if self.fail_remove.contains(&applied.id) {
                return Err("busy".into());
            }
            Ok(())
        }

        fn set_dns(&mut self, servers: &[IpAddr]) -> Result<String, ItemError> {
            let list = servers
                .iter()
                .map(|s| s.to_string())
                .collect::<Vec<_>>()
                .join(",");
            self.calls.push(format!("dns {list}"));
            if self.dns_fails {
                return Err(ItemError::Failed("no adapter".into()));
            }
            Ok("dns-handle".into())
        }

        fn reset_dns(&mut self, handle: &str) -> Result<(), String> {
            self.calls.push(format!("reset dns {handle}"));
            Ok(())
        }
    }

    fn drive(id: i64, address: &str) -> Value {
        json!({"id": id, "type": "network_drive", "name": "Z:", "address": address})
    }

    fn args(revision: &str, resources: Vec<Value>) -> Value {
        json!({"revision": revision, "resources": resources})
    }

    fn ids(saved: &Saved) -> Vec<i64> {
        saved.applied.iter().map(|a| a.id).collect()
    }

    #[test]
    fn the_list_is_the_desired_state() {
        let mut fake = Fake::default();
        let first = args(
            "r1",
            vec![
                drive(1, "\\\\srv\\a"),
                drive(2, "\\\\srv\\b"),
                json!({"id": 3, "type": "dns", "name": "", "address": "10.0.0.53, 10.0.0.54"}),
                json!({"id": 4, "type": "dns", "name": "", "address": "10.0.0.54;1.1.1.1"}),
            ],
        );
        let (saved, status, result) = reconcile(&first, &Saved::default(), &mut fake);
        assert_eq!(status, "ok", "{result}");
        assert_eq!(saved.revision, "r1");
        assert_eq!(result["revision"], "r1");
        assert_eq!(ids(&saved), vec![3, 4, 1, 2]);
        assert_eq!(
            fake.calls,
            vec!["dns 10.0.0.53,10.0.0.54,1.1.1.1", "add 1", "add 2"]
        );
        assert_eq!(result["items"].as_array().unwrap().len(), 4);

        // Item 2 and the DNS servers are gone, item 1 changed its share
        let mut fake = Fake::default();
        let second = args("r2", vec![drive(1, "\\\\srv\\new")]);
        let (saved, status, result) = reconcile(&second, &saved, &mut fake);
        assert_eq!(status, "ok", "{result}");
        assert_eq!(saved.revision, "r2");
        assert_eq!(
            fake.calls,
            vec!["remove 1", "remove 2", "reset dns dns-handle", "add 1"]
        );
        assert_eq!(ids(&saved), vec![1]);
        assert_eq!(saved.applied[0].address, "\\\\srv\\new");

        // The same list again: set up again, nothing taken away
        let mut fake = Fake::default();
        let (again, _, _) = reconcile(&second, &saved, &mut fake);
        assert_eq!(fake.calls, vec!["add 1"]);
        assert_eq!(again, saved);

        // An empty list takes everything away
        let mut fake = Fake::default();
        let (empty, status, _) = reconcile(&args("r3", vec![]), &saved, &mut fake);
        assert_eq!(status, "ok");
        assert_eq!(fake.calls, vec!["remove 1"]);
        assert!(empty.applied.is_empty());
        assert_eq!(empty.revision, "r3");
    }

    #[test]
    fn what_failed_or_is_unsupported_is_not_remembered_as_set_up() {
        let mut fake = Fake {
            fail_add: vec![2],
            unsupported: vec![Kind::Vpn],
            ..Default::default()
        };
        let list = args(
            "r1",
            vec![
                drive(1, "\\\\srv\\a"),
                drive(2, "\\\\srv\\b"),
                json!({"id": 5, "type": "vpn", "name": "Office", "address": "vpn.example.com"}),
                json!({"id": 6, "type": "teleporter", "name": "", "address": ""}),
                json!({"id": 7, "type": "dns", "name": "", "address": "not-an-ip"}),
            ],
        );
        let (saved, status, result) = reconcile(&list, &Saved::default(), &mut fake);
        assert_eq!(status, "error");
        assert_eq!(ids(&saved), vec![1]);
        let status_of = |id: i64| {
            result["items"]
                .as_array()
                .unwrap()
                .iter()
                .find(|item| item["id"] == id)
                .map(|item| item["status"].as_str().unwrap().to_owned())
        };
        assert_eq!(status_of(1).as_deref(), Some("ok"));
        assert_eq!(status_of(2).as_deref(), Some("error"));
        assert_eq!(status_of(5).as_deref(), Some("unsupported"));
        assert_eq!(status_of(6).as_deref(), Some("error"));
        assert_eq!(status_of(7).as_deref(), Some("error"));
        assert!(!fake.calls.iter().any(|call| call.starts_with("dns")));
    }

    #[test]
    fn a_removal_that_fails_is_tried_again_next_time() {
        let saved = Saved {
            revision: "r1".into(),
            applied: vec![Applied {
                id: 9,
                kind: "printer".into(),
                name: "P".into(),
                address: "\\\\srv\\p".into(),
                handle: "unc:\\\\srv\\p".into(),
            }],
        };
        let mut fake = Fake {
            fail_remove: vec![9],
            ..Default::default()
        };
        let (next, status, result) = reconcile(&args("r2", vec![]), &saved, &mut fake);
        assert_eq!(status, "error");
        assert_eq!(result["removed"][0]["status"], "error");
        assert_eq!(ids(&next), vec![9]);
        assert_eq!(next.revision, "r2");
        let mut fake = Fake::default();
        let (next, status, _) = reconcile(&args("r3", vec![]), &next, &mut fake);
        assert_eq!(status, "ok");
        assert_eq!(fake.calls, vec!["remove 9"]);
        assert!(next.applied.is_empty());
    }

    #[test]
    fn a_drive_keeps_the_letter_it_got() {
        let mut fake = Fake::default();
        let list = args(
            "r1",
            vec![
                json!({"id": 1, "type": "network_drive", "name": "Team", "address": "\\\\srv\\t"}),
            ],
        );
        let (saved, _, _) = reconcile(&list, &Saved::default(), &mut fake);
        let mut saved = saved;
        saved.applied[0].handle = "Y:".into();
        let (again, _, _) = reconcile(&list, &saved, &mut fake);
        assert_eq!(again.applied[0].handle, "Y:");
    }

    #[test]
    fn only_one_proxy_applies() {
        let mut fake = Fake::default();
        let list = args(
            "r1",
            vec![
                json!({"id": 1, "type": "proxy", "name": "", "address": "proxy:3128"}),
                json!({"id": 2, "type": "proxy", "name": "", "address": "other:3128"}),
            ],
        );
        let (saved, status, result) = reconcile(&list, &Saved::default(), &mut fake);
        assert_eq!(status, "error");
        assert_eq!(ids(&saved), vec![1]);
        assert_eq!(result["items"][1]["status"], "error");
        assert_eq!(fake.calls, vec!["add 1"]);
    }

    #[test]
    fn dns_that_fails_keeps_the_earlier_servers_on_record() {
        let mut fake = Fake::default();
        let one = args(
            "r1",
            vec![json!({"id": 3, "type": "dns", "name": "", "address": "10.0.0.53"})],
        );
        let (saved, _, _) = reconcile(&one, &Saved::default(), &mut fake);
        let mut failing = Fake {
            dns_fails: true,
            ..Default::default()
        };
        let two = args(
            "r2",
            vec![json!({"id": 3, "type": "dns", "name": "", "address": "10.0.0.99"})],
        );
        let (next, status, _) = reconcile(&two, &saved, &mut failing);
        assert_eq!(status, "error");
        assert_eq!(ids(&next), vec![3]);
        let mut fake = Fake::default();
        reconcile(&args("r3", vec![]), &next, &mut fake);
        assert_eq!(fake.calls, vec!["reset dns dns-handle"]);
    }

    #[test]
    fn addresses_are_checked() {
        assert_eq!(dns_servers("1.1.1.1 2606:4700::1111").unwrap().len(), 2);
        assert!(dns_servers("").is_err());
        assert!(dns_servers("1.1.1.1; rm -rf /").is_err());
        assert_eq!(
            proxy_endpoint("proxy.example.com:3128").unwrap(),
            ("proxy.example.com".into(), 3128)
        );
        assert_eq!(
            proxy_endpoint("http://10.0.0.1:8000/").unwrap(),
            ("10.0.0.1".into(), 8000)
        );
        assert_eq!(proxy_endpoint("proxy").unwrap(), ("proxy".into(), 8080));
        assert_eq!(
            proxy_endpoint("[fd00::1]:3128").unwrap(),
            ("fd00::1".into(), 3128)
        );
        assert!(proxy_endpoint("fd00::1").is_err());
        assert!(proxy_endpoint("proxy:0").is_err());
        assert!(proxy_endpoint("evil';calc;'").is_err());
        assert_eq!(
            unc_path("\\\\srv\\share\\dir\\").as_deref(),
            Some("\\\\srv\\share\\dir")
        );
        assert_eq!(unc_path("//srv/share").as_deref(), Some("\\\\srv\\share"));
        assert!(unc_path("\\\\srv").is_none());
        assert!(unc_path("C:\\x").is_none());
        assert!(unc_path("\\\\srv\\a\"b").is_none());
        assert_eq!(drive_letter("z:"), Some('Z'));
        assert_eq!(drive_letter("Q"), Some('Q'));
        assert_eq!(drive_letter("Team"), None);
        assert_eq!(drive_letter("1:"), None);
        assert!(host_name("printer-3.example.com").is_some());
        assert!(host_name("10.1.2.3").is_some());
        assert!(host_name("-x").is_none());
        assert!(host_name("a b").is_none());
        assert!(parse_resource(
            &json!({"id": 1, "type": "vpn", "name": "", "address": "vpn.example.com"})
        )
        .is_err());
        assert!(parse_resource(
            &json!({"id": 1, "type": "printer", "name": "x\ny", "address": "10.0.0.9"})
        )
        .is_err());
    }

    #[cfg(not(windows))]
    #[test]
    fn printers_drives_and_vpns_are_unsupported_here() {
        let mut backend = unix_backend::Unix;
        for kind in [Kind::Printer, Kind::NetworkDrive, Kind::Vpn] {
            let resource = Resource {
                id: 1,
                kind,
                name: "n".into(),
                address: "10.0.0.1".into(),
            };
            assert!(
                matches!(backend.add(&resource, None), Err(ItemError::Unsupported(_))),
                "{kind:?}"
            );
        }
    }
}
