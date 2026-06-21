# Komo

A tiny macOS **menu-bar** app that quietly counts how you use your keyboard and
mouse. Click the status-bar icon to see:

- **Keystrokes per physical key** (A–Z, 0–9, and Space; main row *and*
  numeric keypad digits share buckets), drawn as a live **keyboard heat-map** —
  your most-used keys glow hottest.
- **Left & right mouse clicks.**
- **Mouse travel distance**, converted to real-world cm / m / km.
- A **Today / All-time** toggle, with a "▲ vs. yesterday" trend.

Komo only ever stores **counts** — never *which* keys you pressed in what order.
It is a statistics toy, not a keylogger. All data stays in a local JSON file.

<p align="center">
  <em>Light & dark, with a permission-prompt state.</em>
</p>

## Requirements

- macOS 14 or later (built and tested on macOS 26, Apple Silicon).
- Swift toolchain — the **Command Line Tools** are enough; full Xcode is *not*
  required.

## Build & run

```bash
./build.sh                 # compiles (release) and assembles Komo.app
open Komo.app              # or drag it to /Applications
```

`build.sh` produces a double-clickable, signed `Komo.app` plus
`Komo-installable.zip`, which another Mac user can unzip and drag to
Applications. To regenerate the app icon (already committed as
`Resources/Komo.icns`):

```bash
./Tools/gen_icon.sh
```

## Permissions

- **Mouse** stats work immediately, no permission needed.
- **Keyboard** stats require **Input Monitoring**:
  *System Settings → Privacy & Security → Input Monitoring → enable Komo.*
  The popover shows a banner with **Grant Access** / **Open Settings** buttons.
  Komo re-detects the grant at runtime (≈2 s) — no relaunch needed.

### Signing

`build.sh` auto-selects a signing identity: a **Developer ID Application** cert
if present (for distribution + notarization — adds hardened runtime & secure
timestamp), else an **Apple Development** cert, else ad-hoc. Override with
`KOMO_SIGN_ID="Apple Development: you@example.com (TEAMID)" ./build.sh`.

Use a **stable** identity (Apple Development is fine for personal use): macOS
keys the Input-Monitoring grant to the code signature, so a stable signature
means the grant **survives rebuilds**. Ad-hoc signing changes every build and
forces a re-grant each time.

If a permission prompt won't reappear after fiddling, clear the stale decision:

```bash
tccutil reset ListenEvent uk.icoco.komo
```

To **distribute to other Macs**, create a *Developer ID Application* certificate
in the Apple Developer portal, then build (it's auto-detected) and notarize.

## Launch at login

Toggle **Launch at login** in the footer (uses `SMAppService`). A stats tracker
is most useful when it starts with your session.

## How it works

| Concern | Approach |
|---|---|
| Menu-bar presence | SwiftUI `MenuBarExtra` (`.window` style) with a custom bunny template icon; `LSUIElement` hides the Dock icon. |
| Keyboard counting | A listen-only `CGEventTap` (`.cgSessionEventTap`). Creating the tap is what registers Komo for Input Monitoring; plain `NSEvent` global keyboard monitors neither register nor receive on recent macOS. |
| Mouse counting | `NSEvent.addGlobalMonitorForEvents` for clicks and movement (no permission needed). Global-only, so interacting with Komo's own popover never inflates the stats. |
| Per-key identity | ANSI virtual key codes (physical positions), so counts are layout-independent; keypad digits fold into the same buckets; keys outside the visible heat-map are ignored. |
| Distance | `NSEvent` deltas summed in points, converted to metres using the display's physical size (`CGDisplayScreenSize`). Approximate on mixed-DPI multi-monitor setups. |
| Persistence | Per-day JSON in `~/Library/Application Support/Komo/stats.json`. Autosaves every 5 s and flushes on quit / power-off. A corrupt file is backed up, not discarded. |
| Performance | High-frequency events mutate plain storage; UI snapshots & disk writes are coalesced on `.common`-mode timers so they keep firing during menu tracking. |

## Project layout

```
Sources/Komo/
  KomoApp.swift        @main App + AppDelegate (monitor lifecycle, permission re-detect, --snapshot/--icon/--appicon CLI)
  InputMonitor.swift   CGEventTap (keyboard) + NSEvent (mouse) → counts
  StatsStore.swift     Counters, per-day JSON persistence, incremental all-time aggregate
  StatsView.swift      The popover UI (heat-map, tiles, controls)
  HeatColor.swift      Heat-map color ramp + legend gradient
  KeyCodeMap.swift     ANSI keycode → label, heat-map layout
  PermissionHelper.swift  Input Monitoring detection / request
  LoginItem.swift      Launch-at-login via SMAppService
  ScreenMetric.swift   Points → metres
  MenuBarIcon.swift    Bunny menu-bar template image
  AppIconRenderer.swift  Bunny app-icon master (used by Tools/gen_icon.sh)
  SnapshotRenderer.swift  Offscreen PNG render of the UI (design review)
Resources/Info.plist   LSUIElement, bundle id uk.icoco.komo, icon
build.sh               Compile + assemble + sign the .app
Tools/                 Icon generator
```

## Manual verification

1. Launch Komo; click the keyboard icon in the menu bar.
2. Move the mouse and click — **Left/Right/Travel** rise immediately.
3. Grant Input Monitoring, then type — the heat-map lights up and the headline
   climbs.
4. Quit and relaunch — yesterday's and today's numbers are still there.
