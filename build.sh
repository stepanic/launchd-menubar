#!/bin/bash
set -e
cd "$(dirname "$0")"
/opt/homebrew/bin/xcodegen generate
xcodebuild -project LaunchdBar.xcodeproj -scheme LaunchdBar -configuration Release \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO | tail -5
echo "Built: build/Build/Products/Release/LaunchdBar.app"
