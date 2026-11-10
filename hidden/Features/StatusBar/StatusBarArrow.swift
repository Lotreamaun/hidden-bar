//
//  StatusBarArrow.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// The arrow glyph of the toggle item, set as the button's own image and changed
// without animation. A symbol content transition (drawn by an image view inside
// the button) replayed whenever the user switched Spaces, so the arrow seemed to
// flip back and forth; the button image is what the status bar redraws itself.
final class StatusBarArrow {
    enum Glyph {
        case expanded
        case collapsed
    }

    // The size of the bitmap arrow this replaced, so the item keeps its width.
    private static let canvasSize = NSSize(width: 16, height: 16)

    private weak var button: NSStatusBarButton?
    private(set) var glyph: Glyph?

    init(button: NSStatusBarButton) {
        self.button = button
        button.setAccessibilityLabel("Hidden Bar")
    }

    func show(_ glyph: Glyph) {
        guard glyph != self.glyph else { return }
        self.glyph = glyph
        button?.image = Self.image(for: glyph)
    }

    // Expanded points away from the hidden section, collapsed toward it, in the
    // reading direction of the UI. Not the forward/backward symbols: the
    // direction is chosen here, where Constant.isUsingLTRLanguage is known.
    static func image(for glyph: Glyph) -> NSImage? {
        let pointsRight = (glyph == .expanded) == Constant.isUsingLTRLanguage
        // Matches the height and stroke of the bitmap arrow it replaces.
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: pointsRight ? "chevron.right" : "chevron.left",
                                   accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let canvas = canvasSize
        let image = NSImage(size: canvas, flipped: false) { _ in
            let size = symbol.size
            symbol.draw(in: NSRect(x: (canvas.width - size.width) / 2,
                                   y: (canvas.height - size.height) / 2,
                                   width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}
