## Context

See [proposal.md](proposal.md) for motivation and
[`macos-27-menu-bar-visibility`](specs/macos-27-menu-bar-visibility/spec.md)
for the behavior contract. The macOS 27 direct-build engine asks macOS to show
only an allow-list of system-item identifiers and application bundle
identifiers (the restriction behind assessment mode); everything else is
hidden. The first iteration of this change built that allow-list from an
Accessibility snapshot of visible extras and aborted the collapse when a
visible extra had no bundle identifier.

## Evidence

Measured on macOS 27.2 (26B123), notch display, 2026-11-10, with a standalone
harness calling the same private API and `MenuBarAgent`'s own log
(`com.apple.menubar`, categories `visibilityRestriction`, `statusItems`,
`analytics`) as ground truth:

- `MBSystemItemIdentifier.allCases` has 9 cases, raw values 0–8, stored as
  8-byte integers; the bridge reads them correctly. Observed mapping: 0
  battery, 2 clock, 6 Wi-Fi, 8 Control Center; the rest matched no item
  present on the test machine.
- System controls are children of `MenuBarAgent`'s `AXExtrasMenuBar` hosting
  views and carry an `AXIdentifier` (`com.apple.menuextra.battery`, `.wifi`,
  `.controlcenter`, `.clock`, `.focusmode`). A system control hidden by a
  restriction disappears from that tree; this tree was consistent in every
  probe.
- Focus (`com.apple.menuextra.focusmode`) is hidden by every restriction
  tried: identifiers 0–8, 0–255, out-of-range values, thirteen candidate owner
  bundle identifiers, and every running application's bundle identifier.
- Third-party snapshots are unreliable. After a restriction changes, processes
  whose items are visible (`com.apple.TextInputMenuAgent`, Hidden Bar) return
  `kAXErrorNoValue` for `AXExtrasMenuBar`, while hidden items keep reporting
  stale frames. After a release most applications report nothing for several
  seconds or longer. One auto-collapse 30 s after an expand left the
  input-source menu off the allow-list and `MenuBarAgent` hid it; the collapse
  before and after kept it.
- Allowing `com.apple.TextInputMenuAgent` by bundle identifier keeps the
  input-source menu visible. Allowing a bundle that owns no item is harmless.
- One locally built, ad-hoc signed app (StayAwake) is logged by `MenuBarAgent`
  with a `nil` owner; in the one trial that produced a reading, allowing its
  bundle identifier did not keep it visible. Not re-measured.
- Live Activities mirrored from iPhone could not be produced on the test
  machine and are unverified.
- `NSLog` output from the app appears as `<private>` in the unified log.
- Signals for Focus turning on, recorded while toggling Focus through Control
  Center with the bar collapsed:
  - Nothing arrived from distributed notifications (observing every name),
    `NSWorkspace` notifications, eighteen guessed Darwin notification names,
    or ten preference domains polled for changes.
  - `DNDStateService` (private) refuses an unentitled client with an XPC
    error. `~/Library/DoNotDisturb` is not readable without Full Disk Access.
  - `INFocusStatusCenter` reports "not determined" for an unsigned tool; it
    was not tested inside the app and is believed to need a provisioned
    entitlement.
  - Accessibility notifications from `MenuBarAgent` showed no event
    attributable to the Focus item; the toggle itself ran through Control
    Center, so this test was noisy.
  - Control Center logs `Adding elements for modules ["FocusModes"]`
    (subsystem `com.apple.controlcenter`, category `menubar`) at the moment
    Focus turns on, and `Removing elements for …` about six seconds after it
    turns off. `/usr/bin/log stream` with that predicate, run as an ordinary
    admin user, delivered the first within a second. The category carried
    three messages in forty minutes, all from Focus toggles.

Hidden Bar's own controls, examined on the same machine:

- macOS 27 has its own overflow control: when the bar runs out of room,
  `MenuBarAgent` shows a button labelled "Show Hidden Menu Bar Items"
  (`menuBar.showOverflowItemsAccessibilityLabel`). Its strings name the SF
  Symbols `chevron.backward.2` and `chevron.forward.2`, and the agent links
  SwiftUI and moves items with its own spring animators (`FluidSpringAnimator`,
  `MenuBarOverflowComponent`, `MenuBarItemTransitionAnimator`). None of this
  is public API, and items of other processes are moved by the agent itself.
- Hidden Bar swaps the arrow's `NSImage` (custom PDF assets) without any
  transition. On macOS 27 it does so only when the collapse completes, after
  the post-activation system-control check, so the icons disappear about
  0.3 s before the arrow changes.

## Goals / Non-Goals

**Goals:**

- A collapse hides only items the user was observed to place in a hidden
  section; missing or late inventory data never hides anything.
- Items that appear while collapsed are visible unless known to be hidden.
- A system control that is on screen is never hidden by an automatic
  collapse. The user can still collapse by hand while it is shown.
- Hidden Bar is configured entirely from the arrow's menu, with only the
  settings people change.
- The arrow changes together with the icons, with no visual artefacts.
- Failures are diagnosable from Console.

**Non-Goals:**

- Independent placement of multiple extras from one app where the macOS API
  accepts only one application identity.
- Making the App Store build hide icons on macOS 27.
- Replacing the existing UI with a managed overflow bar.
- Position-based hiding of system menu-bar controls.
- Showing a non-allowable system control (Focus) and hiding third-party items
  at the same time. A separator-width fallback for that case is a possible
  follow-up.
- Detecting a non-allowable system control that appears while the bar is
  already collapsed.
- Animating other applications' icons; macOS moves them.
- Animating the arrow (dropped after it replayed on Space switches).
- A global shortcut, an always-hidden section, or Notch Overflow.

## Decisions

### Allow everything except what was observed hidden

The allow-list is every running application's bundle identifier (from
`NSWorkspace`, including agents such as `TextInputMenuAgent`), plus Hidden
Bar, minus the bundles whose remembered section is hidden. The Accessibility snapshot only updates
remembered sections: a bundle seen on the visible side becomes visible, one
seen on the hidden side becomes hidden, and one absent from the snapshot keeps
its previous section. A never-seen bundle is visible.

This inverts the failure mode: an inventory omission leaves an item visible
instead of removing it. The snapshot-derived allow-list is rejected because the
evidence shows the snapshot omits on-screen items. Aborting the collapse on any
uncertainty is rejected because uncertainty is the normal state on 27.2 and the
app would rarely collapse.

Frames are trusted only from a snapshot taken while no restriction is active,
as before, because hidden items report stale frames. A snapshot taken shortly
after a release may be sparse; under this rule a sparse snapshot changes
nothing.

### Remember sections across collapses and launches

Persist the bundle-to-section map in user defaults and load it at launch. The
launch-time collapse then no longer depends on the first snapshot being
complete. Entries for bundles not seen running for a long period may be
pruned; a stale entry only affects an app that is running again, where the
next reliable snapshot corrects it. Most-visible-wins stays the rule when one
bundle has items in several sections.

### Re-apply when the set of running applications changes

While a restriction is active, observe application launches and re-activate
with the recomputed allow-list (new restriction first, then release the old
one, as today). Terminations need no action. This covers items that appear
while collapsed without reading positions under a restriction.

### Verify system controls after each activation

Before activating from an unrestricted bar, read the set of system-control
identifiers from `MenuBarAgent`'s extras tree. After activation, read it
again. If any identifier disappeared, the restriction hides a system control
that cannot be allowed. Record the identifiers and remember them as
non-allowable for this macOS build, so later collapses can decide up front
without the hide-and-restore flicker. Identifier-to-item mapping is not
hard-coded beyond what verification learns at runtime, since the enumeration
can change in a point release.

What happens next depends on who asked for the collapse:

- An automatic collapse (launch, auto-collapse timer) is undone: release the
  restriction and hold the bar expanded. While held, the bar is unrestricted,
  so the tree is polled at a low rate; when the blocking control is gone, the
  pending collapse proceeds if auto-collapse is on.
- A collapse the user asked for (a click on the arrow) stands, and the bar
  stays collapsed until the user expands it. Automatic collapses do not learn
  from it: after the next expand they wait again while the control is shown.

Forbidding the manual collapse is rejected because the user wants to be able
to put the indicator away. Always collapsing is rejected because the silently
hidden Focus icon is the behavior this change exists to remove. An earlier
revision let one manual collapse turn automatic collapses back on until the
control was seen gone; it was dropped by decision, because macOS gives every
Focus the same identifier and a Focus that ended and restarted while the bar
stayed collapsed counted as the old one, and because a predictable "auto
collapse is off while Focus is on" is easier to live with.

### Do not detect controls that appear while collapsed

A control that appears while a restriction is active is absent from the
Accessibility tree, and the evidence shows no notification, preference, or
unentitled service that reports it. The one working signal, Control Center's
log line read through a `log stream` child process, was weighed and left out:
it adds a long-lived child process and depends on the wording of an Apple log
message, for a case that corrects itself at the next expand.

The consequence is stated rather than hidden: if a Focus turns on while the
bar is collapsed, its indicator is not shown until the bar is next expanded.
From that expand on, the hold and dismissal rules above apply. The engine
reads system controls only at collapse and expand, so a detection source can
be added later as another trigger for the same re-check without changing
those rules.

Briefly dropping the restriction on a timer to look is rejected because every
hidden icon would flash. Reading `~/Library/DoNotDisturb` is rejected because
it requires Full Disk Access. A Focus Filter (App Intents) is a public
alternative that was not tested; it needs per-Focus setup by the user and
covers only Focus.

### Keep private API use confined to the bridge

Unchanged: `MenuBarClientCore` calls stay in the Objective-C shim, with
selector checks, guarded calls, and the runtime `allCases` list. The list is
read once and cached.

### Remove the always-hidden section

There is one hidden section. The always-hidden status item, its preference,
the Option-click reveal, the engine protocol's always-hidden methods, and the
resolver's always-hidden boundary are removed in every build. Option-click on
the arrow toggles like a plain click.

On macOS 27 the section needs a restriction while the bar is expanded. That
restriction hides non-allowable controls just as a collapse does, so every
expand had to drop it, read the system controls, and reapply it, which showed
the always-hidden icons each time; and the section's presentation was a
second state machine next to collapse and hold. On macOS 13–26 it inflates a
second separator and works only together with "hide separators". Keeping it
was rejected for that cost and because it misbehaved in use.

Migration: remembered `alwaysHidden` entries are read as hidden, so those
icons stay out of sight while collapsed and show when expanded. The
`alwaysHiddenSectionEnabled` and `areSeparatorsHidden` keys are no longer read.
On macOS 13–26, icons left of the old always-hidden separator end up left of
the regular separator, which is the hidden section.

### Settings live in the arrow's menu

The preferences window and About are removed together with their view
controllers, storyboard scenes, the main menu's Preferences item, and assets
and strings only they use. Right-clicking the arrow (or left-clicking the
separator where it exists) opens a menu built fresh for each presentation, as
today:

    Start at Login            ✓
    Auto Collapse           ▸   Off / 5 s / 10 s / 15 s / 30 s / 1 min
    ─────────────
    Quit Hidden Bar         ⌘Q

Auto Collapse maps to the existing `isAutoHide` and
`numberOfSecondForAutoHide` keys: Off clears `isAutoHide`, a delay sets both.
A delay set from Terminal that is not in the list is shown as an extra checked
item so it is not silently replaced. Start at Login keeps the existing
`SMAppService` path and the alert when macOS refuses the change.

Removed with the window, by decision:

- The global shortcut: it needs a recorder UI. The HotKey registration and the
  package dependency go; a stored binding is ignored.
- Notch Overflow: macOS 27 has its own overflow control for icons behind the
  notch. The controller, its menu item, preference, and tests go.
- "Show preferences on launch" (nothing to show) and "Use the full menu bar on
  expanding" (the app stays an accessory app).

`hoverToExpand` stays a Terminal-only setting; it has no UI today.

### Switch the arrow with the icons, without animation

The arrow becomes an SF Symbol, `chevron.left` / `chevron.right` at 12 pt
semibold (the height and stroke of the bitmap it replaces), drawn centred on a
16 × 16 template canvas so the item keeps its width, in the same orientation
as the current glyphs. The direction is chosen explicitly from the UI's layout
direction, as `Assets` did: relying on `forward`/`backward` mirroring could
not be checked in a right-to-left session and would flip twice if combined
with the explicit choice. The double chevrons are left to the system's
overflow control so the two are not confused.

The glyph is the button's own image and changes without animation. A first
version drew the symbol in an `NSImageView` hosted in the button and changed it
with the symbol replace transition (crossfade on macOS 13 and with Reduce
Motion). In use, switching Spaces made the arrow flip back and forth before
settling, as if the last transition replayed. The cause could not be
confirmed without switching the user's Spaces: the transition does not show
up as layer animations, so an off-screen probe saw nothing. By decision the
animation was dropped rather than shipped with a suspected artefact; the
button image is what the status bar itself redraws on every Space.

The glyph follows the icons. The engine reports when hiding takes effect (on
macOS 27, when the restriction is active, before the system-control check),
and the controller switches the glyph then. If the check undoes an automatic
collapse, or activation fails, the glyph switches back. The legacy engine
reports at once.

Rejected: rotating one chevron, a custom animation on the button's layer (the
status bar owns that layer, and it would risk the same artefact), and
animating the item's width (macOS 27 ejects wide items).

### Readable diagnostics

Replace `NSLog` in the engine with `os.Logger` (subsystem = bundle identifier,
category `visibility`) and mark bundle identifiers, section names, and
system-control identifiers public. No window titles or user content are
logged.

## Risks / Trade-offs

- [Focus is on for long periods, so the bar stays expanded after each expand]
  → Accepted by decision; a click on the arrow collapses it until the next
  expand. Described in the manual. A separator-width fallback is listed as a
  follow-up, not attempted here.
- [A Focus turns on while the bar is collapsed] → Its indicator stays hidden
  until the next expand. Accepted by decision; described in the manual.
- [Allow-list grows to every running bundle] → A few hundred short strings per
  activation; activation is already asynchronous.
- [An item whose owner macOS cannot resolve is hidden by any restriction] →
  Seen once with a locally built app. Record the case in diagnostics; do not
  block collapsing on it.
- [Remembered sections go stale after the user rearranges icons while
  collapsed] → Not possible: hidden icons cannot be dragged; visible ones are
  re-read at the next unrestricted snapshot.
- [Private framework behavior changes in a point release] → Runtime checks and
  post-activation verification fail open.
- [The held auto-collapse is retried by the controller's auto-collapse timer]
  → No separate poll in the engine; each retry reads only the system-control
  tree until the control is gone.
- [Users lose the always-hidden section, the global shortcut, Notch Overflow,
  and two settings] → By decision; listed in the changelog. Always-hidden
  icons become ordinary hidden icons.
- [No window on first launch, so nothing explains the app] → The manual and
  README explain it; on macOS 27 the Accessibility prompt still appears at the
  first collapse.
- [On macOS 27, an undone automatic collapse now switches the arrow twice]
  → It matches what the icons do; the alternative leaves the arrow behind the
  icons on every collapse.
- [The arrow no longer animates] → Accepted by decision over a suspected
  replay artefact on Space switches; an animation can return once it can be
  checked on a live bar.

## Migration Plan

1. Rework the layout model, allow-list derivation, and section memory behind
   the existing direct-build flag; update unit tests.
2. Add system-control verification and the hold and dismissal rules.
3. Remove the always-hidden section, the preferences window and About, the
   global shortcut, and Notch Overflow; build the settings menu; update
   localized strings.
4. Switch the arrow at the engine's report, as the button's image.
5. Build the direct scheme, run the XCTest targets, lint string tables.
6. Validate on macOS 27.2: input-source menu across repeated auto-collapses,
   Focus turned on while expanded and while collapsed, a manual collapse
   during Focus followed by an expand, Focus off, an app launched while collapsed, the settings
   menu, and the arrow across Space switches.
   Live Activities are checked if one can be produced.
7. Ship in the direct distribution. Reverting restores the previous engine;
   the persisted section map is ignored by older builds.
