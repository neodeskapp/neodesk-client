//! Which public key a join sends to the console.
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

#[cfg(test)]
mod tests {
    use super::*;

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
