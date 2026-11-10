import XCTest
@testable import Hidden_Bar

/// Contract: the arrow's menu is the only place Hidden Bar is configured. It
/// offers Start at Login, an Auto Collapse submenu, and Quit, with checkmarks
/// matching the settings it was built from.
final class SettingsMenuTests: XCTestCase {
    private var loginToggles = 0
    private var chosenDelays: [TimeInterval?] = []
    private var settingsMenu: SettingsMenu!

    override func setUp() {
        super.setUp()
        loginToggles = 0
        chosenDelays = []
        settingsMenu = SettingsMenu(toggleStartAtLogin: { [unowned self] in self.loginToggles += 1 },
                                    chooseAutoCollapse: { [unowned self] in self.chosenDelays.append($0) })
    }

    private func menu(login: Bool = false, autoCollapses: Bool = true, delay: TimeInterval = 10) -> NSMenu {
        return settingsMenu.makeMenu(for: .init(startsAtLogin: login, autoCollapses: autoCollapses, autoCollapseDelay: delay))
    }

    private func delayItems(of menu: NSMenu) -> [NSMenuItem] {
        return menu.items[1].submenu!.items.filter { !$0.isSeparatorItem }
    }

    func testMenuHasOnlyLoginAutoCollapseAndQuit() {
        let menu = self.menu()
        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items[0].title, "Start at Login".localized)
        XCTAssertEqual(menu.items[1].title, "Auto Collapse".localized)
        XCTAssertNotNil(menu.items[1].submenu)
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Quit Hidden Bar".localized)
        XCTAssertEqual(menu.items[3].keyEquivalent, "q")
        XCTAssertEqual(menu.items[3].action, #selector(NSApplication.terminate(_:)))
    }

    func testCheckmarksFollowTheSettings() {
        let menu = self.menu(login: true, autoCollapses: true, delay: 15)
        XCTAssertEqual(menu.items[0].state, .on)
        let checked = delayItems(of: menu).filter { $0.state == .on }
        XCTAssertEqual(checked.map(\.title), [SettingsMenu.title(forDelay: 15)])
    }

    func testOffIsCheckedWhenAutoCollapseIsOff() {
        let menu = self.menu(login: false, autoCollapses: false, delay: 15)
        XCTAssertEqual(menu.items[0].state, .off)
        let checked = delayItems(of: menu).filter { $0.state == .on }
        XCTAssertEqual(checked.map(\.title), ["Off".localized])
    }

    func testOffersTheStandardDelays() {
        let titles = delayItems(of: menu()).map(\.title)
        XCTAssertEqual(titles, ["Off".localized] + SettingsMenu.delays.map(SettingsMenu.title(forDelay:)))
        XCTAssertEqual(SettingsMenu.title(forDelay: 60), "1 minute".localized)
    }

    func testCustomDelayIsShownAndChecked() {
        let items = delayItems(of: menu(autoCollapses: true, delay: 7))
        XCTAssertEqual(items.count, 1 + SettingsMenu.delays.count + 1)
        XCTAssertEqual(items.first { $0.state == .on }?.representedObject as? TimeInterval, 7)
        XCTAssertEqual(SettingsMenu.listedDelays(current: 7), [5, 7, 10, 15, 30, 60])
    }

    func testChoosingADelayReportsIt() {
        let submenu = menu(autoCollapses: false).items[1].submenu!
        let index = submenu.items.firstIndex { ($0.representedObject as? TimeInterval) == 30 }!
        submenu.performActionForItem(at: index)
        XCTAssertEqual(chosenDelays, [30])
    }

    func testChoosingOffReportsNil() {
        let submenu = menu(autoCollapses: true).items[1].submenu!
        submenu.performActionForItem(at: 0)
        XCTAssertEqual(chosenDelays, [nil])
    }

    func testStartAtLoginTogglesThroughTheController() {
        let menu = self.menu()
        menu.performActionForItem(at: 0)
        XCTAssertEqual(loginToggles, 1)
    }

    func testDefaultsNoLongerOpenAWindowOrRegisterAShortcut() {
        let keys = Set(AppDelegate.defaultPreferenceValues.keys)
        XCTAssertEqual(keys, [UserDefaults.Key.isAutoStart, UserDefaults.Key.isAutoHide, UserDefaults.Key.numberOfSecondForAutoHide])
    }
}
