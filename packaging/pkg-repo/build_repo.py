#!/usr/bin/env python3
"""Builds the NeoDesk package repository (https://pkg.neode.sk) from the
client's GitHub releases.

    python3 packaging/pkg-repo/build_repo.py --out tree --work work \
        --key-id <fingerprint> --passphrase-file <file> [--keep 3] \
        [--require-tag desktop-v1.5.0] [--allow-mismatch desktop-v1.5.0-rc.4]

The repository is a function of the releases: every run rebuilds the whole
tree from the newest desktop-v* releases, so running it twice publishes the
same packages.

- stable: the newest --keep releases that are not pre-releases
- testing: the newest --keep releases of any kind (release candidates too)

Each release's SHA256SUMS must carry a good SHA256SUMS.sig from the release
key (scripts/collect_desktop_dist.sh) and its packages must match it. A
release whose packages don't carry its version (1.5.0-rc.4 as 1.5.0~rc.4 in
the deb and the rpm) is left out, unless --allow-mismatch names it.

Output in --out:
  deb/    apt: dists/{stable,testing}/main/binary-{amd64,arm64}, pool/
  rpm/    dnf (Fedora, RHEL and alikes): {stable,testing}/ and neodesk.repo
  suse/   zypper (openSUSE, SLES): {stable,testing}/ and neodesk.repo
  README.txt, MANIFEST.sha256 (sha256sum of every other file)
and --work/upload.tar with MANIFEST.sha256 and the files that the live
repository (--live-url) doesn't have yet, for neodesk-pkg-receive.

rpm packages are signed with the repository key. A package that is live
already with a good signature and the same header and payload is reused, so
reruns change no package file.
"""

import argparse
import base64
import gzip
import hashlib
import json
import lzma
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
SUITES = ("stable", "testing")
# release asset suffix -> (tree, architecture as the package manager names it)
ASSETS = {
    "linux-x86_64.deb": ("deb", "amd64"),
    "linux-aarch64.deb": ("deb", "arm64"),
    "linux-x86_64.rpm": ("rpm", "x86_64"),
    "linux-aarch64.rpm": ("rpm", "aarch64"),
    "linux-x86_64-suse.rpm": ("suse", "x86_64"),
    "linux-aarch64-suse.rpm": ("suse", "aarch64"),
}
DEB_ARCHES = ("amd64", "arm64")
PUBLIC = "https://pkg.neode.sk"


def log(msg):
    print(msg, flush=True)


def run(*cmd, cwd=None, capture=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=capture, text=True)
    if r.returncode != 0:
        sys.exit(f"failed: {' '.join(cmd)}\n{r.stdout or ''}{r.stderr or ''}")
    return r.stdout if capture else ""


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def version_key(version):
    """1.5.0 > 1.5.0-rc.10 > 1.5.0-rc.4 > 1.4.2."""
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?", version)
    if not m:
        return None
    pre = m.group(4)
    parts = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split(".")) if pre else ()
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), 0 if pre else 1, parts)


def release_public_key():
    text = open(os.path.join(REPO_ROOT, "scripts/collect_desktop_dist.sh"), encoding="utf-8").read()
    return re.search(r'^RELEASE_PUBLIC_KEY="([A-Za-z0-9+/=]+)"', text, re.M).group(1)


def github(url, accept="application/vnd.github+json"):
    headers = {"Accept": accept, "User-Agent": "neodesk-pkg-repo", "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300)


def releases(args):
    """desktop-v* releases, newest version first. From GitHub, or for tests
    from --local-releases: <dir>/<tag>/ with the release's files and a
    release.json ({"prerelease": true|false})."""
    raw = []
    if args.local_releases:
        for tag in sorted(os.listdir(args.local_releases)):
            d = os.path.join(args.local_releases, tag)
            meta = json.load(open(os.path.join(d, "release.json")))
            raw.append({"tag": tag, "draft": False, "prerelease": bool(meta.get("prerelease")),
                        "assets": {n: os.path.join(d, n) for n in os.listdir(d)}})
    else:
        url = f"https://api.github.com/repos/{args.repo}/releases?per_page=100"
        while url:
            with github(url) as r:
                page, link = json.load(r), r.headers.get("Link") or ""
            for rel in page:
                raw.append({"tag": rel["tag_name"], "draft": rel["draft"], "prerelease": rel["prerelease"],
                            "assets": {a["name"]: a["browser_download_url"] for a in rel["assets"]}})
            m = re.search(r'<([^>]+)>;\s*rel="next"', link)
            url = m.group(1) if m else None
    found = []
    for r in raw:
        if r["draft"] or not r["tag"].startswith("desktop-v"):
            continue
        version = r["tag"][len("desktop-v"):]
        key = version_key(version)
        if key is None:
            log(f"skip {r['tag']}: not <major>.<minor>.<patch>[-<suffix>]")
            continue
        # A version with a suffix is a pre-release whatever the flag says.
        r["prerelease"] = r["prerelease"] or "-" in version
        found.append({**r, "version": version, "key": key})
    return sorted(found, key=lambda r: r["key"], reverse=True)


def download(source, dest):
    if os.path.isfile(dest):
        return
    if os.path.isfile(source):
        shutil.copyfile(source, dest)
        return
    # Public download address, without the token: it redirects to storage
    # that refuses a second kind of authorization.
    req = urllib.request.Request(source, headers={"User-Agent": "neodesk-pkg-repo"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest + ".part", "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    os.rename(dest + ".part", dest)


def verify_release(rel, work, public_key):
    """Downloads a release's Linux packages, checks SHA256SUMS.sig and the
    sums, reads the package metadata. Returns {asset suffix: info} or a
    reason it can't be used."""
    d = os.path.join(work, "releases", rel["tag"])
    os.makedirs(d, exist_ok=True)
    wanted = ["SHA256SUMS", "SHA256SUMS.sig"] + [f"neodesk-{rel['version']}-{s}" for s in ASSETS]
    if "SHA256SUMS" not in rel["assets"] or "SHA256SUMS.sig" not in rel["assets"]:
        return None, "no SHA256SUMS or SHA256SUMS.sig"
    try:
        for name in wanted:
            if name in rel["assets"]:
                download(rel["assets"][name], os.path.join(d, name))
    except (OSError, urllib.error.URLError) as e:
        return None, f"download failed: {e}"
    sums_path, sig_path = os.path.join(d, "SHA256SUMS"), os.path.join(d, "SHA256SUMS.sig")
    der = bytes.fromhex("302a300506032b6570032100") + base64.b64decode(public_key)
    with open(os.path.join(work, "release-key.pem"), "w") as f:
        f.write("-----BEGIN PUBLIC KEY-----\n" + base64.b64encode(der).decode() + "\n-----END PUBLIC KEY-----\n")
    with open(os.path.join(d, "sig.bin"), "wb") as f:
        f.write(base64.b64decode(open(sig_path).read().strip()))
    r = subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey",
                        os.path.join(work, "release-key.pem"), "-rawin", "-in", sums_path,
                        "-sigfile", os.path.join(d, "sig.bin")], capture_output=True, text=True)
    if r.returncode != 0:
        return None, "SHA256SUMS.sig does not verify with the release key"
    sums = {}
    for line in open(sums_path, encoding="utf-8"):
        digest, name = line.split(None, 1)
        sums[name.strip().lstrip("*")] = digest
    want = rel["version"].replace("-", "~", 1)
    found = {}
    for suffix, (tree, arch) in ASSETS.items():
        name = f"neodesk-{rel['version']}-{suffix}"
        path = os.path.join(d, name)
        if not os.path.isfile(path):
            log(f"  {rel['tag']}: no {name}")
            continue
        if sums.get(name) != sha256(path):
            return None, f"{name} does not match SHA256SUMS"
        if tree == "deb":
            fields = dict(l.split(": ", 1) for l in run("dpkg-deb", "-f", path, "Package", "Version",
                                                         "Architecture").strip().splitlines())
            meta = (fields["Package"], fields["Version"], fields["Architecture"])
            expect = ("neodesk", want, arch)
            pkgname = f"neodesk_{fields['Version']}_{arch}.deb"
        else:
            out = run("rpm", "-qp", "--nosignature", "--nodigest", "--qf",
                      "%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}", path).split("\t")
            meta = (out[0], out[1], out[3])
            expect = ("neodesk", want, arch)
            pkgname = f"{out[0]}-{out[1]}-{out[2]}.{out[3]}.rpm"
        found[suffix] = {"path": path, "name": pkgname, "tree": tree, "arch": arch,
                         "meta": meta, "ok": meta == expect}
    if not found:
        return None, "no Linux packages"
    return found, None


def plan(args, work):
    public_key = args.release_key or release_public_key()
    allow = {t for t in (args.allow_mismatch or "").split(",") if t}
    picked = {s: [] for s in SUITES}
    for rel in releases(args):
        if all(len(picked[s]) >= args.keep for s in SUITES):
            break
        if rel["prerelease"] and len(picked["testing"]) >= args.keep:
            continue
        found, reason = verify_release(rel, work, public_key)
        if found:
            bad = [f"{f['name']} says {'/'.join(f['meta'])}" for f in found.values() if not f["ok"]]
            if bad and rel["tag"] not in allow:
                reason = "its packages don't carry its version: " + "; ".join(bad)
            elif bad:
                log(f"  {rel['tag']}: version metadata does not match, taken anyway (--allow-mismatch)")
        if reason:
            if rel["tag"] == args.require_tag:
                sys.exit(f"{rel['tag']} can't be published: {reason}")
            log(f"skip {rel['tag']}: {reason}")
            continue
        rel["files"] = found
        suites = ["testing"] if rel["prerelease"] else ["stable", "testing"]
        for s in suites:
            if len(picked[s]) < args.keep:
                picked[s].append(rel)
        log(f"take {rel['tag']} for {', '.join(s for s in suites if rel in picked[s])}")
    if args.require_tag and not any(r["tag"] == args.require_tag for s in SUITES for r in picked[s]):
        sys.exit(f"{args.require_tag} is not among the releases this run publishes")
    return picked


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def live_manifest(url):
    data = fetch(url + "/MANIFEST.sha256")
    out = {}
    for line in (data or b"").decode(errors="replace").splitlines():
        m = re.fullmatch(r"([0-9a-f]{64})  (\S+)", line)
        if m:
            out[m.group(2)] = m.group(1)
    return out


def gpg(args, *cmd):
    return run("gpg", "--batch", "--yes", "--pinentry-mode", "loopback", "--passphrase-file",
               args.passphrase_file, "--local-user", args.key_id, "--digest-algo", "SHA512", *cmd)


def rpm_ids(path):
    return run("rpm", "-qp", "--nosignature", "--nodigest", "--qf", "%{SHA256HEADER} %{PAYLOADDIGEST}", path)


def signed_rpm(args, work, f, rel_path, live, rpmdb):
    """The signed rpm for rel_path: the live one when it is the same package
    with a good signature, else the release's package signed now."""
    dest = os.path.join(work, "signed", f["tree"], f["name"])
    if os.path.isfile(dest):
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if rel_path in live:
        data = fetch(f"{args.live_url}/{rel_path}")
        if data and hashlib.sha256(data).hexdigest() == live[rel_path]:
            with open(dest + ".live", "wb") as out:
                out.write(data)
            ok = subprocess.run(["rpmkeys", "--dbpath", rpmdb, "-K", dest + ".live"],
                                capture_output=True, text=True)
            ids = rpm_ids(dest + ".live")
            if ok.returncode == 0 and "(none)" not in ids and ids == rpm_ids(f["path"]):
                os.rename(dest + ".live", dest)
                log(f"  reuse signed {rel_path}")
                return dest
            os.unlink(dest + ".live")
    shutil.copyfile(f["path"], dest)
    run("rpmsign", "--define", f"_gpg_name {args.key_id}",
        "--define", "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback "
                    f"--passphrase-file {args.passphrase_file}",
        "--addsign", dest)
    r = subprocess.run(["rpmkeys", "--dbpath", rpmdb, "-K", dest], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"signed {dest} but it doesn't verify: {r.stdout}{r.stderr}")
    log(f"  signed {rel_path}")
    return dest


def link(src, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if not os.path.exists(dest):
        os.link(src, dest)


def build_deb(args, picked, out):
    deb = os.path.join(out, "deb")
    for s in SUITES:
        for rel in picked[s]:
            for f in rel["files"].values():
                if f["tree"] == "deb":
                    link(f["path"], os.path.join(deb, "pool/main/n/neodesk", f["name"]))
    paragraphs = {}
    if os.path.isdir(os.path.join(deb, "pool")):
        text = run("apt-ftparchive", "packages", "pool", cwd=deb)
        for para in text.strip().split("\n\n"):
            if para.strip():
                fn = re.search(r"^Filename: (.+)$", para, re.M).group(1)
                paragraphs[fn] = para.strip() + "\n"
    for s in SUITES:
        dist = os.path.join(deb, "dists", s)
        for arch in DEB_ARCHES:
            names = sorted({f["name"] for rel in picked[s] for f in rel["files"].values()
                            if f["tree"] == "deb" and f["arch"] == arch})
            body = "\n".join(paragraphs[f"pool/main/n/neodesk/{n}"] for n in names).encode()
            d = os.path.join(dist, "main", f"binary-{arch}")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "Packages"), "wb") as f:
                f.write(body)
            with open(os.path.join(d, "Packages.gz"), "wb") as raw:
                with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0, filename="") as f:
                    f.write(body)
            with lzma.open(os.path.join(d, "Packages.xz"), "wb", preset=6) as f:
                f.write(body)
        label = "release candidates and releases" if s == "testing" else "releases"
        release = run("apt-ftparchive",
                      "-o", "APT::FTPArchive::Release::Origin=NeoDesk",
                      "-o", "APT::FTPArchive::Release::Label=NeoDesk",
                      "-o", f"APT::FTPArchive::Release::Suite={s}",
                      "-o", f"APT::FTPArchive::Release::Codename={s}",
                      "-o", f"APT::FTPArchive::Release::Architectures={' '.join(DEB_ARCHES)}",
                      "-o", "APT::FTPArchive::Release::Components=main",
                      "-o", f"APT::FTPArchive::Release::Description=NeoDesk client, {label}",
                      "release", dist)
        with open(os.path.join(dist, "Release"), "w", encoding="utf-8") as f:
            f.write(release)
        gpg(args, "--clearsign", "-o", os.path.join(dist, "InRelease"), os.path.join(dist, "Release"))
        gpg(args, "--armor", "--detach-sign", "-o", os.path.join(dist, "Release.gpg"),
            os.path.join(dist, "Release"))


def build_rpm(args, picked, out, work, live, key_asc):
    rpmdb = os.path.join(work, "rpmdb")
    if not os.path.isdir(rpmdb):
        os.makedirs(rpmdb)
        run("rpmkeys", "--dbpath", rpmdb, "--import", key_asc)
    for tree, product in (("rpm", "Fedora, RHEL, Rocky, AlmaLinux"), ("suse", "openSUSE, SLES")):
        for s in SUITES:
            repo = os.path.join(out, tree, s)
            os.makedirs(os.path.join(repo, "Packages"), exist_ok=True)
            for rel in picked[s]:
                for f in rel["files"].values():
                    if f["tree"] == tree:
                        rel_path = f"{tree}/{s}/Packages/{f['name']}"
                        signed = signed_rpm(args, work, f, rel_path, live, rpmdb)
                        link(signed, os.path.join(repo, "Packages", f["name"]))
            run("createrepo_c", "--quiet", "--general-compress-type", "gz", "--checksum", "sha256",
                "--no-database", repo)
            gpg(args, "--armor", "--detach-sign", "-o", os.path.join(repo, "repodata/repomd.xml.asc"),
                os.path.join(repo, "repodata/repomd.xml"))
        extra = "type=rpm-md\nautorefresh=1\npkg_gpgcheck=1\n" if tree == "suse" else "metadata_expire=6h\n"
        with open(os.path.join(out, tree, "neodesk.repo"), "w", encoding="utf-8") as f:
            for s, enabled in (("stable", 1), ("testing", 0)):
                name = "neodesk" if s == "stable" else "neodesk-testing"
                title = "NeoDesk" if s == "stable" else "NeoDesk testing (release candidates)"
                f.write(f"[{name}]\nname={title}\nbaseurl={PUBLIC}/{tree}/{s}\nenabled={enabled}\n"
                        f"gpgcheck=1\nrepo_gpgcheck=1\n{extra}gpgkey={PUBLIC}/neodesk.asc\n\n")
        log(f"{tree}: repositories for {product} written")


README = """NeoDesk client packages, signed with the key at
https://pkg.neode.sk/neodesk.asc (also as binary keyring: neodesk.gpg).
Fingerprint: {fpr}

Debian, Ubuntu and derivatives (amd64, arm64):
  sudo install -d -m 0755 /etc/apt/keyrings
  sudo curl -fsSLo /etc/apt/keyrings/neodesk.gpg https://pkg.neode.sk/neodesk.gpg
  echo "deb [signed-by=/etc/apt/keyrings/neodesk.gpg] https://pkg.neode.sk/deb stable main" \\
    | sudo tee /etc/apt/sources.list.d/neodesk.list
  sudo apt update && sudo apt install neodesk

Fedora, RHEL, Rocky, AlmaLinux (x86_64, aarch64):
  sudo curl -fsSLo /etc/yum.repos.d/neodesk.repo https://pkg.neode.sk/rpm/neodesk.repo
  sudo dnf install neodesk

openSUSE, SLES (x86_64, aarch64):
  sudo zypper addrepo https://pkg.neode.sk/suse/neodesk.repo
  sudo zypper refresh && sudo zypper install neodesk

Suites: stable has releases, testing has release candidates and releases
(apt: "testing" instead of "stable"; dnf and zypper: enable neodesk-testing).
Each suite keeps the newest {keep} versions.

Releases: https://github.com/neodeskapp/neodesk-client/releases
"""


def write_manifest(out):
    lines = []
    for dirpath, _, names in os.walk(out):
        for n in names:
            path = os.path.join(dirpath, n)
            rel = os.path.relpath(path, out).replace(os.sep, "/")
            if rel != "MANIFEST.sha256":
                lines.append(f"{sha256(path)}  {rel}")
    lines.sort(key=lambda l: l.split("  ", 1)[1])
    with open(os.path.join(out, "MANIFEST.sha256"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return {l.split("  ", 1)[1]: l.split("  ", 1)[0] for l in lines}


def upload_tar(out, manifest, live, path):
    """MANIFEST.sha256 plus every file the live tree lacks or has with another
    hash. Files with several links in the tree go in once and as hard links."""
    send = [n for n, d in manifest.items() if live.get(n) != d]

    def owner(ti):
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = ""
        ti.mode = 0o644
        return ti

    with tarfile.open(path, "w", format=tarfile.PAX_FORMAT) as tf:
        tf.add(os.path.join(out, "MANIFEST.sha256"), "MANIFEST.sha256", filter=owner)
        for n in sorted(send):
            tf.add(os.path.join(out, n), n, filter=owner)
    return send


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "neodeskapp/neodesk-client"))
    p.add_argument("--out", required=True)
    p.add_argument("--work", required=True)
    p.add_argument("--keep", type=int, default=3)
    p.add_argument("--key-id", required=True, help="fingerprint of the repository key in the gpg keyring")
    p.add_argument("--passphrase-file", required=True)
    p.add_argument("--public-key", required=True, help="the repository key, armored (neodesk.asc)")
    p.add_argument("--live-url", default=PUBLIC)
    p.add_argument("--require-tag", default="", help="fail unless this release is published")
    p.add_argument("--allow-mismatch", default="", help="comma-separated tags taken despite wrong version metadata")
    p.add_argument("--local-releases", default="", help="for tests: releases from this folder instead of GitHub")
    p.add_argument("--release-key", default="", help="for tests: release public key (base64 ed25519)")
    args = p.parse_args()
    if args.keep < 1:
        sys.exit("--keep must be at least 1")
    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    os.makedirs(args.out)
    os.makedirs(args.work, exist_ok=True)
    args.passphrase_file = os.path.abspath(args.passphrase_file)

    picked = plan(args, args.work)
    for s in SUITES:
        log(f"{s}: {', '.join(r['tag'] for r in picked[s]) or 'nothing'}")
    live = live_manifest(args.live_url)
    log(f"live repository: {len(live)} files")
    build_deb(args, picked, args.out)
    build_rpm(args, picked, args.out, args.work, live, os.path.abspath(args.public_key))
    fpr = run("gpg", "--batch", "--with-colons", "--fingerprint", args.key_id)
    fpr = re.search(r"^fpr:+([0-9A-F]{40}):", fpr, re.M).group(1)
    with open(os.path.join(args.out, "README.txt"), "w", encoding="utf-8") as f:
        f.write(README.format(fpr=fpr, keep=args.keep))
    manifest = write_manifest(args.out)
    send = upload_tar(args.out, manifest, live, os.path.join(args.work, "upload.tar"))
    size = sum(os.path.getsize(os.path.join(args.out, n)) for n in send)
    log(f"tree: {len(manifest)} files; upload: {len(send)} new or changed ({size} bytes)")
    summary = {s: [r["tag"] for r in picked[s]] for s in SUITES}
    with open(os.path.join(args.work, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    main()
