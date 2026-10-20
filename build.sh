#!/bin/bash
# MACWIN.app 만들기: ./build.sh  →  build/MACWIN.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product MACWIN

APP=build/MACWIN.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MACWIN "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "만들었어요: $APP"
