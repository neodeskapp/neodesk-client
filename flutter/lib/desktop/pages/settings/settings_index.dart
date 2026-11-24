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
  SettingsIndexEntry('general', 'nd-sec-language-and-look', 'Language', 'nd-desc:Language', 'select', false, 'System (English)', ['System (English)', 'every language the client has'], ''),
  SettingsIndexEntry('general', 'nd-sec-language-and-look', 'Theme', 'nd-desc:Theme', 'seg', false, '2', ['Light', 'Dark', 'System'], ''),
  SettingsIndexEntry('general', 'nd-sec-account', 'nd-set-row-not-signed-in', 'nd-desc:nd-set-row-not-signed-in', 'button', false, 'Sign in', [], ''),
  SettingsIndexEntry('general', 'nd-sec-updates', 'Check for software update on startup', 'nd-desc:Check for software update on startup', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-updates', 'Auto update', 'nd-desc:Auto update', 'switch', true, '', [], 'Windows and macOS, installed'),
  SettingsIndexEntry('general', 'nd-sec-sessions-you-start', 'Open connection in new tab', 'nd-desc:Open connection in new tab', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-sessions-you-start', 'Confirm before closing multiple tabs', 'nd-desc:Confirm before closing multiple tabs', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-sessions-you-start', 'keep-awake-during-outgoing-sessions-label', 'nd-desc:keep-awake-during-outgoing-sessions-label', 'switch', true, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-sessions-you-start', 'note-at-conn-end-tip', 'nd-desc:note-at-conn-end-tip', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-recording', 'Automatically record outgoing sessions', 'nd-desc:Automatically record outgoing sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-recording', 'Automatically record incoming sessions', 'nd-desc:Automatically record incoming sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('general', 'nd-sec-recording', 'nd-set-row-recordings-folder', 'nd-desc:nd-set-row-recordings-folder', 'button', false, 'Change', [], ''),
  SettingsIndexEntry('security', 'nd-sec-connections-to-this-computer', 'nd-set-row-allow-connections-to-this-computer', 'nd-desc:nd-set-row-allow-connections-to-this-computer', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-connections-to-this-computer', 'nd-set-row-how-someone-gets-in', 'nd-desc:nd-set-row-how-someone-gets-in', 'select', false, 'Password or Allow', ['Password or Allow', 'Only the password', 'Only Allow'], ''),
  SettingsIndexEntry('security', 'nd-sec-password', 'nd-set-row-which-password-works', 'nd-desc:nd-set-row-which-password-works', 'select', false, 'One-time password', ['One-time password', 'Permanent password', 'Both'], ''),
  SettingsIndexEntry('security', 'nd-sec-password', 'Set permanent password', 'nd-desc:Set permanent password', 'button', false, 'Set password', [], ''),
  SettingsIndexEntry('security', 'nd-sec-password', 'One-time password length', 'nd-desc:One-time password length', 'seg', false, '1', ['6', '8', '10'], ''),
  SettingsIndexEntry('security', 'nd-sec-password', 'Numeric one-time password', 'nd-desc:Numeric one-time password', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'nd-set-row-access', 'nd-desc:nd-set-row-access', 'seg', false, '2', ['Full access', 'Screen only', 'Custom'], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable keyboard/mouse', 'nd-desc:Enable keyboard/mouse', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable clipboard', 'nd-desc:Enable clipboard', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable file transfer', 'nd-desc:Enable file transfer', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable audio', 'nd-desc:Enable audio', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable camera', 'nd-desc:Enable camera', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable terminal', 'nd-desc:Enable terminal', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable TCP tunneling', 'nd-desc:Enable TCP tunneling', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable remote restart', 'nd-desc:Enable remote restart', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable recording session', 'nd-desc:Enable recording session', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable remote printer', 'nd-desc:Enable remote printer', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable blocking user input', 'nd-desc:Enable blocking user input', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable privacy mode', 'nd-desc:Enable privacy mode', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-what-others-may-do', 'Enable remote configuration modification', 'nd-desc:Enable remote configuration modification', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-sign-in-protection', 'nd-set-row-two-step-sign-in', 'nd-desc:nd-set-row-two-step-sign-in', 'button', false, 'Set up', [], ''),
  SettingsIndexEntry('security', 'nd-sec-sign-in-protection', 'Telegram bot', 'nd-desc:Telegram bot', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-sign-in-protection', 'Enable trusted devices', 'nd-desc:Enable trusted devices', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'allow-only-conn-window-open-tip', 'nd-desc:allow-only-conn-window-open-tip', 'switch', false, '', [], 'Installed'),
  SettingsIndexEntry('security', 'nd-sec-limits', 'auto_disconnect_option_tip', 'nd-desc:auto_disconnect_option_tip', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'Use IP Whitelisting', 'nd-desc:Use IP Whitelisting', 'button', false, 'Edit', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'Use ID whitelisting', 'nd-desc:Use ID whitelisting', 'button', false, 'Edit', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'Deny LAN discovery', 'nd-desc:Deny LAN discovery', 'switch', false, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'keep-awake-during-incoming-sessions-label', 'nd-desc:keep-awake-during-incoming-sessions-label', 'switch', true, '', [], ''),
  SettingsIndexEntry('security', 'nd-sec-limits', 'Unlock with PIN', 'nd-desc:Unlock with PIN', 'button', false, 'Set PIN', [], 'Installed'),
  SettingsIndexEntry('security', 'nd-sec-limits', 'Change ID', 'nd-desc:Change ID', 'button', false, 'Change ID', [], ''),
  SettingsIndexEntry('server', 'nd-sec-connection', 'Socks5/Http(s) Proxy', 'nd-desc:Socks5/Http(s) Proxy', 'button', false, 'Set up', [], ''),
  SettingsIndexEntry('server', 'nd-sec-connection', 'Use WebSocket', 'nd-desc:Use WebSocket', 'switch', false, '', [], ''),
  SettingsIndexEntry('server', 'nd-sec-connection', 'Disable UDP', 'nd-desc:Disable UDP', 'switch', false, '', [], ''),
  SettingsIndexEntry('server', 'nd-sec-connection', 'Allow insecure TLS fallback', 'nd-desc:Allow insecure TLS fallback', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Default View Style', 'nd-desc:Default View Style', 'select', false, 'Fit to window', ['Fit to window', 'Original size'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Default Scroll Style', 'nd-desc:Default Scroll Style', 'select', false, 'Automatic', ['Automatic', 'Scroll bars', 'At the window edge (with edge width)'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Default Image Quality', 'nd-desc:Default Image Quality', 'select', false, 'Balanced', ['Best image', 'Balanced', 'Fastest response', 'Custom (quality and frame rate)'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Default Codec', 'nd-desc:Default Codec', 'select', false, 'Automatic', ['Automatic', 'VP8', 'VP9', 'AV1', 'H.264', 'H.265'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Default trackpad speed', 'nd-desc:Default trackpad speed', 'select', false, '100 %', ['Slider, 10 to 1000 %'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'View Mode', 'nd-desc:View Mode', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'nd-set-row-show-their-screens-in-the-toolbar', 'nd-desc:nd-set-row-show-their-screens-in-the-toolbar', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Collapse toolbar', 'nd-desc:Collapse toolbar', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Show remote cursor', 'nd-desc:Show remote cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Follow remote cursor', 'nd-desc:Follow remote cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Follow remote window focus', 'nd-desc:Follow remote window focus', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Zoom cursor', 'nd-desc:Zoom cursor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Show quality monitor', 'nd-desc:Show quality monitor', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Mute', 'nd-desc:Mute', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Enable file copy and paste', 'nd-desc:Enable file copy and paste', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Disable clipboard', 'nd-desc:Disable clipboard', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Lock after session end', 'nd-desc:Lock after session end', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Privacy mode', 'nd-desc:Privacy mode', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'True color (4:4:4)', 'nd-desc:True color (4:4:4)', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Reverse mouse wheel', 'nd-desc:Reverse mouse wheel', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'nd-set-row-swap-left-and-right-mouse-button', 'nd-desc:nd-set-row-swap-left-and-right-mouse-button', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Show displays as individual windows', 'nd-desc:Show displays as individual windows', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Use all my displays for the remote session', 'nd-desc:Use all my displays for the remote session', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Keep terminal sessions on disconnect', 'nd-desc:Keep terminal sessions on disconnect', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-new-sessions-you-start', 'Sync clipboard between sessions', 'nd-desc:Sync clipboard between sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-toolbar', 'allow-remote-toolbar-docking-any-edge', 'nd-desc:allow-remote-toolbar-docking-any-edge', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-toolbar', 'Show monitor switch button on the main toolbar', 'nd-desc:Show monitor switch button on the main toolbar', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-toolbar', 'Show on the minimized toolbar', 'nd-desc:Show on the minimized toolbar', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Remove wallpaper during incoming sessions', 'nd-desc:Remove wallpaper during incoming sessions', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Adaptive bitrate', 'nd-desc:Adaptive bitrate', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Capture screen using DirectX', 'nd-desc:Capture screen using DirectX', 'switch', true, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Enable hardware codec', 'nd-desc:Enable hardware codec', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Audio Input Device', 'nd-desc:Audio Input Device', 'select', false, 'System default', ['System default', 'the microphones found'], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'nd-set-row-privacy-mode-method', 'nd-desc:nd-set-row-privacy-mode-method', 'select', false, 'Default', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'Enable RDP session sharing', 'nd-desc:Enable RDP session sharing', 'switch', false, '', [], 'Windows, installed'),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'nd-set-row-choose-the-shared-screen-again', 'nd-desc:nd-set-row-choose-the-shared-screen-again', 'button', false, 'Reset', [], 'Linux with Wayland'),
  SettingsIndexEntry('advanced', 'nd-sec-this-computer-during-sessions', 'nd-set-row-ask-again-for-keyboard-shortcuts', 'nd-desc:nd-set-row-ask-again-for-keyboard-shortcuts', 'button', false, 'Reset', [], 'Linux with Wayland'),
  SettingsIndexEntry('advanced', 'nd-sec-network', 'Enable UDP hole punching', 'nd-desc:Enable UDP hole punching', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-network', 'Enable IPv6 P2P connection', 'nd-desc:Enable IPv6 P2P connection', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-network', 'Enable direct IP access', 'nd-desc:Enable direct IP access', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-drawing', 'Always use software rendering', 'nd-desc:Always use software rendering', 'switch', false, '', [], 'Linux'),
  SettingsIndexEntry('advanced', 'nd-sec-drawing', 'Use texture rendering', 'nd-desc:Use texture rendering', 'switch', true, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-drawing', 'Use D3D rendering', 'nd-desc:Use D3D rendering', 'switch', false, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'nd-sec-printing', 'nd-set-row-neodesk-printer', 'nd-desc:nd-set-row-neodesk-printer', 'button', false, 'Install', [], 'Windows'),
  SettingsIndexEntry('advanced', 'nd-sec-printing', 'nd-set-row-print-jobs-from-other-computers', 'nd-desc:nd-set-row-print-jobs-from-other-computers', 'select', false, 'Default printer', ['Don\'t print', 'Default printer', 'This printer: (list)'], 'Windows'),
  SettingsIndexEntry('advanced', 'nd-sec-printing', 'nd-set-row-print-without-asking', 'nd-desc:nd-set-row-print-without-asking', 'switch', false, '', [], 'Windows'),
  SettingsIndexEntry('advanced', 'nd-sec-reports-and-branding', 'nd-set-row-share-app-activity-with-the-server', 'nd-desc:nd-set-row-share-app-activity-with-the-server', 'switch', false, '', [], ''),
  SettingsIndexEntry('advanced', 'nd-sec-reports-and-branding', 'Clear', 'nd-desc:Clear', 'button', false, 'Edit', [], ''),
];
