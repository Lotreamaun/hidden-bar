# Manual

Everything Hidden Bar can do, including the parts with no UI.

## Basics

- **Left-click the arrow** (`<` / `>`): expand or collapse the hidden section.
  Option-click does the same.
- **Right-click the arrow** or **left-click the separator** (`|`): the settings
  menu, see below.
- **⌘-drag** icons in the menu bar to move them across the separator: icons to
  the separator's left are hidden when collapsed.

### macOS 27, direct download build

The direct (non-App Store) build hides icons natively on macOS 27, and the
**arrow itself is the boundary**: there is no `|` separator. ⌘-drag icons to
the arrow's left to hide them when collapsed, to its right to keep them
visible.

- Needs **Accessibility** permission (System Settings › Privacy & Security ›
  Accessibility) to see where your icons are. Without it the bar stays
  expanded.
- **Only what Hidden Bar saw on the hidden side is hidden.** It reads the icon
  positions while the bar is expanded and remembers, per app, the last side it
  saw the app on. An app it has never seen, or one it could not read this
  time, stays visible. The memory survives restarts of Hidden Bar.
- Because of that, a new app's icon that macOS drops left of the arrow is
  hidden only once Hidden Bar has read it there, which happens when the bar
  collapses from the expanded state. ⌘-drag it right of the arrow to keep it.
- An app launched while the bar is collapsed is visible straight away, unless
  it was last seen on the hidden side.
- Hiding is per app: an app with several icons hides or shows them together,
  and stays visible if any of its icons is right of the arrow. The same rule
  applies to icons owned by helper or background processes.
- macOS's own items (clock, Wi-Fi, Sound, Control Center, battery, and the
  microphone/camera indicators) always stay visible, even when they sit to the
  left of the arrow. They are not part of Hidden Bar's placement.
- Run Hidden Bar from `/Applications`; macOS only recognizes that copy as
  Hidden Bar, and a copy elsewhere hides its own arrow.

#### Focus and other controls macOS will not keep visible

macOS hides the **Focus** indicator under any native restriction; no setting
of Hidden Bar's can keep it visible while the bar is collapsed. (Live
Activities mirrored from iPhone may behave the same way; this is unverified.)
Hidden Bar therefore does the following:

- While the Focus indicator is in the menu bar, **automatic collapses wait**
  (the launch-time collapse and the auto-collapse timer). The bar collapses by
  itself once the indicator is gone, if auto collapse is on.
- **You can still collapse by hand** (click the arrow). That hides the
  indicator until you expand the bar again. Automatic collapses stay off
  while Focus is on, also after a manual collapse.
- **Known gap**: a Focus that turns on while the bar is already collapsed is
  not shown until you next expand the bar. macOS gives no usable signal for
  it.
- The first time Hidden Bar meets such a control after a launch, the
  indicator disappears for a moment and comes back as the collapse is undone;
  the arrow turns and turns back with it.

#### Notification Center

While the bar is collapsed, **clicking the date and time does not open
Notification Center**. The restriction Hidden Bar hides icons with is macOS's
assessment (exam) mode, and Notification Center refuses to open under it, even
when nothing would be hidden. Expand the bar, then click the clock.

Diagnostics: Console.app, subsystem `com.dwarvesv.minimalbar`, category
`visibility`. Each collapse logs the sections read and the apps hidden; a
collapse that waits logs the control it is waiting for.

## Settings menu

Hidden Bar has no window. Right-click the arrow:

| Item | What it does |
|---|---|
| Start at Login | Login item via `SMAppService` (macOS 13+); revocable in System Settings > General > Login Items. If macOS refuses the change, the checkmark stays as it was and an alert says where to allow it |
| Auto Collapse ▸ | Off, or collapse again 5, 10, 15 or 30 seconds or 1 minute after expanding. A delay set from Terminal is listed too |
| Quit Hidden Bar (⌘Q) | Quits |

Removed in this version: the preferences window and About, the always-hidden
section, the global shortcut, Notch Overflow (macOS 27 has its own button for
icons behind the notch), "Show preferences on launch", and "Use the full menu
bar on expanding". Icons you kept in the always-hidden section are now in the
hidden section: hidden when collapsed, shown when expanded.

## Behaviors you get for free

- **It won't collapse mid-use**: while your pointer is anywhere in the menu bar,
  the auto-collapse countdown defers and restarts; it resumes when you leave.
- **Self-repair**: if the arrow or separator was ⌘-dragged off the bar (which
  used to make the app unreachable forever), they come back on next launch.
- **Display changes**: plugging in or removing monitors re-sizes the hidden zone
  for the widest attached screen automatically.

## Hidden settings (Terminal)

All via `defaults`; quit and relaunch the app after changing them.

```sh
# expand by hovering the menu bar for ~0.5s (off by default)
defaults write com.dwarvesv.minimalbar hoverToExpand -bool true

# auto-collapse delay in seconds (the menu offers a fixed list and lists this value too)
defaults write com.dwarvesv.minimalbar numberOfSecondForAutoHide -float 5

# force the app language regardless of system order (issue #287)
defaults write com.dwarvesv.minimalbar AppleLanguages '(en)'
```

To undo any of them: `defaults delete com.dwarvesv.minimalbar <key>`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons I want visible got hidden after an update | ⌘-drag them to the right of the separator |
| Login item missing after denying it once | System Settings > General > Login Items: re-enable Hidden Bar, then turn Start at Login off and on in the arrow's menu |
| A ghost "LauncherApplication" login item from old versions | Launch the current version once; it deauthorizes the legacy item automatically |
| App language stuck | See the `AppleLanguages` command above, or System Settings > General > Language & Region > Applications |
| Nothing hides on macOS 27 | The App Store build cannot hide there (issue #360); use the direct download build and grant Accessibility |
| A new or just-updated app's icon shows up already hidden | Expected on macOS 13–26, see "Why new icons start hidden" below; ⌘-drag it to the right of the separator once |
| macOS 27: the bar does not auto-collapse | A Focus is on: auto collapse is off while it is, see "Focus and other controls" above; click the arrow to collapse. Otherwise check the Accessibility permission |
| macOS 27: the Focus indicator is missing | It turned on while the bar was collapsed; expand the bar |
| macOS 27: clicking the date and time does not open Notification Center | Expected while the bar is collapsed, see "Notification Center" above; expand the bar |
| macOS 27: an icon left of the arrow is not hidden | Hidden Bar has not seen it there yet; expand and collapse once more. If it persists, the app may have no bundle identifier (logged in Console) |

### Why new icons start hidden

On macOS 13–26, Hidden Bar hides icons by widening its separator so everything to the *left* of
it slides off-screen. macOS always inserts a brand-new menu-bar icon at the
far-left slot, which is inside that hidden zone, so a freshly launched or updated
app can appear "swallowed". This is macOS positioning behavior, not Hidden Bar
moving your icon: there is no way for one app to reposition another app's menu-bar
icon. The one-time fix is to ⌘-drag the icon to the right of the separator;
macOS remembers that placement per app. A built-in way to keep chosen icons
pinned is being explored as part of the larger menu-bar redesign.

## Requirements

macOS 13 Ventura or later. Pre-Ventura (10.13 - 12.x): use
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10), the last release
on the old autostart mechanism.
