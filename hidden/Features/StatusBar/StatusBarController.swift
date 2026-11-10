//
//  StatusBarController.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/30/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit

class StatusBarController: MenuBarItemProvider {
    
    //MARK: - Variables
    private var timer:Timer? = nil

    //MARK: - BarItems

    private let btnExpandCollapse = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let btnSeparate = NSStatusBar.system.statusItem(withLength: 1)

    var toggleItem: NSStatusItem { btnExpandCollapse }
    var separatorItem: NSStatusItem { btnSeparate }
    
    // How hiding is achieved (separator lengths) lives in the engine; this class
    // owns the items, the UI, and when to collapse or expand.
    private lazy var menuBarEngine: MenuBarEngine = MenuBarEngineFactory.make(items: self)

    private var arrow: StatusBarArrow?

    private lazy var settingsMenu = SettingsMenu(
        toggleStartAtLogin: { [weak self] in self?.toggleStartAtLogin() },
        chooseAutoCollapse: { [weak self] delay in self?.chooseAutoCollapse(delay) })
    
    private let imgIconLine = NSImage(named:NSImage.Name("ic_line"))
    
    private var isCollapsed: Bool {
        return menuBarEngine.state == .collapsed
    }
    
    private var isToggle = false

    private var hoverMonitor: Any?
    private var hoverDwellTimer: Timer?

    // True while the pointer sits in any screen's menubar band (the strip between
    // visibleFrame.maxY and frame.maxY, which is the menubar's exact height there).
    // On fullscreen spaces the menubar is hidden and the band collapses to ~zero,
    // so this returns false there: intentional, no visible menubar = no deferral.
    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY && mouse.y <= screen.frame.maxY
        }
    }
    
    //MARK: - Methods
    init() {
        setupUI()
        restoreRemovedStatusItems()
        setupHoverToExpandIfEnabled()
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAutoHide), name: .prefsChanged, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.collapseMenuBar(origin: .automatic)
        }

        autoCollapseIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        hoverDwellTimer?.invalidate()
        if let monitor = hoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // Opt-in via `defaults write com.dwarvesv.minimalbar hoverToExpand -bool true`.
    // No monitor is installed at all unless the pref is true at launch.
    private func setupHoverToExpandIfEnabled() {
        guard Preferences.hoverToExpand else { return }
        NSLog("HoverToExpand: enabled, installing global mouse monitor")
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            guard self.isCollapsed && self.isMouseInMenuBar else {
                self.hoverDwellTimer?.invalidate()
                self.hoverDwellTimer = nil
                return
            }
            // Short dwell so a pointer merely passing through doesn't expand.
            guard self.hoverDwellTimer == nil else { return }
            self.hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.hoverDwellTimer = nil
                if self.isCollapsed && self.isMouseInMenuBar {
                    self.expandMenubar()
                }
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        // Re-apply the recomputed length to the LIVE item when collapsed, or a
        // display hot-plug leaves the separator at a stale length (PR #354).
        menuBarEngine.invalidateLayout()
    }
    
    private func restoreRemovedStatusItems() {
        // Cmd-dragging a status item off the bar is persisted by macOS via
        // autosaveName, leaving the app running but unreachable. These items are
        // the app's only UI, so they self-restore at launch.
        btnExpandCollapse.isVisible = true
        btnSeparate.isVisible = true
        // Create the engine now so one that does not use the separator (macOS 27
        // native hiding) takes it back out before it is ever drawn.
        _ = menuBarEngine
        // The arrow changes with the icons, which can be before a collapse
        // completes (macOS 27 checks system controls afterwards).
        menuBarEngine.onHidingChange = { [weak self] hidden in
            self?.arrow?.show(hidden ? .collapsed : .expanded)
        }
    }

    private func setupUI() {
        if let button = btnSeparate.button {
            button.image = self.imgIconLine
            button.target = self
            button.action = #selector(self.showContextMenuFromSeparator(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        if let button = btnExpandCollapse.button {
            arrow = StatusBarArrow(button: button)
            arrow?.show(.expanded)
            button.target = self
            
            button.action = #selector(self.btnExpandCollapsePressed(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        btnExpandCollapse.autosaveName = "hiddenbar_expandcollapse";
        btnSeparate.autosaveName = "hiddenbar_separate";
    }
    
    @objc func btnExpandCollapsePressed(sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // AXPress synthesis carries no NSEvent; the resolver maps nil to .toggle
        // so VoiceOver can operate the bar.
        switch ExpandCollapseActionResolver.action(eventType: event?.type, optionPressed: event?.modifierFlags.contains(.option) ?? false) {
        case .toggle:
            self.expandCollapseIfNeeded()
        case .contextMenu:
            // Right-click opens the same menu the separator has (#356).
            showContextMenu(from: sender)
        }
    }

    @objc private func showContextMenuFromSeparator(sender: NSStatusBarButton) {
        showContextMenu(from: sender)
    }

    // Builds a brand-new NSMenu for every presentation rather than mutating
    // a reused one via a delegate callback (content changes on an
    // already-displayed-before NSMenu instance could leave its backing
    // window at a stale size until an unrelated redraw corrected it).
    //
    // Uses popUp(at:), not performClick(nil): this method is ITSELF called
    // from this same button's own action handler (a real click already in
    // progress). performClick(nil) here re-entered NSStatusBarButtonCell's
    // own sendAction dispatch, recursing into this handler again and
    // stack-overflowing (SIGSEGV, confirmed via crash report).
    //
    // Anchored at the button's BOTTOM edge (y: 0): anchoring above its top
    // edge put the menu's first row in the sliver above the visible screen,
    // where AppKit showed a scroll caret instead of rendering it.
    private func showContextMenu(from button: NSStatusBarButton) {
        let settings = SettingsMenu.Settings(startsAtLogin: Preferences.isAutoStart,
                                             autoCollapses: Preferences.isAutoHide,
                                             autoCollapseDelay: Preferences.numberOfSecondForAutoHide)
        settingsMenu.makeMenu(for: settings).popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    private func expandCollapseIfNeeded() {
        //prevented rapid click cause icon show many in Dock
        if isToggle {return}
        isToggle = true
        self.isCollapsed ? self.expandMenubar() : self.collapseMenuBar(origin: .user)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggle = false
        }
    }
    
    private func collapseMenuBar(origin: CollapseOrigin) {
        guard menuBarEngine.isArrangementValid && !self.isCollapsed else {
            autoCollapseIfNeeded()
            return
        }

        menuBarEngine.collapse(origin: origin) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .collapsed:
                self.arrow?.show(.collapsed)
            case .unavailable:
                // Nothing was hidden: the engine cannot hide on this system, or
                // is waiting for a permission.
                self.arrow?.show(.expanded)
            case .held:
                // A system control is on screen. Stay expanded and look again
                // after the auto-collapse delay, so the collapse goes through
                // once the control leaves.
                self.arrow?.show(.expanded)
                self.autoCollapseIfNeeded()
            }
        }
    }

    private func expandMenubar() {
        guard self.isCollapsed else {return}
        menuBarEngine.expand()
        arrow?.show(.expanded)
        autoCollapseIfNeeded()
    }
    
    private func autoCollapseIfNeeded() {
        guard Preferences.isAutoHide else {
            timer?.invalidate()
            return
        }
        guard !isCollapsed else { return }

        startTimerToAutoHide()
    }

    private func startTimerToAutoHide() {
        timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: Preferences.numberOfSecondForAutoHide, repeats: false) { [weak self] _ in
            guard let self = self, Preferences.isAutoHide else { return }
            // Don't yank the bar shut mid-interaction: while the pointer is in the
            // menubar (hovering, clicking, dragging icons), defer and re-arm.
            // Intentionally unbounded; each re-arm invalidates the previous timer,
            // so deferral never accumulates timers.
            if self.isMouseInMenuBar {
                self.startTimerToAutoHide()
            } else {
                self.collapseMenuBar(origin: .automatic)
            }
        }
    }

    @objc func updateAutoHide() {
        autoCollapseIfNeeded()
    }

    //MARK: - Settings

    private func toggleStartAtLogin() {
        let wanted = !Preferences.isAutoStart
        Preferences.isAutoStart = wanted
        // On failure the pref keeps the previous value, so the next menu shows
        // reality; tell the user why instead of swallowing the error.
        guard Preferences.isAutoStart != wanted else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Could not update the login item".localized
        alert.informativeText = "Check System Settings > General > Login Items and make sure Hidden Bar is allowed.".localized
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func chooseAutoCollapse(_ delay: TimeInterval?) {
        if let delay = delay {
            Preferences.numberOfSecondForAutoHide = delay
        }
        Preferences.isAutoHide = delay != nil
    }
}
