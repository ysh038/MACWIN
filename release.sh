#!/bin/bash
# 배포 파일 만들기: ./release.sh  →  dist/MACWIN.zip, dist/MACWIN.dmg
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

rm -rf dist
mkdir -p dist

# ZIP: ditto로 묶어야 앱 번들 구조·서명이 유지됨. ._ 파일은 안 넣음
ditto -c -k --norsrc --noextattr --noacl --keepParent build/MACWIN.app dist/MACWIN.zip

# DMG: 열면 MACWIN.app과 응용 프로그램 폴더 바로가기가 보임
STAGE=$(mktemp -d)
cp -R build/MACWIN.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname MACWIN -srcfolder "$STAGE" -ov -format UDZO dist/MACWIN.dmg >/dev/null
rm -rf "$STAGE"

ls -lh dist
