#!/usr/bin/env bash
# Puts the desktop build artifacts of one CI run under their published names.
#
#   collect_desktop_dist.sh collect <raw dir> <dist dir> <version>
#   collect_desktop_dist.sh sums <dir>
#
# <raw dir> holds the build artifacts as the release workflow downloads them:
#   rustdesk-unsigned-windows-<arch>/   Windows build folder (betterdesk.exe, DLLs)
#   windows-installers/                 betterdesk-<version>-<arch>.exe and .msi
#   msi-template-arts/                  MSI templates for the console generator
#   betterdesk-unsigned-macos-<arch>/   betterdesk-<version>-<arch>.dmg, -app.zip, -app.tar.gz
#   linux-debs/                         betterdesk-<version>-<arch>.deb
#   linux-rpms/                         rpmbuild output, -suse.rpm for openSUSE
#
# "collect" fills <dist dir> with:
#   <os>-<arch>/    unpacked builds, read by pack_generator_templates.py
#   msi-template/   betterdesk-template-<arch>.msi
#   clean/          the packages:
#     betterdesk-<version>-windows-<arch>.exe            runs without install, can install itself
#     betterdesk-<version>-windows-<arch>.msi            installer
#     betterdesk-<version>-windows-<arch>.tar.gz         the unpacked build folder
#     betterdesk-<version>-linux-<arch>.deb              installer (Debian, Ubuntu)
#     betterdesk-<version>-linux-<arch>.rpm              installer (Fedora, RHEL)
#     betterdesk-<version>-linux-<arch>-suse.rpm         installer (openSUSE)
#     betterdesk-<version>-linux-<arch>-portable.tar.gz  runs without install
#     betterdesk-<version>-macos-<arch>.dmg              installer
#     betterdesk-<version>-macos-<arch>-portable.zip     the app, runs from any folder
# Only platforms present in <raw dir> show up.
#
# "sums" writes <dir>/SHA256SUMS over every other file in <dir>, in the
# format of `sha256sum` (check with `sha256sum -c SHA256SUMS`).

set -euo pipefail

ARCHES="x86_64 aarch64"

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
      if [ -f "${stage}/rustdesk.exe" ] && [ ! -f "${stage}/betterdesk.exe" ]; then
        mv "${stage}/rustdesk.exe" "${stage}/betterdesk.exe"
      fi
      # Never ship a Support Agent bake-in from CI.
      rm -f "${stage}/custom.txt"
      tar -C "${stage}" -czf "${dist}/clean/betterdesk-${version}-windows-${arch}.tar.gz" .
    fi
    for ext in exe msi; do
      file="$(first "${raw}/windows-installers" -type f -name "betterdesk-*-${arch}.${ext}")"
      if [ -n "${file}" ]; then
        cp "${file}" "${dist}/clean/betterdesk-${version}-windows-${arch}.${ext}"
      fi
    done
  done

  if [ -d "${raw}/msi-template-arts" ]; then
    mkdir -p "${dist}/msi-template"
    for arch in ${ARCHES}; do
      file="$(first "${raw}/msi-template-arts" -type f -name "*-template-${arch}.msi")"
      if [ -n "${file}" ]; then
        cp "${file}" "${dist}/msi-template/betterdesk-template-${arch}.msi"
      fi
    done
  fi

  for arch in ${ARCHES}; do
    src="$(first "${raw}" -maxdepth 2 -type d -name "betterdesk-unsigned-macos-${arch}")"
    [ -n "${src}" ] || continue
    dmg="$(first "${src}" -maxdepth 1 -type f -name '*.dmg')"
    if [ -n "${dmg}" ]; then
      cp "${dmg}" "${dist}/clean/betterdesk-${version}-macos-${arch}.dmg"
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
      cp "${app_zip}" "${dist}/clean/betterdesk-${version}-macos-${arch}-portable.zip"
    elif [ -n "$(first "${stage}" -maxdepth 1 -name '*.app')" ]; then
      # zip -y keeps the symlinks inside the app's frameworks.
      (cd "${stage}" && zip -qry "${clean}/betterdesk-${version}-macos-${arch}-portable.zip" ./*.app)
    fi
  done

  for arch in ${ARCHES}; do
    deb="$(first "${raw}/linux-debs" -type f -name "*${arch}*.deb")"
    if [ -n "${deb}" ]; then
      cp "${deb}" "${dist}/clean/betterdesk-${version}-linux-${arch}.deb"
      mkdir -p "${dist}/linux-${arch}"
      dpkg-deb -x "${deb}" "${dist}/linux-${arch}/root"
      bin="$(first "${dist}/linux-${arch}/root" -type f \( -name betterdesk -o -name rustdesk \))"
      if [ -n "${bin}" ]; then
        stage="${dist}/linux-${arch}/portable"
        mkdir -p "${stage}"
        cp -a "$(dirname "${bin}")/." "${stage}/"
        if [ -f "${stage}/rustdesk" ] && [ ! -f "${stage}/betterdesk" ]; then
          mv "${stage}/rustdesk" "${stage}/betterdesk"
        fi
        rm -f "${stage}/custom.txt"
        tar -C "${stage}" -czf "${dist}/clean/betterdesk-${version}-linux-${arch}-portable.tar.gz" .
      fi
    fi
    rpm="$(first "${raw}/linux-rpms" -type f -name "*${arch}*.rpm" ! -name '*-suse.rpm')"
    suse="$(first "${raw}/linux-rpms" -type f -name "*${arch}*-suse.rpm")"
    if [ -n "${rpm}" ]; then
      cp "${rpm}" "${dist}/clean/betterdesk-${version}-linux-${arch}.rpm"
    fi
    if [ -n "${suse}" ]; then
      cp "${suse}" "${dist}/clean/betterdesk-${version}-linux-${arch}-suse.rpm"
    fi
  done

  # Never publish Support Agent bake-ins from CI.
  local bad
  bad="$(find "${dist}/clean" "${dist}/msi-template" \
    \( -iname '*betterdesk-support*' -o -iname '*incoming-only*' -o -name 'custom.txt' \) 2>/dev/null || true)"
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
    rm -f SHA256SUMS
    names="$(find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
    printf '%s\n' "${names}" | while IFS= read -r name; do sha256sum -- "${name}"; done > SHA256SUMS
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
  *)
    echo "usage: $0 collect <raw dir> <dist dir> <version> | sums <dir>" >&2
    exit 2
    ;;
esac
