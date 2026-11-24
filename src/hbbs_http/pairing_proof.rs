//! Which requests the device's server process signs for another process of
//! this client: a pairing ("Set up by hand" with a code) and a join (Add a
//! computer with an invite).
//!
//! The server binds the key a pairing or join proves to the device, and
//! refuses a join for a device ID it knows unless the request proves the
//! key it holds for that ID (L483). So the proof has to come from the key
//! the device's server process registers and signs sessions with. Pairing
//! and joining run in the person's window, which has a config and a key of
//! its own, or none at all in an installed client (L442); a proof made
//! there leaves the server with two keys for one device, or none. So the
//! window asks the server process over IPC for its public key and a proof
//! for the request, and makes its own only when no server process answers:
//! then the window runs the server itself.
//!
//! The server process signs nothing else for another process: a proof for
//! these two requests does not open the device's other signed requests.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/hbbs_http/pairing_proof.rs`.

/// The method of the pairing request and of the join.
pub const METHOD: &str = "POST";
/// The path of the pairing request.
pub const PATH: &str = "/api/pairing/redeem";
/// The path of the join (onboard/join.rs).
pub const JOIN_PATH: &str = "/api/onboard/join";

/// Whether the server process signs a key proof for `method` and `path` on
/// behalf of another process: the pairing request and the join only.
pub fn signs_for_others(method: &str, path: &str) -> bool {
    method == METHOD && (path == PATH || path == JOIN_PATH)
}

/// The public key and proof a pairing request goes out with: the server
/// process's when it answered, else this process's own, made by `own` only
/// then.
pub fn proof_for_pairing<T>(from_server_process: Option<T>, own: impl FnOnce() -> T) -> T {
    from_server_process.unwrap_or_else(own)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_server_process_signs_the_pairing_request() {
        assert!(signs_for_others(METHOD, PATH));
    }

    #[test]
    fn the_server_process_signs_the_join() {
        assert!(signs_for_others("POST", "/api/onboard/join"));
        assert!(signs_for_others(METHOD, JOIN_PATH));
    }

    #[test]
    fn the_server_process_signs_nothing_else_for_others() {
        assert!(!signs_for_others("GET", PATH));
        assert!(!signs_for_others(METHOD, "/api/devices/register"));
        assert!(!signs_for_others(METHOD, "/x/api/pairing/redeem"));
        assert!(!signs_for_others(METHOD, "/api/pairing/redeem/"));
        assert!(!signs_for_others(METHOD, ""));
        for method in ["GET", "PUT", "DELETE", "post", ""] {
            assert!(!signs_for_others(method, JOIN_PATH), "{method} {JOIN_PATH}");
        }
        for path in [
            "/api/onboard/join/",
            "/x/api/onboard/join",
            "/api/onboard/join/x",
            "/api/onboard/joinx",
            "/api/onboard/join?code=1",
            "/api/onboard",
            "/api/onboard/support",
            "api/onboard/join",
            "//api/onboard/join",
            "/API/ONBOARD/JOIN",
        ] {
            assert!(!signs_for_others(METHOD, path), "{path}");
        }
    }

    #[test]
    fn a_pairing_next_to_a_running_service_sends_its_proof() {
        let proof = proof_for_pairing(Some("service"), || {
            panic!("the window made a proof with its own key")
        });
        assert_eq!(proof, "service");
    }

    #[test]
    fn without_a_server_process_the_window_signs() {
        assert_eq!(proof_for_pairing(None, || "own"), "own");
    }
}
