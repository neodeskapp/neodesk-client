# Security policy

How to report a vulnerability in NeoDesk Client and what to expect after
you do.

## Supported versions

Security fixes go into the `main` branch and the next release. Older
releases may get a backport for a critical issue at the maintainers'
discretion.

| Version | Supported |
| ------- | --------- |
| `main` | Yes |
| Newest release | Yes |
| Older releases | Best effort |

## Reporting a vulnerability

Please don't post a security problem in public, on Discord or in the
Discussions. Report it privately by email to security@neode.sk.

Please include, where you can:

- What the problem is and what an attacker gains.
- How to reproduce it: a proof of concept, the steps in the client, or a
  test case.
- The affected version or commit, the operating system, and how the
  client was installed (the installer, the MSI, a package, a build from
  source).
- Logs, screenshots or traffic captures, with sensitive data removed.

## Response targets

- **Acknowledgement:** within 7 days of the report.
- **Triage decision:** within 14 days (severity, scope, fix plan).
- **Coordinated disclosure:** at most 90 days from the acknowledgement,
  shorter if the issue is being exploited.
- **Credit:** if you want it, in the release notes or the advisory.

If you get no acknowledgement within 7 days, post in the
[Discussions of neodeskapp/neodesk](https://github.com/neodeskapp/neodesk/discussions)
that you are waiting for an answer to a security report, with no details.

## Scope

In scope, everything in this repository: the desktop client (the Rust
code in `src/` and `libs/`, the Flutter app in `flutter/`), its
installers and packages, and the release workflows in
`.github/workflows/`.

Out of scope:

- The NeoDesk server and web console. They are built in
  [neodeskapp/neodesk](https://github.com/neodeskapp/neodesk); its
  [SECURITY.md](https://github.com/neodeskapp/neodesk/blob/main/SECURITY.md)
  says how to report them.
- Issues that need an attacker who already controls the computer's
  operating system or an administrator account on it.
- Theoretical issues without a concrete way to exploit them.
- Reports from automated scanners that nobody checked by hand.
