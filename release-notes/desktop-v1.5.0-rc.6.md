<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.6, pre-release of 24 November 2026, installs on Windows and keeps its key: 41 commits, 220 files changed, 10,675 lines added, 5,670 lines removed and 25 fixes since v1.5.0-rc.4">

This pre-release installs on Windows, runs next to stock RustDesk on the same computer, and keeps a joined computer reachable after a restart. It covers everything since [1.5.0-rc.4](https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.4), because 1.5.0-rc.5 was never published. It goes with the NeoDesk server [3.6.0-rc.4](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.4).

## What's new

### A joined computer keeps its key

A Windows computer that joined with an invite lost its key at the next restart. The server kept showing it online, but every session to it ended with "could not be secured". The join now asks the NeoDesk service for its key, so the server holds the key the service signs with, and the computer stays reachable after a restart. A computer set up by hand with a pairing code gets the service's key too.

With the server 3.6.0-rc.4, a computer that comes back with another key anyway is refused and shows offline, instead of showing online while every session fails, and Home and the tray say that the server refuses this computer's key. Running its invite again then offers **Approve new key** on its device page in the console.

### The Windows installer installs

In rc.4, Install closed the setup window and installed nothing. Now Install asks Windows for permission, puts NeoDesk Client into `C:\Program Files\NeoDesk Client` and starts its service. The setup file from an invite does the same, then joins the computer to the server.

### The installers' new look

The exe opens with a loading window that shows what it does and how far it is, and keeps it on screen until the app's window is up.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/loading.png" width="400" alt="The NeoDesk loading window: the NeoDesk logo, Unpacking NeoDesk and a progress bar about a quarter full">

Install names each step while it runs: asking Windows for permission, copying NeoDesk to this computer, setting up the service that starts with Windows, and starting NeoDesk. When Windows doesn't get permission, the page says that nothing was installed and how to try again.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/installing.png" width="560" alt="The Install NeoDesk window: Installing NeoDesk, this takes about a minute, with Asking Windows for permission and Copying NeoDesk to this computer ticked, Setting up the service that starts with Windows running and Starting NeoDesk still to come">

The MSI has pages of its own instead of WiX's red artwork. They say in plain words what setup does, the progress page names each step, and the last page says that NeoDesk runs, where its icon is, and offers to open it. After a removal the last page says the app is removed, and an MSI started over an install from the exe says so and what to do. The licence page shows the AGPL, and Windows names NeoDesk Client when it asks for permission.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/msi-welcome.png" width="516" alt="The first page of the NeoDesk Client setup MSI: the NeoDesk logo, Set up NeoDesk Client, and that setup installs the app and a service that starts with Windows, so people you allow can reach this computer">

### The tray menu

The tray menu shows whether the computer is ready and which server it is connected to, the computer's ID, which a click copies, and Open NeoDesk, Settings, Stop accepting connections and About NeoDesk with the version. Before, it had Open and Stop service.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/tray-menu.png" width="262" alt="The NeoDesk tray menu on Windows: Ready, connected to the server, this computer's ID 525 129 550, Open NeoDesk, Settings, Stop accepting connections and About NeoDesk with the version">

### Next to stock RustDesk

NeoDesk and stock RustDesk run on the same computer, each with its own ID, and both stay online. Before, both took the same ID, and only the one that registered first could be reached.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/side-by-side.png" width="800" alt="NeoDesk and stock RustDesk open next to each other on Windows 11, NeoDesk with the ID 525 129 550 and Ready, stock RustDesk with the ID 289 485 454 and Ready">

On Linux the package installs as `neodesk.service` next to RustDesk's own `rustdesk.service`, and no longer removes an installed RustDesk.

`neodesk://` links open NeoDesk on Windows, macOS and Linux. `rustdesk://` links stay with stock RustDesk: on Windows NeoDesk takes them only on a computer without stock RustDesk and gives them back when it is removed, and on Linux and macOS it never takes them. See [Links that open the app](https://neode.sk/docs/getting-started/connect-a-client/#links-that-open-the-app).

### Quick support says what it allows

The consent screen lists what the supporter can do after Allow: see the screen and use the mouse and keyboard. Copying text and sending files are two more choices, off until the person ticks them, and the session gets only what the person allowed.

<img src="https://raw.githubusercontent.com/neodeskapp/website/ad79b7fc54897f1775d69f64d375c5c4c24aaed8/public/img/releases/desktop-v1.5.0-rc.6/consent.png" width="400" alt="The NeoDesk Quick Support consent screen: admin from NeoDesk wants to see your screen to help you, with See your screen and Use your mouse and keyboard, and two unticked choices, Copy text between the two computers and Send and receive files">

During the session the bar at the top of the screen says that the supporter is viewing and controlling the computer, with Chat and Stop.

### Home says why it isn't connected

Home says when the computer is waiting for approval, and when the server refuses this computer's new key, instead of "Can't reach". A refused invite shows the server's reason, such as "Ask your administrator to approve the new key or to delete the device in the console.", and the same invite works again once the admin has done that.

**Set up by hand** opens the server settings, and Home shows as soon as the server is saved. When you enter an invite code, the client asks for the server address that is under the code on the invite page.

### Packages for Linux

- The packages carry the release candidate in their version, `1.5.0~rc.6`, and the client reports 1.5.0-rc.6 to the server.
- The package metadata names NeoDesk and neode.sk.
- The rpm finishes without an error on systems without systemd or desktop-file-utils.
- The Linux packages also come from the signed package repository at pkg.neode.sk. Its `testing` suite gets this release candidate, `stable` gets the first release. See [Install from the package repository](https://neode.sk/docs/getting-started/connect-a-client/#install-from-the-package-repository).

### Fixes

- An invite link that starts the client asks once whether to join the server, not twice.
- An invite file's install page names the server once.
- The password step names no product: it asks for the password shown or set on the other computer.
- About credits RustDesk and Purslane Ltd. by their own names.
- A custom client stages its update in NeoDesk's own folder under ProgramData, apart from stock RustDesk's.

## Upgrade notes

- **Computers that joined with an invite on a build from CI before this release don't get their key back by updating.** After the update the server refuses the computer's key. Join the computer again with a new invite, click **Approve new key** on its device page in the console, and run the same invite once more.
- **Every computer that runs rc.4 gets a new ID once**, when rc.6 first starts. rc.4 took the ID that stock RustDesk uses on that computer; rc.6 moves to an ID of its own and keeps it from then on, also after a reinstall. To the server it is a new computer with the new ID, and the entry with the old ID stays offline until you delete it. Give the new ID to everyone who connects by ID.
- The rc.4 packages for Linux say 1.5.0 without a suffix, so apt and dnf take rc.6 for an older version. Install it over rc.4 with `sudo apt-get install --allow-downgrades ./neodesk-1.5.0-rc.6-linux-x86_64.deb` or `sudo dnf downgrade ./neodesk-1.5.0-rc.6-linux-x86_64.rpm`.
- Quick support with choices and Approve new key need the server 3.6.0-rc.3 or later. The key check after a restart needs 3.6.0-rc.4.

## Known issues

- Windows' permission prompt for the exe install names Windows Command Processor by Microsoft, not NeoDesk.
- Uninstalling the exe install shows a console window with service commands for a few seconds.
- Right after the console approves a computer, Home and the tray say "Can't reach" until the service connects again.
- After **Stop accepting connections** the tray icon goes away with the service, so connections can be turned on again only from the app's window.
- Updating with the MSI while the service runs can end with Windows Installer's message that a restart may be needed.
- The MSI is in English only.
- The tray menu has only been tried on Windows.
- After an upgrade from the rc.4 rpm, rc.4's `rustdesk.service` stays on the system.
- The NeoDesk Support Agent and the NeoDesk Client on one computer share an ID.
- The console's links that open a device in the app use `rustdesk://`, so on Linux and macOS they open stock RustDesk or nothing.
- "Join another server?" also asks when the invite is for the server the client already uses.
- A second quick support app started while the first is open stays offline once the first one closes.
- On a Linux desktop without a compositor, the quick support bar has a black frame.
- The bar lists a file transfer when it starts, without progress and without saying when it is done.
- Texts that are new in this release are in English in every language but English and German.
