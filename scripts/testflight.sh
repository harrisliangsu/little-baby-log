#!/bin/sh
# Archives a Release build and uploads the binary to App Store Connect.
#
#   scripts/testflight.sh <build-number>
#
# This only uploads. It does not submit App Store review, Beta App Review,
# or an external TestFlight group. Needs Config/Local.xcconfig with a confirmed
# DEVELOPMENT_TEAM, and Xcode signed in (or an App Store Connect API key).
# Each upload needs a build number higher than the last. Without a team the
# script stops before archiving and must not be described as a successful upload.
set -eu
cd "$(dirname "$0")/.."

BUILD="${1:?usage: scripts/testflight.sh <build-number>}"
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
[ -n "$TEAM" ] || { echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig" >&2; exit 1; }

ARCHIVE=.build/archive/LittleBabyLog.xcarchive
EXPORT=.build/export
mkdir -p "$EXPORT"
cat > "$EXPORT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

xcodegen generate -q
rm -rf "$ARCHIVE"
xcodebuild -project LittleBabyLog.xcodeproj -scheme LittleBabyLog -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" archive
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT/ExportOptions.plist" \
  -exportPath "$EXPORT" -allowProvisioningUpdates
