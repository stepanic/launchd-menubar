#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ -x /opt/homebrew/bin/xcodegen ] && xcodebuild -version >/dev/null 2>&1; then
  /opt/homebrew/bin/xcodegen generate
  xcodebuild -project LaunchdBar.xcodeproj -scheme LaunchdBar -configuration Release \
    -derivedDataPath build build CODE_SIGNING_ALLOWED=NO | tail -5
  APP="build/Build/Products/Release/LaunchdBar.app"
else
  # No Xcode/xcodegen (e.g. a machine with only Command Line Tools): compile with
  # swiftc and assemble the bundle by hand. Mirrors the settings in project.yml.
  echo "ℹ️  Xcode/xcodegen not found — building with swiftc (Command Line Tools)"
  APP="build/swiftc/LaunchdBar.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$(uname -m)-apple-macos14.0" \
    -framework SwiftUI -framework AppKit \
    Sources/*.swift -o "$APP/Contents/MacOS/LaunchdBar"
  cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>LaunchdBar</string>
  <key>CFBundleIdentifier</key><string>com.stepanic.LaunchdBar</string>
  <key>CFBundleName</key><string>LaunchdBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
  codesign --force -s - "$APP"
fi
echo "Built: $APP"

# The launchd autostart (~/Library/LaunchAgents/com.stepanic.LaunchdBar.plist)
# runs /Applications/LaunchdBar.app, so a build alone won't survive a reboot.
# `./build.sh install` deploys the fresh build there and restarts the job.
if [ "$1" = "install" ]; then
  DST="/Applications/LaunchdBar.app"
  LABEL="com.stepanic.LaunchdBar"
  AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
  echo "⚙️  Installing to $DST and restarting launchd job..."
  pkill -x LaunchdBar 2>/dev/null || true
  sleep 1
  rm -rf "$DST"
  cp -R "$APP" "$DST"
  # Re-sign ad-hoc after the copy: the kernel caches signatures per inode, so the
  # fresh copy at the old path spawns with OS_REASON_CODESIGNING without this.
  codesign --force --deep -s - "$DST"
  # Register with LaunchServices so the first launchd spawn doesn't hit a
  # stale code-signature cache (OS_REASON_CODESIGNING).
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$DST"
  # First install on a new machine: create the autostart agent. KeepAlive only
  # on crash, so the menu's Quit (exit 0) still quits.
  if [ ! -f "$AGENT" ]; then
    echo "⚙️  Creating $AGENT"
    cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DST/Contents/MacOS/LaunchdBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
  fi
  launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 \
    || launchctl bootstrap "gui/$(id -u)" "$AGENT"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "✅ Installed and (re)started from $DST"
else
  echo "Tip: run './build.sh install' to deploy to /Applications (the autostart path) and restart."
fi
