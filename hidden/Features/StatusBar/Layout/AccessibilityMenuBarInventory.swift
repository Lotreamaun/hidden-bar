//
//  AccessibilityMenuBarInventory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import ApplicationServices

// Lists other processes' status items through public Accessibility API: every
// running process's AXExtrasMenuBar children, with its visibility identity.
// Needs the Accessibility permission, and does not work inside the App Sandbox
// (the sandbox denies the mach-lookup to com.apple.axserver even when the
// permission is granted), so only the non-sandboxed direct build uses it.
final class AccessibilityMenuBarInventory: MenuBarInventoryProviding {
    private static let messagingTimeout: Float = 0.1

    private var hasRequestedAuthorization = false

    var isAuthorized: Bool {
        return AXIsProcessTrusted()
    }

    // Shows the system prompt once per launch; asking on every collapse would
    // nag while the user is still in System Settings.
    func requestAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Accessibility round-trips to every app take about a second in total, so the
    // walk runs off the main thread.
    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        // Helpers and system processes can own extras too. Every probe is bounded
        // by messagingTimeout, so a non-responsive XPC process cannot stall the
        // collapse indefinitely.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID }
            .map { (pid: $0.processIdentifier,
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName) }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = Self.statusItems(of: processes)
            DispatchQueue.main.async { completion(items) }
        }
    }

    // The system controls live under MenuBarAgent, whose extras tree stays
    // consistent under a restriction, unlike third-party processes.
    func systemControls(completion: @escaping (Set<String>?) -> Void) {
        guard let agent = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == Self.menuBarAgentBundleIdentifier }) else {
            return completion(nil)
        }
        let pid = agent.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let identifiers = Self.systemControlIdentifiers(of: pid)
            DispatchQueue.main.async { completion(identifiers) }
        }
    }

    private static let menuBarAgentBundleIdentifier = "com.apple.MenuBarAgent"
    private static let systemControlPrefix = "com.apple.menuextra."

    // The identifiers sit on the children of hosting views inside the extras bar,
    // so look a few levels down. An unreadable or empty tree is nil, never "all
    // controls are gone".
    private static func systemControlIdentifiers(of pid: pid_t) -> Set<String>? {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
              let bar = barValue else { return nil }
        var identifiers = Set<String>()
        collectControlIdentifiers(in: bar as! AXUIElement, depth: 0, into: &identifiers)
        return identifiers.isEmpty ? nil : identifiers
    }

    private static func collectControlIdentifiers(in element: AXUIElement, depth: Int, into identifiers: inout Set<String>) {
        var identifierValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue) == .success,
           let identifier = identifierValue as? String, identifier.hasPrefix(systemControlPrefix) {
            identifiers.insert(identifier)
        }
        guard depth < 4 else { return }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return }
        for child in children {
            collectControlIdentifiers(in: child, depth: depth + 1, into: &identifiers)
        }
    }

    private static func statusItems(of processes: [(pid: pid_t, bundleIdentifier: String?, localizedName: String?)]) -> [MenuBarInventoryItem] {
        var items: [MenuBarInventoryItem] = []
        for process in processes {
            let element = AXUIElementCreateApplication(process.pid)
            // The default timeout is several seconds per app, and one busy or hung
            // app then stalls the collapse (measured: ~18s on a normal session).
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                guard let frame = frame(of: child) else { continue }
                items.append(MenuBarInventoryItem(identity: identity(for: process.bundleIdentifier),
                                                  frame: frame,
                                                  processIdentifier: process.pid,
                                                  processName: process.localizedName))
            }
        }
        return items
    }

    private static func identity(for bundleIdentifier: String?) -> MenuBarVisibilityIdentity {
        guard let bundleIdentifier = bundleIdentifier else {
            return .unclassifiable(reason: "missing bundle identifier")
        }
        if MenuBarLayoutResolver.systemItemOwners.contains(bundleIdentifier) {
            return .system(ownerBundleIdentifier: bundleIdentifier)
        }
        return .application(bundleIdentifier: bundleIdentifier)
    }

    // Accessibility frames use a top-left origin, AppKit's bottom-left. Only the
    // horizontal position matters for sections, and x is the same in both.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
