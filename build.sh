#!/bin/bash
set -e
cd "$(dirname "$0")"
/opt/homebrew/bin/xcodegen generate
xcodebuild -project LaunchdBar.xcodeproj -scheme LaunchdBar -configuration Release \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO | tail -5

APP="build/Build/Products/Release/LaunchdBar.app"
echo "Built: $APP"

# The launchd autostart (~/Library/LaunchAgents/com.stepanic.LaunchdBar.plist)
# runs /Applications/LaunchdBar.app, so a build alone won't survive a reboot.
# `./build.sh install` deploys the fresh build there and restarts the job.
if [ "$1" = "install" ]; then
  DST="/Applications/LaunchdBar.app"
  echo "⚙️  Installing to $DST and restarting launchd job..."
  pkill -x LaunchdBar 2>/dev/null || true
  sleep 1
  rm -rf "$DST"
  cp -R "$APP" "$DST"
  # Register with LaunchServices so the first launchd spawn doesn't hit a
  # stale code-signature cache (OS_REASON_CODESIGNING).
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$DST"
  launchctl kickstart -k "gui/$(id -u)/com.stepanic.LaunchdBar"
  echo "✅ Installed and (re)started from $DST"
else
  echo "Tip: run './build.sh install' to deploy to /Applications (the autostart path) and restart."
fi
