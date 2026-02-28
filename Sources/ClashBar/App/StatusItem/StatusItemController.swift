import AppKit
import Combine
import SwiftUI

@MainActor
final class PopoverLayoutModel: ObservableObject {
    @Published var maxPanelHeight: CGFloat
    @Published var preferredPanelHeight: CGFloat

    init(maxPanelHeight: CGFloat = 640, preferredPanelHeight: CGFloat = 600) {
        self.maxPanelHeight = maxPanelHeight
        self.preferredPanelHeight = preferredPanelHeight
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let panel: FloatingPanel
    private let statusContentView: StatusItemContentView
    private let popoverLayoutModel = PopoverLayoutModel()
    private let popoverContentWidth: CGFloat = 340
    private let popoverFallbackMaxHeight: CGFloat = 640
    private let popoverMinimumHeight: CGFloat = 280
    private let popoverScreenPadding: CGFloat = 10
    private let panelTopSpacing: CGFloat = 6
    private let panelHorizontalPadding: CGFloat = MenuBarLayoutTokens.hPage

    private var changeCancellable: AnyCancellable?
    private var layoutCancellable: AnyCancellable?
    private var refreshWorkItem: DispatchWorkItem?
    private var lastRenderedDisplay: MenuBarDisplay?
    private var globalEventMonitor: Any?
    private var screenParametersObserver: Any?
    private var lockedPanelOriginX: CGFloat?
    private var popoverHostingController: NSHostingController<AnyView>?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: popoverContentWidth, height: popoverLayoutModel.preferredPanelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        self.statusContentView = StatusItemContentView(frame: .zero)

        super.init()

        configurePanel()
        configureStatusItem()
        bindAppState()
        bindPopoverLayout()
        observeScreenParameterChanges()
        refreshPopoverMaximumHeight()
        refreshDisplayNow()
    }

    func shutdown() {
        refreshWorkItem?.cancel()
        changeCancellable?.cancel()
        layoutCancellable?.cancel()
        stopGlobalMonitor()
        stopObservingScreenParameters()
        unloadPopoverContent()
        appState.setPanelVisibility(false)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if panel.isVisible {
            closePopover(nil)
            return
        }

        ensurePopoverContent()
        refreshPopoverMaximumHeight()
        applyPopoverSize(preferredHeight: popoverLayoutModel.preferredPanelHeight, preserveHorizontalPosition: false)
        placePanelRelativeToStatusButton(button, preserveHorizontalPosition: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startGlobalMonitor()
        appState.setPanelVisibility(true)
    }

    @objc
    private func closePopover(_ sender: Any?) {
        panel.orderOut(sender)
        lockedPanelOriginX = nil
        stopGlobalMonitor()
        unloadPopoverContent()
        appState.setPanelVisibility(false)
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
        panel.contentViewController = nil
    }

    private func ensurePopoverContent() {
        if popoverHostingController == nil {
            popoverHostingController = NSHostingController(rootView: makePopoverRootView())
        } else {
            popoverHostingController?.rootView = makePopoverRootView()
        }
        panel.contentViewController = popoverHostingController
    }

    private func unloadPopoverContent() {
        panel.contentViewController = nil
        popoverHostingController = nil
    }

    private func makePopoverRootView() -> AnyView {
        AnyView(
            MenuBarRoot()
                .environmentObject(appState)
                .environmentObject(popoverLayoutModel)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        statusContentView.frame = button.bounds
        statusContentView.autoresizingMask = [.width, .height]
        button.addSubview(statusContentView)
    }

    private func bindAppState() {
        changeCancellable = appState.$menuBarDisplaySnapshot
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] display in
                self?.scheduleRefresh(display: display)
            }
    }

    private func bindPopoverLayout() {
        layoutCancellable = popoverLayoutModel.$preferredPanelHeight
            .receive(on: RunLoop.main)
            .sink { [weak self] preferredHeight in
                self?.applyPopoverSize(preferredHeight: preferredHeight, preserveHorizontalPosition: true)
            }
    }

    private func scheduleRefresh(display: MenuBarDisplay) {
        refreshWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.refreshDisplay(display)
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    private func refreshDisplayNow() {
        refreshDisplay(appState.menuBarDisplaySnapshot)
    }

    private func refreshDisplay(_ display: MenuBarDisplay) {
        guard display != lastRenderedDisplay else { return }

        statusContentView.apply(display: display)
        statusItem.length = statusContentView.requiredWidth
        lastRenderedDisplay = display
    }

    private func startGlobalMonitor() {
        stopGlobalMonitor()
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover(nil)
            }
        }
    }

    private func stopGlobalMonitor() {
        guard let globalEventMonitor else { return }
        NSEvent.removeMonitor(globalEventMonitor)
        self.globalEventMonitor = nil
    }

    private func observeScreenParameterChanges() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPopoverMaximumHeight()
            }
        }
    }

    private func stopObservingScreenParameters() {
        guard let screenParametersObserver else { return }
        NotificationCenter.default.removeObserver(screenParametersObserver)
        self.screenParametersObserver = nil
    }

    private func refreshPopoverMaximumHeight() {
        let maximumHeight = computeMaximumPopoverHeight()
        if abs(popoverLayoutModel.maxPanelHeight - maximumHeight) > 0.5 {
            popoverLayoutModel.maxPanelHeight = maximumHeight
        }
    }

    private func computeMaximumPopoverHeight() -> CGFloat {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window
        else {
            return popoverFallbackMaxHeight
        }

        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else { return popoverFallbackMaxHeight }

        let visibleFrame = screen.visibleFrame
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let availableHeightBelowButton = buttonFrameOnScreen.minY - visibleFrame.minY - popoverScreenPadding - panelTopSpacing
        let visibleHeight = visibleFrame.height - popoverScreenPadding
        let maximumHeight = min(availableHeightBelowButton, visibleHeight)

        return max(1, maximumHeight.rounded(.down))
    }

    private func applyPopoverSize(preferredHeight: CGFloat, preserveHorizontalPosition: Bool) {
        let maximumHeight = max(1, popoverLayoutModel.maxPanelHeight)
        let minimumHeight = min(popoverMinimumHeight, maximumHeight)
        let clampedHeight = max(minimumHeight, min(preferredHeight, maximumHeight)).rounded(.down)
        let targetSize = NSSize(width: popoverContentWidth, height: clampedHeight)

        let widthChanged = abs(panel.frame.width - targetSize.width) > 0.5
        let heightChanged = abs(panel.frame.height - targetSize.height) > 0.5
        guard widthChanged || heightChanged else { return }

        if panel.isVisible,
           let origin = resolvedPanelOrigin(
               for: statusItem.button,
               panelSize: targetSize,
               preserveHorizontalPosition: preserveHorizontalPosition
           ) {
            let frame = NSRect(origin: origin, size: targetSize)
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        var newFrame = panel.frame
        newFrame.size = targetSize
        panel.setFrame(newFrame, display: true, animate: false)
    }

    private func placePanelRelativeToStatusButton(_ button: NSStatusBarButton?, preserveHorizontalPosition: Bool) {
        guard let origin = resolvedPanelOrigin(
            for: button,
            panelSize: panel.frame.size,
            preserveHorizontalPosition: preserveHorizontalPosition
        ) else {
            return
        }
        panel.setFrameOrigin(origin)
    }

    private func resolvedPanelOrigin(
        for button: NSStatusBarButton?,
        panelSize: NSSize,
        preserveHorizontalPosition: Bool
    ) -> NSPoint? {
        guard
            let button,
            let buttonWindow = button.window
        else {
            return nil
        }

        let screen = buttonWindow.screen ?? NSScreen.main
        guard let screen else { return nil }

        let visibleFrame = screen.visibleFrame
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        let panelWidth = panelSize.width
        let panelHeight = panelSize.height
        let minX = visibleFrame.minX + panelHorizontalPadding
        let maxX = visibleFrame.maxX - panelHorizontalPadding - panelWidth

        let centeredX = buttonFrameOnScreen.midX - panelWidth / 2
        let lockedX = lockedPanelOriginX ?? centeredX
        let targetX = preserveHorizontalPosition ? lockedX : centeredX
        let clampedX = min(max(targetX, minX), maxX)

        if !preserveHorizontalPosition || lockedPanelOriginX == nil {
            lockedPanelOriginX = clampedX
        }

        let topY = buttonFrameOnScreen.minY - panelTopSpacing
        let minY = visibleFrame.minY + popoverScreenPadding
        let targetY = max(minY, topY - panelHeight)

        return NSPoint(x: clampedX, y: targetY)
    }
}
