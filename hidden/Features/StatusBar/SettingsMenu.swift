//
//  SettingsMenu.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// The arrow's right-click menu, the only place Hidden Bar is configured. Built
// fresh for every presentation from the current settings, so it never shows a
// stale checkmark.
final class SettingsMenu: NSObject {
    // The auto-collapse delays offered, in seconds.
    static let delays: [TimeInterval] = [5, 10, 15, 30, 60]

    struct Settings: Equatable {
        var startsAtLogin: Bool
        var autoCollapses: Bool
        var autoCollapseDelay: TimeInterval
    }

    private let toggleStartAtLogin: () -> Void
    // nil turns auto collapse off; a delay turns it on with that delay.
    private let chooseAutoCollapse: (TimeInterval?) -> Void

    init(toggleStartAtLogin: @escaping () -> Void,
         chooseAutoCollapse: @escaping (TimeInterval?) -> Void) {
        self.toggleStartAtLogin = toggleStartAtLogin
        self.chooseAutoCollapse = chooseAutoCollapse
    }

    // The offered delays plus one set from Terminal, so a custom value is shown
    // rather than silently replaced.
    static func listedDelays(current: TimeInterval) -> [TimeInterval] {
        guard current > 0, !delays.contains(current) else { return delays }
        return (delays + [current]).sorted()
    }

    static func title(forDelay seconds: TimeInterval) -> String {
        if seconds == 60 {
            return "1 minute".localized
        }
        return String(format: "%ld seconds".localized, Int(seconds))
    }

    func makeMenu(for settings: Settings) -> NSMenu {
        let menu = NSMenu()

        let login = NSMenuItem(title: "Start at Login".localized, action: #selector(startAtLoginChosen), keyEquivalent: "")
        login.target = self
        login.state = settings.startsAtLogin ? .on : .off
        menu.addItem(login)

        let delays = NSMenu()
        let off = NSMenuItem(title: "Off".localized, action: #selector(autoCollapseChosen(_:)), keyEquivalent: "")
        off.target = self
        off.state = settings.autoCollapses ? .off : .on
        delays.addItem(off)
        delays.addItem(.separator())
        for delay in Self.listedDelays(current: settings.autoCollapseDelay) {
            let item = NSMenuItem(title: Self.title(forDelay: delay), action: #selector(autoCollapseChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = delay
            item.state = settings.autoCollapses && delay == settings.autoCollapseDelay ? .on : .off
            delays.addItem(item)
        }
        let autoCollapse = NSMenuItem(title: "Auto Collapse".localized, action: nil, keyEquivalent: "")
        autoCollapse.submenu = delays
        menu.addItem(autoCollapse)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hidden Bar".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func startAtLoginChosen() {
        toggleStartAtLogin()
    }

    @objc private func autoCollapseChosen(_ sender: NSMenuItem) {
        chooseAutoCollapse(sender.representedObject as? TimeInterval)
    }
}
