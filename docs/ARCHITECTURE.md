# Architecture

Hidden Bar is a single-process AppKit menubar utility with no third-party
dependencies. There is no helper app, no daemon, no network, and no window:
everything happens inside two `NSStatusItem`s and the arrow's menu.

## The core trick

macOS offers no API to hide other apps' menubar icons. Hidden Bar fakes it with
geometry: a separator status item whose **length is inflated to roughly the
width of the widest attached screen**, shoving every icon to its left off-screen.
Collapsing and expanding is just flipping that length between ~20pt and the
inflated value.

```mermaid
flowchart LR
    subgraph menubar [menu bar, right to left]
        direction RL
        ARROW["arrow item\n(toggle, variable length)"]
        SEP["separator item\n20pt expanded / ~2x screen width collapsed"]
        HIDDEN["other apps' icons\npushed off-screen when collapsed"]
    end
    ARROW --- SEP --- HIDDEN
```

Key consequences of this design:

- The menubar replicates on every display, so the collapse length derives from
  the **widest** screen (`NSScreen.screens`), never `NSScreen.main`, and is
  re-applied to the live item on `didChangeScreenParametersNotification`
  (display hot-plug).
- The length is bounded: `max(500, min(widestFrameWidth * 2, 10_000))`. macOS
  enforces a hard 10,000pt maximum on `NSStatusItem.length`.
- `isCollapsed` is derived state: `separator.length > 20`, deliberately not an
  equality check, so it survives the length being recomputed while collapsed.
- Icons macOS inserts to the LEFT of the separator (where new status items
  appear) are in the hidden zone by default; that is inherent to the trick.

## Topology

```mermaid
flowchart TD
    AD[AppDelegate] -->|owns| SBC[StatusBarController]
    AD -->|registers| SM["SMAppService.mainApp\n(login item, macOS 13+)"]
    SBC -->|2 status items| NSB[NSStatusBar.system]
    SBC -->|auto-hide| T["one-shot Timer\n(re-arms while pointer in menubar)"]
    SBC -->|opt-in| HM["global mouseMoved monitor\n(hover-to-expand, only if pref on)"]
    PREFS[Preferences facade] -->|UserDefaults| UD[(UserDefaults)]
    PREFS -->|posts| NC{{NotificationCenter\n.prefsChanged}}
    NC --> SBC
    SBC -->|right-click| SMENU[SettingsMenu] --> PREFS
    SBC -->|glyph| ARR[StatusBarArrow]
```

- **`AppDelegate`** (entry): registers default prefs, runs the one-shot legacy
  login-item migration, owns the `StatusBarController`.
- **`StatusBarController`** (the product): the two status items,
  when to collapse/expand, auto-hide timer, interaction-awareness, hover-to-expand,
  self-restore of dragged-off items.
- **`MenuBarEngine`** (`Features/StatusBar/Engine/`): how hiding is achieved.
  The controller calls `collapse` / `expand` / `invalidateLayout` and never
  writes a status-item length itself; the engine reports through
  `onHidingChange` the moment icons are hidden or come back.
  `MenuBarEngineFactory` is the one place that picks an engine: the direct build
  on macOS 27 gets `NativeVisibilityEngine` (an allow-list restriction, see the
  manual), everything else `LegacyLengthEngine` (the length trick above).
- **`Preferences`** (facade enum): typed accessors over `UserDefaults`; setters
  post `NotificationCenter` notifications that the controller observes. The
  native engine also persists remembered sections (`menuBarSectionMemory`).
- **`SettingsMenu`**: the arrow's right-click menu (Start at Login, Auto
  Collapse, Quit), built fresh for every presentation.
- **`StatusBarArrow`**: the arrow's SF Symbol, set as the status button's image
  and changed without animation (a symbol transition replayed on Space
  switches).

## Behavior layers on the core trick

| Layer | Mechanism | Cost when unused |
|---|---|---|
| Auto-hide | one-shot `Timer` after expand; at fire, if the pointer sits in any screen's menubar band (`visibleFrame.maxY ... frame.maxY`), it re-arms instead of collapsing | none (single point-in-rect check at fire) |
| Hover-to-expand (opt-in) | global `.mouseMoved` monitor + 0.5s dwell timer; installed only when the `hoverToExpand` default is true at launch | zero: monitor not installed |
| Self-restore | `isVisible = true` forced on our items at launch; Cmd-dragging them off otherwise bricks the app (its only UI is those items) | none |

## Autostart

macOS 13+ `SMAppService.mainApp`: the app registers itself; the login item is
visible and revocable in System Settings > General > Login Items. On first
launch after upgrade, a one-shot migration deauthorizes the legacy
`com.dwarvesv.LauncherApplication` helper registration (the BTM database never
garbage-collects those; see Apple TN3111). The helper app itself is gone.

## Security posture

The App Store build is sandboxed (`com.apple.security.app-sandbox`); the direct
build is not, so it can read menu-bar positions through Accessibility. Both use
the hardened runtime, no network entitlement, no IPC surface, no shell or
subprocess use, and no third-party code. The opt-in hover monitor observes
pointer position only and discards event payloads.
A full-tree audit (2026-06) scored 9/10 with hygiene-level findings only.

## Known architectural limits

- **The notch**: hidden icons sit "under" the notch area on notched Macs; the
  trick cannot reveal them there. The real fix is a spillover/second-bar design
  (tracked in issues #357/#341/#148; candidate implementations in PRs #350/#358).
- **macOS 27**: the menu bar re-architecture breaks length-inflation hiding
  (issue #360). The direct build hides through a private allow-list API instead;
  the App Store build cannot hide there.
- **Other apps' open menus**: interaction-awareness is pointer-position-based;
  a pointer deep inside another app's open dropdown is below the menubar band,
  so the collapse can still fire there.
