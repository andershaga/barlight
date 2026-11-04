# Barlight

A macOS agent app (`LSUIElement`). A hotkey opens a Spotlight-style panel listing every menu bar item, and Return opens that item's menu. That is the whole scope: no hiding, reordering or styling of the bar.

## Build and run

- Use `scripts/build-app.sh`, which builds `~/Library/Caches/Barlight-build/Barlight.app`, ad-hoc signed. Build products live outside the repo on purpose.
- Only the Command Line Tools are installed; there is **no Xcode**. That rules out:
  - SwiftUI macros such as `@State` and `@Observable`, and packages that need them (KeyboardShortcuts failed). Use AppKit.
  - `xcodebuild`, `.xcodeproj` and asset catalogs.
- The toolchain is SwiftPM tools 6.2, Swift 6 strict concurrency, minimum macOS 26.
- `scripts/release.sh` builds a universal zip into `dist/`. It is unsigned and not notarized.
- `swift scripts/make-icon.swift` renders `Resources/AppIcon.svg` into `AppIcon.icns` and `AppIcon.png`. The 16 and 32 px sizes drop the wave layer.
- Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString`).

## Accessibility: read before touching scanning

- **Every rebuild loses the Accessibility grant** (ad-hoc signing ties it to the binary's hash). After each build, tell the user to re-grant Barlight in System Settings › Privacy & Security › Accessibility.
- **Never make AX calls before `AXIsProcessTrusted()` is true.** Querying first leaves some apps (Stats, Rectangle Pro, LinearMouse) refusing Barlight until it restarts. `ItemStore.refresh()` guards this, and onboarding relaunches the app after the grant.
- Claude's shell has no Accessibility and cannot take screenshots. To verify:
  - Run the trusted binary: `Barlight.app/Contents/MacOS/Barlight --dump` (one scan as a table) or `--dump-raw` (every AX element in the menu bar).
  - Read the logs: `log show --last 2m --predicate 'subsystem == "digital.haga.Barlight"'`.
  - Ask the user to look, or to send a screenshot.

## How the menu bar looks to AX on macOS 27

- Status items are not windows other apps can see, so `CGWindowList` finds nothing. Every app's `AXExtrasMenuBar` is the only source.
- Scan all running apps in parallel with a 0.5 s AX timeout per app. A shorter timeout drops items; a sequential scan takes about 2.4 s.
- System items (Wi‑Fi, Clock…) live under `com.apple.MenuBarAgent`. Each is an `AXGroup` with no actions; the pressable `AXMenuBarItem` sits one level down.
- The » overflow chevron is an `AXButton` with id `menu-bar-overflow-indicator` in MenuBarAgent's bar.
- **Items behind » disappear from AX entirely.** Pressing the chevron brings them back. This is why `HiddenItemsMode` has two modes:
  - `remember` (default) caches items while they are visible, and does one » read on the first open of each launch.
  - `reveal` presses » on every open.
- Opening a hidden item means pressing », polling until the item reappears, then pressing it (see `Activator.openHidden`).

## Source map (`Sources/Barlight/`)

| File | Owns |
|---|---|
| `App.swift` | `@main`, the status item and its menu, wiring, CLI flags (`--dump`, `--dump-raw`, `--demo`, `--show-panel`, `--open-settings`) |
| `ItemScanner.swift` | `MenuBarItem`, the parallel AX scan, chevron lookup |
| `ItemStore.swift` | the cached scan, memory of hidden items, the » reveal scan |
| `Activator.swift` | pressing items, the hidden-item flow, the ⌥Return right-click |
| `SearchPanel.swift` | the panel: glass `NSPanel`, field, table, footer |
| `Matcher.swift` / `Recents.swift` | fuzzy ranking and frecency |
| `SettingsWindow.swift` / `Preferences.swift` | Settings UI and `UserDefaults` keys |
| `OnboardingWindow.swift` | the first-run Accessibility walkthrough |
| `Hotkey.swift` / `HotkeyCombo.swift` | Carbon global hotkey and its recorder model |
| `Demo.swift` | `--demo`: made-up apps for screenshots |
| `Diagnostics.swift` | `--dump-raw` |

## Conventions

- [Ice](https://github.com/jordanbaird/Ice) and its successor [Thaw](https://github.com/thaw-app/Thaw) (both GPL‑3) are references for ideas only. Barlight is clean-room and MIT, so never copy code from either.
- Take screenshots for docs with `open Barlight.app --args --demo`, so the user's own apps never appear.
- Use AppKit only, and no third-party dependencies.
- Comments explain *why*, briefly; match the existing density.
