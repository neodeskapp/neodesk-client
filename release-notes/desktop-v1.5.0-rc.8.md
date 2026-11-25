<img src="https://raw.githubusercontent.com/neodeskapp/website/554e14fa74f4137d269a37ca59b26d2af4109761/public/img/releases/desktop-v1.5.0-rc.8/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.8, pre-release of 26 November 2026, support chat and secrets kept in the service: 71 commits, 280 files changed, 15,938 lines added, 8,305 lines removed and 46 fixes since v1.5.0-rc.7">

This pre-release brings the support chat to the computer: a chat window, and a tray that keeps the person reachable for support from the moment they sign in. On Windows the computer's key and passwords stay in NeoDesk's service. Saved sign-in works without the password reaching the browser, the console gets real CPU and network numbers, and a computer the server knows can join again with an invite. It goes with the NeoDesk server [3.6.0-rc.6](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.6).

## Updating from 1.5.0-rc.7

- Install rc.8 over rc.7 with the exe, the MSI or the Linux package. The computer keeps its ID, key and server. The exe now offers to update an older NeoDesk that is installed, instead of running next to it.
- The Linux packages carry the version `1.5.0~rc.8`, so rc.8 installs as a normal update, from the file or from the `testing` suite at pkg.neode.sk.
- On Windows, the first start moves the computer's key pair, the stored permanent password and the two-factor secret out of the person's profile into NeoDesk's service, once. See [Security fixes](#security-fixes).
- On Windows, NeoDesk's service now starts the tray in the session of the person who is signed in, with normal rights, also after a quiet install or update over SSH or a management tool. No installer starts the tray any more, and the MSI property `LAUNCH_TRAY_APP` no longer does anything.
- A computer the server already knows can join again with an invite: this client proves the computer's key, which the server 3.6.0-rc.6 asks for. The client 1.5.0-rc.7 got "This computer's ID is already enrolled on this server. Update NeoDesk on this computer and open the invite again" there.
- The German texts say "du".
- Coming from rc.6 or older, the [updating notes of rc.7](https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.7) apply too.

## What's new

### Chat with support

The person at the computer can now write to the support team, and the support team can reach them outside a remote session.

- **Home** shows Chat with support, with the number of new messages. The chat opens in the main window: who is helping, replies, editing your own messages for 24 hours, deleting them, reactions, and files through the attach button, up to 10 at once and 50 MB each. Pictures show as thumbnails. Enter sends, Shift+Enter adds a line. While the chat is not connected, what you type stays and goes out when the chat is back, once.
- **The tray holds the chat from sign-in**, so the console can reach the computer without NeoDesk's window being open. The tray menu has Chat with support, with "(2 new)" when there are new messages, the tooltip counts them, and a notification shows a new message unless the chat is in front.
- **NeoDesk's service keeps the connection.** The computer's device token never leaves it: the window and the tray talk to the chat through it, on one connection to the server's API port, the port the computer already uses. After a restart of the server or the service, the chat is back within seconds.

The chat needs the server 3.6.0-rc.6 or later with Chat with computers on, which is the default. When an admin turns it off, the button and the tray entry go away, and the client asks again after the time the server names. Against an older server there is no chat button, and the client asks again every 10 minutes.

On Linux a click on a notification doesn't open the chat; use the tray entry. On macOS the tray entry and the count are there, but no notifications.

### Saved sign-in without the password in the browser

With saved sign-in in the console (server 3.6.0-rc.5 or later), this client signs in at the Windows lock or sign-in screen itself. It tells the server that it can, and tells the browser viewer whether the computer shows its lock or sign-in screen. The server seals the details for this computer, and NeoDesk's service opens them, presses Ctrl+Alt+Del and types them, once. The password never reaches the browser. It signs in only while nobody is signed in or the session is locked, never on an open desktop. Once a computer has reported this, the server hands out no readable details for it any more.

### Real CPU and network numbers

The client measures the CPU load and the network traffic over the time since its last heartbeat, without the loopback interface, and sends network rates per second. The console of the server 3.6.0-rc.6 shows them and draws them as graphs. The client 1.5.0-rc.7 sent 100 % CPU on Windows and 0 % on Linux, and no network traffic.

### Icons and the title bar

- Every icon comes from Material Symbols, the icon set of the console. Empty lists say in plain words that they are empty and what to do, without an icon.
- The whole height of the free part of the title bar moves the window, and a double-click maximises it.
- About links the NeoDesk Discord, except in branded builds, and copies the address when no browser opens.

## Fixes

- **Joining after the console moved to port 3375:** Join a server keeps a moved console of the same server instead of asking to leave it, and a bare code whose stored console doesn't answer is tried once more on port 3375, unless you typed the address.
- **A typed address that doesn't answer:** Join a server says Can't reach within seconds instead of waiting for ever. Joining again with the same code works.
- **`neodesk.exe --join` on Windows** prints its result, naming the console that answered, and exits. Before, it waited on a message box nobody could see, in an SSH or management session.
- **Signing in to an account on Linux and macOS** keeps you signed in. Before, the dialog closed and the client stayed signed out.
- **The Devices tab** loads through the service. When the service isn't running, it says so with Retry, instead of a signing error.
- **Start the service** on Home starts the stopped service instead of installing it again, and Home shows nothing that needs the service while it isn't running.
- **Installing and updating:** the exe offers to update an older installed NeoDesk and never sets up the service of an older binary. An install or update on a paused computer keeps the service and the tray. An install that takes a portable run's settings keeps the service's ID, key and settings.
- **Plain HTTP:** Join a server and Set up by hand warn about an `http://` address, since the invite code travels unencrypted, and ask before they continue.
- **Settings, Server** shows the current connection after a join, and redraws only when the status changes. Before, it redrew every second, which kept a lab computer without a graphics card about 10 % busy.
- **The settings search** lists only the settings this system shows, and says when a permanent password is set.
- **Names:** the command line's result box and the authenticator entry carry the client's name, and the English ID hint says that public servers are off in NeoDesk.
- **German:** every text says "du", the Pair with code dialog and the activity switch are translated, and the German settings search placeholder fits its field.
- The connection window says "Connected for 1 min" instead of "1 minutes".

## Security fixes

- **Windows: the computer's secrets stay in the service.** The key pair, the stored permanent password and the two-factor secret live in NeoDesk's service, in a folder only SYSTEM and Administrators can open. Before, the window of the signed-in person held copies, and other programs of that person could read them. A join's or pairing's device token no longer reaches the window either.
- **Windows: the service's pipes** have names only administrators can take, and no other account can create instances of them, also while the service is stopped.
- **The join proof:** a join is signed with the computer's key, by the service, so the server can refuse someone who uses this computer's ID. The window of an installed client takes the proof only from the service.
- **Requests to the server** are sealed only by the process that holds the computer's keys. The window asks it for its few calls, such as the device list and the account sign-in.
- **The tray never runs elevated.** An interactive MSI install started the tray with administrator rights, and so did the exe install. Now the service starts it with normal rights.

## Known issues

- On Linux, 30 to 60 seconds after an incoming session ends, NeoDesk starts its process for the signed-in person again. A connection that comes in at that moment fails, and the chat drops for a few seconds.
- On Linux and macOS, the computer's key, the stored permanent password and the two-factor secret are still in the signed-in person's own config file, where that person's programs can read them. Windows is fixed in this release; Linux and macOS follow after 1.5.0.
- On Linux, changing a setting in the window can write older values of other settings back over what NeoDesk's service changed meanwhile.
- A copy made in Notepad on a Windows computer reaches the console's browser viewer one copy late.
- Nothing in this release was tried on a Mac. The chat, the tray and saved sign-in have only been tested on Windows and Linux.
- On macOS, switching off Allow connections to this computer in Settings still removes NeoDesk's service instead of pausing.
- The tray menu keeps the language it started with until it starts again.
- After a join from Join a server, Home shows its "This computer is now connected" page only when you go back to Home, which can be much later.
- Pair with code on a computer that is already joined leaves the Server page showing the address with port 21116 and the API server as not set, while the computer keeps working.
- In Set up by hand, the plain HTTP warning shows below the visible part of the dialog in a small window.
- A settings search hit opens its page at the top instead of at the setting.
- A portable NeoDesk next to an older installed one, or next to a newer paused one, gives no hint when Start the service or Accept connections can't act on the installed copy.
- Files go into the chat through the attach button only: pasting a picture or dropping a file doesn't add it.
- With the server 3.6.0-rc.6: when the computer writes in a conversation the console closed, the console shows it open again only after a reload, and "Seen" also shows when a colleague in the console read the message.
- The console can't tell a paused computer from one that is turned off. It lists the computer as offline, and a browser session to it says to turn it on or wake it up.
- Windows' permission prompt for installing, updating or removing the exe install names Windows Command Processor by Microsoft, not NeoDesk. 1.5.0 will still ask this way.
- Right after the console approves a computer, Home and the tray can keep saying "Can't reach" or "Waiting for an administrator to approve this computer" for about two minutes, while sessions to it already work.
- Updating with the MSI while the service runs can end with Windows Installer's message that a restart may be needed.
- The MSI is in English only.
- Uninstalling the exe install shows a console window with service commands for a few seconds.
- After an upgrade from the rc.4 rpm, rc.4's `rustdesk.service` stays on the system.
- The NeoDesk Support Agent and the NeoDesk Client on one computer share an ID.
- A second quick support app started while the first is open stays offline once the first one closes.
- On a Linux desktop without a compositor, the quick support bar has a black frame.
- The bar lists a file transfer when it starts, without progress and without saying when it is done.
- Texts that are new in this release are in English in every language but English and German.

## Which server

This client goes with the NeoDesk server [3.6.0-rc.6](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.6), and that server's notes list what needs this client: joining again under a known ID, CPU load and network rates, the chat on the computer, and saved sign-in without the password in the browser. All four are in this release.

- The chat needs the server 3.6.0-rc.6 or later, with Chat with computers on.
- Saved sign-in through the sealed way needs the server 3.6.0-rc.5 or later.
- With an older server the client works as rc.7 did, without the chat.
