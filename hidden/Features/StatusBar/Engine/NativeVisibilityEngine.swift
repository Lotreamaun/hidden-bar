//
//  NativeVisibilityEngine.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import os

// macOS 27 hiding for the direct (non-App Store) build. Instead of inflating the
// separator, which macOS 27 ejects from the layout once it is too wide (#360),
// this asks macOS to show only an allow-list of apps through the menu-bar
// visibility restriction behind assessment mode. macOS then hides the rest and
// reflows the bar itself, so the result does not depend on display width, the
// notch or the frontmost app's menus.
//
// The arrow is the boundary: apps left of it (LTR) are hidden, apps right of it
// stay visible. The separator is not needed and is taken out of the bar; even
// at zero width macOS keeps a gap for it.
//
// Only what was observed in a hidden section is hidden. The allow-list is every
// running app minus the bundles last seen on the hidden side, so a snapshot that
// misses an item (common on macOS 27.2) leaves it visible rather than hiding it.
// Sections are remembered across collapses and launches, and read only while
// nothing is hidden, because hidden items report stale positions.
//
// Limits, all from what macOS 27 exposes:
// - Hiding is per app: an app with several icons hides or shows them together
//   (the most visible section wins).
// - macOS's own items (clock, Wi-Fi, Control Center...) are always allowed. A few
//   (Focus) cannot be allowed by any identifier; the engine notices when one
//   disappears after an activation, and automatic collapses wait while it is on
//   screen. A collapse by click still hides it.
// - A Focus that turns on while collapsed is not shown until the next expand.
// - Notification Center does not open while collapsed: clicking the clock does
//   nothing. It refuses under any restriction with an allow-list, even one that
//   allows everything; only the unrestricted configuration leaves it working.
final class NativeVisibilityEngine: MenuBarEngine {
    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let memory: MenuBarSectionMemory
    private let ownBundleIdentifier: String?
    private let runningBundles: () -> [String]
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let isLTR: () -> Bool
    private let verificationDelay: TimeInterval
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.dwarvesv.minimalbar", category: "visibility")

    // .calibrating stands for "an activation is in flight".
    private(set) var state: MenuBarEngineState = .expanded
    private(set) var layout: MenuBarLayout?

    var onHidingChange: ((Bool) -> Void)?

    private var assertion: NativeVisibilityAssertion?
    // The bundles the held restriction allows.
    private var allowedBundles: [String] = []
    // Bumped whenever a pending activation must no longer win (an expand, a newer
    // activation); a late success is then invalidated straight away.
    private var generation = 0
    private var lastUnavailableReason: String?

    // System controls that disappeared after an activation, so no allow-list can
    // keep them. Learned at runtime: the identifier set can change in a point release.
    private var nonAllowableControls: Set<String> = []

    private var launchObserver: NSObjectProtocol?
    private let workspaceNotifications: NotificationCenter

    init(items: MenuBarItemProvider,
         inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
         visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
         memory: MenuBarSectionMemory = MenuBarSectionMemory(),
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         runningBundles: @escaping () -> [String] = { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) },
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         verificationDelay: TimeInterval = 0.3,
         itemFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
         isLTR: @escaping () -> Bool = { Constant.isUsingLTRLanguage }) {
        self.items = items
        self.inventory = inventory
        self.visibility = visibility
        self.memory = memory
        self.ownBundleIdentifier = ownBundleIdentifier
        self.runningBundles = runningBundles
        self.workspaceNotifications = workspaceNotifications
        self.verificationDelay = verificationDelay
        self.itemFrame = itemFrame
        self.isLTR = isLTR
        items.separatorItem.isVisible = false
        launchObserver = workspaceNotifications.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.applicationDidLaunch()
        }
    }

    deinit {
        if let launchObserver = launchObserver {
            workspaceNotifications.removeObserver(launchObserver)
        }
    }

    func collapse(origin: CollapseOrigin, completion: @escaping (CollapseResult) -> Void) {
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            // The activation in flight answers the request that started it.
            return
        case .expanded, .unavailable:
            break
        }

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }
        guard inventory.isAuthorized else {
            // Without Accessibility the sections cannot be read, and guessing would
            // hide icons the user kept visible. Not latched: it works as soon as
            // the permission is granted.
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }
        state = .calibrating
        generation += 1
        let generation = self.generation
        // The system controls come first: they are one cheap read, and a collapse
        // that has to wait for one of them then costs no walk over every app.
        inventory.systemControls { [weak self] before in
            guard let self = self, generation == self.generation else { return }
            let blocking = (before ?? []).intersection(self.nonAllowableControls)
            if origin == .automatic, !blocking.isEmpty {
                return self.hold(blocking, completion: completion)
            }
            self.refreshSections { [weak self] refreshed in
                guard let self = self else { return }
                guard refreshed else {
                    self.logUnavailableOnce("the arrow's position cannot be read yet")
                    self.state = .expanded
                    return completion(.unavailable)
                }
                self.collapse(origin: origin, controlsBefore: before, completion: completion)
            }
        }
    }

    private func collapse(origin: CollapseOrigin, controlsBefore before: Set<String>?, completion: @escaping (CollapseResult) -> Void) {
        activate { [weak self] succeeded in
            guard let self = self else { return }
            guard succeeded else {
                self.state = .expanded
                return completion(.unavailable)
            }
            // The icons are gone now; the check below takes a moment more.
            self.onHidingChange?(true)
            self.verifySystemControls(before: before) { [weak self] lost in
                guard let self = self else { return }
                if !lost.isEmpty {
                    self.nonAllowableControls.formUnion(lost)
                    if origin == .automatic {
                        self.releaseAssertion()
                        self.onHidingChange?(false)
                        return self.hold(lost, completion: completion)
                    }
                    self.log.info("collapse by request hides system controls \(lost.sorted().joined(separator: ","), privacy: .public)")
                }
                self.state = .collapsed
                completion(.collapsed)
            }
        }
    }

    // An automatic collapse that would hide a system control the user is looking
    // at leaves the bar expanded; the caller tries again later.
    private func hold(_ controls: Set<String>, completion: (CollapseResult) -> Void) {
        log.info("collapse held: would hide system controls \(controls.sorted().joined(separator: ","), privacy: .public)")
        state = .expanded
        completion(.held)
    }

    // Compares the controls on screen before and after an activation; the ones
    // that vanished are what the restriction hides although it should not.
    private func verifySystemControls(before: Set<String>?, completion: @escaping (Set<String>) -> Void) {
        guard let before = before else { return completion([]) }
        let generation = self.generation
        let read = { [weak self] in
            guard let self = self, generation == self.generation else { return }
            self.inventory.systemControls { [weak self] after in
                guard let self = self, generation == self.generation else { return }
                completion(after.map { before.subtracting($0) } ?? [])
            }
        }
        if verificationDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + verificationDelay, execute: read)
        } else {
            read()
        }
    }

    func expand() {
        state = .expanded
        releaseAssertion()
    }

    // Native hiding does not depend on display geometry, so only drop the cached
    // layout; the next read from an unrestricted bar replaces it.
    func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    // Brings the remembered sections up to date. A fresh read happens only from an
    // unrestricted bar; while a restriction is active the memory stands in. Then
    // the body runs with false if the arrow cannot be located. Superseded by any
    // later expand or activation, like an activation is.
    private func refreshSections(_ body: @escaping (Bool) -> Void) {
        if assertion != nil {
            return body(true)
        }
        guard let arrow = items?.toggleItem,
              let boundary = itemFrame(arrow) else { return body(false) }
        let isLTR = self.isLTR()
        generation += 1
        let generation = self.generation
        inventory.snapshot { [weak self] inventory in
            guard let self = self, generation == self.generation else { return }
            let layout = MenuBarLayoutResolver.resolve(inventory: inventory,
                                                       separatorFrame: boundary,
                                                       isLTR: isLTR,
                                                       excludingBundle: self.ownBundleIdentifier)
            self.memory.update(with: layout.sections)
            self.layout = layout
            self.logLayout(layout)
            body(true)
        }
    }

    // Everything running except what was last seen on the hidden side.
    private func allowedBundleIdentifiers() -> [String] {
        var allowed = Set(runningBundles())
        allowed.formUnion(memory.bundles(in: [.visible]))
        allowed.subtract(memory.bundles(in: [.hidden]))
        if let own = ownBundleIdentifier {
            allowed.insert(own)
        }
        return allowed.sorted()
    }

    // Activates the new restriction before dropping the old one, so replacing it
    // never flashes the whole bar visible.
    private func activate(releasingOnFailure: Bool = true,
                          completion: @escaping (Bool) -> Void) {
        guard let systemItems = visibility.supportedSystemItems(), !systemItems.isEmpty else {
            logUnavailableOnce("the supported system menu-bar controls could not be determined")
            if releasingOnFailure {
                releaseAssertion()
            }
            return completion(false)
        }
        generation += 1
        let generation = self.generation
        let allowed = allowedBundleIdentifiers()
        visibility.activate(allowedSystemItems: systemItems,
                            allowedBundleIdentifiers: allowed) { [weak self] result in
            guard let self = self, generation == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                self.allowedBundles = allowed
                old?.invalidate()
                self.log.info("restriction active, hiding \(self.memory.bundles(in: [.hidden]).joined(separator: ","), privacy: .public)")
                completion(true)
            case .failure(let error):
                // Fail open: never leave icons hidden after an error.
                self.log.error("activation failed: \(error.localizedDescription, privacy: .public)")
                if releasingOnFailure {
                    self.releaseAssertion()
                }
                completion(false)
            }
        }
    }

    // An app launched while a restriction is active has no item on the allow-list
    // yet, so it would be hidden. Recompute the list; an app known to be hidden
    // is not on it and stays hidden.
    private func applicationDidLaunch() {
        guard assertion != nil, state == .collapsed else { return }
        guard allowedBundleIdentifiers() != allowedBundles else { return }
        activate(releasingOnFailure: false) { _ in }
    }

    // Any arrangement works: whatever sits left of the arrow is the hidden section.
    var isArrangementValid: Bool {
        return true
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
        allowedBundles = []
    }

    // Logged when the reason changes, so a retried collapse does not spam.
    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        log.error("hiding unavailable: \(reason, privacy: .public)")
    }

    private func logLayout(_ layout: MenuBarLayout) {
        log.info("sections read: visible \(layout.bundles(in: [.visible]).joined(separator: ","), privacy: .public); hidden \(layout.bundles(in: [.hidden]).joined(separator: ","), privacy: .public)")
        if layout.hasUnclassifiableVisibleItems {
            let details = layout.unclassifiableVisibleItems.map(\.diagnosticDescription).joined(separator: "; ")
            log.info("visible extras without a bundle identifier are not managed: \(details, privacy: .public)")
        }
    }
}
