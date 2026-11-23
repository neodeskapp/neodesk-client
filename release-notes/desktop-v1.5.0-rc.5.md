<img src="https://raw.githubusercontent.com/neodeskapp/website/17b6f552ef4ebf317e47f1f93676b16d19b44f44/public/img/releases/desktop-v1.5.0-rc.5/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.5, pre-release of 23 November 2026, next to stock RustDesk: 24 commits, 83 files changed, 5,106 lines added, 991 lines removed and 16 fixes since v1.5.0-rc.4">

This pre-release installs on Windows, runs next to stock RustDesk on the same computer, and says what quick support allows before the person agrees. It goes with the NeoDesk server [3.6.0-rc.3](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.3): the quick support choices and approving a reinstalled computer's new key need that server.

## What's new

### The Windows installer installs

In rc.4, Install closed the setup window and installed nothing. Now Install asks Windows for permission, puts NeoDesk Client into `C:\Program Files\NeoDesk Client` and starts its service. The setup file from an invite does the same, then joins the computer to the server.

### Next to stock RustDesk

NeoDesk and stock RustDesk run on the same computer, each with its own ID, and both stay online. Before, both took the same ID, and only the one that registered first could be reached.

<img src="https://raw.githubusercontent.com/neodeskapp/website/17b6f552ef4ebf317e47f1f93676b16d19b44f44/public/img/releases/desktop-v1.5.0-rc.5/side-by-side.png" width="800" alt="NeoDesk and stock RustDesk open next to each other on Windows 11, NeoDesk with the ID 525 129 550 and Ready, stock RustDesk with the ID 289 485 454 and Ready">

On Linux the package installs as `neodesk.service` next to RustDesk's own `rustdesk.service`, and no longer removes an installed RustDesk.

`neodesk://` links open NeoDesk on Windows, macOS and Linux. `rustdesk://` links stay with stock RustDesk: on Windows NeoDesk takes them only on a computer without stock RustDesk and gives them back when it is removed, and on Linux and macOS it never takes them. See [Links that open the app](https://neode.sk/docs/getting-started/connect-a-client/#links-that-open-the-app).

### Quick support says what it allows

The consent screen lists what the supporter can do after Allow: see the screen and use the mouse and keyboard. Copying text and sending files are two more choices, off until the person ticks them, and the session gets only what the person allowed.

<img src="https://raw.githubusercontent.com/neodeskapp/website/17b6f552ef4ebf317e47f1f93676b16d19b44f44/public/img/releases/desktop-v1.5.0-rc.5/consent.png" width="400" alt="The NeoDesk Quick Support consent screen: admin from NeoDesk wants to see your screen to help you, with See your screen and Use your mouse and keyboard, and two unticked choices, Copy text between the two computers and Send and receive files">

During the session the bar at the top of the screen says that the supporter is viewing and controlling the computer, with Chat and Stop.

<img src="https://raw.githubusercontent.com/neodeskapp/website/17b6f552ef4ebf317e47f1f93676b16d19b44f44/public/img/releases/desktop-v1.5.0-rc.5/bar.png" width="510" alt="The quick support bar: admin is viewing and controlling your computer, with the buttons Chat and Stop">

### Home says why it isn't connected

Home says when the computer is waiting for approval, and when the server refuses this computer's new key, instead of "Can't reach". A refused invite shows the server's reason, such as "Ask your administrator to approve the new key or to delete the device in the console.", and the same invite works again once the admin has done that.

**Set up by hand** opens the server settings, and Home shows as soon as the server is saved. When you enter an invite code, the client asks for the server address that is under the code on the invite page.

### The Windows MSI

The MSI shows the AGPL licence on its licence page, and Windows names NeoDesk Client when it asks for permission.

<img src="https://raw.githubusercontent.com/neodeskapp/website/17b6f552ef4ebf317e47f1f93676b16d19b44f44/public/img/releases/desktop-v1.5.0-rc.5/msi-licence.png" width="520" alt="The licence page of the NeoDesk Client Setup MSI: NeoDesk is free software, licensed under the GNU Affero General Public License, version 3, and based on RustDesk, followed by the licence text">

### Packages for Linux

- The packages carry the release candidate in their version, `1.5.0~rc.5`, and the client reports 1.5.0-rc.5 to the server.
- The package metadata names NeoDesk and neode.sk.
- The rpm finishes without an error on systems without systemd or desktop-file-utils.
- The Linux packages also come from the signed package repository at pkg.neode.sk. Its `testing` suite gets this release candidate, `stable` gets the first release. See [Install from the package repository](https://neode.sk/docs/getting-started/connect-a-client/#install-from-the-package-repository).

### Fixes

- An invite link that starts the client asks once whether to join the server, not twice.
- The password step names no product: it asks for the password shown or set on the other computer.
- About credits RustDesk and Purslane Ltd. by their own names.
- A custom client stages its update in NeoDesk's own folder under ProgramData, apart from stock RustDesk's.

## Upgrade notes

- **Every computer that runs rc.4 gets a new ID once**, when rc.5 first starts. rc.4 took the ID that stock RustDesk uses on that computer; rc.5 moves to an ID of its own and keeps it from then on, also after a reinstall. To the server it is a new computer with the new ID, and the entry with the old ID stays offline until you delete it. Give the new ID to everyone who connects by ID.
- The rc.4 packages for Linux say 1.5.0 without a suffix, so apt and dnf take rc.5 for an older version. Install it over rc.4 with `sudo apt-get install --allow-downgrades ./neodesk-1.5.0-rc.5-linux-x86_64.deb` or `sudo dnf downgrade ./neodesk-1.5.0-rc.5-linux-x86_64.rpm`.
- Quick support with choices and Approve new key need the server 3.6.0-rc.3.

## Known issues

- After an upgrade from the rc.4 rpm, rc.4's `rustdesk.service` stays on the system.
- The NeoDesk Support Agent and the NeoDesk Client on one computer share an ID.
- The MSI's banner and side images are still WiX's red default ones.
- The console's links that open a device in the app use `rustdesk://`, so on Linux and macOS they open stock RustDesk or nothing.
- "Join another server?" also asks when the invite is for the server the client already uses.
- A second quick support app started while the first is open stays offline once the first one closes.
- On a Linux desktop without a compositor, the quick support bar has a black frame.
- The bar lists a file transfer when it starts, without progress and without saying when it is done.
- Texts that are new in this release are in English in every language but English and German.
