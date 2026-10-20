# MACWIN

맥에서 만든 파일을 **윈도우로 보내거나 웹(사내 그룹웨어 등)에 올리기 전에** 파일명을 검토하고 고쳐주는 메뉴바 앱입니다.

맥에서 이름을 지은 한글 파일은 윈도우에서 `ㅎㅏㄴㄱㅡㄹ` 처럼 자소가 분리되어 보이거나, 검색이 안 되거나, 아예 복사가 안 되는 경우가 많습니다. 보내기 전에 메뉴바 아이콘에 한 번 올려두면 문제가 되는 이름을 찾아서 고쳐줍니다.

- macOS 13 (Ventura) 이상, Apple Silicon·인텔 맥 모두 지원

## 무엇을 검사하나요

| 항목 | 설명 | 처리 |
|---|---|---|
| 자소분리 | 맥식(NFD) 한글을 윈도우식(NFC)으로 바꿉니다. 보이는 이름은 그대로예요. | 고침 |
| 특수 공백 | 좁은 공백(U+202F), 제로폭 문자 등을 일반 공백으로 바꾸거나 지웁니다. | 고침 |
| 제어 문자 | 보이지 않는 제어 문자를 `_` 로 바꿉니다. | 고침 |
| 금지 문자 | 윈도우에서 못 쓰는 `\ : * ? " < > \|` 를 `_` 로 바꿉니다. | 고침 |
| 끝 공백/점 | `메모. ` 처럼 이름 끝의 공백·마침표를 지웁니다. | 고침 |
| 예약어 | `CON`, `NUL`, `COM1` 같은 이름 뒤에 `_` 를 붙입니다. | 고침 |
| 이름 충돌 | 고친 이름이 같은 폴더의 다른 파일과 겹치면 바꾸지 않고 알려줍니다. | 경고만 |
| 대소문자 충돌 | `File.txt` / `file.txt` 처럼 대소문자만 다른 이름이 있으면 알려줍니다. | 경고만 |
| 긴 경로 | 윈도우 260자 경로 제한에 걸릴 수 있으면 알려줍니다. | 경고만 |

건드리지 않는 것:

- `.DS_Store`, `._*`, `__MACOSX` 같은 맥 숨김파일 (개수만 알려줌)
- `.git`, `.svn` 폴더 안쪽, `.app`·Pages·Keynote 같은 번들 안쪽
- 파일 **내용** (이름만 바꿉니다)

## 설치

### 방법 1: 내려받기

[Releases](https://github.com/ysh038/MACWIN/releases/latest)에 두 가지 형식이 있습니다. 내용은 같으니 편한 쪽을 받으세요.

| 파일 | 설치 방법 |
|---|---|
| [MACWIN.dmg](https://github.com/ysh038/MACWIN/releases/latest/download/MACWIN.dmg) | 열면 나오는 창에서 `MACWIN` 을 `Applications` 폴더로 끌어다 놓기 |
| [MACWIN.zip](https://github.com/ysh038/MACWIN/releases/latest/download/MACWIN.zip) | 압축을 풀고 `MACWIN.app` 을 `응용 프로그램(Applications)` 폴더로 옮기기 |

설치한 다음:

1. 응용 프로그램 폴더에서 `MACWIN` 을 실행합니다.
2. 처음 실행할 때 "Apple은 이 앱이 악성 코드가 없음을 확인할 수 없습니다" 경고가 뜹니다. Apple 개발자 서명·공증을 받지 않은 앱이라 그렇고, 처음 한 번만 허용하면 됩니다.
   1. 경고 창에서 **완료**를 누릅니다.
   2. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 아래쪽의 **그래도 열기**를 누르고 암호(또는 Touch ID)를 입력합니다.
      - macOS 14 이하라면 `MACWIN.app` 을 **우클릭 → 열기 → 열기**로도 됩니다.
   3. 또는 터미널에서 아래를 한 번 실행해도 됩니다. "손상되었기 때문에 열 수 없습니다"가 뜰 때도 이 방법을 쓰세요.

      ```bash
      xattr -dr com.apple.quarantine /Applications/MACWIN.app
      ```

### 방법 2: 직접 빌드

Xcode 또는 Command Line Tools(`xcode-select --install`)가 필요합니다.

```bash
git clone https://github.com/ysh038/MACWIN.git
cd MACWIN
./build.sh
```

`build/MACWIN.app` 이 만들어집니다. 응용 프로그램 폴더로 옮겨서 실행하세요.

배포용 파일(`dist/MACWIN.zip`, `dist/MACWIN.dmg`)은 `./release.sh` 로 만듭니다.

### 로그인할 때 자동 실행

**시스템 설정 → 일반 → 로그인 항목**에서 `+` 를 눌러 `MACWIN.app` 을 추가하세요.

## 사용법

실행하면 Dock에는 안 보이고 메뉴바에 윈도우 모양(⊞) 아이콘이 생깁니다.

1. **검사할 폴더/파일 올리기** — 셋 중 편한 방법으로
   - Finder에서 끌어다 메뉴바 ⊞ 아이콘 위에 놓기
   - ⊞ 아이콘을 눌러 창을 열고, 창에 끌어다 놓기
   - 창에서 **선택…** 버튼으로 고르기
2. **결과 확인**
   - **고칠 것**: 체크된 항목만 고칩니다. 원하지 않는 항목은 체크를 풀어주세요. 이름이 바뀌는 경우 `원래:` 로 원래 이름을 보여줍니다.
   - **직접 확인할 것**: 자동으로 고치지 않는 항목입니다. 필요하면 직접 이름을 바꿔주세요.
   - 문제가 없으면 "깨끗해요"가 뜹니다.
3. **고치기** 버튼(또는 Enter)을 누르면 이름이 바뀝니다.
4. **다시 검사**로 남은 문제가 없는지 확인할 수 있습니다.

창은 바깥을 클릭하거나 Esc를 누르면 닫힙니다. 파일을 끌어오는 중에는 닫히지 않습니다.

### 되돌리기

고친 직후 완료 화면의 **되돌리기**, 또는 창 오른쪽 위 `⋯` 메뉴의 **마지막 수정 되돌리기**로 원래 이름으로 돌릴 수 있습니다.

바꾼 기록은 여기에 남습니다.

- `~/Library/Application Support/MACWIN/last.json` — 마지막 작업 (되돌리기용)
- `~/Library/Application Support/MACWIN/history.log` — 전체 기록

## 주의할 점

- **원본 파일의 이름을 직접 바꿉니다.** 사본을 만들지 않습니다.
- 같은 이름이 이미 있으면 덮어쓰지 않고 실패로 표시합니다.
- 다른 문서나 코드가 파일 이름으로 참조하고 있다면(HTML 링크, 코드 안 경로, 엑셀 외부 참조 등) 연결이 끊길 수 있습니다.
- iCloud·Dropbox 폴더라면 이름이 바뀐 파일이 다시 동기화됩니다.

## 터미널에서 쓰기 (개발용)

```bash
swift build --product macwin-cli
.build/debug/macwin-cli scan <경로...>   # 검사만
.build/debug/macwin-cli fix <경로...>    # 검사하고 고치기
.build/debug/macwin-cli undo             # 마지막 작업 되돌리기
```

## 구조

```
Sources/
  ScrubCore/    검사·수정 로직 (Rules: 규칙, Scanner: 폴더 검사, Fixer: 이름 바꾸기·되돌리기)
  MACWIN/       메뉴바 앱 (AppKit + SwiftUI)
  macwin-cli/   터미널용 도구
build.sh        build/MACWIN.app 만들기 (유니버설)
release.sh      dist/MACWIN.zip, dist/MACWIN.dmg 만들기
```
