## 1. Inventory and classification

- [x] 1.1 Extend the menu-bar inventory model to represent app, system-owner, and unclassifiable visibility identities.
- [x] 1.2 Enumerate helper and system processes that expose menu-bar extras without filtering them out before Accessibility inspection.
- [x] 1.3 Resolve each rendered extra into a section using its live frame and record the reason when a visible third-party identity is unsupported.

## 2. Native visibility safety

- [x] 2.1 Add a bridge adapter that obtains and validates the complete system-item identity set supported by the running macOS release.
- [x] 2.2 Build native allow-lists from visible third-party extras plus all supported system items, retaining the most-visible-wins rule for shared app identities.
- [x] 2.3 Make collapse fail open when any visible third-party rendered extra cannot be safely represented, preserving the expanded state and emitting diagnostics.
- [x] 2.4 Preserve the existing direct-build gating, runtime API checks, and Accessibility-unavailable behavior.

## 3. Automated verification

- [x] 3.1 Add resolver tests for helper-owned, SystemUIServer-owned, and unclassifiable extras in visible and hidden sections.
- [x] 3.2 Add native-engine tests proving that unclassifiable visible extras abort collapse without creating an assertion.
- [x] 3.3 Add tests for shared application identities and all supported system controls remaining visible after collapse.

## 4. macOS 27.2 validation and documentation

- [x] 4.1 Build the direct scheme and run the relevant XCTest targets.
- [ ] 4.2 Validate on macOS 27.2 that Notification Center, Control Center, microphone/camera, and other system controls remain visible, and validate helper-owned and multi-extra app icons by placement.
- [x] 4.3 Update the manual and release notes with third-party placement behavior, always-visible system controls, and the fail-open outcome for unsupported visible third-party extras.

## 5. Hide only observed-hidden items (reworks 2.2, 2.3, 3.2)

- [x] 5.1 Change the layout model so a snapshot updates remembered sections instead of replacing them: seen bundles take their observed section, absent bundles keep theirs.
- [x] 5.2 Derive the allow-list as all running application bundle identifiers plus Hidden Bar, minus bundles remembered as hidden (and always-hidden when concealed); inject the running-applications source for tests.
- [x] 5.3 Remove the abort-on-unclassifiable-visible path from collapse and expanded presentation; keep the diagnostic for extras without a bundle identifier.
- [x] 5.4 Persist the bundle-to-section map in user defaults, load it at launch, and prune entries not seen for a long period.
- [x] 5.5 Re-activate with a recomputed allow-list when an application launches while a restriction is active.
- [x] 5.6 Read the supported system-item list once and cache it in the bridge.

## 6. System-control verification

- [x] 6.1 Add an inventory query for system-control identifiers from `MenuBarAgent`'s extras tree, behind the inventory protocol.
- [x] 6.2 Compare identifiers before and after activation and remember lost identifiers as non-allowable for the current macOS build.
- [x] 6.3 Distinguish user-requested from automatic collapses in the engine interface. Undo an automatic collapse that hides a non-allowable control and hold the bar expanded, polling at a low rate so the pending auto-collapse proceeds when the control leaves.
- [x] 6.4 Let a user-requested collapse stand, mark the hidden controls dismissed, let automatic collapses ignore dismissed controls, and clear the dismissal when the control is observed absent from an unrestricted bar.
- [x] 6.5 Look for a usable signal for Focus appearing while collapsed (result: only a `log stream` workaround; not adopted, see design).
- [x] 6.7 Drop the dismissal (supersedes part of 6.4): automatic collapses wait whenever a non-allowable control is shown, also after a manual collapse.
- [x] 6.6 Replace engine `NSLog` calls with `os.Logger` using public privacy for bundle identifiers, sections, and control identifiers.

## 7. Remove the always-hidden section (supersedes the earlier always-hidden presentation)

- [x] 7.1 Remove the always-hidden status item, the Option-click reveal and separator toggling, and the conceal-on-collapse logic from `StatusBarController`; make Option-click toggle like a plain click.
- [x] 7.2 Remove always-hidden support from the engine protocol, both engines, the layout resolver, and the allow-list derivation; read remembered always-hidden entries as hidden.
- [x] 7.3 Stop registering and reading `alwaysHiddenSectionEnabled` and `areSeparatorsHidden`.

## 8. Settings menu instead of the preferences window (supersedes the earlier preferences window rework)

- [x] 8.1 Build the arrow's menu: Start at Login with checkmark, an Auto Collapse submenu (Off, 5, 10, 15, 30 seconds, 1 minute, plus a stored custom delay as an extra checked item), a separator, and Quit Hidden Bar ⌘Q; keep the login-item failure alert.
- [x] 8.2 Remove the preferences window, About, their controllers and storyboard scenes, the main menu's Preferences item, and opening a window at launch.
- [x] 8.3 Remove the global shortcut (registration, stored binding, HotKey package) and Notch Overflow (controller, menu item, preference, tests).
- [x] 8.4 Remove the "Use the full menu bar on expanding" and "Show preferences on launch" settings; delete code, assets, and strings no longer referenced; add the menu titles to every string table.

## 9. Arrow transition

- [x] 9.1 Draw the arrow as `chevron.left` / `chevron.right` (direction chosen from the layout direction) in an image view hosted in the status button, keeping size, position, right-to-left direction, accessibility label, and press action.
- [x] 9.2 Switch the glyph with the symbol replace transition on macOS 14 and later and a crossfade on macOS 13 and with Reduce Motion; target the current state so rapid toggles end on the right glyph.
- [x] 9.4 Drop the arrow animation (supersedes the image view and transition of 9.1–9.2): set the symbol as the button's own image on a 16 × 16 canvas, change it without animation.
- [x] 9.3 Have the engines report when hiding takes effect and when a collapse is undone; switch the glyph on those reports instead of on the collapse result.

## 10. Tests

- [x] 10.1 Replace the abort-on-unclassifiable tests with tests for allow-list derivation: absent bundle keeps its section, never-seen bundle is allowed, empty snapshot changes nothing.
- [x] 10.2 Add tests for section persistence across engine instances and for re-activation on application launch.
- [x] 10.3 Add tests for system-control loss after activation: an automatic collapse is undone and held, a user-requested collapse stands and dismisses, a held collapse proceeds when the control leaves, and a dismissal ends when it leaves.
- [x] 10.4 Replace the always-hidden presentation tests with tests for reading remembered always-hidden entries as hidden.
- [x] 10.5 Add tests for the settings menu model: items and checkmarks, choosing a delay turns auto collapse on, Off turns it off, a custom delay is shown.
- [x] 10.8 Add tests for the arrow: the glyph is the button's template image at the old size, nothing is drawn over the button, an unchanged state leaves the image alone.
- [x] 10.7 Replace the dismissal tests: a manual collapse during Focus stands, and after the next expand automatic collapses wait again.
- [x] 10.6 Add engine tests for the hiding-took-effect report: sent on activation, followed by an undo report when an automatic collapse is held after activation, not sent when a collapse is declined before activation.

## 11. Build, validation, and documentation

- [x] 11.1 Build the direct scheme and run both XCTest targets with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; lint the string tables.
- [ ] 11.2 Validate on macOS 27.2: input-source menu survives repeated auto-collapses; with Focus on and the bar expanded, auto-collapse waits; a manual collapse during Focus sticks, and after the next expand auto-collapse waits again; after Focus off, auto-collapse resumes; Focus turned on while collapsed shows at the next expand; an app launched while collapsed is visible; the settings menu applies changes at once; the arrow looks right in light and dark mode, keeps its glyph when switching Spaces, and turns back when a held collapse is undone. Check Live Activities if one can be produced.
- [x] 11.3 Update the manual, runbook, README, and changelog: remove the always-hidden section, preferences window, About, global shortcut, and Notch Overflow; describe the settings menu and the arrow transition; keep the observed-hidden rule and the Focus behavior.
- [x] 11.4 Produce a runnable build and report its path; replace the installed copy only with the user's confirmation.
