//
//  MenuBarLayout.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// Which side of Hidden Bar's boundary a menu-bar item is on, read from where the
// user ⌘-dragged it:
//
//     LTR:  [ hidden ] > [ visible ]
//                      ^
//                      the boundary (the arrow on macOS 27, the separator before)
enum MenuBarSection: Int, Comparable {
    case visible
    case hidden

    static func < (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum MenuBarVisibilityIdentity: Equatable {
    case application(bundleIdentifier: String)
    case system(ownerBundleIdentifier: String?)
    case unclassifiable(reason: String)
}

// One status item another process owns. Accessibility exposes its process and
// frame, but not a per-extra identifier.
struct MenuBarInventoryItem: Equatable {
    let identity: MenuBarVisibilityIdentity
    let frame: CGRect
    let processIdentifier: pid_t
    let processName: String?

    init(identity: MenuBarVisibilityIdentity,
         frame: CGRect,
         processIdentifier: pid_t = 0,
         processName: String? = nil) {
        self.identity = identity
        self.frame = frame
        self.processIdentifier = processIdentifier
        self.processName = processName
    }

    init(bundleIdentifier: String?, frame: CGRect) {
        if let bundleIdentifier = bundleIdentifier {
            identity = MenuBarLayoutResolver.systemItemOwners.contains(bundleIdentifier)
                ? .system(ownerBundleIdentifier: bundleIdentifier)
                : .application(bundleIdentifier: bundleIdentifier)
        } else {
            identity = .unclassifiable(reason: "missing bundle identifier")
        }
        self.frame = frame
        processIdentifier = 0
        processName = nil
    }

    var diagnosticDescription: String {
        let owner: String
        switch identity {
        case .application(let bundleIdentifier): owner = bundleIdentifier
        case .system(let bundleIdentifier): owner = bundleIdentifier ?? "system process"
        case .unclassifiable(let reason): owner = reason
        }
        return "owner=\(owner), pid=\(processIdentifier), frame=\(NSStringFromRect(frame))"
    }
}

protocol MenuBarInventoryProviding: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization()
    // Every other app's status items, delivered on the main queue. Only meaningful
    // while nothing is hidden: once a native visibility assertion is active,
    // hidden items report stale frames.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void)

    // Accessibility identifiers of the system controls macOS draws in the menu
    // bar (Wi-Fi, Focus, clock...), delivered on the main queue. nil when they
    // cannot be read. Unlike third-party items this tree stays consistent under a
    // restriction: a control that is hidden drops out of it.
    func systemControls(completion: @escaping (Set<String>?) -> Void)
}

struct MenuBarLayout: Equatable {
    // One section per owning bundle, because hiding is per bundle.
    var sections: [String: MenuBarSection]
    var unclassifiableVisibleItems: [MenuBarInventoryItem] = []

    func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }

    var hasUnclassifiableVisibleItems: Bool {
        return !unclassifiableVisibleItems.isEmpty
    }
}

// The last section each application was observed in. A snapshot only updates the
// bundles it contains: one missing from it keeps its section, and one never seen
// is unknown, which the engine treats as visible. Persisted so the first collapse
// after a launch does not depend on a complete first snapshot.
final class MenuBarSectionMemory {
    private struct Entry {
        var section: MenuBarSection
        var lastSeen: Date
    }

    static let defaultsKey = "menuBarSectionMemory"

    private let defaults: UserDefaults
    private let key: String
    private var entries: [String: Entry] = [:]

    // Entries not seen for `retention` are dropped at load. A stale entry would
    // only affect an app that runs again, where the next snapshot corrects it.
    init(defaults: UserDefaults = .standard,
         key: String = MenuBarSectionMemory.defaultsKey,
         retention: TimeInterval = 90 * 24 * 60 * 60,
         now: Date = Date()) {
        self.defaults = defaults
        self.key = key
        let stored = defaults.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        for (bundle, value) in stored {
            // 2 was the always-hidden section, which is now part of the hidden one.
            guard let raw = value["section"], let section = MenuBarSection(rawValue: min(Int(raw), MenuBarSection.hidden.rawValue)),
                  let seen = value["seen"] else { continue }
            let lastSeen = Date(timeIntervalSince1970: seen)
            if now.timeIntervalSince(lastSeen) <= retention {
                entries[bundle] = Entry(section: section, lastSeen: lastSeen)
            }
        }
    }

    func section(of bundle: String) -> MenuBarSection? {
        return entries[bundle]?.section
    }

    func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return entries.filter { wanted.contains($0.value.section) }.map(\.key).sorted()
    }

    func update(with sections: [String: MenuBarSection], at date: Date = Date()) {
        guard !sections.isEmpty else { return }
        for (bundle, section) in sections {
            entries[bundle] = Entry(section: section, lastSeen: date)
        }
        save()
    }

    private func save() {
        let stored = entries.mapValues { ["section": Double($0.section.rawValue),
                                          "seen": $0.lastSeen.timeIntervalSince1970] }
        defaults.set(stored, forKey: key)
    }
}

enum MenuBarLayoutResolver {
    // Bundles whose items are macOS's own controls (clock, Wi-Fi, Control Center...).
    // They cannot be hidden by bundle, so they are left out of the layout and kept
    // visible separately.
    static let systemItemOwners: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]

    static func resolve(inventory: [MenuBarInventoryItem],
                        separatorFrame: CGRect,
                        isLTR: Bool,
                        excludingBundle ownBundle: String?) -> MenuBarLayout {
        var sections: [String: MenuBarSection] = [:]
        var unclassifiableVisibleItems: [MenuBarInventoryItem] = []
        for item in inventory {
            let section = self.section(of: item.frame, separatorFrame: separatorFrame, isLTR: isLTR)
            switch item.identity {
            case .system:
                // System controls are always allowed by the native bridge.
                continue
            case .unclassifiable:
                if section == .visible {
                    unclassifiableVisibleItems.append(item)
                }
            case .application(let bundle):
                guard bundle != ownBundle else { continue }
                // One app can own several items, but hiding applies to the whole
                // bundle. The most visible item wins so an icon the user kept
                // visible is never hidden because a sibling sits in the hidden
                // section.
                sections[bundle] = min(sections[bundle] ?? section, section)
            }
        }
        return MenuBarLayout(sections: sections,
                             unclassifiableVisibleItems: unclassifiableVisibleItems)
    }

    static func section(of frame: CGRect, separatorFrame: CGRect, isLTR: Bool) -> MenuBarSection {
        // Distance toward the arrow side: positive means on the visible side.
        let towardArrow = isLTR ? frame.midX - separatorFrame.midX : separatorFrame.midX - frame.midX
        return towardArrow > 0 ? .visible : .hidden
    }
}
