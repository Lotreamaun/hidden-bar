//
//  StatusBarArrow.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit

// The arrow glyph inside the toggle item's button, changed the way the system
// changes its own symbols. NSButton cannot take a symbol content transition, so
// the symbol is drawn by an image view hosted in the button, and the button
// keeps an empty image of the old glyph's size: the item's width, click target
// and press action stay as they were.
final class StatusBarArrow {
    enum Glyph {
        case expanded
        case collapsed
    }

    private static let glyphSize = NSSize(width: 16, height: 16)
    private static let crossfadeDuration: CFTimeInterval = 0.2

    private let imageView = PassthroughImageView()
    private(set) var glyph: Glyph?

    init(button: NSStatusBarButton) {
        button.image = NSImage(size: Self.glyphSize)
        button.setAccessibilityLabel("Hidden Bar")

        imageView.wantsLayer = true
        imageView.imageScaling = .scaleNone
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    // Each call names the state to end on, so rapid toggles finish on the glyph
    // of the last one.
    func show(_ glyph: Glyph) {
        guard glyph != self.glyph, let image = Self.image(for: glyph) else { return }
        let isFirst = self.glyph == nil
        self.glyph = glyph
        if isFirst {
            imageView.image = image
        } else if #available(macOS 14.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            imageView.setSymbolImage(image, contentTransition: .replace)
        } else {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Self.crossfadeDuration
            imageView.layer?.add(fade, forKey: "glyph")
            imageView.image = image
        }
    }

    // Expanded points away from the hidden section, collapsed toward it, in the
    // reading direction of the UI. Not the forward/backward symbols: the
    // direction is chosen here, where Constant.isUsingLTRLanguage is known.
    private static func image(for glyph: Glyph) -> NSImage? {
        let pointsRight = (glyph == .expanded) == Constant.isUsingLTRLanguage
        // Matches the height and stroke of the bitmap arrow it replaces.
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: pointsRight ? "chevron.right" : "chevron.left",
                       accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

// Clicks go to the button underneath, not the image.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
