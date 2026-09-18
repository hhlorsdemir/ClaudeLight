import Cocoa

// ClaudeLight — a traffic light on the screen edge showing Claude Code and Codex status.
// State source: ~/.claude/claude-light/state/<session_id> files ("working" | "waiting").
// Yellow takes priority when input is needed; red means no tracked activity.

enum Side: String { case left, right }

let sideKey = "ClaudeLightSide"
let yKey = "ClaudeLightY"
let compactKey = "ClaudeLightCompact"
let normalSize = NSSize(width: 18, height: 92)
let compactSize = NSSize(width: 18, height: 44)

final class LightView: NSView {
    var state = LightState() { didSet { if state != oldValue { needsDisplay = true } } }
    var side: Side = .right { didSet { needsDisplay = true } }
    var compact = false { didSet { needsDisplay = true } }
    weak var controller: AppDelegate?

    override func draw(_ dirtyRect: NSRect) {
        // A bump that flares out of the edge, flat in the middle, tapering back at both ends.
        // Drawn for the right edge; mirrored on x for the left edge.
        let r = bounds
        let flare: CGFloat = compact ? 14 : 20
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.maxX, y: r.maxY))
        path.curve(to: NSPoint(x: r.minX, y: r.maxY - flare),
                   controlPoint1: NSPoint(x: r.maxX, y: r.maxY - flare * 0.55),
                   controlPoint2: NSPoint(x: r.minX, y: r.maxY - flare * 0.45))
        path.line(to: NSPoint(x: r.minX, y: r.minY + flare))
        path.curve(to: NSPoint(x: r.maxX, y: r.minY),
                   controlPoint1: NSPoint(x: r.minX, y: r.minY + flare * 0.45),
                   controlPoint2: NSPoint(x: r.maxX, y: r.minY + flare * 0.55))
        path.close()
        if side == .left {
            let t = NSAffineTransform()
            t.translateX(by: r.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            path.transform(using: t as AffineTransform)
        }
        NSColor.black.setFill()
        path.fill()

        let green  = NSColor(calibratedRed: 0.20, green: 0.85, blue: 0.35, alpha: 1)
        let yellow = NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.15, alpha: 1)
        let red    = NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.30, alpha: 1)
        let d: CGFloat = 7, gap: CGFloat = 9

        func dot(_ rect: NSRect, _ color: NSColor, on: Bool) {
            if on {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = color
                shadow.shadowBlurRadius = 4
                shadow.set()
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                color.withAlphaComponent(0.14).setFill()
                NSBezierPath(ovalIn: rect).fill()
            }
        }

        let x = r.midX - d / 2
        if compact {
            // Single light: requests for input take priority over background work.
            let color = state.waiting ? yellow : (state.working ? green : red)
            dot(NSRect(x: x, y: r.midY - d / 2, width: d, height: d), color, on: true)
        } else {
            let lights: [(Bool, NSColor)] = [(state.working && !state.waiting, green), (state.waiting, yellow), (state.idle, red)]
            let total = 3 * d + 2 * gap
            var y = r.midY + total / 2 - d
            for (on, color) in lights {
                dot(NSRect(x: x, y: y, width: d, height: d), color, on: on)
                y -= d + gap
            }
        }
    }

    // Left click: switch to the most recently active agent. Drag: vertical only, glued to the edge.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let w = window, let c = controller else { return }
        let grabOffsetY = NSEvent.mouseLocation.y - w.frame.origin.y
        let startY = w.frame.origin.y
        var didDrag = false
        // Track events here until the mouse is released
        while let e = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let targetY = NSEvent.mouseLocation.y - grabOffsetY
            if !didDrag && abs(targetY - startY) > 3 { didDrag = true }
            if didDrag { c.place(y: targetY) }
        }
        if didDrag { c.saveY(); return }
        // Read at click time so activity since the last refresh is included.
        guard let agent = readState().latestAgent else { return }
        let bundleID = agent.bundleIdentifier
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let left = menu.addItem(withTitle: "Snap to Left Edge", action: #selector(AppDelegate.snapLeft), keyEquivalent: "")
        let right = menu.addItem(withTitle: "Snap to Right Edge", action: #selector(AppDelegate.snapRight), keyEquivalent: "")
        left.state = side == .left ? .on : .off
        right.state = side == .right ? .on : .off
        menu.addItem(.separator())
        let small = menu.addItem(withTitle: "Compact", action: #selector(AppDelegate.toggleCompact), keyEquivalent: "")
        small.state = compact ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClaudeLight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: LightView!
    var timer: Timer?
    var side: Side = Side(rawValue: UserDefaults.standard.string(forKey: sideKey) ?? "") ?? .right
    var compact = UserDefaults.standard.bool(forKey: compactKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = compact ? compactSize : normalSize
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        view = LightView(frame: NSRect(origin: .zero, size: size))
        view.side = side
        view.compact = compact
        view.controller = self
        panel.contentView = view

        let savedY = UserDefaults.standard.object(forKey: yKey) as? CGFloat
        place(y: savedY ?? (screen().visibleFrame.midY - size.height / 2))
        panel.orderFrontRegardless()

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func screen() -> NSScreen {
        panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Glues the panel to the chosen edge and keeps its vertical position on screen.
    func place(y: CGFloat) {
        let vf = screen().visibleFrame
        let size = panel.frame.size
        let x = side == .right ? vf.maxX - size.width : vf.minX
        let clampedY = min(max(y, vf.minY), vf.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: clampedY))
    }

    func saveY() { UserDefaults.standard.set(panel.frame.origin.y, forKey: yKey) }

    func setSide(_ s: Side) {
        side = s
        view.side = s
        UserDefaults.standard.set(s.rawValue, forKey: sideKey)
        place(y: panel.frame.origin.y)
    }

    @objc func toggleCompact() {
        compact.toggle()
        view.compact = compact
        UserDefaults.standard.set(compact, forKey: compactKey)
        let midY = panel.frame.midY
        let size = compact ? compactSize : normalSize
        panel.setContentSize(size)
        place(y: midY - size.height / 2)
        saveY()
    }

    @objc func snapLeft() { setSide(.left) }
    @objc func snapRight() { setSide(.right) }

    @objc func screenChanged() { place(y: panel.frame.origin.y) }

    func refresh() { view.state = readState() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
