//
//  MenuBarEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// StatusBarController decides WHAT the user wants (collapsed or expanded, which
// sections exist); an engine decides HOW the menu bar is made to do it. Keeping
// the mechanics here lets an OS release that changes menu-bar layout (#360) get
// its own engine without version checks spreading through the controller.
protocol MenuBarEngine: AnyObject {
    var state: MenuBarEngineState { get }

    func collapse(origin: CollapseOrigin, completion: @escaping (CollapseResult) -> Void)
    func expand()

    // Called with true the moment icons are hidden and with false when a collapse
    // that already hid them is undone, ahead of the collapse's completion, so the
    // arrow can change together with the icons.
    var onHidingChange: ((Bool) -> Void)? { get set }

    // Whether the user's ⌘-drag arrangement lets the engine hide anything: its
    // hiding boundary must sit on the hidden side of the arrow. The controller
    // does not collapse otherwise.
    var isArrangementValid: Bool { get }

    // Display geometry changed. Re-applies the collapse to the live items when
    // collapsed, so a hot-plug does not leave a stale length behind (PR #354).
    func invalidateLayout()
}

enum MenuBarEngineState {
    case expanded
    case calibrating
    case collapsed
    case unavailable
}

// Who asked for the collapse. A system control the engine cannot keep visible
// stops an automatic collapse but not one the user asked for.
enum CollapseOrigin {
    case user
    case automatic
}

enum CollapseResult {
    case collapsed
    case unavailable
    // Declined because a system control would be hidden; the bar stays expanded
    // and the caller may try again later.
    case held
}

enum MenuBarOrder {
    // True when `item` sits on the hidden side of `boundary`: to its left in a
    // left-to-right layout, to its right otherwise. False when either is not on
    // screen, since nothing can be judged then.
    static func isItem(_ item: NSStatusItem?, onHiddenSideOf boundary: NSStatusItem?) -> Bool {
        guard let itemX = item?.button?.window?.frame.origin.x,
              let boundaryX = boundary?.button?.window?.frame.origin.x else { return false }
        return Constant.isUsingLTRLanguage ? boundaryX >= itemX : boundaryX <= itemX
    }
}

// The controller owns and recreates the status items; engines only borrow them.
protocol MenuBarItemProvider: AnyObject {
    var toggleItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
}
