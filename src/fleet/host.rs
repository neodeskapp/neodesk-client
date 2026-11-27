//! What the fleet module needs from the computer besides running programs:
//! a place to keep its state and whether it runs with full rights. Tests
//! keep the state in memory, so they never touch the real config.

#[cfg(not(test))]
pub fn load(key: &str) -> String {
    hbb_common::config::LocalConfig::get_option(key)
}

#[cfg(not(test))]
pub fn store(key: &str, value: String) {
    hbb_common::config::LocalConfig::set_option(key.to_owned(), value);
}

#[cfg(test)]
lazy_static::lazy_static! {
    static ref STORE: std::sync::Mutex<std::collections::HashMap<String, String>> =
        Default::default();
}

#[cfg(test)]
pub fn load(key: &str) -> String {
    STORE.lock().unwrap().get(key).cloned().unwrap_or_default()
}

#[cfg(test)]
pub fn store(key: &str, value: String) {
    STORE.lock().unwrap().insert(key.to_owned(), value);
}

/// True when the client runs as SYSTEM (Windows) or root, as the
/// installed service does.
pub fn is_elevated() -> bool {
    #[cfg(windows)]
    {
        crate::platform::windows::is_root()
    }
    #[cfg(unix)]
    {
        unsafe { hbb_common::libc::geteuid() == 0 }
    }
    #[cfg(not(any(windows, unix)))]
    {
        false
    }
}

/// `value` in single quotes for PowerShell
pub fn ps_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

/// `value` in single quotes for /bin/sh
pub fn sh_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quoting_keeps_a_value_in_one_argument() {
        assert_eq!(ps_quote("a'b"), "'a''b'");
        assert_eq!(sh_quote("a'b; rm -rf /"), "'a'\\''b; rm -rf /'");
    }

    #[cfg(unix)]
    #[test]
    fn sh_quote_survives_the_shell() {
        let tricky = "it's $HOME `id` \"x\" \\n";
        let out = std::process::Command::new("/bin/sh")
            .arg("-c")
            .arg(format!("printf %s {}", sh_quote(tricky)))
            .output()
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&out.stdout), tricky);
    }
}
