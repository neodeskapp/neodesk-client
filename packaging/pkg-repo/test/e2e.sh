#!/usr/bin/env bash
# End-to-end test of the package repository, with throwaway keys and dummy
# packages: build_repo.py builds from fixture releases, neodesk-pkg-receive
# takes the upload, a local web server serves it, and clean containers of
# Ubuntu 24.04, Debian 12, Fedora, Rocky Linux 9 and openSUSE Leap install,
# upgrade and refuse tampered metadata.
#
# Needs Ubuntu 24.04 with Docker and root (a throwaway VM, e.g. a boat
# sandbox):  sudo bash packaging/pkg-repo/test/e2e.sh
# Nothing secret goes in: every key is made here and thrown away.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(dirname "${HERE}")"
W="$(mktemp -d /tmp/pkg-e2e.XXXXXX)"
PORT=8780
URL="http://127.0.0.1:${PORT}"
pass=0
fail=0
ok() { echo "PASS: $*"; pass=$((pass + 1)); }
bad() { echo "FAIL: $*"; fail=$((fail + 1)); }
expect_ok() { local what="$1"; shift; if "$@" > "${W}/last.log" 2>&1; then ok "${what}"; else bad "${what}"; tail -n 20 "${W}/last.log"; fi; }
expect_fail() { local what="$1"; shift; if "$@" > "${W}/last.log" 2>&1; then bad "${what} (it worked)"; tail -n 20 "${W}/last.log"; else ok "${what}"; fi; }

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  apt-utils createrepo-c rpm gpgv gnupg openssl dpkg-dev python3 curl ca-certificates > /dev/null

# Throwaway repository key and release key
export GNUPGHOME="${W}/gnupg"
mkdir -m 700 "${GNUPGHOME}"
printf 'test-passphrase' > "${W}/passphrase"
gpg --batch --pinentry-mode loopback --passphrase-file "${W}/passphrase" \
  --quick-generate-key "NeoDesk test repo <test@invalid>" rsa3072 sign 1d 2> /dev/null
KEY_ID="$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ {print $10; exit}')"
gpg --batch --armor --export "${KEY_ID}" > "${W}/neodesk.asc"
gpg --batch --export "${KEY_ID}" > "${W}/neodesk.gpg"
openssl genpkey -algorithm ed25519 -out "${W}/release.pem" 2> /dev/null
RELEASE_KEY="$(openssl pkey -in "${W}/release.pem" -pubout -outform DER | tail -c 32 | base64 -w0)"

# Fixture releases with dummy packages
make_release() { # tag prerelease [wrong-version]
  local tag="$1" pre="$2" version="${1#desktop-v}" d="${W}/releases/$1"
  local pkgver="${3:-${version/-/\~}}"
  mkdir -p "${d}"
  for arch in amd64:x86_64 arm64:aarch64; do
    local deb="${arch%%:*}" rpmarch="${arch##*:}"
    local root="${W}/build/${tag}-${deb}"
    mkdir -p "${root}/DEBIAN" "${root}/usr/share/neodesk"
    echo "${version}" > "${root}/usr/share/neodesk/version"
    printf 'Package: neodesk\nVersion: %s\nArchitecture: %s\nMaintainer: test <test@invalid>\nDescription: dummy\n' \
      "${pkgver}" "${deb}" > "${root}/DEBIAN/control"
    dpkg-deb --root-owner-group -Zgzip -b "${root}" "${d}/neodesk-${version}-linux-${rpmarch}.deb" > /dev/null
    cat > "${W}/build/neodesk.spec" <<EOF
Name: neodesk
Version: ${pkgver}
Release: 0
Summary: dummy
License: AGPL-3.0-only
%description
dummy
%install
mkdir -p %{buildroot}/usr/share/neodesk
echo ${version} > %{buildroot}/usr/share/neodesk/version
%files
/usr/share/neodesk/version
EOF
    rpmbuild --quiet --target "${rpmarch}" --define "_topdir ${W}/rpmbuild" -bb "${W}/build/neodesk.spec" > /dev/null 2>&1
    local built
    built="$(find "${W}/rpmbuild/RPMS" -name "neodesk-*.${rpmarch}.rpm" | head -n 1)"
    cp "${built}" "${d}/neodesk-${version}-linux-${rpmarch}.rpm"
    cp "${built}" "${d}/neodesk-${version}-linux-${rpmarch}-suse.rpm"
    rm -rf "${W}/rpmbuild/RPMS"
  done
  (cd "${d}" && sha256sum neodesk-* > SHA256SUMS)
  openssl pkeyutl -sign -inkey "${W}/release.pem" -rawin -in "${d}/SHA256SUMS" -out "${W}/sig.bin"
  base64 -w0 "${W}/sig.bin" > "${d}/SHA256SUMS.sig"
  printf '{"prerelease": %s}\n' "${pre}" > "${d}/release.json"
}
mkdir -p "${W}/build"
make_release desktop-v1.4.0 false
make_release desktop-v1.5.0-rc.5 true 1.5.0
make_release desktop-v1.5.0-rc.4 true
make_release desktop-v1.5.0 false

# The "server": receive script with its own root and keyring, served over http
mkdir -p "${W}/srv/trees" "${W}/web"
for n in deb rpm suse MANIFEST.sha256 README.txt; do ln -s "${W}/srv/current/${n}" "${W}/web/${n}"; done
cp "${W}/neodesk.gpg" "${W}/neodesk.asc" "${W}/web/"
(cd "${W}/web" && exec python3 -m http.server "${PORT}" --bind 127.0.0.1 > "${W}/http.log" 2>&1) &
HTTP_PID=$!
trap 'kill ${HTTP_PID} 2> /dev/null || true; docker rm -f $(docker ps -aq --filter label=pkg-e2e) > /dev/null 2>&1 || true' EXIT
export NEODESK_PKG_ROOT="${W}/srv" NEODESK_PKG_KEYRING="${W}/neodesk.gpg"
receive() { SSH_ORIGINAL_COMMAND="$1" python3 -I "${PKG}/server/neodesk-pkg-receive" < "$2"; }
build() { # extra args
  rm -rf "${W}/work/signed"
  python3 "${PKG}/build_repo.py" --out "${W}/tree" --work "${W}/work" --keep 2 \
    --key-id "${KEY_ID}" --passphrase-file "${W}/passphrase" --public-key "${W}/neodesk.asc" \
    --live-url "${URL}" --local-releases "${W}/releases" --release-key "${RELEASE_KEY}" "$@"
}
sleep 1

echo "== build 1"
build | tee "${W}/build1.log"
grep -q "skip desktop-v1.5.0-rc.5: its packages don't carry its version" "${W}/build1.log" && ok "rc.5 with the wrong version is left out" || bad "rc.5 left out"
grep -q "^stable: desktop-v1.5.0, desktop-v1.4.0$" "${W}/build1.log" && ok "stable has 1.5.0 and 1.4.0" || bad "stable suite"
grep -q "^testing: desktop-v1.5.0, desktop-v1.5.0-rc.4$" "${W}/build1.log" && ok "testing has 1.5.0 and rc.4" || bad "testing suite"
expect_fail "--require-tag of the mismatched rc.5 fails" build --require-tag desktop-v1.5.0-rc.5
expect_ok "--allow-mismatch takes rc.5" build --require-tag desktop-v1.5.0-rc.5 --allow-mismatch desktop-v1.5.0-rc.5
build > /dev/null
expect_ok "receive check" receive check "${W}/work/upload.tar"
expect_ok "receive upload 1" receive upload "${W}/work/upload.tar"
cmp -s <(curl -fsS "${URL}/MANIFEST.sha256") "${W}/tree/MANIFEST.sha256" && ok "live manifest matches" || bad "live manifest"

echo "== the receive script refuses bad uploads"
mkdir -p "${W}/evil"
tarof() { tar -C "$1" -cf "$2" .; }
# 1. a symlink
rm -rf "${W}/evil/t" && mkdir -p "${W}/evil/t" && cp "${W}/tree/MANIFEST.sha256" "${W}/evil/t/" && ln -s /etc/passwd "${W}/evil/t/deb"
tarof "${W}/evil/t" "${W}/evil/1.tar"; expect_fail "symlink refused" receive check "${W}/evil/1.tar"
# 2. a name with ..
python3 - "${W}/evil/2.tar" "${W}/tree/MANIFEST.sha256" <<'PY'
import sys, tarfile, io
with tarfile.open(sys.argv[1], "w") as t:
    t.add(sys.argv[2], "MANIFEST.sha256")
    data = b"x"; ti = tarfile.TarInfo("deb/../../escape"); ti.size = 1; t.addfile(ti, io.BytesIO(data))
PY
expect_fail "path with .. refused" receive check "${W}/evil/2.tar"
# 3. a changed Packages file (hash differs from the manifest and InRelease)
rm -rf "${W}/evil/t" && cp -a "${W}/tree" "${W}/evil/t"
echo "Package: evil" >> "${W}/evil/t/deb/dists/stable/main/binary-amd64/Packages"
tarof "${W}/evil/t" "${W}/evil/3.tar"; expect_fail "changed Packages refused" receive check "${W}/evil/3.tar"
# 4. consistent manifest, but Packages no longer matches the signed InRelease
(cd "${W}/evil/t" && find . -type f ! -name MANIFEST.sha256 -printf '%P\n' | sort | xargs sha256sum > MANIFEST.sha256)
tarof "${W}/evil/t" "${W}/evil/4.tar"; expect_fail "Packages not matching InRelease refused" receive check "${W}/evil/4.tar"
# 5. metadata signed with another key
rm -rf "${W}/evil/t" && cp -a "${W}/tree" "${W}/evil/t"
GNUPGHOME="${W}/gnupg2" && mkdir -m 700 "${GNUPGHOME}" && export GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "other <o@invalid>" rsa3072 sign 1d 2> /dev/null
gpg --batch --yes --clearsign -o "${W}/evil/t/deb/dists/stable/InRelease" "${W}/evil/t/deb/dists/stable/Release"
export GNUPGHOME="${W}/gnupg"
(cd "${W}/evil/t" && find . -type f ! -name MANIFEST.sha256 -printf '%P\n' | sort | xargs sha256sum > MANIFEST.sha256)
tarof "${W}/evil/t" "${W}/evil/5.tar"; expect_fail "InRelease signed by another key refused" receive check "${W}/evil/5.tar"
# 6. a manifest that names a file neither uploaded nor live
printf '%064d  deb/missing\n' 0 >> "${W}/evil/t/MANIFEST.sha256"
tar -C "${W}/evil/t" -cf "${W}/evil/6.tar" MANIFEST.sha256; expect_fail "missing file refused" receive check "${W}/evil/6.tar"

echo "== clients, step 1"
SOURCES="deb [signed-by=/etc/apt/keyrings/neodesk.gpg] ${URL}/deb"
apt_client() { # image suite expected
  docker run --rm --label pkg-e2e --network host "$1" bash -ec "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq curl ca-certificates > /dev/null
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSLo /etc/apt/keyrings/neodesk.gpg ${URL}/neodesk.gpg
    echo '${SOURCES} $2 main' > /etc/apt/sources.list.d/neodesk.list
    apt-get update -qq
    apt-get install -y -qq neodesk > /dev/null
    test \"\$(dpkg-query -W -f '\${Version}' neodesk)\" = '$3'"
}
dnf_client() { # image expected testing
  docker run --rm --label pkg-e2e --network host "$1" bash -ec "
    curl -fsSLo /etc/yum.repos.d/neodesk.repo ${URL}/rpm/neodesk.repo
    sed -i 's#https://pkg.neode.sk#${URL}#' /etc/yum.repos.d/neodesk.repo
    dnf -y -q ${3:+--enablerepo=neodesk-testing} install neodesk > /dev/null
    test \"\$(rpm -q --qf '%{VERSION}' neodesk)\" = '$2'"
}
zypper_client() { # image expected
  docker run --rm --label pkg-e2e --network host "$1" bash -ec "
    zypper -q --non-interactive install -y curl > /dev/null 2>&1 || true
    curl -fsSLo /tmp/neodesk.repo ${URL}/suse/neodesk.repo
    sed -i 's#https://pkg.neode.sk#${URL}#' /tmp/neodesk.repo
    zypper -q --non-interactive addrepo /tmp/neodesk.repo
    zypper -q --non-interactive --gpg-auto-import-keys refresh
    zypper -q --non-interactive install -y neodesk > /dev/null
    test \"\$(rpm -q --qf '%{VERSION}' neodesk)\" = '$2'"
}
expect_ok "Ubuntu 24.04 stable installs 1.5.0" apt_client ubuntu:24.04 stable 1.5.0
expect_ok "Debian 12 testing installs 1.5.0 (newer than rc.4)" apt_client debian:12 testing 1.5.0
expect_ok "Fedora installs 1.5.0" dnf_client fedora:latest 1.5.0
expect_ok "Rocky 9 installs 1.5.0" dnf_client rockylinux/rockylinux:9 1.5.0
expect_ok "openSUSE Leap installs 1.5.0" zypper_client opensuse/leap:15.6 1.5.0

echo "== upgrade path: clients on step 1 stay running while step 2 goes live"
for c in ubuntu:24.04 rockylinux/rockylinux:9 opensuse/leap:15.6; do
  docker run -d --label pkg-e2e --network host --name "e2e-${c//[:\/.]/-}" "${c}" sleep 3600 > /dev/null
done
docker exec "e2e-ubuntu-24-04" bash -ec "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq curl ca-certificates > /dev/null
  install -d -m 0755 /etc/apt/keyrings && curl -fsSLo /etc/apt/keyrings/neodesk.gpg ${URL}/neodesk.gpg
  echo '${SOURCES} stable main' > /etc/apt/sources.list.d/neodesk.list
  apt-get update -qq && apt-get install -y -qq neodesk > /dev/null"
docker exec "e2e-rockylinux-rockylinux-9" bash -ec "
  curl -fsSLo /etc/yum.repos.d/neodesk.repo ${URL}/rpm/neodesk.repo
  sed -i 's#https://pkg.neode.sk#${URL}#' /etc/yum.repos.d/neodesk.repo
  dnf -y -q install neodesk > /dev/null"
docker exec "e2e-opensuse-leap-15-6" bash -ec "
  curl -fsSLo /tmp/neodesk.repo ${URL}/suse/neodesk.repo
  sed -i 's#https://pkg.neode.sk#${URL}#' /tmp/neodesk.repo
  zypper -q -n addrepo /tmp/neodesk.repo && zypper -q -n --gpg-auto-import-keys refresh && zypper -q -n install -y neodesk > /dev/null"

make_release desktop-v1.5.1-rc.1 true
make_release desktop-v1.5.1 false
build | tee "${W}/build2.log"
grep -q "^stable: desktop-v1.5.1, desktop-v1.5.0$" "${W}/build2.log" && ok "stable keeps the newest two" || bad "stable after step 2"
grep -q "reuse signed rpm/stable/Packages/neodesk-1.5.0-0" "${W}/build2.log" && ok "live signed rpm reused" || bad "rpm reuse"
expect_ok "receive upload 2" receive upload "${W}/work/upload.tar"
ls "${W}/srv/trees" | grep -v '^\.' | wc -l | grep -qx 2 && ok "previous tree kept" || bad "previous tree kept"
build | tee "${W}/build3.log" > /dev/null
if grep -E "^  signed rpm|^  signed suse" "${W}/build3.log"; then bad "rerun signed an rpm again"; else ok "rerun reuses every signed rpm"; fi
if grep -Eq "\.(deb|rpm)$" <(tar -tf "${W}/work/upload.tar"); then bad "rerun uploads packages again"; else ok "rerun uploads metadata only"; fi

expect_ok "Ubuntu upgrades to 1.5.1" docker exec e2e-ubuntu-24-04 bash -ec "
  export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get upgrade -y -qq > /dev/null
  test \"\$(dpkg-query -W -f '\${Version}' neodesk)\" = 1.5.1"
expect_ok "Rocky upgrades to 1.5.1" docker exec e2e-rockylinux-rockylinux-9 bash -ec "
  dnf -y -q --refresh upgrade neodesk > /dev/null; test \"\$(rpm -q --qf '%{VERSION}' neodesk)\" = 1.5.1"
expect_ok "openSUSE upgrades to 1.5.1" docker exec e2e-opensuse-leap-15-6 bash -ec "
  zypper -q -n refresh && zypper -q -n update -y neodesk > /dev/null; test \"\$(rpm -q --qf '%{VERSION}' neodesk)\" = 1.5.1"
expect_ok "Rocky can downgrade to 1.5.0 (two versions kept)" docker exec e2e-rockylinux-rockylinux-9 bash -ec "
  dnf -y -q --refresh downgrade neodesk > /dev/null; test \"\$(rpm -q --qf '%{VERSION}' neodesk)\" = 1.5.0"

echo "== tampered copies are refused"
cp -aL "${W}/srv/current" "${W}/web-bad"
cp "${W}/neodesk.gpg" "${W}/neodesk.asc" "${W}/web-bad/"
(cd "${W}/web-bad" && exec python3 -m http.server 8781 --bind 127.0.0.1 > /dev/null 2>&1) &
BAD_PID=$!
trap 'kill ${HTTP_PID} ${BAD_PID} 2> /dev/null || true; docker rm -f $(docker ps -aq --filter label=pkg-e2e) > /dev/null 2>&1 || true' EXIT
sleep 1
BAD="http://127.0.0.1:8781"
sed -i 's/^Version: 1.5.1$/Version: 1.5.9/' "${W}/web-bad/deb/dists/stable/main/binary-amd64/Packages"
rm -f "${W}/web-bad/deb/dists/stable/main/binary-amd64/Packages."{gz,xz}
expect_fail "apt refuses a changed Packages file" docker run --rm --label pkg-e2e --network host ubuntu:24.04 bash -ec "
  apt-get update -qq && apt-get install -y -qq curl > /dev/null
  install -d /etc/apt/keyrings && curl -fsSLo /etc/apt/keyrings/neodesk.gpg ${BAD}/neodesk.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/neodesk.gpg] ${BAD}/deb stable main' > /etc/apt/sources.list.d/n.list
  apt-get update -o APT::Update::Error-Mode=any"
sed -i 's/^Suite: testing$/Suite: testinG/' "${W}/web-bad/deb/dists/testing/InRelease"
expect_fail "apt refuses an InRelease changed after signing" docker run --rm --label pkg-e2e --network host debian:12 bash -ec "
  apt-get update -qq && apt-get install -y -qq curl > /dev/null
  install -d /etc/apt/keyrings && curl -fsSLo /etc/apt/keyrings/neodesk.gpg ${BAD}/neodesk.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/neodesk.gpg] ${BAD}/deb testing main' > /etc/apt/sources.list.d/n.list
  apt-get update -o APT::Update::Error-Mode=any"
expect_fail "apt refuses the repository with another key in signed-by" docker run --rm --label pkg-e2e --network host debian:12 bash -ec "
  apt-get update -qq && apt-get install -y -qq curl gnupg > /dev/null
  install -d /etc/apt/keyrings
  GNUPGHOME=/tmp/g gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key x@invalid rsa2048 sign 1d 2> /dev/null
  GNUPGHOME=/tmp/g gpg --batch --export > /etc/apt/keyrings/neodesk.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/neodesk.gpg] ${URL}/deb stable main' > /etc/apt/sources.list.d/n.list
  apt-get update -o APT::Update::Error-Mode=any"
rpm_file="$(cd "${W}/web-bad/rpm/stable/Packages" && ls neodesk-1.5.1-*.x86_64.rpm)"
printf 'X' | dd of="${W}/web-bad/rpm/stable/Packages/${rpm_file}" bs=1 seek=2000 conv=notrunc 2> /dev/null
expect_fail "dnf refuses a changed rpm" docker run --rm --label pkg-e2e --network host fedora:latest bash -ec "
  curl -fsSLo /etc/yum.repos.d/neodesk.repo ${BAD}/rpm/neodesk.repo
  sed -i 's#https://pkg.neode.sk#${BAD}#' /etc/yum.repos.d/neodesk.repo
  dnf -y -q install neodesk"
echo 'tampered' >> "${W}/web-bad/suse/stable/repodata/repomd.xml"
expect_fail "zypper refuses a changed repomd.xml" docker run --rm --label pkg-e2e --network host opensuse/leap:15.6 bash -ec "
  curl -fsSLo /tmp/neodesk.repo ${BAD}/suse/neodesk.repo
  sed -i 's#https://pkg.neode.sk#${BAD}#' /tmp/neodesk.repo
  zypper -q -n addrepo /tmp/neodesk.repo && zypper -q -n --gpg-auto-import-keys refresh && zypper -q -n install -y neodesk"

echo
echo "passed ${pass}, failed ${fail}"
[ "${fail}" -eq 0 ]
