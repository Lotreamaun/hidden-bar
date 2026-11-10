//
//  MenuBarEngineTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

// The engine sources are compiled straight into this bundle (no host app), so
// the tests never put items in the real menu bar, never need Accessibility, and
// never touch the private visibility API.

// MARK: - Fakes

private final class FakeItems: MenuBarItemProvider {
    private let bar = NSStatusBar()
    let toggleItem: NSStatusItem
    let separatorItem: NSStatusItem

    init() {
        toggleItem = bar.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem = bar.statusItem(withLength: 1)
    }
}

private final class FakeInventory: MenuBarInventoryProviding {
    var isAuthorized = true
    var items: [MenuBarInventoryItem] = []
    var authorizationRequests = 0
    var snapshots = 0
    // What the system-control tree reports at the moment it is read.
    var controlsProvider: () -> Set<String>? = { ["com.apple.menuextra.clock", "com.apple.menuextra.wifi"] }

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        snapshots += 1
        completion(items)
    }

    func systemControls(completion: @escaping (Set<String>?) -> Void) {
        completion(controlsProvider())
    }
}

private final class FakeAssertion: NativeVisibilityAssertion {
    let allowed: [String]
    private(set) var isInvalidated = false
    var onInvalidate: (() -> Void)?

    init(allowed: [String]) {
        self.allowed = allowed
    }

    func invalidate() {
        isInvalidated = true
        onInvalidate?()
    }
}

// Hands every activation to the test, which decides when and how it completes.
private final class FakeVisibility: NativeVisibilityProviding {
    struct Request {
        let systemItems: [Int]
        let bundles: [String]
        let completion: (Result<NativeVisibilityAssertion, Error>) -> Void
    }

    var isAvailable = true
    var systemItems: [Int]? = [2, 5, 6, 8]
    var requests: [Request] = []
    private(set) var assertions: [FakeAssertion] = []

    var isRestricting: Bool {
        return assertions.contains { !$0.isInvalidated }
    }

    func supportedSystemItems() -> [Int]? {
        return systemItems
    }

    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        requests.append(Request(systemItems: allowedSystemItems, bundles: allowedBundleIdentifiers, completion: completion))
    }

    @discardableResult
    func succeed(_ index: Int) -> FakeAssertion {
        let assertion = FakeAssertion(allowed: requests[index].bundles)
        assertions.append(assertion)
        requests[index].completion(.success(assertion))
        return assertion
    }

    func fail(_ index: Int) {
        requests[index].completion(.failure(NSError(domain: "test", code: 1)))
    }
}

private func item(_ bundle: String?, x: CGFloat, width: CGFloat = 24) -> MenuBarInventoryItem {
    return MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: width, height: 24))
}

// LTR bar used throughout: the boundary at 1300 (the separator for the
// resolver, the arrow for the native engine).
private let separator = CGRect(x: 1300, y: 0, width: 20, height: 24)

// MARK: - Layout resolver

final class MenuBarLayoutResolverTests: XCTestCase {
    func testLTRSectionsFollowTheBoundary() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.far", x: 100), item("com.hidden", x: 1100), item("com.visible", x: 1400)],
            separatorFrame: separator, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.far": .hidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testRTLSectionsAreMirrored() {
        // RTL: arrow on the left, hidden further right.
        let rtlSeparator = CGRect(x: 300, y: 0, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.visible", x: 200), item("com.hidden", x: 450), item("com.far", x: 700)],
            separatorFrame: rtlSeparator, isLTR: false, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.far": .hidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testMostVisibleItemWinsForABundle() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.split", x: 1100), item("com.split", x: 1400),
                        item("com.pair", x: 900), item("com.pair", x: 1100)],
            separatorFrame: separator, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections["com.split"], .visible)
        XCTAssertEqual(layout.sections["com.pair"], .hidden)
    }

    func testSkipsOwnAndSystemItemsButKeepsUnknownHiddenItemsOutOfTheAllowList() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.dwarvesv.minimalbar", x: 1100), item("com.apple.MenuBarAgent", x: 1100),
                        item(nil, x: 1100), item("com.app", x: 1100)],
            separatorFrame: separator, isLTR: true, excludingBundle: "com.dwarvesv.minimalbar")
        XCTAssertEqual(layout.sections, ["com.app": .hidden])
        XCTAssertFalse(layout.hasUnclassifiableVisibleItems)
    }

    func testHelperOwnedExtraUsesItsBundleIdentity() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [MenuBarInventoryItem(identity: .application(bundleIdentifier: "com.example.helper"),
                                             frame: CGRect(x: 1400, y: 0, width: 24, height: 24),
                                             processIdentifier: 42,
                                             processName: "Example Helper")],
            separatorFrame: separator, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.example.helper": .visible])
    }

    func testSystemUIServerExtrasNeverRequireAPlacementIdentity() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [
                MenuBarInventoryItem(identity: .system(ownerBundleIdentifier: "com.apple.systemuiserver"),
                                     frame: CGRect(x: 1100, y: 0, width: 24, height: 24)),
                MenuBarInventoryItem(identity: .system(ownerBundleIdentifier: "com.apple.systemuiserver"),
                                     frame: CGRect(x: 1400, y: 0, width: 24, height: 24))
            ],
            separatorFrame: separator, isLTR: true, excludingBundle: nil)
        XCTAssertTrue(layout.sections.isEmpty)
        XCTAssertFalse(layout.hasUnclassifiableVisibleItems)
    }

    func testVisibleUnclassifiableExtraIsReportedButHiddenOneIsNot() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [
                MenuBarInventoryItem(identity: .unclassifiable(reason: "missing bundle identifier"),
                                     frame: CGRect(x: 1100, y: 0, width: 24, height: 24)),
                MenuBarInventoryItem(identity: .unclassifiable(reason: "missing bundle identifier"),
                                     frame: CGRect(x: 1400, y: 0, width: 24, height: 24))
            ],
            separatorFrame: separator, isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.unclassifiableVisibleItems.count, 1)
    }

    func testBundlesAreFilteredAndSorted() {
        let layout = MenuBarLayout(sections: ["b": .visible, "a": .visible, "c": .hidden])
        XCTAssertEqual(layout.bundles(in: [.visible]), ["a", "b"])
        XCTAssertEqual(layout.bundles(in: [.visible, .hidden]), ["a", "b", "c"])
    }
}

// MARK: - Section memory

final class MenuBarSectionMemoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MenuBarSectionMemoryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUpdateKeepsBundlesMissingFromASnapshot() {
        let memory = MenuBarSectionMemory(defaults: defaults)
        memory.update(with: ["com.a": .hidden, "com.b": .visible])
        memory.update(with: ["com.b": .hidden])

        XCTAssertEqual(memory.section(of: "com.a"), .hidden)
        XCTAssertEqual(memory.section(of: "com.b"), .hidden)
        XCTAssertNil(memory.section(of: "com.never"))
    }

    func testEmptySnapshotChangesNothing() {
        let memory = MenuBarSectionMemory(defaults: defaults)
        memory.update(with: ["com.a": .hidden])
        memory.update(with: [:])
        XCTAssertEqual(memory.bundles(in: [.hidden]), ["com.a"])
    }

    func testSectionsSurviveANewInstance() {
        MenuBarSectionMemory(defaults: defaults).update(with: ["com.a": .hidden, "com.b": .visible])
        let reloaded = MenuBarSectionMemory(defaults: defaults)
        XCTAssertEqual(reloaded.section(of: "com.a"), .hidden)
        XCTAssertEqual(reloaded.section(of: "com.b"), .visible)
    }

    func testFormerAlwaysHiddenEntriesAreReadAsHidden() {
        // What builds with the always-hidden section stored for it.
        let seen = Date().timeIntervalSince1970
        defaults.set(["com.always": ["section": 2.0, "seen": seen], "com.visible": ["section": 0.0, "seen": seen]],
                     forKey: MenuBarSectionMemory.defaultsKey)

        let memory = MenuBarSectionMemory(defaults: defaults)
        XCTAssertEqual(memory.section(of: "com.always"), .hidden)
        XCTAssertEqual(memory.section(of: "com.visible"), .visible)
        XCTAssertEqual(memory.bundles(in: [.hidden]), ["com.always"])
    }

    func testLongUnseenEntriesArePruned() {
        let long = Date(timeIntervalSinceNow: -200 * 24 * 60 * 60)
        MenuBarSectionMemory(defaults: defaults).update(with: ["com.old": .hidden], at: long)
        MenuBarSectionMemory(defaults: defaults).update(with: ["com.recent": .hidden])

        let reloaded = MenuBarSectionMemory(defaults: defaults)
        XCTAssertNil(reloaded.section(of: "com.old"))
        XCTAssertEqual(reloaded.section(of: "com.recent"), .hidden)
    }
}

// MARK: - Native engine

final class NativeVisibilityEngineTests: XCTestCase {
    private let focus = "com.apple.menuextra.focusmode"

    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var workspace: NotificationCenter!
    private var running: [String] = []
    private var focusOn = false

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.far", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
        suiteName = "NativeVisibilityEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        workspace = NotificationCenter()
        running = ["com.far", "com.hidden", "com.visible", "com.new"]
        focusOn = false
        // Focus is shown unless a restriction is active: no allow-list keeps it.
        inventory.controlsProvider = { [unowned self] in
            var controls: Set<String> = ["com.apple.menuextra.clock", "com.apple.menuextra.wifi"]
            if self.focusOn && !self.visibility.isRestricting {
                controls.insert(self.focus)
            }
            return controls
        }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      memory: MenuBarSectionMemory(defaults: defaults),
                                      ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                      runningBundles: { [unowned self] in self.running },
                                      workspaceNotifications: workspace,
                                      verificationDelay: 0,
                                      itemFrame: { $0 === items.toggleItem ? separator : nil },
                                      isLTR: { true })
    }

    // Collapses and completes the activation; returns the result.
    @discardableResult
    private func collapse(_ engine: NativeVisibilityEngine, origin: CollapseOrigin = .automatic) -> CollapseResult? {
        var result: CollapseResult?
        let before = visibility.requests.count
        engine.collapse(origin: origin) { result = $0 }
        if visibility.requests.count > before {
            visibility.succeed(visibility.requests.count - 1)
        }
        return result
    }

    func testCollapseHidesOnlyWhatWasSeenHiddenAndKeepsSystemItems() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse(origin: .user) { results.append($0) }

        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertEqual(visibility.requests.first?.bundles, ["com.dwarvesv.minimalbar", "com.new", "com.visible"])
        XCTAssertEqual(visibility.requests.first?.systemItems, visibility.systemItems)
        XCTAssertFalse(items.separatorItem.isVisible, "the arrow is the boundary; no separator needed")

        visibility.succeed(0)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(results, [.collapsed])

        engine.expand()
        XCTAssertFalse(items.separatorItem.isVisible)
    }

    func testSeparatorStaysOutOfTheBar() {
        let engine = makeEngine()
        XCTAssertFalse(items.separatorItem.isVisible)
        collapse(engine)
        engine.expand()
        XCTAssertFalse(items.separatorItem.isVisible)
    }

    func testUnavailableAPIFailsOpen() {
        visibility.isAvailable = false
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse(origin: .user) { result = $0 }

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    func testMissingAccessibilityAsksAndRetriesLater() {
        inventory.isAuthorized = false
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse(origin: .user) { results.append($0) }

        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(inventory.authorizationRequests, 1)
        XCTAssertTrue(visibility.requests.isEmpty, "never guess which icons to hide")

        inventory.isAuthorized = true
        engine.collapse(origin: .user) { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1, "works once the permission is granted")
    }

    func testVisibleExtraWithoutBundleDoesNotBlockCollapse() {
        inventory.items = [MenuBarInventoryItem(identity: .unclassifiable(reason: "missing bundle identifier"),
                                                frame: CGRect(x: 1400, y: 0, width: 24, height: 24),
                                                processIdentifier: 42,
                                                processName: "Unknown Helper")]
        let engine = makeEngine()

        XCTAssertEqual(collapse(engine), .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(visibility.requests.count, 1, "an inventory gap never keeps the bar from collapsing")
    }

    func testMissingSystemItemInventoryFailsOpen() {
        visibility.systemItems = nil
        let engine = makeEngine()

        XCTAssertEqual(collapse(engine), .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    func testEmptySystemItemInventoryFailsOpen() {
        visibility.systemItems = []
        let engine = makeEngine()

        XCTAssertEqual(collapse(engine), .unavailable)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(visibility.requests.isEmpty, "an empty allow-list would hide every system control")
    }

    func testActivationFailureReportsUnavailable() {
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse(origin: .user) { result = $0 }
        visibility.fail(0)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .expanded)
    }

    func testExpandDropsTheRestriction() {
        let engine = makeEngine()
        collapse(engine)
        let collapsed = visibility.assertions[0]

        engine.expand()
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testExpandDuringActivationDropsTheLateResult() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse(origin: .user) { results.append($0) }

        engine.expand()
        let late = visibility.succeed(0)

        XCTAssertTrue(late.isInvalidated, "a restriction nobody wants any more is released")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(results, [])
    }

    func testDisplayChangeKeepsTheBarCollapsed() {
        let engine = makeEngine()
        collapse(engine)

        engine.invalidateLayout()
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(visibility.assertions[0].isInvalidated)
    }

    // MARK: Allow-list derivation

    func testBundleMissingFromASnapshotKeepsItsSection() {
        let engine = makeEngine()
        collapse(engine)
        engine.expand()

        inventory.items = [item("com.visible", x: 1400)]
        collapse(engine)

        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.new", "com.visible"])
    }

    func testNeverSeenRunningBundleIsAllowed() {
        let engine = makeEngine()
        running.append("com.brand.new")
        collapse(engine)

        XCTAssertTrue(visibility.requests[0].bundles.contains("com.brand.new"))
    }

    func testEmptySnapshotChangesNothing() {
        let engine = makeEngine()
        collapse(engine)
        engine.expand()

        inventory.items = []
        collapse(engine)

        XCTAssertFalse(visibility.requests.last!.bundles.contains("com.hidden"))
        XCTAssertFalse(visibility.requests.last!.bundles.contains("com.far"))
    }

    func testSectionsSurviveARestart() {
        collapse(makeEngine())

        // A new launch whose first snapshot is empty still hides what was hidden.
        inventory.items = []
        let relaunched = makeEngine()
        collapse(relaunched)

        XCTAssertEqual(visibility.requests.last?.bundles, ["com.dwarvesv.minimalbar", "com.new", "com.visible"])
    }

    func testSectionsAreNotReadWhileSomethingIsHidden() {
        let engine = makeEngine()
        collapse(engine)
        let snapshotsBefore = inventory.snapshots

        // Hidden items would report stale positions now; the memory is used.
        inventory.items = [item("com.hidden", x: 1400)]
        running.append("com.launched")
        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(inventory.snapshots, snapshotsBefore)
        XCTAssertFalse(visibility.requests.last!.bundles.contains("com.hidden"))
    }

    // MARK: Applications launching under a restriction

    func testApplicationLaunchedWhileCollapsedIsAllowed() {
        let engine = makeEngine()
        collapse(engine)
        let first = visibility.assertions[0]

        running.append("com.launched")
        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        XCTAssertEqual(visibility.requests.count, 2)
        XCTAssertTrue(visibility.requests[1].bundles.contains("com.launched"))
        XCTAssertFalse(first.isInvalidated, "the old restriction stays until the new one is active")
        visibility.succeed(1)
        XCTAssertTrue(first.isInvalidated)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testRelaunchOfAHiddenApplicationKeepsItHidden() {
        let engine = makeEngine()
        collapse(engine)

        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        XCTAssertEqual(visibility.requests.count, 1, "the allow-list did not change")
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testLaunchWhileExpandedDoesNothing() {
        let engine = makeEngine()
        running.append("com.launched")
        workspace.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertTrue(visibility.requests.isEmpty)
        XCTAssertEqual(engine.state, .expanded)
    }

    // MARK: System controls that cannot be allowed

    func testAutomaticCollapseIsUndoneAndHeldWhileFocusIsShown() {
        focusOn = true
        let engine = makeEngine()

        XCTAssertEqual(collapse(engine, origin: .automatic), .held)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertTrue(visibility.assertions[0].isInvalidated, "the restriction that hid Focus is released")
        XCTAssertFalse(visibility.isRestricting)
    }

    func testLaterAutomaticCollapseWaitsWithoutActivating() {
        focusOn = true
        let engine = makeEngine()
        collapse(engine)
        let requests = visibility.requests.count

        XCTAssertEqual(collapse(engine), .held)
        XCTAssertEqual(visibility.requests.count, requests, "decided up front, without flicker")
    }

    func testHeldCollapseProceedsWhenTheControlLeaves() {
        focusOn = true
        let engine = makeEngine()
        collapse(engine)

        focusOn = false
        XCTAssertEqual(collapse(engine), .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testCollapseByRequestStandsWhileFocusIsShown() {
        focusOn = true
        let engine = makeEngine()
        collapse(engine)   // learns that Focus cannot be allowed

        XCTAssertEqual(collapse(engine, origin: .user), .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testAutomaticCollapsesWaitAgainAfterACollapseByRequest() {
        focusOn = true
        let engine = makeEngine()
        collapse(engine, origin: .user)   // learns Focus and hides it by request
        engine.expand()

        let requests = visibility.requests.count
        XCTAssertEqual(collapse(engine, origin: .automatic), .held, "a manual collapse does not turn auto collapse back on")
        XCTAssertEqual(visibility.requests.count, requests)
        XCTAssertEqual(engine.state, .expanded)
    }

    func testCollapseByRequestBeforeFocusIsKnownStillTeachesIt() {
        focusOn = true
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine, origin: .user), .collapsed)
        engine.expand()

        focusOn = false
        XCTAssertEqual(collapse(engine), .collapsed, "auto collapse resumes once Focus is off")
        engine.expand()

        focusOn = true
        XCTAssertEqual(collapse(engine), .held)
    }

    func testUnreadableControlTreeNeverBlocksCollapse() {
        inventory.controlsProvider = { nil }
        let engine = makeEngine()
        XCTAssertEqual(collapse(engine), .collapsed)
    }

    // MARK: Reporting when icons are hidden

    func testHidingIsReportedWhenTheRestrictionIsActive() {
        let engine = makeEngine()
        var reports: [Bool] = []
        engine.onHidingChange = { reports.append($0) }

        engine.collapse(origin: .user) { _ in }
        XCTAssertEqual(reports, [], "nothing is hidden before activation")
        visibility.succeed(0)
        XCTAssertEqual(reports, [true])
    }

    func testUndoneCollapseReportsTheIconsBack() {
        focusOn = true
        let engine = makeEngine()
        var reports: [Bool] = []
        engine.onHidingChange = { reports.append($0) }

        XCTAssertEqual(collapse(engine, origin: .automatic), .held)
        XCTAssertEqual(reports, [true, false])
    }

    func testCollapseDeclinedBeforeActivationReportsNothing() {
        focusOn = true
        let engine = makeEngine()
        collapse(engine)   // learns that Focus cannot be allowed
        var reports: [Bool] = []
        engine.onHidingChange = { reports.append($0) }

        XCTAssertEqual(collapse(engine), .held)
        XCTAssertEqual(reports, [])
    }

    func testFailedActivationReportsNothing() {
        let engine = makeEngine()
        var reports: [Bool] = []
        engine.onHidingChange = { reports.append($0) }

        engine.collapse(origin: .user) { _ in }
        visibility.fail(0)
        XCTAssertEqual(reports, [])
    }
}

// MARK: - Legacy engine

final class LegacyLengthEngineTests: XCTestCase {
    func testCollapseAndExpandFlipSeparatorLength() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items)
        XCTAssertEqual(engine.state, .expanded)

        var result: CollapseResult?
        var reports: [Bool] = []
        engine.onHidingChange = { reports.append($0) }
        engine.collapse(origin: .user) { result = $0 }
        XCTAssertEqual(result, .collapsed)
        XCTAssertEqual(reports, [true])
        XCTAssertEqual(engine.state, .collapsed)

        engine.expand()
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.separatorItem.length, 20)
    }
}
