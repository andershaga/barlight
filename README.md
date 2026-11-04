<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Barlight icon"></p>

# Barlight

Search your Mac's menu bar from the keyboard. Press a hotkey, type part of an item's name, press Return, and its menu opens.

It finds every menu bar item, including the ones macOS hides behind the » overflow chevron when the bar runs out of space.

## Use

| Key | Action |
|---|---|
| ⇧⌘Space | Open Barlight (change it in Settings) |
| Type | Filter by item or app name |
| ↑ ↓ | Move the selection |
| Return | Open the item's menu |
| ⌥Return | Open the item's right-click menu |
| ⌘, | Open Settings |
| Esc | Close |

Items you open often move to the top.

## Settings

- **Search hotkey:** any combination with ⌘, ⌥ or ⌃.
- **Open Barlight at login.**
- **Show system items:** Clock, Wi‑Fi, Sound and other Apple items. Off by default.
- **Items behind »:** choose how hidden items are found:
  - **Remember items when seen** (default): instant, with no flicker. An item must have been visible once.
  - **Reveal with » on every open:** always complete, with a brief flicker. Nothing is saved.

## Requirements

- macOS 26 or later.
- **Accessibility** permission. Barlight reads and presses menu bar items through the Accessibility API. It needs no Screen Recording permission and makes no network access.

## Build

You need Swift 6.2 or later. The Xcode Command Line Tools are enough.

```bash
scripts/build-app.sh
```

This builds `Barlight.app` in `~/Library/Caches/Barlight-build/`, ad-hoc signed. Copy it to `/Applications` and open it. The welcome window walks you through granting Accessibility.

Ad-hoc signed builds lose the Accessibility grant on every rebuild, so grant it again after each one.

To regenerate the app icon from `Resources/AppIcon.svg`:

```bash
swift scripts/make-icon.swift
```

## Debugging

```bash
Barlight.app/Contents/MacOS/Barlight --dump       # one scan, printed as a table
Barlight.app/Contents/MacOS/Barlight --dump-raw   # every Accessibility element in the menu bar
```

Logs use the subsystem `digital.haga.Barlight`:

```bash
log stream --predicate 'subsystem == "digital.haga.Barlight"'
```

## Credits

Inspired by the search panel in [Thaw](https://github.com/thaw-app/Thaw). Barlight is written from scratch and contains no Thaw code.

## License

[MIT](LICENSE)
