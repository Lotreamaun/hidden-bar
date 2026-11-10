## Purpose

Protects visible menu-bar controls when Hidden Bar applies native visibility
restrictions on macOS 27 direct-download builds, and keeps Hidden Bar's own
controls (one hidden section, the arrow, and its settings menu) simple and
native in every build.

## ADDED Requirements

### Requirement: Preserve system menu-bar controls
When collapsing on macOS 27, the system SHALL keep every system menu-bar
control that the restriction can allow visible and interactive. System
controls SHALL not be hidden based on their position relative to the Hidden
Bar arrow. The system SHALL not hide any system control through an automatic
collapse: if an automatic collapse would hide one, the menu bar SHALL stay
expanded and a diagnostic SHALL name the control.

#### Scenario: System extra is in the hidden section
- **WHEN** a supported system-owned menu-bar extra is positioned on the hidden side of the Hidden Bar arrow
- **THEN** collapsing Hidden Bar keeps that extra visible and interactive

#### Scenario: Focus indicator is shown when auto-collapse fires
- **WHEN** the Focus indicator is in the menu bar, the user has not collapsed by hand since it appeared, and the auto-collapse timer fires
- **THEN** the Focus indicator stays visible, the menu bar stays expanded, and a diagnostic names the control

#### Scenario: Blocking control goes away
- **WHEN** the menu bar is held expanded because of a system control, auto-collapse is enabled, and that control leaves the menu bar
- **THEN** the menu bar collapses without further user action

### Requirement: Show system controls that appeared while collapsed at the next expand
When a system control that the restriction cannot allow appears while the menu
bar is collapsed, the system SHALL show it the next time the menu bar is
expanded, and from then on SHALL treat it as a control that is on screen. The
system SHALL not expand the menu bar by itself for this reason.

#### Scenario: Focus turns on while collapsed
- **WHEN** the menu bar is collapsed and the user turns on a Focus
- **THEN** the menu bar stays collapsed, and the Focus indicator is visible the next time it is expanded

#### Scenario: Expanded after Focus turned on
- **WHEN** a Focus turned on while collapsed, the user expands the bar, and the auto-collapse timer fires
- **THEN** the Focus indicator stays visible and the menu bar stays expanded until the user collapses it or the Focus ends

### Requirement: Honor a manual collapse while a system control is shown
The system SHALL collapse the menu bar when the user requests it by clicking
the arrow even if that hides a system control the restriction cannot allow.
Automatic collapses SHALL keep waiting while such a control is shown, also
after a manual collapse.

#### Scenario: User collapses during Focus
- **WHEN** the Focus indicator is shown and the user clicks the arrow to collapse
- **THEN** the menu bar collapses and stays collapsed until the user expands it

#### Scenario: User expands again during the same Focus
- **WHEN** the user collapsed by hand during a Focus, later expands the bar, and the auto-collapse timer fires
- **THEN** the menu bar stays expanded and the Focus indicator is visible

### Requirement: Hide only items observed in a hidden section
When collapsing on macOS 27, the system SHALL hide a third-party or
helper-owned menu-bar extra only if its owning application was last observed on
the hidden side of the arrow. An application that is missing from the current
inventory SHALL keep its last observed section, and an application that was
never observed SHALL remain visible.

#### Scenario: Helper-owned extra is in the visible section
- **WHEN** a helper process owns an extra positioned on the visible side of the Hidden Bar arrow
- **THEN** collapsing Hidden Bar keeps that extra visible and interactive

#### Scenario: Visible extra is missing from the inventory
- **WHEN** the input-source menu is on the visible side but its process reports no extras at collapse time
- **THEN** collapsing Hidden Bar keeps the input-source menu visible

#### Scenario: Inventory is empty after an expand
- **WHEN** a collapse follows an expand and no third-party process reports extras yet
- **THEN** the same items are hidden as in the previous collapse and no other item disappears

### Requirement: Keep items that appear while collapsed
While the menu bar is collapsed, the system SHALL keep the extras of a newly
launched application visible unless that application was previously observed
in a hidden section.

#### Scenario: Application launches while collapsed
- **WHEN** an application that was never observed launches and adds a menu-bar extra while the bar is collapsed
- **THEN** its extra is visible without expanding the bar

#### Scenario: Previously hidden application relaunches while collapsed
- **WHEN** an application last observed in the hidden section launches while the bar is collapsed
- **THEN** its extra stays hidden until the bar is expanded

### Requirement: Remember sections
The system SHALL retain each application's last observed section across
collapses and across launches of Hidden Bar.

#### Scenario: Hidden Bar restarts
- **WHEN** Hidden Bar is relaunched and collapses before any inventory is available
- **THEN** applications hidden before the restart are hidden and all others are visible

### Requirement: Maintain predictable placement semantics
For third-party and helper-owned extras whose application identity is
supported, the system SHALL derive the section from the extra's position
relative to the arrow when it is observed on an unrestricted menu bar. Extras
from the same application SHALL share one visibility outcome when macOS exposes
only an application-level identity.

#### Scenario: App icon is moved to the visible section
- **WHEN** a supported app-owned icon is positioned on the visible side and observed before collapse
- **THEN** the app's exposed menu-bar extras remain visible after collapse

#### Scenario: Multiple extras belong to one application
- **WHEN** one application owns extras in more than one section
- **THEN** the app remains visible if any of its extras are in the visible section

### Requirement: Offer a single hidden section
The system SHALL offer one hidden section and SHALL NOT offer an always-hidden
section. An application last observed in the former always-hidden section
SHALL be treated as hidden. Option-click on the arrow SHALL act like a plain
click.

#### Scenario: Update with the always-hidden section enabled
- **WHEN** a user who had the always-hidden section enabled launches the updated app
- **THEN** no always-hidden separator appears, and the icons that were in that section are hidden while collapsed and shown while expanded

#### Scenario: Option-click on the arrow
- **WHEN** the user Option-clicks the arrow
- **THEN** the menu bar toggles between collapsed and expanded as with a plain click

### Requirement: Preserve existing availability behavior
The native visibility mechanism SHALL remain limited to the direct,
non-sandboxed build on macOS 27 and later. If Accessibility permission or the
native visibility API is unavailable, the system SHALL leave the menu bar
expanded.

#### Scenario: Accessibility permission is unavailable
- **WHEN** a user requests collapse without Accessibility permission
- **THEN** the system requests permission at most once per launch and leaves the menu bar expanded

### Requirement: Provide readable diagnostics
The system SHALL record, in a form readable in Console without private-data
redaction, the sections applied at each collapse and the reason whenever a
collapse is declined.

#### Scenario: Collapse is declined
- **WHEN** a collapse is declined because of a system control or an unavailable API
- **THEN** a log entry states the reason and the identifiers involved

### Requirement: Offer settings in the arrow's menu
The system SHALL NOT present a preferences or About window. Right-clicking the
arrow, or left-clicking the separator where one is shown, SHALL open a menu
containing, in order: Start at Login with a checkmark when enabled; an Auto
Collapse submenu with Off, 5 seconds, 10 seconds, 15 seconds, 30 seconds and 1
minute, with a checkmark on the current choice; a separator; and Quit Hidden
Bar (⌘Q). A delay stored outside that list SHALL appear as an additional
checked item. Changes SHALL take effect immediately and persist across
launches. Every title SHALL be localized in every string table.

#### Scenario: Menu is opened
- **WHEN** the user right-clicks the arrow
- **THEN** the menu shows Start at Login, Auto Collapse, and Quit Hidden Bar, with checkmarks matching the current settings, and nothing else

#### Scenario: Delay is chosen while auto collapse is off
- **WHEN** auto collapse is off, the bar is expanded, and the user chooses 10 seconds
- **THEN** auto collapse is on with a 10-second delay and the countdown starts

#### Scenario: Auto collapse is turned off
- **WHEN** the user chooses Off
- **THEN** no automatic collapse happens until a delay is chosen again

#### Scenario: Login item cannot be changed
- **WHEN** the user toggles Start at Login and macOS refuses the change
- **THEN** the checkmark shows the actual state and the user is told to allow Hidden Bar in System Settings › General › Login Items

#### Scenario: App launches
- **WHEN** Hidden Bar launches
- **THEN** no window opens and no global shortcut is registered

### Requirement: Switch the arrow with the icons
The arrow SHALL be drawn as a system chevron symbol set as the status button's
image, and SHALL change between its collapsed and expanded glyphs without
animation. The glyph SHALL change when icons are hidden or shown, not after
later checks, and SHALL change back when a collapse is undone or fails. The
arrow SHALL keep its width, its direction in right-to-left languages, and its
accessibility label and press action, and SHALL NOT change when nothing is
hidden or shown.

#### Scenario: Collapse takes effect
- **WHEN** a collapse takes effect
- **THEN** the arrow shows the collapsed glyph as the icons disappear

#### Scenario: Automatic collapse is undone
- **WHEN** an automatic collapse is undone because it hid a system control
- **THEN** the arrow shows the expanded glyph again

#### Scenario: Switching Spaces
- **WHEN** the user switches to another Space or desktop
- **THEN** the arrow keeps its glyph without flipping

#### Scenario: Rapid toggling
- **WHEN** the user toggles the bar several times quickly
- **THEN** the arrow ends on the glyph matching the final state
