<img src="https://raw.githubusercontent.com/neodeskapp/website/5b1fa1c319dd11c2c9de7f5c8b93fa2dbd0d9056/public/img/releases/desktop-v1.5.0-rc.7/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.7, pre-release of 24 November 2026, pausing connections and typing in Settings: 7 commits, 24 files changed, 934 lines added, 203 lines removed and 5 fixes since v1.5.0-rc.6">

This pre-release lets you pause connections without removing NeoDesk's service, makes typing work in Settings and on the Set up NeoDesk screen, and shows the server's reason when it refuses a join. It goes with the NeoDesk server [3.6.0-rc.4](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.4).

## What's new

### Pausing connections keeps NeoDesk running

On Windows and Linux, Stop accepting connections in the tray now pauses connections. NeoDesk stays installed and running, no permission prompt comes up, and the window stays open. Open sessions end, and nobody can connect until you click Accept connections in the tray or on Home, which asks for no permission either. The pause holds when the computer restarts.

<img src="https://raw.githubusercontent.com/neodeskapp/website/5b1fa1c319dd11c2c9de7f5c8b93fa2dbd0d9056/public/img/releases/desktop-v1.5.0-rc.7/tray-paused.png" width="600" alt="The NeoDesk tray menu on Linux while paused: Paused. Not accepting connections, this computer's ID 523 280 558, Open NeoDesk, Settings, Accept connections and About NeoDesk with the version">

Home says "Paused. This computer does not accept connections right now." with Accept connections under it.

<img src="https://raw.githubusercontent.com/neodeskapp/website/5b1fa1c319dd11c2c9de7f5c8b93fa2dbd0d9056/public/img/releases/desktop-v1.5.0-rc.7/home-paused.png" width="800" alt="NeoDesk's Home on Windows while paused: under This computer it says Paused. This computer does not accept connections right now., with an Accept connections link, the ID 525 129 550 and the one-time password">

In rc.6 on Windows, Stop accepting connections asked Windows for permission, removed NeoDesk's service and its tray icon and closed the window. Opened again, the window showed the Set up NeoDesk screen, although the computer was still joined.

Allow connections to this computer in Settings, Security pauses and accepts the same way. Only Unlock asks for permission.

### Typing works in Settings and on the Set up NeoDesk screen

In rc.6, text typed into Settings and its dialogs often never arrived, while pasting worked. Typed text now arrives in the settings search, Join a server, Set up by hand, Pair with code, Set permanent password, Set PIN, and the invite and server address fields of the Set up NeoDesk screen. Join a server takes typing as soon as it opens, Tab moves through the fields and buttons, and Escape closes a dialog without saving.

### Join a server says why the server refused

When the server refuses a join, Join a server in Settings, Server now shows the server's answer and what to do next, such as "This computer's ID is already enrolled with another key. Ask your administrator to approve the new key or to delete the device in the console." The dialog stays open with the invite filled in, so Continue tries the same invite again once the administrator has done that. In rc.6 both dialogs closed without a message, and the reason showed only on Home.

<img src="https://raw.githubusercontent.com/neodeskapp/website/5b1fa1c319dd11c2c9de7f5c8b93fa2dbd0d9056/public/img/releases/desktop-v1.5.0-rc.7/join-refused.png" width="800" alt="The Join a server dialog in Settings with an invite code and the server address filled in, and the server's answer in red: 10.10.10.74 answered: This computer's ID is already enrolled with another key. Ask your administrator to approve the new key or to delete the device in the console. Under it: When your administrator has done that, try the same invite again. It still works.">

While the join runs, the dialog stays open and says that it is connecting this computer to the server.

### Back online when the new key is approved

When the server refuses this computer's key, the client now offers its key again each time it registers. When the administrator clicks Approve new key in the console, the computer is online again within seconds, and Home and the tray say Ready without a restart of NeoDesk. The service log says that the server refused this device's key, once every ten minutes, instead of "unknown RegisterPkResponse" at every answer.

### The settings search uses the Security page's names

The settings search finds the Security settings under the names the page shows, such as Accept sessions via password, Use permanent password, Enable two-factor authentication and Direct IP access, and a hit opens the Security page. In rc.6 it listed names such as "How someone gets in" that the page doesn't have.

## Updating

- Install rc.7 over rc.6 with the exe, the MSI or the Linux package. Nothing in this release changes the computer's ID, key or server.
- The Linux packages carry the version `1.5.0~rc.7`, which apt and dnf sort after rc.6's `1.5.0~rc.6`, so rc.7 installs as a normal update, from the file or from the `testing` suite at pkg.neode.sk.
- **If you used Stop accepting connections in rc.6 on Windows**, it removed NeoDesk's service. Click Accept connections on Home once after the update. Windows may ask for permission to set up the service again, and its prompt names Windows Command Processor. If the window shows the Set up NeoDesk screen instead of Home, the computer is still joined: open Settings, Security, click Unlock and switch on Allow connections to this computer. From then on, pausing and accepting ask for no permission.
- Coming from rc.4, the [upgrade notes of rc.6](https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.6) apply too: the computer gets a new ID once, and the rc.4 packages for Linux need the downgrade options given there, with rc.7's file names.

## Known issues

- A computer whose key the server refuses still shows Online in the console of the server 3.6.0-rc.4. Sessions to it are refused, and its client's Home and tray say that the server refuses its key.
- The console can't tell a paused computer from one that is turned off. It lists the computer as offline, and a browser session to it says to turn it on or wake it up.
- On macOS, switching off Allow connections to this computer in Settings still removes NeoDesk's service instead of pausing.
- Windows' permission prompt for installing, updating or removing the exe install names Windows Command Processor by Microsoft, not NeoDesk. 1.5.0 will still ask this way.
- After a successful join from Join a server, the Server page in Settings keeps saying "Not connected to" the server in red, while Home and the tray say Ready. Leave Settings and open it again to see the new state.
- On Linux the settings search also lists Windows-only settings, such as Share Windows remote desktop sessions and NeoDesk printer, which the Linux pages don't have. The search hit Set permanent password always says "Not set.", also when a permanent password is set. A few entries for General and Advanced still use names those pages don't show.
- Uninstalling the exe install shows a console window with service commands for a few seconds.
- Right after the console approves a computer, Home and the tray can keep saying "Can't reach" or "Waiting for an administrator to approve this computer" for about two minutes, while sessions to it already work.
- Updating with the MSI while the service runs can end with Windows Installer's message that a restart may be needed.
- The MSI is in English only.
- The tray menu hasn't been tried on macOS.
- After an upgrade from the rc.4 rpm, rc.4's `rustdesk.service` stays on the system.
- The NeoDesk Support Agent and the NeoDesk Client on one computer share an ID.
- The console's links that open a device in the app use `rustdesk://`, so on Linux and macOS they open stock RustDesk or nothing.
- "Join another server?" also asks when the invite is for the server the client already uses.
- A second quick support app started while the first is open stays offline once the first one closes.
- On a Linux desktop without a compositor, the quick support bar has a black frame.
- The bar lists a file transfer when it starts, without progress and without saying when it is done.
- Texts that are new in this release are in English in every language but English and German.
