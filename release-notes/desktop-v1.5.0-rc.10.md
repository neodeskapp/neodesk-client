<img src="https://raw.githubusercontent.com/neodeskapp/website/22d6a40e2964eccfcffeec86381a1f954b897775/public/img/releases/desktop-v1.5.0-rc.10/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.10, pre-release of 28 November 2026, the receiver app: 8 commits, 64 files changed, 7,114 lines added, 102 lines removed and 3 fixes since v1.5.0-rc.9">

This pre-release brings the receiver app, NeoDesk for the computer that gets help. It opens on Get help, Messages and My tickets, runs as a service that joins your server by itself, and installs silently from the Support Agent MSI with the server's details as properties. A quick support session can now end with an offer to keep it on the computer. The receiver needs the NeoDesk server's development build 3.6.64 or later; the server 3.6.0-rc.6 doesn't have it yet.

## Updating from 1.5.0-rc.9

- Install rc.10 over rc.9 with the exe, the MSI or the Linux package. The computer keeps its ID, key and server.
- The Linux packages carry the version `1.5.0~rc.10`, so rc.10 installs as a normal update, from the file or from the `testing` suite at pkg.neode.sk.
- Nothing changes for the full client apart from the fixes below.
- Coming from rc.8 or older, the [updating notes of rc.8](https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.8) apply too.

## What's new

### The receiver app

The receiver is the app for the person at a supported computer. It has three areas and nothing else: no settings, no ID or password, and no connections to other computers. The company's name, logo and colour come from the server's branding.

- **Get help:** the person enters the code or link the supporter gave them, and quick support starts. On an installed receiver it runs with the computer's own ID instead of a random one.
- **Messages:** the chat with support, with history, files and a button "Add a picture of my screen", which hides the window while the picture is taken.
- **My tickets:** "Something isn't working" opens a form with what's wrong, an optional picture of the screen and files. The person's name and the system go with it, and the server adds the computer's details. The list shows each ticket's status as Received, Being worked on, Solved or Closed, and "New answer" when the support team replied. A reply raises the notification "News about your ticket", and the person answers in the ticket.
- **The tray** has Open, Get help, Messages and My tickets, with the number of new messages and tickets. While anything is new, its icon gets a red dot.

### Installed, joined and managed without a click

- The receiver runs as a Windows service with a tray in every signed-in session.
- At its first start it joins the server with the token or admission it was installed with. Without one, on a server where new computers need approval, it sends a join request and asks again every two minutes, like the full client.
- It follows the server's policy for the computer: with the connection mode unattended an operator gets in with the permanent password or the person's Allow, with ask always only with the person's Allow, and with attended the computer's own access policy decides.
- It runs the full client's telemetry and fleet tasks.
- When the policy doesn't allow uninstalling, Settings › Apps doesn't list the app and the Start menu has no Uninstall shortcut. An administrator can still remove it with `msiexec /x`.
- A quick support file for the same server, started later on this computer, hands its link to the running receiver and closes.

### Silent install with the Support Agent MSI

The MSI of the Support Agent takes the server as properties and then installs the receiver:

```
msiexec /i neodesk-support.msi /qn SERVER=support.example.com:21116 KEY=<key> API=https://support.example.com TOKEN=<token> GROUP=12
```

- In the console, Add computers › Receiver app downloads the MSI with an install.cmd that has this server's values and a token filled in. The MSI comes from the Support Agent release that the console imported under Support agents.
- `API` defaults to `https://` and the host of `SERVER`. `TOKEN` is hidden from the install log and removed from the computer once the server answered.
- Without `SERVER` nothing is written, and an upgrade without properties keeps the receiver.
- The Support Agent's MSI now installs as "NeoDesk Support Agent", with its own folder, service, registry keys and upgrade code. Before, it used the full client's, so installing it replaced an installed NeoDesk Client.

### Keep support after quick support

At the end of a quick support session that ran without installing, after the feedback, the app can ask whether to keep the company's support on the computer, with the company's name from its branding. Install asks Windows for administrator rights, installs the receiver and joins it with a one-time admission from the session, so a server where new computers need approval takes the computer without a second approval. No thanks ends quick support as before.

The question comes only when the console's setting Offer to install after quick support is on, which is the default, and when the computer has no NeoDesk installed. Windows only.

### The connection window as a bar

This came in rc.9, which had no notes. Once someone is let in, the connection window becomes a bar at the top centre of the screen. It says who is connected and what they are doing, and has Files, Chat, Stop and Show details. Chat and Files open under the bar, and Show details brings back the card with the Access switches. A new request always shows the card. With several people the bar says "2 people are connected". Quick support uses the same bar.

## Fixes

- **The bar's chat field** takes typing right after the supporter moved their mouse. Before, it stayed blocked until the local mouse left the window and came back, which with a viewer on the same computer happened every time.
- **The logo** in the title bar and in Settings has the larger wordmark of the console's header.
- **Release notes:** the download buttons stay on one line, and every desktop and Support Agent release warns about support scams above the downloads.

## Known issues

- The receiver hasn't been tried as an installed app on a Windows computer before this release. Its parts were tested on their own and the builds passed.
- A receiver and a full NeoDesk Client on one computer share the names of their service pipes. Install only one of them on a computer.
- The installed receiver and the offer after quick support are Windows only.
- A picture of the screen shows the main screen only.
- The MSI is in English only.
- Texts that are new in this release are in English in every language but English and German.
- The known issues of [rc.8](https://github.com/neodeskapp/neodesk-client/releases/tag/desktop-v1.5.0-rc.8#known-issues) that aren't named here were not checked again for this release.

## Which server

- The receiver needs the server's development build 3.6.64 or later: the device ticket routes, the Receiver app tab with rollout tokens, the device policy at the API port and the offer after quick support all come from there.
- With the server 3.6.0-rc.6 the full client works as rc.9 did, and the receiver has no tickets and no offer.
