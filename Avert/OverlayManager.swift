import AppKit
import QuartzCore

enum PanicCoverMode: Equatable {
    case solidBlack
    case image(NSImage)
}

/// Full-display privacy overlays: side veil, look-down dim, look-up / panic cover.
@MainActor
final class OverlayManager {
    private var panels: [NSNumber: OverlayPanel] = [:]
    private var fadeDuration: TimeInterval = 0.2
    private var coverage: DisplayCoverage = .allDisplays
    private(set) var panicActive = false
    private var panicCoverMode: PanicCoverMode = .solidBlack

    private let nearOpacity: CGFloat = 1.0
    private let farOpacity: CGFloat = 0.14
    private let baseHeavyZoneEnd: CGFloat = 0.68

    func setFadeDuration(_ duration: TimeInterval) {
        fadeDuration = duration
    }

    func setDisplayCoverage(_ coverage: DisplayCoverage) {
        self.coverage = coverage
        recreateForDisplayChange()
    }

    func setPanicCoverMode(_ mode: PanicCoverMode) {
        panicCoverMode = mode
        for overlay in panels.values {
            overlay.configurePanicCover(mode)
        }
        if panicActive {
            applyPanic(true)
        }
    }

    func apply(_ intent: BlurIntent) {
        if panicActive {
            applyPanic(true)
            return
        }

        ensurePanelsForCurrentDisplays()

        if intent.lookUpPanic {
            for overlay in panels.values {
                overlay.applyPanicCover(mode: panicCoverMode, duration: fadeDuration)
            }
            return
        }

        let heavy = min(0.82, baseHeavyZoneEnd + CGFloat(intent.intensity) * 0.12)

        for overlay in panels.values {
            overlay.apply(
                side: intent.side,
                strength: intent.intensity,
                lookDownDim: intent.lookDownDim,
                near: nearOpacity,
                far: farOpacity,
                heavyZoneEnd: heavy,
                duration: fadeDuration
            )
        }
    }

    @discardableResult
    func togglePanic() -> Bool {
        setPanic(!panicActive)
    }

    @discardableResult
    func setPanic(_ on: Bool) -> Bool {
        guard panicActive != on else { return panicActive }
        panicActive = on
        applyPanic(on)
        return panicActive
    }

    func clearPanic() {
        _ = setPanic(false)
        apply(.clear)
    }

    private func applyPanic(_ on: Bool) {
        ensurePanelsForCurrentDisplays()
        if on {
            for overlay in panels.values {
                overlay.applyPanicCover(mode: panicCoverMode, duration: fadeDuration)
            }
        } else {
            for overlay in panels.values {
                overlay.apply(
                    side: .none,
                    strength: 0,
                    lookDownDim: 0,
                    near: nearOpacity,
                    far: farOpacity,
                    heavyZoneEnd: baseHeavyZoneEnd,
                    duration: fadeDuration
                )
            }
        }
    }

    func clear() {
        if panicActive { return }
        apply(.clear)
    }

    func tearDown() {
        for overlay in panels.values {
            overlay.tearDown()
        }
        panels.removeAll()
    }

    func recreateForDisplayChange() {
        tearDown()
        ensurePanelsForCurrentDisplays()
    }

    private func ensurePanelsForCurrentDisplays() {
        let screens: [NSScreen]
        switch coverage {
        case .allDisplays:
            screens = NSScreen.screens
        case .mainOnly:
            screens = NSScreen.main.map { [$0] } ?? NSScreen.screens
        }
        let ids = Set(screens.map(\.displayIDNumber))

        for key in panels.keys where !ids.contains(key) {
            panels[key]?.tearDown()
            panels.removeValue(forKey: key)
        }

        for screen in screens {
            let id = screen.displayIDNumber
            if let existing = panels[id] {
                existing.layout(on: screen)
                existing.configurePanicCover(panicCoverMode)
            } else {
                let panel = OverlayPanel(screen: screen)
                panel.configurePanicCover(panicCoverMode)
                panels[id] = panel
            }
        }
    }
}

@MainActor
private final class OverlayPanel {
    private let panel: NSPanel
    private let container: NSView
    private let sideRoot: NSView
    private let effectView: NSVisualEffectView
    private let tintView: NSView
    private let lookDownView: NSView
    private let panicRoot: NSView
    private let panicBlackView: NSView
    private let panicImageView: NSImageView
    private let maskLayer = CAGradientLayer()

    private let tintAlpha: CGFloat = 0.62

    init(screen: NSScreen) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        container = NSView(frame: .zero)
        container.wantsLayer = true

        sideRoot = NSView(frame: .zero)
        sideRoot.wantsLayer = true
        sideRoot.alphaValue = 0
        sideRoot.autoresizingMask = [.width, .height]

        effectView = NSVisualEffectView(frame: .zero)
        effectView.material = .fullScreenUI
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.autoresizingMask = [.width, .height]

        tintView = NSView(frame: .zero)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor
        tintView.autoresizingMask = [.width, .height]

        lookDownView = NSView(frame: .zero)
        lookDownView.wantsLayer = true
        // Opaque black — strength is driven only by view alpha (was too faint at 0.45 × dim).
        lookDownView.layer?.backgroundColor = NSColor.black.cgColor
        lookDownView.alphaValue = 0
        lookDownView.autoresizingMask = [.width, .height]

        panicRoot = NSView(frame: .zero)
        panicRoot.wantsLayer = true
        panicRoot.alphaValue = 0
        panicRoot.autoresizingMask = [.width, .height]

        panicBlackView = NSView(frame: .zero)
        panicBlackView.wantsLayer = true
        panicBlackView.layer?.backgroundColor = NSColor.black.cgColor
        panicBlackView.autoresizingMask = [.width, .height]

        panicImageView = NSImageView(frame: .zero)
        panicImageView.imageScaling = .scaleAxesIndependently
        panicImageView.imageAlignment = .alignCenter
        panicImageView.autoresizingMask = [.width, .height]
        panicImageView.isHidden = true

        sideRoot.addSubview(effectView)
        sideRoot.addSubview(tintView)
        panicRoot.addSubview(panicBlackView)
        panicRoot.addSubview(panicImageView)
        container.addSubview(sideRoot)
        container.addSubview(lookDownView)
        container.addSubview(panicRoot)

        maskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        maskLayer.colors = Array(repeating: NSColor.clear.cgColor, count: 4)
        maskLayer.locations = [0, 0.68, 0.85, 1]
        sideRoot.layer?.mask = maskLayer

        panel.contentView = container
        layout(on: screen)
        panel.orderFrontRegardless()
    }

    func configurePanicCover(_ mode: PanicCoverMode) {
        switch mode {
        case .solidBlack:
            panicImageView.image = nil
            panicImageView.isHidden = true
            panicBlackView.isHidden = false
        case .image(let image):
            panicImageView.image = image
            panicImageView.isHidden = false
            panicBlackView.isHidden = true
        }
    }

    func layout(on screen: NSScreen) {
        panel.setFrame(screen.frame, display: true)
        let bounds = container.bounds
        sideRoot.frame = bounds
        effectView.frame = bounds
        tintView.frame = bounds
        lookDownView.frame = bounds
        panicRoot.frame = bounds
        panicBlackView.frame = bounds
        panicImageView.frame = bounds
        maskLayer.frame = bounds
    }

    func apply(
        side: BlurSide,
        strength: Double,
        lookDownDim: Double,
        near: CGFloat,
        far: CGFloat,
        heavyZoneEnd: CGFloat,
        duration: TimeInterval
    ) {
        let bounds = container.bounds
        sideRoot.frame = bounds
        effectView.frame = bounds
        tintView.frame = bounds
        lookDownView.frame = bounds
        panicRoot.frame = bounds
        maskLayer.frame = bounds

        let strengthClamp = CGFloat(min(1, max(0, strength)))
        let gate: CGFloat = side == .none ? 0 : max(strengthClamp, 0.85)
        let nearA = near * gate
        let midA = ((near + far) / 2) * gate
        let farA = far * gate
        let heavy = min(0.85, max(0.55, heavyZoneEnd))
        let soft = min(0.95, heavy + 0.18)

        let colors: [CGColor]
        let locations: [NSNumber]
        switch side {
        case .none:
            colors = Array(repeating: NSColor.clear.cgColor, count: 4)
            locations = [0, NSNumber(value: Double(heavy)), NSNumber(value: Double(soft)), 1]
        case .left:
            colors = [
                NSColor.white.withAlphaComponent(nearA).cgColor,
                NSColor.white.withAlphaComponent(nearA).cgColor,
                NSColor.white.withAlphaComponent(midA).cgColor,
                NSColor.white.withAlphaComponent(farA).cgColor,
            ]
            locations = [0, NSNumber(value: Double(heavy)), NSNumber(value: Double(soft)), 1]
        case .right:
            colors = [
                NSColor.white.withAlphaComponent(farA).cgColor,
                NSColor.white.withAlphaComponent(midA).cgColor,
                NSColor.white.withAlphaComponent(nearA).cgColor,
                NSColor.white.withAlphaComponent(nearA).cgColor,
            ]
            locations = [0, NSNumber(value: Double(1 - soft)), NSNumber(value: Double(1 - heavy)), 1]
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        maskLayer.colors = colors
        maskLayer.locations = locations
        CATransaction.commit()

        let sideAlpha: CGFloat = side == .none ? 0 : 1
        let downAlpha = CGFloat(min(1, max(0, lookDownDim)))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sideRoot.animator().alphaValue = sideAlpha
            lookDownView.animator().alphaValue = downAlpha
            panicRoot.animator().alphaValue = 0
        }

        if side != .none || lookDownDim > 0.01 {
            panel.orderFrontRegardless()
        } else if sideRoot.alphaValue < 0.02 && lookDownView.alphaValue < 0.02 && panicRoot.alphaValue < 0.02 {
            panel.orderOut(nil)
        }
    }

    func applyPanicCover(mode: PanicCoverMode, duration: TimeInterval) {
        configurePanicCover(mode)
        let bounds = container.bounds
        panicRoot.frame = bounds
        panicBlackView.frame = bounds
        panicImageView.frame = bounds

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            sideRoot.animator().alphaValue = 0
            lookDownView.animator().alphaValue = 0
            panicRoot.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
    }

    func tearDown() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

private extension NSScreen {
    var displayIDNumber: NSNumber {
        let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return NSNumber(value: id)
    }
}
