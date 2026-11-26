//! NeoDesk Client releases on GitHub: which one is newer than the running
//! build on the chosen channel, and which package of it to install.
//!
//! A desktop release is tagged `desktop-v<version>` on neodeskapp/neodesk-client
//! and carries `SHA256SUMS`, its ed25519 signature `SHA256SUMS.sig` (the
//! release key, the same the console checks) and `neodesk-desktop-manifest.json`
//! with each package's size. A package is installed only when the signature
//! holds, the manifest's hash is in the signed list, and the package's hash
//! in the manifest matches the signed list.

use crate::update_metadata::{UpdateArtifactQuery, VerifiedUpdateArtifact};
use hbb_common::{
    anyhow::{anyhow, Context},
    base64::{engine::general_purpose::STANDARD, Engine as _},
    bail,
    sodiumoxide::crypto::sign::{verify_detached, PublicKey, Signature},
    ResultType,
};
use serde_derive::Deserialize;
use std::{cmp::Ordering, collections::HashMap};

pub(crate) const RELEASE_REPO: &str = "neodeskapp/neodesk-client";
pub(crate) const RELEASE_TAG_PREFIX: &str = "desktop-v";
pub(crate) const RELEASES_API_URL: &str =
    "https://api.github.com/repos/neodeskapp/neodesk-client/releases?per_page=30";
pub(crate) const SUMS_FILE: &str = "SHA256SUMS";
pub(crate) const SUMS_SIGNATURE_FILE: &str = "SHA256SUMS.sig";
pub(crate) const MANIFEST_FILE: &str = "neodesk-desktop-manifest.json";

/// Config option with the update channel: "beta", "stable", or empty for the
/// default (see [`UpdateChannel::from_option`]).
pub(crate) const OPTION_UPDATE_CHANNEL: &str = "update-channel";

/// Public half of the release key (base64 iwissiXvSjeFFsG8SdKEZq11uAtRLWCrD7Ky1vfY2n4=),
/// as in scripts/collect_desktop_dist.sh and the console's clientrelease keys.
pub(crate) const RELEASE_PUBLIC_KEY: [u8; 32] = [
    139, 8, 172, 178, 37, 239, 74, 55, 133, 22, 193, 188, 73, 210, 132, 102, 173, 117, 184, 11,
    81, 45, 96, 171, 15, 178, 178, 214, 247, 216, 218, 126,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UpdateChannel {
    /// Only releases without a pre-release suffix (1.5.0).
    Stable,
    /// Release candidates and betas as well (1.5.0-rc.9).
    Beta,
}

impl UpdateChannel {
    pub fn as_str(self) -> &'static str {
        match self {
            UpdateChannel::Stable => "stable",
            UpdateChannel::Beta => "beta",
        }
    }

    /// The channel the option `value` names. Without a choice every build
    /// is on Stable, a release candidate too: only the Beta versions switch
    /// (or the server's strategy) puts a computer on Beta.
    pub fn from_option(value: &str) -> Self {
        match value.trim() {
            "beta" => UpdateChannel::Beta,
            _ => UpdateChannel::Stable,
        }
    }
}

/// The channel this computer follows. The window reads the service's
/// options as it keeps them (the switch writes them through the service);
/// the service reads its own config.
pub fn update_channel() -> UpdateChannel {
    let value = if crate::common::is_main() {
        crate::ui_interface::get_option(OPTION_UPDATE_CHANNEL)
    } else {
        hbb_common::config::Config::get_option(OPTION_UPDATE_CHANNEL)
    };
    UpdateChannel::from_option(&value)
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum PreIdent {
    Number(u64),
    Text(String),
}

impl Ord for PreIdent {
    fn cmp(&self, other: &Self) -> Ordering {
        match (self, other) {
            (PreIdent::Number(a), PreIdent::Number(b)) => a.cmp(b),
            (PreIdent::Number(_), PreIdent::Text(_)) => Ordering::Less,
            (PreIdent::Text(_), PreIdent::Number(_)) => Ordering::Greater,
            (PreIdent::Text(a), PreIdent::Text(b)) => a.cmp(b),
        }
    }
}

impl PartialOrd for PreIdent {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// A version as NeoDesk tags them, ordered by semver precedence:
/// 1.5.0-beta.2 < 1.5.0-rc.1 < 1.5.0-rc.10 < 1.5.0 < 1.5.1.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Version {
    core: [u64; 3],
    pre: Vec<PreIdent>,
}

impl Version {
    pub fn parse(value: &str) -> Option<Self> {
        let value = value.trim();
        let value = value.split_once('+').map_or(value, |(version, _)| version);
        let (core, pre) = match value.split_once('-') {
            Some((core, pre)) => (core, Some(pre)),
            None => (value, None),
        };
        let parts = core.split('.').collect::<Vec<_>>();
        if parts.len() != 3 {
            return None;
        }
        let mut numbers = [0u64; 3];
        for (number, part) in numbers.iter_mut().zip(parts) {
            if part.is_empty() || !part.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            *number = part.parse().ok()?;
        }
        let pre = match pre {
            None => Vec::new(),
            Some(pre) => {
                let mut idents = Vec::new();
                for ident in pre.split('.') {
                    if ident.is_empty()
                        || !ident.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                    {
                        return None;
                    }
                    idents.push(if ident.bytes().all(|b| b.is_ascii_digit()) {
                        PreIdent::Number(ident.parse().ok()?)
                    } else {
                        PreIdent::Text(ident.to_owned())
                    });
                }
                idents
            }
        };
        Some(Version {
            core: numbers,
            pre,
        })
    }

    pub fn is_prerelease(&self) -> bool {
        !self.pre.is_empty()
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        self.core.cmp(&other.core).then_with(|| {
            match (self.pre.is_empty(), other.pre.is_empty()) {
                (true, true) => Ordering::Equal,
                (true, false) => Ordering::Greater,
                (false, true) => Ordering::Less,
                (false, false) => self.pre.cmp(&other.pre),
            }
        })
    }
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// The version in a desktop release tag (desktop-v1.5.0-rc.9 is 1.5.0-rc.9).
pub fn version_of_tag(tag: &str) -> Option<String> {
    let version = tag.strip_prefix(RELEASE_TAG_PREFIX)?;
    Version::parse(version)?;
    if version.contains('+') {
        return None;
    }
    Some(version.to_owned())
}

#[derive(Deserialize)]
struct GithubRelease {
    tag_name: String,
    #[serde(default)]
    draft: bool,
    #[serde(default)]
    prerelease: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NewRelease {
    pub tag: String,
    pub version: String,
}

impl NewRelease {
    pub fn page_url(&self) -> String {
        release_page_url(&self.tag)
    }
}

pub fn release_page_url(tag: &str) -> String {
    format!("https://github.com/{RELEASE_REPO}/releases/tag/{tag}")
}

pub fn release_download_url(tag: &str, file_name: &str) -> String {
    format!("https://github.com/{RELEASE_REPO}/releases/download/{tag}/{file_name}")
}

/// The newest desktop release in the GitHub API's release list that is newer
/// than `running_version` and belongs to `channel`, or None when there is
/// none. Drafts, other products' tags (support-v*) and tags that are not a
/// version are skipped. A release GitHub marks as pre-release counts as one
/// even when its version has no suffix.
pub fn newest_release(
    releases_json: &[u8],
    running_version: &str,
    channel: UpdateChannel,
) -> ResultType<Option<NewRelease>> {
    let running = Version::parse(running_version)
        .ok_or_else(|| anyhow!("the running version {running_version} is not a version"))?;
    let releases: Vec<GithubRelease> =
        serde_json::from_slice(releases_json).context("invalid release list")?;
    let mut newest: Option<(Version, NewRelease)> = None;
    for release in releases {
        if release.draft {
            continue;
        }
        let Some(version_text) = version_of_tag(&release.tag_name) else {
            continue;
        };
        let Some(version) = Version::parse(&version_text) else {
            continue;
        };
        if channel == UpdateChannel::Stable && (release.prerelease || version.is_prerelease()) {
            continue;
        }
        if version <= running {
            continue;
        }
        if newest.as_ref().map_or(true, |(best, _)| version > *best) {
            newest = Some((
                version,
                NewRelease {
                    tag: release.tag_name,
                    version: version_text,
                },
            ));
        }
    }
    Ok(newest.map(|(_, release)| release))
}

/// Checks `signature` (base64, as SHA256SUMS.sig holds it) over `sums` with
/// `public_key` and returns the list as file name to lowercase hash.
pub fn verify_signed_sums(
    sums: &[u8],
    signature: &[u8],
    public_key: &[u8; 32],
) -> ResultType<HashMap<String, String>> {
    let encoded = std::str::from_utf8(signature)
        .map_err(|_| anyhow!("the release signature is not text"))?
        .trim();
    let decoded = STANDARD
        .decode(encoded)
        .map_err(|_| anyhow!("the release signature is not base64"))?;
    if decoded.len() != 64 {
        bail!("the release signature has the wrong length");
    }
    let mut bytes = [0u8; 64];
    bytes.copy_from_slice(&decoded);
    let signature =
        Signature::from_bytes(&bytes).map_err(|_| anyhow!("the release signature is invalid"))?;
    hbb_common::sodiumoxide::init().map_err(|_| anyhow!("failed to initialize sodiumoxide"))?;
    if !verify_detached(&signature, sums, &PublicKey(*public_key)) {
        bail!("the release signature does not match SHA256SUMS");
    }
    parse_sums(sums)
}

fn parse_sums(sums: &[u8]) -> ResultType<HashMap<String, String>> {
    let text = std::str::from_utf8(sums).map_err(|_| anyhow!("SHA256SUMS is not text"))?;
    let mut hashes = HashMap::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let (hash, name) = line
            .split_once("  ")
            .or_else(|| line.split_once(" *"))
            .ok_or_else(|| anyhow!("SHA256SUMS has a line without a file name"))?;
        if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_hexdigit()) {
            bail!("SHA256SUMS has a line without a hash");
        }
        if name.is_empty() || name.contains(['/', '\\', ':']) {
            bail!("SHA256SUMS names a file that is not a plain name");
        }
        if hashes
            .insert(name.to_owned(), hash.to_ascii_lowercase())
            .is_some()
        {
            bail!("SHA256SUMS lists {name} twice");
        }
    }
    Ok(hashes)
}

#[derive(Deserialize)]
struct Manifest {
    version: String,
    assets: Vec<ManifestAsset>,
}

#[derive(Deserialize)]
struct ManifestAsset {
    name: String,
    sha256: String,
    size: u64,
}

/// The package file of `version` for a platform, as the release workflow
/// names them (neodesk-1.5.0-rc.9-windows-x86_64.msi).
pub fn package_file_name(version: &str, query: &UpdateArtifactQuery<'_>) -> String {
    format!(
        "{}-{version}-{}-{}.{}",
        hbb_common::config::EXE_NAME,
        query.platform,
        query.arch,
        query.format
    )
}

/// The package of release `tag` for `query`, checked against the release's
/// signed SHA256SUMS: the release is newer than `running_version` (an older
/// signed release handed in by its address is no update), the signature, the
/// manifest's hash and version, and the package's hash in both lists.
pub fn verified_package(
    tag: &str,
    sums: &[u8],
    signature: &[u8],
    manifest: &[u8],
    query: &UpdateArtifactQuery<'_>,
    public_key: &[u8; 32],
    running_version: &str,
) -> ResultType<VerifiedUpdateArtifact> {
    let version = version_of_tag(tag).ok_or_else(|| anyhow!("{tag} is not a desktop release"))?;
    let running = Version::parse(running_version)
        .ok_or_else(|| anyhow!("the running version {running_version} is not a version"))?;
    if Version::parse(&version).map_or(true, |release| release <= running) {
        bail!("release {version} is not newer than the running {running_version}");
    }
    let hashes = verify_signed_sums(sums, signature, public_key)?;
    let manifest_hash = crate::update_hash::sha256_reader_hex(&mut &manifest[..])?;
    if hashes.get(MANIFEST_FILE) != Some(&manifest_hash) {
        bail!("the release manifest is not the one SHA256SUMS lists");
    }
    let manifest: Manifest =
        serde_json::from_slice(manifest).context("invalid release manifest")?;
    if manifest.version != version {
        bail!(
            "the release manifest is for {}, not {version}",
            manifest.version
        );
    }
    let file_name = package_file_name(&version, query);
    let sha256 = hashes
        .get(&file_name)
        .ok_or_else(|| anyhow!("release {version} has no {file_name}"))?;
    let asset = manifest
        .assets
        .iter()
        .find(|asset| asset.name == file_name)
        .ok_or_else(|| anyhow!("the release manifest has no {file_name}"))?;
    if !asset.sha256.eq_ignore_ascii_case(sha256) {
        bail!("the release manifest and SHA256SUMS disagree on {file_name}");
    }
    if asset.size == 0 {
        bail!("the release manifest gives {file_name} no size");
    }
    Ok(VerifiedUpdateArtifact {
        version,
        url: release_download_url(tag, &file_name),
        #[cfg(target_os = "macos")]
        file_name: file_name.clone(),
        size: asset.size,
        sha256: sha256.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::sodiumoxide::crypto::sign;

    fn v(value: &str) -> Version {
        Version::parse(value).unwrap()
    }

    #[test]
    fn versions_follow_semver_precedence() {
        let ordered = [
            "1.4.9",
            "1.5.0-beta.2",
            "1.5.0-dev.42",
            "1.5.0-rc.1",
            "1.5.0-rc.2",
            "1.5.0-rc.10",
            "1.5.0",
            "1.5.1",
            "1.10.0",
        ];
        for pair in ordered.windows(2) {
            assert!(v(pair[0]) < v(pair[1]), "{} < {}", pair[0], pair[1]);
        }
        assert_eq!(v("1.5.0+build.7"), v("1.5.0"));
        for bad in ["", "1.5", "1.5.0.1", "v1.5.0", "1.5.x", "1.5.0-", "1.5.0-rc..1", "1.5.0-rc_1"] {
            assert!(Version::parse(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn channel_is_stable_unless_beta_is_chosen() {
        // No build picks Beta by itself, a release candidate neither (A267)
        assert_eq!(UpdateChannel::from_option(""), UpdateChannel::Stable);
        assert_eq!(UpdateChannel::from_option("stable"), UpdateChannel::Stable);
        assert_eq!(UpdateChannel::from_option("other"), UpdateChannel::Stable);
        assert_eq!(UpdateChannel::from_option("beta"), UpdateChannel::Beta);
        assert_eq!(UpdateChannel::from_option(" beta "), UpdateChannel::Beta);
    }

    fn release(tag: &str, prerelease: bool, draft: bool) -> String {
        format!(r#"{{"tag_name":"{tag}","prerelease":{prerelease},"draft":{draft},"assets":[]}}"#)
    }

    fn list(releases: &[String]) -> Vec<u8> {
        format!("[{}]", releases.join(",")).into_bytes()
    }

    #[test]
    fn beta_gets_the_newest_release_candidate() {
        let releases = list(&[
            release("desktop-v1.5.0-rc.9", true, false),
            release("desktop-v1.5.0-rc.10", true, false),
            release("desktop-v1.5.0-rc.8", true, false),
            release("support-v1.6.0", false, false),
            release("desktop-v1.7.0", false, true),
            release("desktop/1.6.0", false, false),
            release("desktop-vnext", false, false),
        ]);
        let newest = newest_release(&releases, "1.5.0-rc.8", UpdateChannel::Beta)
            .unwrap()
            .unwrap();
        assert_eq!(newest.tag, "desktop-v1.5.0-rc.10");
        assert_eq!(newest.version, "1.5.0-rc.10");
        assert_eq!(
            newest.page_url(),
            "https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.10"
        );
    }

    #[test]
    fn stable_skips_prereleases() {
        let releases = list(&[
            release("desktop-v1.5.0-rc.9", true, false),
            release("desktop-v1.5.1", true, false),
        ]);
        assert_eq!(
            newest_release(&releases, "1.4.9", UpdateChannel::Stable).unwrap(),
            None
        );
        let releases = list(&[
            release("desktop-v1.5.0-rc.9", true, false),
            release("desktop-v1.5.0", false, false),
        ]);
        let newest = newest_release(&releases, "1.4.9", UpdateChannel::Stable)
            .unwrap()
            .unwrap();
        assert_eq!(newest.version, "1.5.0");
        // Beta takes the stable release too once it is the newest.
        let newest = newest_release(&releases, "1.5.0-rc.8", UpdateChannel::Beta)
            .unwrap()
            .unwrap();
        assert_eq!(newest.version, "1.5.0");
    }

    #[test]
    fn nothing_newer_is_no_update() {
        let releases = list(&[
            release("desktop-v1.5.0-rc.8", true, false),
            release("desktop-v1.5.0-rc.7", true, false),
        ]);
        assert_eq!(
            newest_release(&releases, "1.5.0-rc.8", UpdateChannel::Beta).unwrap(),
            None
        );
        assert_eq!(
            newest_release(&releases, "1.5.0", UpdateChannel::Beta).unwrap(),
            None
        );
        assert!(newest_release(b"{}", "1.5.0", UpdateChannel::Beta).is_err());
        assert!(newest_release(&releases, "dev", UpdateChannel::Beta).is_err());
    }

    struct Fixture {
        public: [u8; 32],
        secret: sign::SecretKey,
        sums: Vec<u8>,
        manifest: Vec<u8>,
    }

    const EXE: &str = "neodesk-1.5.0-rc.9-windows-x86_64.exe";
    const EXE_HASH: &str = "6bf93803e7bd6e42c9a57a6b7fbeb5824b364418fb060541d8738368e18595ec";
    const TAG: &str = "desktop-v1.5.0-rc.9";
    const RUNNING: &str = "1.5.0-rc.8";
    const QUERY: UpdateArtifactQuery<'static> = UpdateArtifactQuery {
        platform: "windows",
        arch: "x86_64",
        format: "exe",
    };

    fn manifest(version: &str, hash: &str, size: u64) -> Vec<u8> {
        format!(
            r#"{{"schema_version":1,"version":"{version}","assets":[{{"name":"{EXE}","sha256":"{hash}","size":{size}}}]}}"#
        )
        .into_bytes()
    }

    fn sums_for(manifest: &[u8], exe_hash: &str) -> Vec<u8> {
        let manifest_hash = crate::update_hash::sha256_reader_hex(&mut &manifest[..]).unwrap();
        format!("{exe_hash}  {EXE}\n{manifest_hash}  {MANIFEST_FILE}\n").into_bytes()
    }

    fn fixture() -> Fixture {
        hbb_common::sodiumoxide::init().unwrap();
        let (public, secret) = sign::gen_keypair();
        let manifest = manifest("1.5.0-rc.9", EXE_HASH, 25586064);
        let sums = sums_for(&manifest, EXE_HASH);
        Fixture {
            public: public.0,
            secret,
            sums,
            manifest,
        }
    }

    fn sign_sums(sums: &[u8], secret: &sign::SecretKey) -> Vec<u8> {
        let signature = sign::sign_detached(sums, secret);
        format!("{}\n", STANDARD.encode(signature.to_bytes())).into_bytes()
    }

    #[test]
    fn a_signed_release_gives_the_package_with_hash_and_size() {
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        let package =
            verified_package(TAG, &f.sums, &signature, &f.manifest, &QUERY, &f.public, RUNNING).unwrap();
        assert_eq!(package.version, "1.5.0-rc.9");
        assert_eq!(
            package.url,
            "https://github.com/neodeskapp/neodesk-client/releases/download/desktop-v1.5.0-rc.9/neodesk-1.5.0-rc.9-windows-x86_64.exe"
        );
        assert_eq!(package.sha256, EXE_HASH);
        assert_eq!(package.size, 25586064);
        // The download URL passes the updater's own check of asset URLs.
        assert!(crate::updater::get_update_download_file_from_url(&package.url).is_some());
    }

    #[test]
    fn a_release_signed_with_another_key_is_refused() {
        let f = fixture();
        let (_, other_secret) = sign::gen_keypair();
        let signature = sign_sums(&f.sums, &other_secret);
        let err = verified_package(TAG, &f.sums, &signature, &f.manifest, &QUERY, &f.public, RUNNING)
            .err().expect("refused");
        assert!(err.to_string().contains("signature"), "{err}");
    }

    #[test]
    fn a_changed_hash_list_is_refused() {
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        let other = "0".repeat(64);
        let tampered = String::from_utf8(f.sums.clone())
            .unwrap()
            .replace(EXE_HASH, &other)
            .into_bytes();
        assert!(
            verified_package(TAG, &tampered, &signature, &f.manifest, &QUERY, &f.public, RUNNING).is_err()
        );
    }

    #[test]
    fn a_manifest_outside_the_signed_list_is_refused() {
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        // Same package hash, but a bigger size: the manifest's own hash changes.
        let bigger = manifest("1.5.0-rc.9", EXE_HASH, 99999999);
        let err = verified_package(TAG, &f.sums, &signature, &bigger, &QUERY, &f.public, RUNNING)
            .err().expect("refused");
        assert!(err.to_string().contains("manifest"), "{err}");
    }

    #[test]
    fn an_older_release_under_a_newer_tag_is_refused() {
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        let err = verified_package(
            "desktop-v1.5.0-rc.10",
            &f.sums,
            &signature,
            &f.manifest,
            &QUERY,
            &f.public,
            RUNNING,
        )
        .err().expect("refused");
        assert!(err.to_string().contains("1.5.0-rc.10"), "{err}");
    }

    #[test]
    fn a_signed_release_not_newer_than_the_running_build_is_refused() {
        // A release page handed in by address (About, the notice, update-me)
        // skips the release list: the package check refuses a downgrade too.
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        for running in ["1.5.0-rc.9", "1.5.0-rc.10", "1.5.0", "1.6.0"] {
            let err = verified_package(TAG, &f.sums, &signature, &f.manifest, &QUERY, &f.public, running)
                .err()
                .unwrap_or_else(|| panic!("rc.9 accepted on {running}"));
            assert!(err.to_string().contains("not newer"), "{running}: {err}");
        }
        assert!(
            verified_package(TAG, &f.sums, &signature, &f.manifest, &QUERY, &f.public, "dev").is_err()
        );
        assert!(
            verified_package(TAG, &f.sums, &signature, &f.manifest, &QUERY, &f.public, "1.5.0-rc.8").is_ok()
        );
    }

    #[test]
    fn manifest_and_list_must_agree_on_the_package() {
        hbb_common::sodiumoxide::init().unwrap();
        let (public, secret) = sign::gen_keypair();
        let other = "1".repeat(64);
        let manifest = manifest("1.5.0-rc.9", &other, 25586064);
        let sums = sums_for(&manifest, EXE_HASH);
        let signature = sign_sums(&sums, &secret);
        let err = verified_package(TAG, &sums, &signature, &manifest, &QUERY, &public.0, RUNNING)
            .err().expect("refused");
        assert!(err.to_string().contains("disagree"), "{err}");
    }

    #[test]
    fn a_platform_without_a_package_is_refused() {
        let f = fixture();
        let signature = sign_sums(&f.sums, &f.secret);
        let msi = UpdateArtifactQuery {
            format: "msi",
            ..QUERY
        };
        assert!(verified_package(TAG, &f.sums, &signature, &f.manifest, &msi, &f.public, RUNNING).is_err());
    }

    #[test]
    fn the_release_key_checks_the_published_rc8_list() {
        // SHA256SUMS and SHA256SUMS.sig as published with desktop-v1.5.0-rc.8.
        let sums = include_bytes!("release_tests/SHA256SUMS");
        let signature = include_bytes!("release_tests/SHA256SUMS.sig");
        let hashes = verify_signed_sums(sums, signature, &RELEASE_PUBLIC_KEY).unwrap();
        assert_eq!(
            hashes["neodesk-1.5.0-rc.8-windows-x86_64.msi"],
            "8ccf08e09cc61b3fc39ef0559e79b4139eb63fffbae4359328ae7e64beaae8e8"
        );
        assert!(verify_signed_sums(&sums[1..], signature, &RELEASE_PUBLIC_KEY).is_err());
    }

    #[test]
    fn sums_lines_must_be_hash_and_plain_name() {
        let hash = "a".repeat(64);
        assert!(parse_sums(format!("{hash}  a.exe\n{hash} *b.msi\n").as_bytes()).is_ok());
        for bad in [
            format!("{hash} a.exe"),
            format!("abc  a.exe"),
            format!("{hash}  ../a.exe"),
            format!("{hash}  a.exe\n{hash}  a.exe"),
        ] {
            assert!(parse_sums(bad.as_bytes()).is_err(), "{bad}");
        }
    }
}
