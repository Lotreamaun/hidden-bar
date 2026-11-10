import XCTest
@testable import Hidden_Bar

/// Contract: the arrow is the status button's own image, swapped without
/// animation. A hosted image view replayed its symbol transition on every
/// Space switch.
final class StatusBarArrowTests: XCTestCase {
    private let bar = NSStatusBar()
    private var item: NSStatusItem!

    override func setUp() {
        super.setUp()
        item = bar.statusItem(withLength: NSStatusItem.variableLength)
    }

    override func tearDown() {
        bar.removeStatusItem(item)
        super.tearDown()
    }

    func testGlyphIsTheButtonImage() {
        let button = item.button!
        let subviewsBefore = button.subviews.count
        let arrow = StatusBarArrow(button: button)

        arrow.show(.expanded)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.image?.isTemplate, true)
        XCTAssertEqual(button.image?.size, NSSize(width: 16, height: 16), "keeps the old item width")
        XCTAssertEqual(button.subviews.count, subviewsBefore, "nothing is drawn over the button")
    }

    func testChangingStateReplacesTheImage() {
        let button = item.button!
        let arrow = StatusBarArrow(button: button)
        arrow.show(.expanded)
        let expanded = button.image

        arrow.show(.collapsed)
        XCTAssertFalse(button.image === expanded)
        XCTAssertEqual(arrow.glyph, .collapsed)
    }

    func testShowingTheSameStateLeavesTheImageAlone() {
        let button = item.button!
        let arrow = StatusBarArrow(button: button)
        arrow.show(.collapsed)
        let collapsed = button.image

        arrow.show(.collapsed)
        XCTAssertTrue(button.image === collapsed)
    }

    func testKeepsTheAccessibilityLabel() {
        let button = item.button!
        _ = StatusBarArrow(button: button)
        XCTAssertEqual(button.accessibilityLabel(), "Hidden Bar")
    }
}
