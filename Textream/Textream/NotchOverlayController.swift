import AppKit
import SwiftUI
import Combine

class NotchOverlayController: NSObject {
    private var panel: NSPanel?
    private(set) var tracker: PresentationTracker?
    var onComplete: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var mouseTrackingTimer: AnyCancellable?
    private var currentScreenID: UInt32 = 0
    private var escMonitor: Any?

    var isShowing: Bool { panel != nil }

    // MARK: - Show Coaching Overlay

    func show(storyline: Storyline, onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
        forceClose()

        let tracker = PresentationTracker(storyline: storyline)
        self.tracker = tracker

        let settings = NotchSettings.shared

        let screen: NSScreen
        switch settings.notchDisplayMode {
        case .followMouse:
            screen = screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        case .fixedDisplay:
            screen = NSScreen.screens.first(where: { $0.displayID == settings.pinnedScreenID })
                ?? NSScreen.main ?? NSScreen.screens[0]
        }

        if settings.overlayMode == .floating {
            showFloating(settings: settings, screen: screen, tracker: tracker)
        } else {
            showPinned(settings: settings, screen: screen, tracker: tracker)
        }

        installKeyMonitor()
        tracker.start()
    }

    // MARK: - Pinned (Notch) Mode

    private func showPinned(settings: NotchSettings, screen: NSScreen, tracker: PresentationTracker) {
        let notchWidth = settings.notchWidth
        let textAreaHeight = settings.textAreaHeight
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

        let totalHeight = menuBarHeight + textAreaHeight
        let xPosition = screenFrame.midX - notchWidth / 2
        let yPosition = screenFrame.maxY - totalHeight

        let overlayView = CoachingOverlayView(
            tracker: tracker,
            onStop: { [weak self] in self?.dismiss() },
            menuBarHeight: menuBarHeight
        )

        let hostingView = NSHostingView(rootView:
            ZStack(alignment: .top) {
                DynamicIslandShape(topInset: 16, bottomRadius: 18)
                    .fill(.black)
                    .frame(width: notchWidth, height: totalHeight)

                overlayView
                    .frame(width: notchWidth, height: totalHeight)
            }
            .frame(width: notchWidth, height: totalHeight)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: notchWidth, height: totalHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.sharingType = settings.hideFromScreenShare ? .none : .readOnly
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
        self.currentScreenID = screen.displayID

        if settings.notchDisplayMode == .followMouse {
            startMouseTracking(width: notchWidth, height: totalHeight)
        }
    }

    // MARK: - Floating Mode

    private func showFloating(settings: NotchSettings, screen: NSScreen, tracker: PresentationTracker) {
        let panelWidth = settings.notchWidth
        let panelHeight = settings.textAreaHeight
        let screenFrame = screen.frame

        let xPosition = screenFrame.midX - panelWidth / 2
        let yPosition = screenFrame.midY - panelHeight / 2 + 100

        let floatingView = FloatingCoachingOverlayView(
            tracker: tracker,
            onStop: { [weak self] in self?.dismiss() }
        )
        let hostingView = NSHostingView(rootView: floatingView)

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = settings.hideFromScreenShare ? .none : .readOnly
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
    }

    // MARK: - Dismiss

    func dismiss() {
        tracker?.stop()

        stopMouseTracking()
        removeEscMonitor()
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        tracker = nil
        onComplete?()
    }

    private func forceClose() {
        tracker?.stop()
        stopMouseTracking()
        removeEscMonitor()
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
        tracker = nil
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // ESC
                self.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
        }
        escMonitor = nil
    }

    // MARK: - Mouse Tracking (follow-mouse for pinned mode)

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }

    private func startMouseTracking(width: CGFloat, height: CGFloat) {
        mouseTrackingTimer?.cancel()
        mouseTrackingTimer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkMouseScreen(width: width, height: height)
            }
    }

    private func stopMouseTracking() {
        mouseTrackingTimer?.cancel()
        mouseTrackingTimer = nil
    }

    private func checkMouseScreen(width: CGFloat, height: CGFloat) {
        guard let panel else { return }
        guard let mouseScreen = screenUnderMouse() else { return }
        let mouseScreenID = mouseScreen.displayID
        guard mouseScreenID != currentScreenID else { return }

        currentScreenID = mouseScreenID
        let screenFrame = mouseScreen.frame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

// MARK: - Dynamic Island Shape

struct DynamicIslandShape: Shape {
    var topInset: CGFloat = 16
    var bottomRadius: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topInset, bottomRadius) }
        set {
            topInset = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = topInset
        let br = bottomRadius
        var p = Path()

        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - br))
        p.addQuadCurve(to: CGPoint(x: t + br, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - br, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - br), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - NSScreen Display ID Helper

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    var displayName: String {
        localizedName
    }
}
