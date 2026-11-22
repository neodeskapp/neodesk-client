#!/usr/bin/env bash
# Puts the desktop build artifacts of one CI run under their published names.
#
#   collect_desktop_dist.sh collect <raw dir> <dist dir> <version>
#   collect_desktop_dist.sh sums <dir>
#   collect_desktop_dist.sh sign <dir>
#
# <raw dir> holds the build artifacts as the release workflow downloads them:
#   rustdesk-unsigned-windows-<arch>/   Windows build folder (neodesk.exe, DLLs)
#   windows-installers/                 neodesk-<version>-<arch>.exe and .msi
#   msi-template-arts/                  MSI templates for the console generator
#   neodesk-unsigned-macos-<arch>/   neodesk-<version>-<arch>.dmg, -app.zip, -app.tar.gz
#   linux-debs/                         neodesk-<version>-<arch>.deb
#   linux-rpms/                         rpmbuild output, -suse.rpm for openSUSE
#
# "collect" fills <dist dir> with:
#   <os>-<arch>/    unpacked builds, read by pack_generator_templates.py
#   msi-template/   neodesk-template-<arch>.msi
#   clean/          the packages:
#     neodesk-<version>-windows-<arch>.exe            runs without install, can install itself
#     neodesk-<version>-windows-<arch>.msi            installer
#     neodesk-<version>-windows-<arch>.tar.gz         the unpacked build folder
#     neodesk-<version>-linux-<arch>.deb              installer (Debian, Ubuntu)
#     neodesk-<version>-linux-<arch>.rpm              installer (Fedora, RHEL)
#     neodesk-<version>-linux-<arch>-suse.rpm         installer (openSUSE)
#     neodesk-<version>-linux-<arch>-portable.tar.gz  runs without install
#     neodesk-<version>-macos-<arch>.dmg              installer
#     neodesk-<version>-macos-<arch>-portable.zip     the app, runs from any folder
# Only platforms present in <raw dir> show up.
#
# "sums" writes <dir>/SHA256SUMS over every other file in <dir>, in the
# format of `sha256sum` (check with `sha256sum -c SHA256SUMS`).
#
# "sign" writes <dir>/SHA256SUMS.sig: the ed25519 signature of the
# SHA256SUMS bytes in base64, with the release key (DECISIONS A152) given
# as a PKCS#8 PEM in RELEASE_SIGNING_KEY. The console checks it against the
# public key compiled into it (console/clientrelease/keys.go). It refuses a
# key whose public half is not RELEASE_SIGNING_PUBLIC_KEY (base64 of the
# raw key, the release key when unset).

set -euo pipefail

ARCHES="x86_64 aarch64"
RELEASE_PUBLIC_KEY="iwissiXvSjeFFsG8SdKEZq11uAtRLWCrD7Ky1vfY2n4="

first() {
  # Prints the first file or folder find reports, or nothing.
  find "$@" 2>/dev/null | LC_ALL=C sort | head -n 1 || true
}

collect() {
  local raw="$1" dist="$2" version="$3"
  local arch src stage file app_zip app_tar dmg deb rpm suse bin clean
  mkdir -p "${dist}/clean"
  clean="$(cd "${dist}/clean" && pwd)"

  for arch in ${ARCHES}; do
    src="$(first "${raw}" -maxdepth 2 -type d -name "rustdesk-unsigned-windows-${arch}")"
    if [ -n "${src}" ]; then
      stage="${dist}/windows-${arch}"
      mkdir -p "${stage}"
      cp -a "${src}/." "${stage}/"
      if [ -f "${stage}/rustdesk.exe" ] && [ ! -f "${stage}/neodesk.exe" ]; then
        mv "${stage}/rustdesk.exe" "${stage}/neodesk.exe"
      fi
      # Never ship a Support Agent bake-in from CI.
      rm -f "${stage}/custom.txt"
      tar -C "${stage}" -czf "${dist}/clean/neodesk-${version}-windows-${arch}.tar.gz" .
    fi
    for ext in exe msi; do
      file="$(first "${raw}/windows-installers" -type f -name "neodesk-*-${arch}.${ext}")"
      if [ -n "${file}" ]; then
        cp "${file}" "${dist}/clean/neodesk-${version}-windows-${arch}.${ext}"
      fi
    done
  done

  if [ -d "${raw}/msi-template-arts" ]; then
    mkdir -p "${dist}/msi-template"
    for arch in ${ARCHES}; do
      file="$(first "${raw}/msi-template-arts" -type f -name "*-template-${arch}.msi")"
      if [ -n "${file}" ]; then
        cp "${file}" "${dist}/msi-template/neodesk-template-${arch}.msi"
      fi
    done
  fi

  for arch in ${ARCHES}; do
    src="$(first "${raw}" -maxdepth 2 -type d -name "neodesk-unsigned-macos-${arch}")"
    [ -n "${src}" ] || continue
    dmg="$(first "${src}" -maxdepth 1 -type f -name '*.dmg')"
    if [ -n "${dmg}" ]; then
      cp "${dmg}" "${dist}/clean/neodesk-${version}-macos-${arch}.dmg"
    fi
    app_zip="$(first "${src}" -maxdepth 1 -type f -name '*-app.zip')"
    app_tar="$(first "${src}" -maxdepth 1 -type f -name '*-app.tar.gz')"
    stage="${dist}/macos-${arch}"
    mkdir -p "${stage}"
    if [ -n "${app_tar}" ]; then
      tar -xzf "${app_tar}" -C "${stage}"
    elif [ -n "${app_zip}" ]; then
      unzip -q "${app_zip}" -d "${stage}"
    fi
    find "${stage}" -name custom.txt -delete
    if [ -n "${app_zip}" ]; then
      cp "${app_zip}" "${dist}/clean/neodesk-${version}-macos-${arch}-portable.zip"
    elif [ -n "$(first "${stage}" -maxdepth 1 -name '*.app')" ]; then
      # zip -y keeps the symlinks inside the app's frameworks.
      (cd "${stage}" && zip -qry "${clean}/neodesk-${version}-macos-${arch}-portable.zip" ./*.app)
    fi
  done

  for arch in ${ARCHES}; do
    deb="$(first "${raw}/linux-debs" -type f -name "*${arch}*.deb")"
    if [ -n "${deb}" ]; then
      cp "${deb}" "${dist}/clean/neodesk-${version}-linux-${arch}.deb"
      mkdir -p "${dist}/linux-${arch}"
      dpkg-deb -x "${deb}" "${dist}/linux-${arch}/root"
      bin="$(first "${dist}/linux-${arch}/root" -type f \( -name neodesk -o -name rustdesk \))"
      if [ -n "${bin}" ]; then
        stage="${dist}/linux-${arch}/portable"
        mkdir -p "${stage}"
        cp -a "$(dirname "${bin}")/." "${stage}/"
        if [ -f "${stage}/rustdesk" ] && [ ! -f "${stage}/neodesk" ]; then
          mv "${stage}/rustdesk" "${stage}/neodesk"
        fi
        rm -f "${stage}/custom.txt"
        tar -C "${stage}" -czf "${dist}/clean/neodesk-${version}-linux-${arch}-portable.tar.gz" .
      fi
    fi
    rpm="$(first "${raw}/linux-rpms" -type f -name "*${arch}*.rpm" ! -name '*-suse.rpm')"
    suse="$(first "${raw}/linux-rpms" -type f -name "*${arch}*-suse.rpm")"
    if [ -n "${rpm}" ]; then
      cp "${rpm}" "${dist}/clean/neodesk-${version}-linux-${arch}.rpm"
    fi
    if [ -n "${suse}" ]; then
      cp "${suse}" "${dist}/clean/neodesk-${version}-linux-${arch}-suse.rpm"
    fi
  done

  # Never publish Support Agent bake-ins from CI.
  local bad
  bad="$(find "${dist}/clean" "${dist}/msi-template" \
    \( -iname '*neodesk-support*' -o -iname '*incoming-only*' -o -name 'custom.txt' \) 2>/dev/null || true)"
  if [ -n "${bad}" ]; then
    echo "Refusing to publish Support Agent / bake-in artifacts from CI:" >&2
    echo "${bad}" >&2
    exit 1
  fi
  if [ -z "$(ls -A "${dist}/clean")" ]; then
    echo "No packages found in ${raw}" >&2
    exit 1
  fi
}

sums() {
  local dir="$1" names
  (
    cd "${dir}"
    rm -f SHA256SUMS SHA256SUMS.sig
    names="$(find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
    printf '%s\n' "${names}" | while IFS= read -r name; do sha256sum -- "${name}"; done > SHA256SUMS
  )
}

sign() {
  local dir="$1"
  if [ -z "${RELEASE_SIGNING_KEY:-}" ]; then
    echo "RELEASE_SIGNING_KEY is empty" >&2
    exit 2
  fi
  [ -f "${dir}/SHA256SUMS" ] || { echo "no SHA256SUMS in ${dir}" >&2; exit 1; }
  (
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT
    umask 077
    printf '%s\n' "${RELEASE_SIGNING_KEY}" > "${tmp}/key.pem"
    openssl pkey -in "${tmp}/key.pem" -pubout -out "${tmp}/public.pem"
    public="$(openssl pkey -pubin -in "${tmp}/public.pem" -outform DER | tail -c 32 | base64 -w0)"
    if [ "${public}" != "${RELEASE_SIGNING_PUBLIC_KEY:-${RELEASE_PUBLIC_KEY}}" ]; then
      echo "RELEASE_SIGNING_KEY is not the release key (its public key is ${public})" >&2
      exit 1
    fi
    openssl pkeyutl -sign -inkey "${tmp}/key.pem" -rawin -in "${dir}/SHA256SUMS" -out "${tmp}/sig"
    openssl pkeyutl -verify -pubin -inkey "${tmp}/public.pem" -rawin \
      -in "${dir}/SHA256SUMS" -sigfile "${tmp}/sig" > /dev/null
    printf '%s\n' "$(base64 -w0 "${tmp}/sig")" > "${dir}/SHA256SUMS.sig"
  )
}

case "${1:-}" in
  collect)
    [ "$#" -eq 4 ] || { echo "usage: $0 collect <raw dir> <dist dir> <version>" >&2; exit 2; }
    collect "$2" "$3" "$4"
    ;;
  sums)
    [ "$#" -eq 2 ] || { echo "usage: $0 sums <dir>" >&2; exit 2; }
    sums "$2"
    ;;
  sign)
    [ "$#" -eq 2 ] || { echo "usage: $0 sign <dir>" >&2; exit 2; }
    sign "$2"
    ;;
  *)
    echo "usage: $0 collect <raw dir> <dist dir> <version> | sums <dir> | sign <dir>" >&2
    exit 2
    ;;
esac
