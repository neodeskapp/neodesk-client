//! Which NeoDesk API calls the device's server process seals, sends and
//! opens for the person's window (L500, L507).
//!
//! A sealed call carries an envelope signed with the device's key and
//! numbered with the device's sequence counter. The server refuses a number
//! it has seen, so only one process may count: the one that holds the key
//! and the counter, the server process (the service's on Windows, the
//! person's `--server` on Linux and macOS, the window itself when it runs
//! the server). Any other process never reads or writes the counter. It asks
//! the server process over the main IPC to make the call, and only for the
//! calls on [`allows`]: the three reads of the Devices tab. The server
//! process seals nothing else for another process.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/hbbs_http/sealed_calls.rs`.

/// The paths the server process calls for another process, all GET.
pub const PATHS: &[&str] = &["/api/device-group/accessible", "/api/users", "/api/peers"];

/// The query parameters these calls take; their values are numbers or empty.
const QUERY_KEYS: &[&str] = &["current", "pageSize", "accessible", "status"];

const MAX_PATH_LEN: usize = 256;
const MAX_AUTHORIZATION_LEN: usize = 4096;

/// The error the window's call answers with when no server process takes it.
pub const SERVICE_UNAVAILABLE: &str = "neodesk_service_unavailable";

/// Whether the server process makes the call `method` `path_and_query`
/// (the path after the API server, with its query) for another process.
pub fn allows(method: &str, path_and_query: &str) -> bool {
    if !method.eq_ignore_ascii_case("GET")
        || path_and_query.len() > MAX_PATH_LEN
        || !path_and_query
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"/-_?&=".contains(&b))
    {
        return false;
    }
    let (path, query) = match path_and_query.split_once('?') {
        Some((path, query)) => (path, Some(query)),
        None => (path_and_query, None),
    };
    if !PATHS.contains(&path) {
        return false;
    }
    let Some(query) = query else {
        return true;
    };
    query.split('&').all(|pair| {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        QUERY_KEYS.contains(&key) && value.bytes().all(|b| b.is_ascii_digit())
    })
}

/// The path with its query of `url` on the API server `api`, None for a URL
/// elsewhere.
pub fn path_and_query<'a>(url: &'a str, api: &str) -> Option<&'a str> {
    let api = api.trim_end_matches('/');
    if api.is_empty() {
        return None;
    }
    url.strip_prefix(api).filter(|rest| rest.starts_with('/'))
}

/// Whether `value` is an account token header the server process passes on:
/// `Bearer` and a token, on one line.
pub fn authorization_ok(value: &str) -> bool {
    value.len() <= MAX_AUTHORIZATION_LEN
        && value
            .strip_prefix("Bearer ")
            .map_or(false, |token| !token.is_empty())
        && value.bytes().all(|b| (0x20..0x7f).contains(&b))
}

/// The answer to the window's call when no server process takes it, in the
/// form of an HTTP answer (status_code, headers, body), so the Devices tab
/// can tell it apart from the server's answers and say what to do.
pub fn service_unavailable_response() -> String {
    format!(
        r#"{{"status_code":503,"headers":{{"content-type":"application/json"}},"body":"{{\"error\":\"{SERVICE_UNAVAILABLE}\"}}"}}"#
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_devices_tab_reads_are_allowed() {
        assert!(allows(
            "GET",
            "/api/device-group/accessible?current=1&pageSize=100"
        ));
        assert!(allows(
            "get",
            "/api/users?current=1&pageSize=100&accessible=&status=1"
        ));
        assert!(allows(
            "GET",
            "/api/peers?current=2&pageSize=100&accessible&status=1"
        ));
        assert!(allows("GET", "/api/peers"));
    }

    #[test]
    fn other_methods_and_paths_are_refused() {
        for (method, path) in [
            ("POST", "/api/users"),
            ("PUT", "/api/peers"),
            ("DELETE", "/api/peers"),
            ("GET", "/api/heartbeat"),
            ("GET", "/api/sysinfo"),
            ("GET", "/api/onboard/join"),
            ("GET", "/api/pairing/redeem"),
            ("GET", "/api/audit/conn"),
            ("GET", "/api/peers/525129550/connect-password"),
            ("GET", "/api/peers/list"),
            ("GET", "/api/users/7/organizations"),
            ("GET", "/api/device-group"),
            ("GET", "/api/users/"),
            ("GET", "api/users"),
            ("GET", ""),
        ] {
            assert!(!allows(method, path), "{method} {path}");
        }
    }

    #[test]
    fn paths_that_could_reach_another_route_are_refused() {
        for path in [
            "/api/peers/../peers/1/connect-password",
            "/api/peers/%2e%2e/x",
            "/api/peers#x",
            "/api/peers?id=525129550",
            "/api/peers?current=1&connect-password=1",
            "/api/peers?current=x",
            "/api/peers?current=1\r\nX: y",
            "/api/peers?current=1 HTTP/1.1",
            "/api/peers;x",
            "//evil/api/peers",
        ] {
            assert!(!allows("GET", path), "{path}");
        }
        let long = format!("/api/peers?current={}", "1".repeat(300));
        assert!(!allows("GET", &long));
    }

    #[test]
    fn the_path_is_taken_after_the_api_server() {
        let api = "http://10.10.10.74:21121";
        assert_eq!(
            path_and_query("http://10.10.10.74:21121/api/users?current=1", api),
            Some("/api/users?current=1")
        );
        assert_eq!(
            path_and_query(
                "http://10.10.10.74:21121/api/peers",
                "http://10.10.10.74:21121/"
            ),
            Some("/api/peers")
        );
        assert_eq!(path_and_query("http://other:21121/api/peers", api), None);
        assert_eq!(
            path_and_query("http://10.10.10.74:211219/api/peers", api),
            None
        );
        assert_eq!(path_and_query("http://x/api/peers", ""), None);
    }

    #[test]
    fn only_a_bearer_token_on_one_line_is_passed_on() {
        assert!(authorization_ok("Bearer abc.def-123"));
        assert!(!authorization_ok(""));
        assert!(!authorization_ok("Bearer "));
        assert!(!authorization_ok("Basic dXNlcjpwYXNz"));
        assert!(!authorization_ok("Bearer abc\r\nX-NeoDesk-Envelope: 1"));
        assert!(!authorization_ok(&format!("Bearer {}", "a".repeat(5000))));
    }

    #[test]
    fn the_unavailable_answer_reads_as_an_http_answer() {
        let answer = service_unavailable_response();
        assert!(answer.starts_with(r#"{"status_code":503,"#));
        assert!(answer.contains(r#""body":"{\"error\":\"neodesk_service_unavailable\"}""#));
    }
}
