//! How a NeoDesk exe stands to a NeoDesk installed on the same computer
//! from another file: older, the same or newer. The exe offers to update an
//! older install, leaves a newer one alone, and never sets up the service of
//! an install it can't tell is at least its own version.

#![cfg_attr(not(windows), allow(dead_code))]

use std::cmp::Ordering;

/// The installed copy's version against the running exe's.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Standing {
    /// The install is older than this exe.
    Older,
    Same,
    /// The install is newer than this exe.
    Newer,
    /// The install's version can't be read or compared.
    Unknown,
}

impl Standing {
    pub fn as_str(self) -> &'static str {
        match self {
            Standing::Older => "older",
            Standing::Same => "same",
            Standing::Newer => "newer",
            Standing::Unknown => "unknown",
        }
    }
}

/// The installed copy's standing, from this exe's version and what the
/// installed exe answered to `--version`.
pub fn standing(this: &str, installed: Option<&str>) -> Standing {
    match installed.and_then(|installed| compare_versions(installed, this)) {
        Some(Ordering::Less) => Standing::Older,
        Some(Ordering::Equal) => Standing::Same,
        Some(Ordering::Greater) => Standing::Newer,
        None => Standing::Unknown,
    }
}

/// Whether the exe offers to update the install to its own version.
pub fn offers_update(standing: Standing) -> bool {
    standing == Standing::Older
}

/// Whether the exe may set up the service of the install, which runs the
/// installed binary.
pub fn may_set_up_service(standing: Standing) -> bool {
    matches!(standing, Standing::Same | Standing::Newer)
}

/// The version in what `neodesk.exe --version` printed: its first line, when
/// it reads as a version.
pub fn parse_version_output(output: &str) -> Option<String> {
    let line = output.lines().next()?.trim();
    parse(line)?;
    Some(line.to_owned())
}

/// Release order: 1.5.0-dev.27 < 1.5.0-rc.6 < 1.5.0-rc.10 < 1.5.0 < 1.5.1.
/// None when either isn't a version.
pub fn compare_versions(a: &str, b: &str) -> Option<Ordering> {
    let (a_core, a_pre) = parse(a)?;
    let (b_core, b_pre) = parse(b)?;
    Some(a_core.cmp(&b_core).then_with(|| match (a_pre.is_empty(), b_pre.is_empty()) {
        (true, true) => Ordering::Equal,
        // A release sorts after its pre-releases.
        (true, false) => Ordering::Greater,
        (false, true) => Ordering::Less,
        (false, false) => compare_pre(&a_pre, &b_pre),
    }))
}

fn parse(version: &str) -> Option<(Vec<u64>, Vec<String>)> {
    let version = version.trim();
    let (core, pre) = match version.split_once('-') {
        Some((core, pre)) => (core, pre),
        None => (version, ""),
    };
    let numbers = core
        .split('.')
        .map(|part| {
            if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
                None
            } else {
                part.parse::<u64>().ok()
            }
        })
        .collect::<Option<Vec<u64>>>()?;
    if numbers.len() != 3 {
        return None;
    }
    let pre: Vec<String> = if pre.is_empty() {
        Vec::new()
    } else {
        pre.split('.').map(str::to_owned).collect()
    };
    if pre
        .iter()
        .any(|p| p.is_empty() || !p.bytes().all(|b| b.is_ascii_alphanumeric()))
    {
        return None;
    }
    Some((numbers, pre))
}

fn compare_pre(a: &[String], b: &[String]) -> Ordering {
    for (x, y) in a.iter().zip(b.iter()) {
        let order = match (x.parse::<u64>(), y.parse::<u64>()) {
            (Ok(x), Ok(y)) => x.cmp(&y),
            // Numbers sort before words, as in semver.
            (Ok(_), Err(_)) => Ordering::Less,
            (Err(_), Ok(_)) => Ordering::Greater,
            (Err(_), Err(_)) => x.cmp(y),
        };
        if order != Ordering::Equal {
            return order;
        }
    }
    a.len().cmp(&b.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_sort_in_release_order() {
        let order = [
            "1.4.9",
            "1.5.0-dev.27",
            "1.5.0-rc.1",
            "1.5.0-rc.6",
            "1.5.0-rc.7",
            "1.5.0-rc.10",
            "1.5.0",
            "1.5.1",
            "1.10.0",
        ];
        for (i, a) in order.iter().enumerate() {
            for (j, b) in order.iter().enumerate() {
                assert_eq!(compare_versions(a, b), Some(i.cmp(&j)), "{a} against {b}");
            }
        }
        assert_eq!(compare_versions("1.5.0", "not a version"), None);
        assert_eq!(compare_versions("1.5", "1.5.0"), None);
        assert_eq!(compare_versions("1.5.0-rc..1", "1.5.0"), None);
    }

    #[test]
    fn the_version_comes_from_the_first_line_of_the_output() {
        assert_eq!(
            parse_version_output("1.5.0-rc.6\r\n").as_deref(),
            Some("1.5.0-rc.6")
        );
        assert_eq!(parse_version_output(""), None);
        assert_eq!(parse_version_output("Error: something\n1.5.0"), None);
    }

    #[test]
    fn an_older_install_gets_the_update_offer() {
        let s = standing("1.5.0-rc.7", Some("1.5.0-rc.6"));
        assert_eq!(s, Standing::Older);
        assert!(offers_update(s));
    }

    #[test]
    fn a_newer_or_the_same_install_is_left_alone() {
        for (installed, expected) in [
            ("1.5.0-rc.7", Standing::Same),
            ("1.5.0", Standing::Newer),
            ("1.5.0-rc.8", Standing::Newer),
        ] {
            let s = standing("1.5.0-rc.7", Some(installed));
            assert_eq!(s, expected, "{installed}");
            assert!(!offers_update(s), "{installed}");
        }
    }

    #[test]
    fn an_install_of_unknown_version_is_left_alone() {
        for installed in [None, Some(""), Some("garbage")] {
            let s = standing("1.5.0-rc.7", installed);
            assert_eq!(s, Standing::Unknown, "{installed:?}");
            assert!(!offers_update(s));
        }
    }

    /// Accept connections in an exe next to an older install set up the
    /// service of the older binary (L476).
    #[test]
    fn the_service_never_runs_an_older_binary() {
        assert!(!may_set_up_service(standing("1.5.0-rc.7", Some("1.5.0-rc.6"))));
        assert!(!may_set_up_service(standing("1.5.0-rc.7", None)));
        assert!(may_set_up_service(standing("1.5.0-rc.7", Some("1.5.0-rc.7"))));
        assert!(may_set_up_service(standing("1.5.0-rc.7", Some("1.5.0"))));
    }
}
