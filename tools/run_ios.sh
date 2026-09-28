#!/bin/bash
# Export the "iOS" preset as an Xcode project, build + sign it (automatic signing with the preset's team),
# then install and launch it on the connected iPhone.
# Usage: tools/run_ios.sh [device-udid]   (defaults to the first paired physical iPhone)
# First time only: on the iPhone, Settings > General > VPN & Device Management > trust your developer
# certificate, and turn on Settings > Privacy & Security > Developer Mode.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Users/hasanalilhadi/My Data/Godot/Godot.app/Contents/MacOS/Godot}"
PRESET=$(awk '/name="iOS"/{f=1} f&&/^\[preset\.[0-9]+\.options\]/{o=1} o' export_presets.cfg)
TEAM=$(echo "$PRESET" | sed -n 's/^application\/app_store_team_id="\(.*\)"/\1/p' | head -1)
BUNDLE=$(echo "$PRESET" | sed -n 's/^application\/bundle_identifier="\(.*\)"/\1/p' | head -1)
NAME=$(sed -n 's/^config\/name="\(.*\)"/\1/p' project.godot | head -1)
# Use the preset's team if Xcode knows it, else the first team signed into Xcode (e.g. a free Personal Team).
XCODE_TEAMS=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]*\);/\1/p')
if [ -z "$TEAM" ] || ! echo "$XCODE_TEAMS" | grep -qx "$TEAM"; then TEAM=$(echo "$XCODE_TEAMS" | head -1); fi
[ -z "$TEAM" ] && { echo "No Apple team: sign in with your Apple ID in Xcode > Settings > Accounts."; exit 1; }
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -z "$DEVICE" ] && { echo "No paired iPhone found (connect it by USB / same Wi-Fi and unlock it)."; exit 1; }

mkdir -p builds/ios
# Only export the Xcode project; xcodebuild below does the signing (the editor may rewrite this file, so force it).
sed -i '' '/name="iOS"/,/^\[preset\.[0-9]*\]$/ s/application\/export_project_only=false/application\/export_project_only=true/' export_presets.cfg
"$GODOT" --headless --path . --export-debug "iOS" "builds/ios/$NAME.ipa"
cd builds/ios
xcodebuild -project "$NAME.xcodeproj" -scheme "$NAME" -configuration Debug -destination "id=$DEVICE" \
	-derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
	CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER="" build -quiet
xcrun devicectl device install app --device "$DEVICE" "build/Build/Products/Debug-iphoneos/$NAME.app"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
