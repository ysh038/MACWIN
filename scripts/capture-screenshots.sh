#!/bin/bash
# README용 화면 캡처 다시 만들기: scripts/capture-screenshots.sh
# 결과: docs/screenshots/<화면>-<언어>-<테마>.png (2배율, 창 그림자 포함)
# 화면 기록 권한이 있는 터미널에서 실행해야 합니다. 실행 중인 MACWIN은 먼저 종료하세요.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh >/dev/null
BIN=build/MACWIN.app/Contents/MacOS/MACWIN
OUT=docs/screenshots
mkdir -p "$OUT"

# 샘플 폴더: 맥식(NFD) 한글·악센트, 금지 문자, 끝 마침표, 예약어, 대소문자 충돌, 맥 숨김파일
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 -I - "$WORK" <<'EOF'
import os, sys, unicodedata as u
N = lambda s: u.normalize('NFD', s)
d = os.path.join(sys.argv[1], N('보고서 폴더')); os.makedirs(d)
def f(name, size=1): open(os.path.join(d, name), 'w').write('x' * size)
f(N('회의록 2024.xlsx'), 2000); f(N('프로젝트 계획.docx'), 3000); f(N('Résumé.pdf'), 5000)
f(N('결과 분석?.txt')); f('notes. '); f('CON.txt'); f('Report.pdf'); f('report.pdf'); f('.DS_Store')
f(N('스크린샷 2024-05-01 3.45 PM.png'), 4000)
EOF
SAMPLE="$WORK/보고서 폴더"
mkdir -p "$WORK/zips"
(cd "$WORK" && ditto -c -k --sequesterRsrc --keepParent "보고서 폴더" "zips/보고서 폴더.zip")
ZIP="$WORK/zips/보고서 폴더.zip"

shoot() { # 화면 언어 테마
  local state=$1 lang=$2 theme=$3
  "$BIN" --demo "$state" "$SAMPLE" "$ZIP" --$theme -AppleLanguages "($lang)" > "$WORK/demo.out" 2>&1 &
  local pid=$!
  sleep 2.5
  local win; win=$(awk '/WINDOW/{print $2}' "$WORK/demo.out")
  screencapture -x -l "$win" "$OUT/$state-$lang-$theme.png"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
}

for lang in en ko; do
  for theme in light dark; do
    for state in idle scanned done zip zipped; do shoot $state $lang $theme; done
  done
done
ls "$OUT"
