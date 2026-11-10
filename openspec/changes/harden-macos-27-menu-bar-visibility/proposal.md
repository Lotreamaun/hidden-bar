## Why

The native visibility mechanism introduced for macOS 27 hides menu-bar items
the user never placed in a hidden section. Live testing on macOS 27.2
(2026-11-10, see [design.md](design.md#evidence)) confirmed three causes:

- The allow-list is rebuilt from an Accessibility snapshot on every collapse,
  and on 27.2 that snapshot is unreliable: processes whose items are on screen
  (the input-source menu, Hidden Bar itself) intermittently report no extras.
  Anything the snapshot misses is left off the allow-list and disappears.
- Items that appear while the bar is collapsed are not on the allow-list until
  the next collapse.
- Some system controls (Focus, confirmed; Live Activities, suspected) cannot be
  kept visible under a restriction by any system-item identifier or bundle
  identifier, so every collapse hides them.

Hidden Bar's own controls get in the way as well. The always-hidden section
does not work reliably: on macOS 27 it needs a restriction while the bar is
expanded, which collides with system controls such as Focus and flashes its
icons on every expand; on macOS 13–26 its icons show unless the separators are
hidden. The preferences window (a mock menu-bar illustration, a tutorial
popover, an About tab, and settings few people change) is more than the app
needs. Switching between collapsed and expanded also feels abrupt: the arrow's
image is swapped instantly, and on macOS 27 only after the icons have already
disappeared.

## What Changes

- Hide only what was positively observed in a hidden section. The allow-list
  becomes every running application minus the bundles last seen on the hidden
  side of the arrow; a bundle missing from a snapshot keeps its last known
  section. **Replaces** the earlier "abort collapse when a visible extra is
  unclassifiable" behavior.
- Remember sections across collapses and launches.
- Re-apply the restriction when an application launches while collapsed, so
  its item is visible unless it is known to be hidden.
- Identify system controls by their Accessibility identifier and verify after
  each activation that none disappeared. A system control that cannot be
  allowed (Focus) is not hidden by an automatic collapse while it is on
  screen: auto-collapse waits until the control goes away. The user can still
  collapse by hand; that choice is kept until the control leaves the menu
  bar.
- Accept one known gap: a control that cannot be allowed and that appears
  while the bar is already collapsed stays hidden until the next expand. The
  only working detection found is a log-stream workaround, which is left out
  by decision.
- Keep the complete runtime system-item identity set, the direct-build
  requirement, and fail-open behavior when the native API or Accessibility is
  unavailable.
- **BREAKING** Remove the always-hidden section in every build: its
  separator, its preference, the Option-click reveal, and engine support.
  Applications last seen in it count as hidden. Option-click on the arrow acts
  like a plain click.
- **BREAKING** Remove the preferences window and the About tab. Every setting
  lives in the arrow's right-click menu: Start at Login, Auto Collapse (Off,
  5, 10, 15, 30 seconds, 1 minute), and Quit. The global shortcut, Notch
  Overflow, "Show preferences on launch", and "Use the full menu bar on
  expanding" are removed; their stored preferences are ignored.
- Animate the arrow like the system's own controls: it becomes an SF Symbol
  chevron that switches with the system symbol replace transition (a
  crossfade on macOS 13 and with Reduce Motion), at the moment the icons are
  hidden or shown rather than after later checks.
- Make diagnostics readable in Console (they are currently redacted as
  `<private>`).
- Unit coverage for the new allow-list derivation, section memory, system
  control verification, the settings menu, and the moment the arrow switches.

## Capabilities

### New Capabilities

- `macos-27-menu-bar-visibility`: Safely classify and preserve menu-bar items
  while applying native visibility restrictions on macOS 27, and present
  Hidden Bar's arrow and its settings menu (every build).

### Modified Capabilities

- None.

## Impact

- Affects `NativeVisibilityEngine`, `LegacyLengthEngine`, the engine
  protocol, the Accessibility inventory and layout resolver, the native bridge
  boundary, `StatusBarController`, `AppDelegate`, `Preferences`,
  `Main.storyboard`, assets, and localized strings.
- Removes `PreferencesViewController`, `PreferencesWindowController`,
  `AboutViewController`, `NotchOverflowController`, their storyboard scenes
  and tests, and the HotKey package dependency.
- Hiding behavior changes only in the direct, non-sandboxed macOS 27 build;
  macOS 13–26 and the App Store build keep the legacy mechanism. The removals,
  the settings menu, and the arrow transition apply to every build.
- Adds one persisted preference (remembered sections) and stops reading
  several; no new dependency or public API is introduced.
