# Changelog

## Unreleased

### Removed
- The preferences window and the About tab. Hidden Bar has no window any more; nothing opens at launch.
- The always-hidden section, in every build. Icons you kept there are now in the hidden section: hidden when collapsed, shown when expanded. Option-click on the arrow now toggles like a plain click.
- The global shortcut, Notch Overflow (macOS 27 has its own button for icons behind the notch), "Show preferences on launch", and "Use the full menu bar on expanding". Their stored settings are ignored. The HotKey package is no longer a dependency.

### Changed
- All settings are in the arrow's right-click menu: Start at Login, Auto Collapse (Off, 5, 10, 15, 30 seconds, 1 minute; a delay set from Terminal is listed too), and Quit Hidden Bar.
- The arrow is now an SF Symbol. On macOS 27 it changes as the icons disappear instead of a moment later.

### Fixed
- macOS 27.2 (direct download build): icons that were never placed in a hidden section no longer disappear on collapse. Hidden Bar now hides only apps it last saw on the hidden side of the arrow and remembers that across collapses and restarts; an app missing from a reading (the input-source menu, for one) keeps its place and an app never seen stays visible.
- macOS 27.2 (direct download build): an app launched while the bar is collapsed is visible unless it was last seen hidden.
- macOS 27.2 (direct download build): menu-bar system controls (Control Center, clock, Wi-Fi, Sound, battery, and the microphone/camera indicators) stay visible when collapsing. The allow-list comes from the complete system-item set exposed by the running macOS instead of a fixed range.
- macOS 27.2 (direct download build): the Focus indicator, which macOS hides under any restriction, is no longer hidden by an automatic collapse. Auto collapse is off while it is shown and resumes when it is gone; clicking the arrow still collapses the bar. Known gap: a Focus turned on while the bar is collapsed shows at the next expand.
- macOS 27.2 (direct download build): menu-bar extras owned by helper or background processes follow their position relative to the arrow.
- macOS 27 (direct download build): diagnostics are readable in Console (subsystem `com.dwarvesv.minimalbar`, category `visibility`) instead of `<private>`.

### Known issues
- macOS 27 (direct download build): while the bar is collapsed, clicking the date and time does not open Notification Center. macOS refuses it under the restriction Hidden Bar hides icons with; expand the bar first.

## v1.11.1 (2026-09-18)

### Fixed
- macOS 27: the Preferences window showed a "Custom View" placeholder instead of the General/About tabs, and the label overlapped the window once clicked (#406).

## v1.11 (2026-09-18)

Requires macOS 13 Ventura or later. (Pre-Ventura users: stay on
[v1.10](https://github.com/dwarvesf/hidden/releases/tag/v1.10).)

### Added
- Opt-in hover-to-expand: set `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true` to expand the bar when the pointer dwells in the menu bar.
- Right-clicking the expand/collapse arrow now opens the same context menu as the separator, so Preferences is reachable from the control you already click.

### Fixed
- macOS 27 (direct download build): hiding works again (#360) using macOS 27's native menu-bar visibility instead of widening the separator, which macOS 27 ejects from the bar. The arrow is the boundary: icons ⌘-dragged to its left hide when collapsed. Needs the Accessibility permission, and Hidden Bar must run from /Applications. Hiding is per app, and macOS's own items always stay visible. The App Store build is unchanged for now.
- Enabling the always-hidden section at runtime no longer creates an invisible (0pt) separator.
- Multi-display: the collapse width is now sized for the widest attached screen, so icons no longer leak on wider external monitors; the width re-applies on display hot-plug.
- Auto-collapse no longer fires while you are interacting with the menu bar (the timer defers and re-arms while the pointer is in the bar).
- The Preferences window no longer closes when auto-collapse fires with "use full menu bar on expanding" enabled (#170, #66, #151).
- Status items that were dragged off the bar are restored at launch instead of leaving the app unreachable.
- Fixed constraint and observer leaks in the tutorial view rebuild.
- Tutorial strings and F-key shortcut labels now render correctly (no more private-use glyphs).

### Changed
- Start-at-login now uses `SMAppService` (macOS 13+); the legacy launcher helper was removed and any leftover login item is deauthorized automatically on first launch.
- Pinned the HotKey dependency to an exact version and removed an unused file-access entitlement and dead code (no behavior change).

### Known / in progress
- macOS 27, App Store build: hiding still does not work (#360). Native hiding needs Accessibility reads that the App Sandbox blocks; an App Store approach is tracked separately.
- New menu-bar icons can appear in the hidden zone because macOS inserts them at the far left; ⌘-drag them to the right of the separator (see the manual). A built-in pin is part of the planned redesign.
