set sh1 to "launchctl unload -w /Library/LaunchDaemons/sk.neode.neodesk_service.plist;"
set sh2 to "/bin/rm /Library/LaunchDaemons/sk.neode.neodesk_service.plist;"
set sh3 to "/bin/rm /Library/LaunchAgents/sk.neode.neodesk_server.plist;"

set sh to sh1 & sh2 & sh3
do shell script sh with prompt "NeoDesk Client wants to unload daemon" with administrator privileges