//! Whether NeoDesk may take stock RustDesk's rustdesk:// link scheme. The
//! owner's rule: NeoDesk always has its own neodesk:// scheme, and takes
//! rustdesk:// only on a computer without stock RustDesk, never away from
//! another program.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/platform/windows/link_schemes.rs`.

/// The program an open command starts: the quoted first part, or the text
/// up to the first space.
pub fn command_program(command: &str) -> &str {
    let command = command.trim_start();
    match command.strip_prefix('"') {
        Some(rest) => rest.split('"').next().unwrap_or(""),
        None => command.split_whitespace().next().unwrap_or(""),
    }
}

/// True when an open command starts a NeoDesk executable: the installed
/// neodesk.exe, or a setup or portable file such as
/// NeoDesk-Setup-host-CODE.exe or neodesk-1.5.0-x86_64.exe.
pub fn starts_neodesk(command: &str) -> bool {
    let program = command_program(command);
    let file = program
        .rsplit(['\\', '/'])
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();
    file.starts_with("neodesk") && file.ends_with(".exe")
}

/// May NeoDesk register rustdesk:// for itself? `handlers` are the open
/// commands registered for rustdesk:// now (the computer's and the user's),
/// `stock_installed` whether stock RustDesk is installed.
pub fn may_claim_rustdesk_scheme(handlers: &[String], stock_installed: bool) -> bool {
    !stock_installed
        && handlers
            .iter()
            .all(|command| command.trim().is_empty() || starts_neodesk(command))
}

#[cfg(test)]
mod tests {
    use super::*;

    const RUSTDESK: &str = r#""C:\Program Files\RustDesk\RustDesk.exe" "%1""#;
    const NEODESK: &str = r#""C:\Program Files\NeoDesk Client\neodesk.exe" "%1""#;
    const NEODESK_SETUP: &str =
        r#""C:\Users\Zoë\Downloads\NeoDesk-Setup-10.10.10.74_5000_http-P373YZ3F.exe" "%1""#;

    fn handlers(commands: &[&str]) -> Vec<String> {
        commands.iter().map(|c| c.to_string()).collect()
    }

    #[test]
    fn no_handler_and_no_rustdesk_lets_neodesk_take_it() {
        assert!(may_claim_rustdesk_scheme(&handlers(&[]), false));
        // A key without an open command is no handler either.
        assert!(may_claim_rustdesk_scheme(&handlers(&["", "  "]), false));
    }

    #[test]
    fn a_handler_that_starts_rustdesk_stays() {
        assert!(!may_claim_rustdesk_scheme(&handlers(&[RUSTDESK]), false));
        assert!(!may_claim_rustdesk_scheme(&handlers(&[RUSTDESK]), true));
        // Even when this user's entry still starts NeoDesk.
        assert!(!may_claim_rustdesk_scheme(
            &handlers(&[NEODESK, RUSTDESK]),
            false
        ));
    }

    #[test]
    fn a_handler_that_starts_neodesk_is_kept_up_to_date() {
        assert!(may_claim_rustdesk_scheme(&handlers(&[NEODESK]), false));
        assert!(may_claim_rustdesk_scheme(
            &handlers(&[NEODESK_SETUP, NEODESK]),
            false
        ));
    }

    #[test]
    fn installed_rustdesk_without_a_handler_keeps_the_scheme_for_itself() {
        assert!(!may_claim_rustdesk_scheme(&handlers(&[]), true));
        assert!(!may_claim_rustdesk_scheme(&handlers(&[NEODESK]), true));
    }

    #[test]
    fn another_program_keeps_its_handler() {
        for other in [
            r#""C:\Program Files\Acme Support\acme.exe" "%1""#,
            r"C:\Tools\rustdesk.exe %1",
            r#""C:\Program Files\NeoDeskless\other.exe" "%1""#,
        ] {
            assert!(
                !may_claim_rustdesk_scheme(&handlers(&[other]), false),
                "{other}"
            );
        }
    }

    #[test]
    fn neodesk_programs_are_told_apart_from_others() {
        for ours in [
            NEODESK,
            NEODESK_SETUP,
            r"C:\nd\NEODESK.EXE %1",
            r#""D:\neodesk-1.5.0-x86_64.exe" "%1""#,
        ] {
            assert!(starts_neodesk(ours), "{ours}");
        }
        for other in [
            RUSTDESK,
            "",
            r#""C:\NeoDesk\rustdesk.exe" "%1""#,
            r"C:\NeoDesk Client\x.exe %1",
        ] {
            assert!(!starts_neodesk(other), "{other}");
        }
        assert_eq!(
            command_program(NEODESK),
            r"C:\Program Files\NeoDesk Client\neodesk.exe"
        );
        assert_eq!(command_program(r"C:\x\neodesk.exe %1"), r"C:\x\neodesk.exe");
    }
}
