#!/bin/bash
# MACWIN.app 만들기: ./build.sh  →  build/MACWIN.app (Apple Silicon + 인텔 유니버설)
set -euo pipefail
cd "$(dirname "$0")"

for arch in arm64 x86_64; do
    swift build -c release --product MACWIN --triple "$arch-apple-macosx13.0"
done

APP=build/MACWIN.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
lipo -create -output "$APP/Contents/MacOS/MACWIN" \
    .build/arm64-apple-macosx/release/MACWIN \
    .build/x86_64-apple-macosx/release/MACWIN
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/windows98-*.png "$APP/Contents/Resources/"
cp -R Resources/en.lproj Resources/ko.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "만들었어요: $APP"
