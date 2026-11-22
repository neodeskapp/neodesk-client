on run {daemon_file, agent_file, user}

  set prefs_dir to "/Users/" & user & "/Library/Preferences/sk.neode.NeoDesk Client/"
  set prefs_toml to quoted form of (prefs_dir & "NeoDesk Client.toml")
  set prefs2_toml to quoted form of (prefs_dir & "NeoDesk Client2.toml")
  set root_prefs_dir to quoted form of "/var/root/Library/Preferences/sk.neode.NeoDesk Client/"

  set sh1 to "echo " & quoted form of daemon_file & " > /Library/LaunchDaemons/sk.neode.neodesk_service.plist && chown root:wheel /Library/LaunchDaemons/sk.neode.neodesk_service.plist;"

  set sh2 to "echo " & quoted form of agent_file & " > /Library/LaunchAgents/sk.neode.neodesk_server.plist && chown root:wheel /Library/LaunchAgents/sk.neode.neodesk_server.plist;"

  set sh3 to "cp -rf " & prefs_toml & " " & root_prefs_dir & ";"

  set sh4 to "cp -rf " & prefs2_toml & " " & root_prefs_dir & ";"

  set sh5 to "launchctl bootout system/sk.neode.neodesk_service 2>/dev/null || launchctl unload -w /Library/LaunchDaemons/sk.neode.neodesk_service.plist 2>/dev/null || true; launchctl bootstrap system /Library/LaunchDaemons/sk.neode.neodesk_service.plist 2>/dev/null || launchctl load -w /Library/LaunchDaemons/sk.neode.neodesk_service.plist;"

  set sh to sh1 & sh2 & sh3 & sh4 & sh5

  do shell script sh with prompt "RustDesk wants to install daemon and agent" with administrator privileges
end run
