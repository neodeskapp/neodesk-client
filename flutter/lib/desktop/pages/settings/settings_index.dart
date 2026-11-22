// The settings of the client with their place on the settings page, for
// search (DESIGN.md, Settings, "Where every setting goes"). Generated from
// the design's settings inventory; label and desc are translation keys.

class SettingsIndexEntry {
  const SettingsIndexEntry(this.group, this.section, this.label, this.desc,
      this.control, this.on, this.value, this.options, this.os);

  /// general, security, server or advanced.
  final String group;
  final String section;
  final String label;
  final String desc;

  /// switch, select, seg or button, with the design's example value.
  final String control;
  final bool on;
  final String value;
  final List<String> options;

  /// The systems it shows on, empty for all.
  final String os;
}

const kSettingsIndex = <SettingsIndexEntry>[
  SettingsIndexEntry('general', 'bd-sec-language-and-look', 'Language', 'bd-desc:Language', 'select', false, 'System (English)', ['System (English)', 'every language the client has'], ''),
  SettingsIndexEntry('general', 'bd-sec-language-and-look', 'Theme', 'bd-desc:Theme', 'seg', false, '2', ['Light', 'Dark', 'System'], ''),
  SettingsIndexEntry('general', 'bd-sec-account', 'bd-set-row-not-signed-in', 'bd-desc:bd-set-row-not-signed-in', 'button', false, 'Sign in', [], ''),
  SettingsIndexEntry('general', 'bd-sec-updates', 'Check for software update on startup', 'bd-desc:Check for software update on startup', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-updates', 'Auto update', 'bd-desc:Auto update', 'switch', true, '', [], 'Windows and macOS, installed'),
  SettingsIndexEntry('general', 'bd-sec-sessions-you-start', 'Open connection in new tab', 'bd-desc:Open connection in new tab', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-sessions-you-start', 'Confirm before closing multiple tabs', 'bd-desc:Confirm before closing multiple tabs', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-sessions-you-start', 'keep-awake-during-outgoing-sessions-label', 'bd-desc:keep-awake-during-outgoing-sessions-label', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-sessions-you-start', 'note-at-conn-end-tip', 'bd-desc:note-at-conn-end-tip', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-recording', 'Automatically record outgoing sessions', 'bd-desc:Automatically record outgoing sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-recording', 'Automatically record incoming sessions', 'bd-desc:Automatically record incoming sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'bd-sec-recording', 'bd-set-row-recordings-folder', 'bd-desc:bd-set-row-recordings-folder', 'button', false, 'Change', [], ''),
  SettingsIndexEntry('security', 'bd-sec-connections-to-this-computer', 'bd-set-row-allow-connections-to-this-computer', 'bd-desc:bd-set-row-allow-connections-to-this-computer', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-connections-to-this-computer', 'bd-set-row-how-someone-gets-in', 'bd-desc:bd-set-row-how-someone-gets-in', 'select', false, 'Password or Allow', ['Password or Allow', 'Only the password', 'Only Allow'], ''),
  SettingsIndexEntry('security', 'bd-sec-password', 'bd-set-row-which-password-works', 'bd-desc:bd-set-row-which-password-works', 'select', false, 'One-time password', ['One-time password', 'Permanent password', 'Both'], ''),
  SettingsIndexEntry('security', 'bd-sec-password', 'Set permanent password', 'bd-desc:Set permanent password', 'button', false, 'Set password', [], ''),
  SettingsIndexEntry('security', 'bd-sec-password', 'One-time password length', 'bd-desc:One-time password length', 'seg', false, '1', ['6', '8', '10'], ''),
  SettingsIndexEntry('security', 'bd-sec-password', 'Numeric one-time password', 'bd-desc:Numeric one-time password', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'bd-set-row-access', 'bd-desc:bd-set-row-access', 'seg', false, '2', ['Full access', 'Screen only', 'Custom'], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable keyboard/mouse', 'bd-desc:Enable keyboard/mouse', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable clipboard', 'bd-desc:Enable clipboard', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable file transfer', 'bd-desc:Enable file transfer', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable audio', 'bd-desc:Enable audio', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable camera', 'bd-desc:Enable camera', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable terminal', 'bd-desc:Enable terminal', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable TCP tunneling', 'bd-desc:Enable TCP tunneling', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable remote restart', 'bd-desc:Enable remote restart', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable recording session', 'bd-desc:Enable recording session', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable remote printer', 'bd-desc:Enable remote printer', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable blocking user input', 'bd-desc:Enable blocking user input', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable privacy mode', 'bd-desc:Enable privacy mode', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-what-others-may-do', 'Enable remote configuration modification', 'bd-desc:Enable remote configuration modification', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-sign-in-protection', 'bd-set-row-two-step-sign-in', 'bd-desc:bd-set-row-two-step-sign-in', 'button', false, 'Set up', [], ''),
  SettingsIndexEntry('security', 'bd-sec-sign-in-protection', 'Telegram bot', 'bd-desc:Telegram bot', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-sign-in-protection', 'Enable trusted devices', 'bd-desc:Enable trusted devices', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'allow-only-conn-window-open-tip', 'bd-desc:allow-only-conn-window-open-tip', 'switch', false, '', [], 'Installed'),
  SettingsIndexEntry('security', 'bd-sec-limits', 'auto_disconnect_option_tip', 'bd-desc:auto_disconnect_option_tip', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'Use IP Whitelisting', 'bd-desc:Use IP Whitelisting', 'button', false, 'Edit', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'Use ID whitelisting', 'bd-desc:Use ID whitelisting', 'button', false, 'Edit', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'Deny LAN discovery', 'bd-desc:Deny LAN discovery', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'keep-awake-during-incoming-sessions-label', 'bd-desc:keep-awake-during-incoming-sessions-label', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'bd-sec-limits', 'Unlock with PIN', 'bd-desc:Unlock with PIN', 'button', false, 'Set PIN', [], 'Installed'),
  SettingsIndexEntry('security', 'bd-sec-limits', 'Change ID', 'bd-desc:Change ID', 'button', false, 'Change ID', [], ''),
  SettingsIndexEntry('server', 'bd-sec-connection', 'Socks5/Http(s) Proxy', 'bd-desc:Socks5/Http(s) Proxy', 'button', false, 'Set up', [], ''),
  SettingsIndexEntry('server', 'bd-sec-connection', 'Use WebSocket', 'bd-desc:Use WebSocket', 'switch', false, '', [], ''),
  SettingsIndexEntry('server', 'bd-sec-connection', 'Disable UDP', 'bd-desc:Disable UDP', 'switch', false, '', [], ''),
  SettingsIndexEntry('server', 'bd-sec-connection', 'Allow insecure TLS fallback', 'bd-desc:Allow insecure TLS fallback', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Default View Style', 'bd-desc:Default View Style', 'select', false, 'Fit to window', ['Fit to window', 'Original size'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Default Scroll Style', 'bd-desc:Default Scroll Style', 'select', false, 'Automatic', ['Automatic', 'Scroll bars', 'At the window edge (with edge width)'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Default Image Quality', 'bd-desc:Default Image Quality', 'select', false, 'Balanced', ['Best image', 'Balanced', 'Fastest response', 'Custom (quality and frame rate)'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Default Codec', 'bd-desc:Default Codec', 'select', false, 'Automatic', ['Automatic', 'VP8', 'VP9', 'AV1', 'H.264', 'H.265'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Default trackpad speed', 'bd-desc:Default trackpad speed', 'select', false, '100 %', ['Slider, 10 to 1000 %'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'View Mode', 'bd-desc:View Mode', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'bd-set-row-show-their-screens-in-the-toolbar', 'bd-desc:bd-set-row-show-their-screens-in-the-toolbar', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Collapse toolbar', 'bd-desc:Collapse toolbar', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Show remote cursor', 'bd-desc:Show remote cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Follow remote cursor', 'bd-desc:Follow remote cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Follow remote window focus', 'bd-desc:Follow remote window focus', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Zoom cursor', 'bd-desc:Zoom cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Show quality monitor', 'bd-desc:Show quality monitor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Mute', 'bd-desc:Mute', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Enable file copy and paste', 'bd-desc:Enable file copy and paste', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Disable clipboard', 'bd-desc:Disable clipboard', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Lock after session end', 'bd-desc:Lock after session end', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Privacy mode', 'bd-desc:Privacy mode', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'True color (4:4:4)', 'bd-desc:True color (4:4:4)', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Reverse mouse wheel', 'bd-desc:Reverse mouse wheel', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'bd-set-row-swap-left-and-right-mouse-button', 'bd-desc:bd-set-row-swap-left-and-right-mouse-button', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Show displays as individual windows', 'bd-desc:Show displays as individual windows', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Use all my displays for the remote session', 'bd-desc:Use all my displays for the remote session', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Keep terminal sessions on disconnect', 'bd-desc:Keep terminal sessions on disconnect', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-new-sessions-you-start', 'Sync clipboard between sessions', 'bd-desc:Sync clipboard between sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-toolbar', 'allow-remote-toolbar-docking-any-edge', 'bd-desc:allow-remote-toolbar-docking-any-edge', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-toolbar', 'Show monitor switch button on the main toolbar', 'bd-desc:Show monitor switch button on the main toolbar', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-toolbar', 'Show on the minimized toolbar', 'bd-desc:Show on the minimized toolbar', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Remove wallpaper during incoming sessions', 'bd-desc:Remove wallpaper during incoming sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Adaptive bitrate', 'bd-desc:Adaptive bitrate', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Capture screen using DirectX', 'bd-desc:Capture screen using DirectX', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Enable hardware codec', 'bd-desc:Enable hardware codec', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Audio Input Device', 'bd-desc:Audio Input Device', 'select', false, 'System default', ['System default', 'the microphones found'], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'bd-set-row-privacy-mode-method', 'bd-desc:bd-set-row-privacy-mode-method', 'select', false, 'Default', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'Enable RDP session sharing', 'bd-desc:Enable RDP session sharing', 'switch', false, '', [], 'Windows, installed'),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'bd-set-row-choose-the-shared-screen-again', 'bd-desc:bd-set-row-choose-the-shared-screen-again', 'button', false, 'Reset', [], 'Linux with Wayland'),
  SettingsIndexEntry('advanced', 'bd-sec-this-computer-during-sessions', 'bd-set-row-ask-again-for-keyboard-shortcuts', 'bd-desc:bd-set-row-ask-again-for-keyboard-shortcuts', 'button', false, 'Reset', [], 'Linux with Wayland'),
  SettingsIndexEntry('advanced', 'bd-sec-network', 'Enable UDP hole punching', 'bd-desc:Enable UDP hole punching', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-network', 'Enable IPv6 P2P connection', 'bd-desc:Enable IPv6 P2P connection', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-network', 'Enable direct IP access', 'bd-desc:Enable direct IP access', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-drawing', 'Always use software rendering', 'bd-desc:Always use software rendering', 'switch', false, '', [], 'Linux'),
  SettingsIndexEntry('advanced', 'bd-sec-drawing', 'Use texture rendering', 'bd-desc:Use texture rendering', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-drawing', 'Use D3D rendering', 'bd-desc:Use D3D rendering', 'switch', false, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'bd-sec-printing', 'bd-set-row-neodesk-printer', 'bd-desc:bd-set-row-neodesk-printer', 'button', false, 'Install', [], 'Windows'),
  SettingsIndexEntry('advanced', 'bd-sec-printing', 'bd-set-row-print-jobs-from-other-computers', 'bd-desc:bd-set-row-print-jobs-from-other-computers', 'select', false, 'Default printer', ['Don\'t print', 'Default printer', 'This printer: (list)'], 'Windows'),
  SettingsIndexEntry('advanced', 'bd-sec-printing', 'bd-set-row-print-without-asking', 'bd-desc:bd-set-row-print-without-asking', 'switch', false, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'bd-sec-reports-and-branding', 'bd-set-row-share-app-activity-with-the-server', 'bd-desc:bd-set-row-share-app-activity-with-the-server', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'bd-sec-reports-and-branding', 'Clear', 'bd-desc:Clear', 'button', false, 'Edit', [], ''),
];
