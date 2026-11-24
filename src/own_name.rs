//! The client's own name where it titles something it shows itself. Texts
//! that mean stock RustDesk (its link scheme, its public servers, the
//! credit in About) keep RustDesk's name.

/// The title of the message box that shows what a command-line option such
/// as `--join` did.
pub fn output_box_caption() -> String {
    output_box_caption_of(&crate::get_app_name())
}

/// The issuer an authenticator app lists the two-factor entry under.
pub fn totp_issuer() -> String {
    totp_issuer_of(&crate::get_app_name())
}

fn output_box_caption_of(app_name: &str) -> String {
    app_name.to_owned()
}

fn totp_issuer_of(app_name: &str) -> String {
    format!("{app_name} Connection")
}

#[cfg(test)]
mod tests {
    use super::*;

    // Other tests switch the app name for custom clients while these run,
    // so they pass the name.

    /// neodesk.exe --join showed its result in a box titled "RustDesk
    /// Output" (L477).
    #[test]
    fn the_result_box_carries_the_clients_name() {
        assert_eq!(output_box_caption_of("NeoDesk Client"), "NeoDesk Client");
        assert_eq!(output_box_caption_of("Fernhill Support"), "Fernhill Support");
    }

    #[test]
    fn authenticator_apps_list_the_client_under_its_own_name() {
        assert_eq!(
            totp_issuer_of("NeoDesk Client"),
            "NeoDesk Client Connection"
        );
    }
}
