# Package repository (pkg.neode.sk)

The apt, dnf and zypper repository of the NeoDesk client. The workflow
`.github/workflows/neodesk-packages.yml` runs `build_repo.py` after every
desktop-v* release and sends the result to the web server, where
`server/neodesk-pkg-receive` checks it and puts it live.

- `build_repo.py` rebuilds the whole repository from the newest releases:
  stable gets the newest three releases, testing the newest three releases
  and release candidates. A release is taken only when its SHA256SUMS.sig
  verifies with the release key and its packages carry its version
  (1.5.0-rc.4 is 1.5.0~rc.4 in the deb and the rpm).
- `server/neodesk-pkg-receive` is the forced command of the user
  neodesk-pkg on the web server. It accepts plain files only, checks every
  signature and hash against the repository key in /etc/neodesk-pkg, and
  swaps the new tree in with one rename.
- `test/e2e.sh` builds from dummy releases with throwaway keys and installs,
  upgrades and tampers on Ubuntu, Debian, Fedora, Rocky Linux and openSUSE
  in containers. Run it as root on a throwaway Ubuntu 24.04 machine with
  Docker.

The repository key is RSA 4096, fingerprint
D9D7D06AFB85042431C608AB79E8A31B2625AA7B, valid until 2029-11-22. The
private key is the repository secret PKG_SIGNING_KEY (passphrase in
PKG_SIGNING_PASSPHRASE). Rotation and the server side are described in the
operator handbook of the colo.

Publish by hand, for example after a failed run:

    gh workflow run neodesk-packages.yml -f tag=desktop-v1.5.0
