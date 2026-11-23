#!/usr/bin/env python3
"""Writes the winget manifests of a NeoDesk client release.

    python3 packaging/winget/make_manifests.py --tag desktop-v1.5.0 --out winget

The manifests land in <out>/manifests/n/NeoDesk/NeoDesk/<version>/, the
layout of github.com/microsoft/winget-pkgs. They point at the release's
Windows MSI packages (x64 and arm64), with their SHA-256, product code,
upgrade code and the version Apps & features shows. The release's
SHA256SUMS must carry a good SHA256SUMS.sig from the release key, and the
MSI packages must match it.

Only stable releases go to winget. --allow-prerelease writes manifests for a
release candidate too, to check the output; don't submit those.

Reading the MSI needs msiinfo (Debian/Ubuntu package msitools) or, on
Windows, the Windows Installer COM object. Check the result with
`winget validate --manifest <folder>` on Windows.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(HERE))
IDENTIFIER = "NeoDesk.NeoDesk"
MANIFEST_VERSION = "1.28.0"
ARCHES = {"x86_64": "x64", "aarch64": "arm64"}


def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"failed: {' '.join(cmd)}\n{r.stdout}{r.stderr}")
    return r.stdout


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def msi_properties(path):
    if shutil.which("msiinfo"):
        out = run("msiinfo", "export", path, "Property")
        props = {}
        for line in out.splitlines()[3:]:
            if "\t" in line:
                k, v = line.split("\t", 1)
                props[k] = v.strip()
        return props
    if os.name == "nt":
        script = (
            "$i = New-Object -ComObject WindowsInstaller.Installer;"
            "$db = $i.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$i,@($env:MSI_PATH,0));"
            "$v = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@('SELECT Property, Value FROM Property'));"
            "$v.GetType().InvokeMember('Execute','InvokeMethod',$null,$v,$null);"
            "$o = @{}; while ($r = $v.GetType().InvokeMember('Fetch','InvokeMethod',$null,$v,$null)) {"
            "$o[$r.GetType().InvokeMember('StringData','GetProperty',$null,$r,1)] = "
            "$r.GetType().InvokeMember('StringData','GetProperty',$null,$r,2) };"
            "$o | ConvertTo-Json -Compress"
        )
        r = subprocess.run(["powershell.exe", "-NoProfile", "-Command", script], capture_output=True,
                           text=True, env={**os.environ, "MSI_PATH": os.path.abspath(path)})
        if r.returncode != 0:
            sys.exit(f"can't read {path}: {r.stderr}")
        return json.loads(r.stdout)
    sys.exit("need msiinfo (apt install msitools) to read the MSI packages")


def release_public_key():
    text = open(os.path.join(REPO_ROOT, "scripts/collect_desktop_dist.sh"), encoding="utf-8").read()
    return re.search(r'^RELEASE_PUBLIC_KEY="([A-Za-z0-9+/=]+)"', text, re.M).group(1)


def verify_sums(d, names):
    sums_path, sig_path = os.path.join(d, "SHA256SUMS"), os.path.join(d, "SHA256SUMS.sig")
    der = bytes.fromhex("302a300506032b6570032100") + base64.b64decode(release_public_key())
    pem = os.path.join(d, "release-key.pem")
    with open(pem, "w") as f:
        f.write("-----BEGIN PUBLIC KEY-----\n" + base64.b64encode(der).decode() + "\n-----END PUBLIC KEY-----\n")
    with open(os.path.join(d, "sig.bin"), "wb") as f:
        f.write(base64.b64decode(open(sig_path).read().strip()))
    r = subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", pem, "-rawin",
                        "-in", sums_path, "-sigfile", os.path.join(d, "sig.bin")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("SHA256SUMS.sig does not verify with the release key")
    sums = {}
    for line in open(sums_path, encoding="utf-8"):
        digest, name = line.split(None, 1)
        sums[name.strip().lstrip("*")] = digest
    for n in names:
        if sums.get(n) != sha256(os.path.join(d, n)):
            sys.exit(f"{n} does not match SHA256SUMS")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--tag", required=True)
    p.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "neodeskapp/neodesk-client"))
    p.add_argument("--out", required=True)
    p.add_argument("--download-dir", default="")
    p.add_argument("--allow-prerelease", action="store_true")
    args = p.parse_args()

    info = json.loads(run("gh", "release", "view", args.tag, "-R", args.repo, "--json",
                          "tagName,isPrerelease,isDraft,publishedAt"))
    version = args.tag[len("desktop-v"):] if args.tag.startswith("desktop-v") else ""
    if not re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", version) or info["isDraft"]:
        sys.exit(f"{args.tag} is not a published desktop-v<version> release")
    if (info["isPrerelease"] or "-" in version) and not args.allow_prerelease:
        sys.exit(f"{args.tag} is a pre-release; winget gets stable releases only")

    d = args.download_dir or os.path.join(args.out, "download")
    os.makedirs(d, exist_ok=True)
    msis = {arch: f"neodesk-{version}-windows-{arch}.msi" for arch in ARCHES}
    cmd = ["gh", "release", "download", args.tag, "-R", args.repo, "-D", d, "--skip-existing",
           "-p", "SHA256SUMS", "-p", "SHA256SUMS.sig"]
    for n in msis.values():
        cmd += ["-p", n]
    run(*cmd)
    verify_sums(d, msis.values())

    base = f"https://github.com/{args.repo}/releases/download/{args.tag}"
    installers = []
    for arch, name in msis.items():
        props = msi_properties(os.path.join(d, name))
        for k in ("ProductCode", "UpgradeCode", "ProductVersion", "ProductName", "Manufacturer"):
            if not props.get(k):
                sys.exit(f"{name} has no {k}")
        installers.append(
            f"- Architecture: {ARCHES[arch]}\n"
            f"  InstallerUrl: {base}/{name}\n"
            f"  InstallerSha256: {sha256(os.path.join(d, name)).upper()}\n"
            f"  ProductCode: '{props['ProductCode']}'\n"
            f"  AppsAndFeaturesEntries:\n"
            f"  - DisplayName: {props['ProductName']}\n"
            f"    Publisher: {props['Manufacturer']}\n"
            f"    DisplayVersion: {props['ProductVersion']}\n"
            f"    ProductCode: '{props['ProductCode']}'\n"
            f"    UpgradeCode: '{props['UpgradeCode']}'\n")

    folder = os.path.join(args.out, "manifests", "n", *IDENTIFIER.split("."), version)
    os.makedirs(folder, exist_ok=True)
    head = "# Written by packaging/winget/make_manifests.py in neodeskapp/neodesk-client\n"
    schema = "# yaml-language-server: $schema=https://aka.ms/winget-manifest.{}.%s.schema.json\n\n" % MANIFEST_VERSION
    common = f"PackageIdentifier: {IDENTIFIER}\nPackageVersion: {version}\n"
    files = {
        f"{IDENTIFIER}.yaml": head + schema.format("version") + common
        + f"DefaultLocale: en-US\nManifestType: version\nManifestVersion: {MANIFEST_VERSION}\n",
        f"{IDENTIFIER}.installer.yaml": head + schema.format("installer") + common
        + "InstallerType: wix\nScope: machine\nInstallModes:\n- interactive\n- silent\n- silentWithProgress\n"
        + "UpgradeBehavior: install\nProtocols:\n- neodesk\n"
        + f"ReleaseDate: {info['publishedAt'][:10]}\nInstallers:\n" + "".join(installers)
        + f"ManifestType: installer\nManifestVersion: {MANIFEST_VERSION}\n",
        f"{IDENTIFIER}.locale.en-US.yaml": head + schema.format("defaultLocale") + common
        + "PackageLocale: en-US\n"
        + "Publisher: NeoDesk\n"
        + "PublisherUrl: https://neode.sk\n"
        + "PublisherSupportUrl: https://github.com/neodeskapp/neodesk-client/issues\n"
        + "PrivacyUrl: https://neode.sk/docs/project/privacy/\n"
        + "Author: NeoDesk contributors\n"
        + "PackageName: NeoDesk\n"
        + "PackageUrl: https://neode.sk\n"
        + "License: AGPL-3.0-only\n"
        + "LicenseUrl: https://github.com/neodeskapp/neodesk-client/blob/main/LICENCE\n"
        + "ShortDescription: Open-source remote desktop client for your own NeoDesk or RustDesk server.\n"
        + "Description: |-\n"
        + "  NeoDesk is a remote desktop client based on RustDesk. It connects through your own\n"
        + "  self-hosted NeoDesk or RustDesk server and does not use a public cloud.\n"
        + "Moniker: neodesk\n"
        + "Tags:\n- remote-desktop\n- remote-support\n- remote-access\n- rustdesk\n- self-hosted\n"
        + f"ReleaseNotesUrl: https://github.com/{args.repo}/releases/tag/{args.tag}\n"
        + f"ManifestType: defaultLocale\nManifestVersion: {MANIFEST_VERSION}\n",
    }
    for name, text in files.items():
        with open(os.path.join(folder, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print(folder)


if __name__ == "__main__":
    main()
