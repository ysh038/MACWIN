<img src="Resources/windows98-96.png" width="64" alt="MACWIN icon">

# MACWIN

**English** | [한국어](README.ko.md)

A macOS menu bar app that checks and fixes file names **before you send files to Windows or upload them to the web** (company groupware, etc.).

Korean file names created on a Mac often show up on Windows with their syllables broken apart (`한글` → `ㅎㅏㄴㄱㅡㄹ`), can't be found by search, or fail to copy at all. Drop your files on the menu bar icon before sending them, and MACWIN finds the problematic names and fixes them.

There are three ways to use it:

- **Fix**: rename the original files in place (can be undone).
- **Compress to a Windows ZIP**: leave the originals alone and create a new ZIP with Windows-safe names.
- **Fix an existing ZIP**: drop a ZIP you already made on a Mac, and MACWIN writes a `(윈도우용)` ("for Windows") copy next to it with the names inside fixed.

ZIPs made with the Mac's built-in compression (Finder's "Compress") don't mark their names as UTF-8, so Windows misreads them as CP949 and the names come out garbled. They also carry a `__MACOSX` folder along. Both ZIP features above avoid these problems.

- macOS 13 (Ventura) or later, on both Apple Silicon and Intel Macs

> The app's interface is in Korean. Button and menu names in this document are given in English with the Korean label in parentheses, e.g. **Fix** (`고치기`).

## What it checks

| Check | Description | Action |
|---|---|---|
| Decomposed Hangul (NFD) | Converts Mac-style (NFD) Korean to Windows-style (NFC). The name looks the same. | Fixed |
| Special spaces | Replaces narrow no-break spaces (U+202F) and similar with a normal space, and removes zero-width characters. | Fixed |
| Control characters | Replaces invisible control characters with `_`. | Fixed |
| Forbidden characters | Replaces `\ : * ? " < > \|`, which Windows doesn't allow, with `_`. | Fixed |
| Trailing space/dot | Removes spaces and dots at the end of a name, like `memo. `. | Fixed |
| Reserved names | Appends `_` to names such as `CON`, `NUL` and `COM1`. | Fixed |
| Name conflict | If a fixed name would clash with another file in the same folder, it's left unchanged and reported. | Warning only |
| Case conflict | Reports names that differ only in case, like `File.txt` / `file.txt`. | Warning only |
| Long path | Reports paths that may hit Windows' 260-character path limit. | Warning only |

What it leaves alone:

- Mac hidden files such as `.DS_Store`, `._*` and `__MACOSX` (only counted)
- The inside of `.git` and `.svn` folders, and of bundles such as `.app`, Pages and Keynote files
- File **contents** (only names are changed)

## Installation

### Option 1: Download

[Releases](https://github.com/ysh038/MACWIN/releases/latest) has two formats. They contain the same app, so pick whichever you like.

| File | How to install |
|---|---|
| [MACWIN.dmg](https://github.com/ysh038/MACWIN/releases/latest/download/MACWIN.dmg) | Open it and drag `MACWIN` onto the `Applications` folder in the window |
| [MACWIN.zip](https://github.com/ysh038/MACWIN/releases/latest/download/MACWIN.zip) | Unzip it and move `MACWIN.app` to your `Applications` folder |

After installing:

1. Launch `MACWIN` from the Applications folder.
2. On first launch you'll see a warning that Apple cannot verify the app is free of malware. This is because the app isn't signed and notarized with an Apple Developer ID. You only need to allow it once.
   1. Click **Done** in the warning dialog.
   2. Go to **System Settings → Privacy & Security**, click **Open Anyway** near the bottom, and enter your password (or use Touch ID).
      - On macOS 14 or earlier, you can also **right-click `MACWIN.app` → Open → Open**.
   3. Alternatively, run this once in Terminal. Use this as well if you see "is damaged and can't be opened".

      ```bash
      xattr -dr com.apple.quarantine /Applications/MACWIN.app
      ```

### Option 2: Build from source

Requires Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ysh038/MACWIN.git
cd MACWIN
./build.sh
```

This creates `build/MACWIN.app`. Move it to the Applications folder and launch it.

Release files (`dist/MACWIN.zip`, `dist/MACWIN.dmg`) are built with `./release.sh`.

### Launch at login

In **System Settings → General → Login Items**, click `+` and add `MACWIN.app`.

## Usage

Once running, MACWIN doesn't appear in the Dock. Instead, a classic Windows logo icon appears in the menu bar.

1. **Drop the folders or files to check** — whichever is easiest:
   - Drag them from Finder onto the menu bar icon
   - Click the menu bar icon to open the window, then drag them into it
   - Use the **Choose…** (`선택…`) button in the window
   - Drop **a single ZIP file** to check the names inside it. See [Fixing an existing ZIP](#fixing-an-existing-zip).
2. **Review the results**
   - **To fix** (`고칠 것`): only checked items are fixed. Uncheck anything you want to leave as is. When a name will change, the original is shown after `원래:` ("original").
   - **Check yourself** (`직접 확인할 것`): items that aren't fixed automatically. Rename them yourself if needed.
   - If nothing is wrong, you'll see "all clean" (`깨끗해요`).
3. Choose one:
   - **Fix** (`고치기`, or Enter): renames the original files. Afterwards, **Check again** (`다시 검사`) confirms nothing is left.
   - **Windows ZIP** (`윈도우용 ZIP`): leaves the originals alone and creates a new ZIP. See [Windows ZIP](#windows-zip) below.

The window closes when you click outside it or press Esc. It stays open while you're dragging files in.

### Windows ZIP

Click **Windows ZIP** (`윈도우용 ZIP`) on the results screen (or the screen after fixing) to create `FolderName.zip` next to the originals. If you dropped several items it's named `보관.zip` ("Archive.zip"), and a number is added if the name is taken, like `보관 2.zip`.

- Names inside the ZIP are fixed using the rules in the table above. The original files are not touched.
- If fixed names collide, a number is added, like `name (2).txt`.
- Mac hidden files such as `.DS_Store`, `._*` and `__MACOSX`, and symbolic links, are left out.
- Already-compressed formats (jpg, mp4, docx, pdf, etc.) are stored without recompressing, which keeps it fast.

Choose the **name encoding** from the `⋯` menu.

| Encoding | When to use it |
|---|---|
| UTF-8 (default) | Windows 10/11 File Explorer, Bandizip, 7-Zip and other modern tools |
| Legacy Windows (CP949) (`옛날 윈도우 호환 (CP949)`) | Windows 7, or old groupware that garbles uploaded file names. Characters not in CP949, such as emoji, become `_`. The original names are stored too, so Bandizip and 7-Zip extract them with their original names. |

ZIPs over 4 GB or with more than 65,535 files can't be created yet.

### Fixing an existing ZIP

Drop a single ZIP file that was compressed on a Mac, and MACWIN checks the names inside it without extracting it.

- If any names would break on Windows, they're listed. Click **Fix for Windows** (`윈도우용으로 고치기`) to create `name (윈도우용).zip` next to the original ZIP.
- File contents are copied over exactly as compressed, so it's fast and the contents don't change. The original ZIP is left as is.
- The naming rules, removal of `__MACOSX` / `._*` / `.DS_Store`, and name encoding (UTF-8 / CP949) are the same as for Windows ZIP above.
- Password-protected ZIPs work too: only the names are fixed, and the password stays the same.
- Split archives (`.z01`, etc.) and ZIPs over 4 GB can't be fixed yet.

### Undo

Right after fixing, use **Undo** (`되돌리기`) on the completion screen, or **Undo last fix** (`마지막 수정 되돌리기`) in the `⋯` menu at the top right of the window, to restore the original names.

Renames are recorded here:

- `~/Library/Application Support/MACWIN/last.json` — the last operation (used for undo)
- `~/Library/Application Support/MACWIN/history.log` — full history

## Things to know

- **Fix renames your original files directly.** If you don't want to touch the originals, use **Windows ZIP** instead.
- If a file with the new name already exists, it isn't overwritten; the rename is reported as failed.
- If other documents or code refer to a file by name (HTML links, paths in code, Excel external references, etc.), those links may break.
- In iCloud or Dropbox folders, renamed files will be synced again.

## Command line (for development)

```bash
swift build --product macwin-cli
.build/debug/macwin-cli scan <paths...>   # check only
.build/debug/macwin-cli fix <paths...>    # check and fix
.build/debug/macwin-cli zip [--cp949] [-o out.zip] <paths...>   # create a Windows ZIP
.build/debug/macwin-cli repair [--check] [--cp949] [-o out.zip] <existing.zip>   # fix an existing ZIP (--check: inspect only)
.build/debug/macwin-cli undo              # undo the last fix
```

## Project layout

```
Sources/
  ScrubCore/    Check/fix logic (Rules: naming rules, Scanner: folder scan, Fixer: rename and undo, Zipper: Windows ZIP, ZipRepair: fix existing ZIPs)
  MACWIN/       Menu bar app (AppKit + SwiftUI)
  macwin-cli/   Command-line tool
build.sh        Builds build/MACWIN.app (universal)
release.sh      Builds dist/MACWIN.zip and dist/MACWIN.dmg
Resources/      Icon images, AppIcon.icns
scripts/make-icns.swift   Regenerates Resources/AppIcon.icns
```

## Credits

- Icon: Windows icon by [Icons8](https://icons8.com) (free license; also credited in the app under `⋯` → **About MACWIN** (`MACWIN 정보`))
