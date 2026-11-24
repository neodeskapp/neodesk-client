//! Which public key a join sends to the console, and who proves it.
//!
//! The device's key is the one its server process registers with the ID
//! server and signs sessions with. A join can run in another process:
//! `neodesk.exe --join` started as SYSTEM or by an administrator, or the
//! join in the person's own window. Such a process either has a config of
//! its own (the person's profile), so a key it makes is one the service
//! never signs with, or shares the service's config file, where a key it
//! writes behind the running service's back gets lost. Either way the
//! server would hold a key nobody signs with. So a join takes the key of
//! the server process, and its own only when no server process answers:
//! then this process is the one that runs the server and signs.
//!
//! The server refuses a join for a device ID it knows unless the request
//! proves the key it holds for that ID (L483). The server process makes
//! that proof for the join too (hbbs_http/pairing_proof.rs), and the join
//! sends the key the proof came with. Without an answer only a process
//! that holds the device's secrets signs; the window of an installed
//! client sends no proof.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/device_key.rs`.

/// The public key (base64) a join sends. `from_server_process` is what the
/// device's server process answered over IPC: `None` when none answered
/// or it does not know the question (an older client). `own_key` makes or
/// loads this process's key; it is called only when no server process
/// gave one, so a join next to a running service never makes a key.
pub fn key_for_join(
    from_server_process: Option<String>,
    own_key: impl FnOnce() -> Option<String>,
) -> Option<String> {
    match from_server_process {
        Some(key) if !key.trim().is_empty() => Some(key),
        _ => own_key(),
    }
}

/// The public key (base64) and key proof a join goes out with (L483).
///
/// `from_server_process` is the key and proof the device's server process
/// made for the join over IPC (hbbs_http/pairing_proof.rs): `None` when
/// none answered, or it is an older one that signs no join. Without it the
/// key is the one [`key_for_join`] picks from `key_of_server_process` (an
/// older server process still tells its key) and `own_key`, and the proof
/// is this process's own, made by `own_proof` only when this process holds
/// the device's secrets and only sent when it proves the key the join
/// sends. The window of an installed client never signs: a join from it
/// then goes out without a proof.
pub fn key_and_proof_for_join<P>(
    from_server_process: Option<(String, P)>,
    key_of_server_process: impl FnOnce() -> Option<String>,
    own_key: impl FnOnce() -> Option<String>,
    holds_secrets: bool,
    own_proof: impl FnOnce() -> Option<(String, P)>,
) -> (Option<String>, Option<P>) {
    if let Some((key, proof)) = from_server_process.filter(|(key, _)| !key.trim().is_empty()) {
        return (Some(key), Some(proof));
    }
    let key = key_for_join(key_of_server_process(), own_key);
    let proof = if holds_secrets {
        own_proof()
            .filter(|(own_key, _)| key.as_ref() == Some(own_key))
            .map(|(_, proof)| proof)
    } else {
        None
    };
    (key, proof)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn none_asked() -> Option<String> {
        panic!("asked for a key although the server process proved one")
    }

    #[test]
    fn a_join_next_to_a_running_service_sends_its_key_and_proof() {
        let (key, proof) = key_and_proof_for_join(
            Some(("c2VydmljZQ==".to_owned(), "service proof")),
            none_asked,
            none_asked,
            true,
            || panic!("the join made a proof of its own next to the service"),
        );
        assert_eq!(key.as_deref(), Some("c2VydmljZQ=="));
        assert_eq!(proof, Some("service proof"));
    }

    #[test]
    fn without_a_server_process_the_holder_of_the_key_signs_the_join() {
        let (key, proof) = key_and_proof_for_join(
            None,
            || None,
            || Some("b3du".to_owned()),
            true,
            || Some(("b3du".to_owned(), "own proof")),
        );
        assert_eq!(key.as_deref(), Some("b3du"));
        assert_eq!(proof, Some("own proof"));
    }

    #[test]
    fn a_window_without_the_device_secrets_never_signs_a_join() {
        let never = || -> Option<(String, &str)> { panic!("the window signed the join") };
        assert_eq!(
            key_and_proof_for_join(None, || None, || None, false, never),
            (None, None)
        );
        // The service's key the window learned earlier still goes out, unproved
        assert_eq!(
            key_and_proof_for_join(None, || None, || Some("c2VydmljZQ==".to_owned()), false, never),
            (Some("c2VydmljZQ==".to_owned()), None)
        );
    }

    #[test]
    fn a_proof_goes_out_only_for_the_key_the_join_sends() {
        // An older server process tells its key but signs no join; this
        // process holds another key
        assert_eq!(
            key_and_proof_for_join(
                None,
                || Some("c2VydmljZQ==".to_owned()),
                none_asked,
                true,
                || Some(("b3du".to_owned(), "own proof")),
            ),
            (Some("c2VydmljZQ==".to_owned()), None)
        );
        // The same key in both (one config file): the proof holds
        assert_eq!(
            key_and_proof_for_join(
                None,
                || Some("c2VydmljZQ==".to_owned()),
                none_asked,
                true,
                || Some(("c2VydmljZQ==".to_owned(), "own proof")),
            ),
            (Some("c2VydmljZQ==".to_owned()), Some("own proof"))
        );
    }

    #[test]
    fn an_empty_key_from_the_server_process_counts_as_no_answer() {
        assert_eq!(
            key_and_proof_for_join(
                Some((" ".to_owned(), "service proof")),
                || None,
                || Some("b3du".to_owned()),
                true,
                || Some(("b3du".to_owned(), "own proof")),
            ),
            (Some("b3du".to_owned()), Some("own proof"))
        );
    }

    #[test]
    fn a_join_sends_the_key_of_the_running_server_process() {
        let key = key_for_join(Some("c2VydmljZQ==".to_owned()), || {
            panic!("a join next to a running service made a key of its own")
        });
        assert_eq!(key.as_deref(), Some("c2VydmljZQ=="));
    }

    #[test]
    fn without_a_server_process_the_join_sends_its_own_key() {
        assert_eq!(
            key_for_join(None, || Some("b3du".to_owned())).as_deref(),
            Some("b3du")
        );
    }

    #[test]
    fn an_empty_answer_counts_as_no_answer() {
        assert_eq!(
            key_for_join(Some(" ".to_owned()), || Some("b3du".to_owned())).as_deref(),
            Some("b3du")
        );
    }
}
