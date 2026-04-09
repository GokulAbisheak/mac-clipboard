# Clipboard (macOS)

A lightweight (<1MB) menu bar clipboard history app for macOS.

<img width="350" height="auto" alt="clipboard-ss-1" src="https://github.com/user-attachments/assets/82788347-7c11-4a20-8139-f2250f5c4235" />
<img width="350" height="auto" alt="clipboard-ss-2" src="https://github.com/user-attachments/assets/54147bb6-e2e8-4e90-92e1-587cc45fb757" />
<!-- <img width="700" height="auto" alt="clipboard-ss-3" src="https://github.com/user-attachments/assets/bc4b59e4-e972-4b6e-ac33-aa947d1138f6" /> -->

## Download & Install

- **Download**: Download the latest release - [**`clipboard_v1.1.0`**](https://github.com/GokulAbisheak/mac-clipboard/releases/download/v1.1.0/clipboard_v1.1.0.dmg)
- **Install**:
  - Open the DMG.
  - Drag **`Clipboard.app`** into the **Applications** folder.
  - Launch **Clipboard** from Applications (it runs as a **menu bar** app).

## How to Use

- **Open history**: **⇧⌘V** (Shift + Command + V)
- Pick an item to copy it back to the system clipboard.
- When pasting into another app, Clipboard requires Accessibility permission.

## Permissions

Clipboard only needs extra permissions for specific features:

- **Accessibility** *(recommended)*: needed to automatically “type” the paste shortcut into the previously active app.
  - Go to **System Settings → Privacy & Security → Accessibility**
  - Enable **Clipboard**
  - Quit and relaunch Clipboard after changing this setting

- **Files & Folder** *(recommended)*: needed to automatically copy the screenshot.
  - Go to **System Settings → Privacy & Security → Files & Folder**
  - Enable folders ender **Clipboard**
  - Quit and relaunch Clipboard after changing this setting

## Features

- **Clipboard history** for text, images, and file/folder copies
- **Image previews** for image clips (and for file clips when the first file is an image)
- **Auto-copy screenshots (optional)**: when you take a screenshot that’s saved to disk, Clipboard can automatically copy it so it appears in history
- **Launch at login**

## Build From Source

Prerequisites:

- macOS 13+
- Xcode + Command Line Tools (for Swift)

Build/run:

```bash
swift build
swift run Clipboard
```

Package a distributable `.app` (and DMG):

```bash
./scripts/package-app.sh        # dist/Clipboard.app
./scripts/package-app.sh --dmg  # dist/Clipboard.dmg
```

## Notes

- The global shortcut **⇧⌘V** commonly maps to “Paste and Match Style” in many apps. If you want a different hotkey, update `Sources/Clipboard/GlobalHotKey.swift`.

