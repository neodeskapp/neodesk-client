<img src="https://raw.githubusercontent.com/neodeskapp/website/335f1c4b7eeab2715ecae07228a7619b58c934c9/public/img/releases/desktop-v1.5.0-rc.4/card.png" width="800" alt="NeoDesk desktop client v1.5.0-rc.4, pre-release of 23 November 2026, the desktop client as NeoDesk: 11 commits, 179 files changed, 1,424 lines added, 1,230 lines removed and 6 fixes since v1.5.0-rc.2, numbers that include the rename of the project">

This pre-release is the desktop client as NeoDesk. It goes with the NeoDesk server [3.6.0-rc.2](https://github.com/neodeskapp/neodesk/releases/tag/v3.6.0-rc.2): both use the new `nd` names for enrollment, and neither keeps the old ones.

## What's new

### The client is NeoDesk

The client is called NeoDesk and shows the NeoDesk logo. It points at the renamed neodeskapp organization, is published as NeoDesk, and the portable download says NeoDesk Client in its file properties. On first start it asks for the invite link or code from your IT support, or for the server address and key under **Set up by hand**.

<img src="https://raw.githubusercontent.com/neodeskapp/website/335f1c4b7eeab2715ecae07228a7619b58c934c9/public/img/releases/desktop-v1.5.0-rc.4/set-up.png" width="700" alt="The NeoDesk client on first start on Linux: Set up NeoDesk, with a field for the invite link or code and the Set up by hand link">

Once it is set up, the main window shows this computer's ID and one-time password next to the field for connecting to another computer.

<img src="https://raw.githubusercontent.com/neodeskapp/website/335f1c4b7eeab2715ecae07228a7619b58c934c9/public/img/releases/desktop-v1.5.0-rc.4/home.png" width="700" alt="The NeoDesk client's main window on Linux, ready and connected to the company's server, with this computer's ID and one-time password on the left and Connect to another computer on the right">

### Settings open in place

Settings opens in place of Home, with a Back button, instead of in a second tab. The window buttons are line glyphs of one size and weight.

<img src="https://raw.githubusercontent.com/neodeskapp/website/335f1c4b7eeab2715ecae07228a7619b58c934c9/public/img/releases/desktop-v1.5.0-rc.4/settings.png" width="700" alt="The client's General settings, opened in place of Home, with a Back button in the title bar and the sections General, Security, Server, Advanced and About on the left">

### Enrollment with the new names

The client signs enrollment as `nd-enrollment-v1` with the `X-ND-Enrollment` headers, as NeoDesk servers from 3.6.0-rc.2 on expect.

### Fixes in the release builds

- A support release no longer becomes the latest release of this repository.
- The server can pass build targets to the support build.
