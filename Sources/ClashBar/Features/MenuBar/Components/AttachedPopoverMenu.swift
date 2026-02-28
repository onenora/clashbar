import AppKit
import SwiftUI

struct AttachedPopoverMenu<Label: View, Content: View>: View {
    let width: CGFloat?
    let maxHeight: CGFloat?
    let onWillPresent: (() -> Void)?
    let label: () -> Label
    let content: (_ dismiss: @escaping () -> Void) -> Content

    @State private var isAnchorHovered = false
    @State private var suppressAutoOpen = false
    @State private var shouldBuildPopoverContent = false

    init(
        width: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        onWillPresent: (() -> Void)? = nil,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> Content
    ) {
        self.width = width
        self.maxHeight = maxHeight
        self.onWillPresent = onWillPresent
        self.label = label
        self.content = content
    }

    var body: some View {
        label()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                requestOpen()
                suppressAutoOpen = false
                isAnchorHovered = true
            }
            .onHover { hovering in
                if hovering && !suppressAutoOpen {
                    requestOpen()
                }
                isAnchorHovered = hovering
                if !hovering {
                    suppressAutoOpen = false
                }
            }
            .background(
                SideAttachedPopoverHost(
                    anchorHovered: $isAnchorHovered,
                    suppressAutoOpen: $suppressAutoOpen,
                    width: width,
                    maxHeight: maxHeight,
                    onVisibilityChanged: { visible in
                        shouldBuildPopoverContent = visible
                    },
                    content: popoverContent
                )
            )
    }

    var popoverContent: AnyView {
        guard shouldBuildPopoverContent else {
            return AnyView(EmptyView())
        }

        return AnyView(
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    content {
                        dismissPopover()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: maxHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.46), lineWidth: 0.65)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.20), radius: 12, x: 0, y: 6)
        )
    }

    private func requestOpen() {
        onWillPresent?()
        shouldBuildPopoverContent = true
    }

    private func dismissPopover() {
        shouldBuildPopoverContent = false
        suppressAutoOpen = true
        isAnchorHovered = false
    }
}

struct AttachedPopoverMenuItem: View {
    let title: String
    var selected: Bool = false
    var destructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: MenuBarLayoutTokens.hDense) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(itemForeground)
            .padding(.horizontal, MenuBarLayoutTokens.hDense)
            .padding(.vertical, MenuBarLayoutTokens.vDense + 1)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(itemBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
    }

    private var itemForeground: Color {
        if isHovered {
            return Color(nsColor: .selectedMenuItemTextColor)
        }
        return destructive ? .red : .primary
    }

    private var itemBackground: Color {
        isHovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

struct AttachedPopoverMenuDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 2)
    }
}

@MainActor
private struct SideAttachedPopoverHost: NSViewRepresentable {
    @Binding var anchorHovered: Bool
    @Binding var suppressAutoOpen: Bool
    let width: CGFloat?
    let maxHeight: CGFloat?
    let onVisibilityChanged: ((Bool) -> Void)?
    let content: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(
            anchorHovered: $anchorHovered,
            suppressAutoOpen: $suppressAutoOpen,
            onVisibilityChanged: onVisibilityChanged
        )
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorHovered = $anchorHovered
        context.coordinator.suppressAutoOpen = $suppressAutoOpen
        context.coordinator.width = width
        context.coordinator.maxHeight = maxHeight
        context.coordinator.onVisibilityChanged = onVisibilityChanged
        context.coordinator.hostingController.rootView = content
        context.coordinator.sync(anchorView: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.closeNow()
    }

    @MainActor
    final class Coordinator: NSObject {
        private static var activeCoordinator: Coordinator?

        private enum HorizontalAttachmentSide {
            case left
            case right
        }

        var anchorHovered: Binding<Bool>
        var suppressAutoOpen: Binding<Bool>
        var width: CGFloat?
        var maxHeight: CGFloat?
        var onVisibilityChanged: ((Bool) -> Void)?

        let panel: SideAttachedMenuPanel
        let hostingController: NSHostingController<AnyView>

        private weak var anchorView: NSView?
        private weak var hostWindow: NSWindow?
        private var panelTrackingArea: NSTrackingArea?
        private var panelHovering = false
        private var localMouseMonitor: Any?
        private var closeWorkItem: DispatchWorkItem?
        private var attachmentSide: HorizontalAttachmentSide = .right
        private let bridgeVerticalPadding: CGFloat = 14
        private let edgeOverlap: CGFloat = 1
        private let closeDebounce: TimeInterval = 0.10
        private var reportedVisible = false

        init(
            anchorHovered: Binding<Bool>,
            suppressAutoOpen: Binding<Bool>,
            onVisibilityChanged: ((Bool) -> Void)?
        ) {
            self.anchorHovered = anchorHovered
            self.suppressAutoOpen = suppressAutoOpen
            self.onVisibilityChanged = onVisibilityChanged
            self.hostingController = NSHostingController(rootView: AnyView(EmptyView()))
            self.panel = SideAttachedMenuPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )

            super.init()

            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = true
            panel.level = .statusBar
            panel.collectionBehavior = [.transient, .moveToActiveSpace, .ignoresCycle]
            panel.contentViewController = hostingController
            panel.acceptsMouseMovedEvents = true

            installTrackingAreaIfNeeded()
        }

        func sync(anchorView: NSView) {
            self.anchorView = anchorView
            self.hostWindow = anchorView.window
            installTrackingAreaIfNeeded()

            let shouldShow = anchorHovered.wrappedValue && !suppressAutoOpen.wrappedValue
            if shouldShow {
                cancelPendingClose()
                showOrUpdate()
                return
            }

            if suppressAutoOpen.wrappedValue {
                closeNow()
            } else {
                evaluateAndCloseIfNeeded()
            }
        }

        private func showOrUpdate() {
            guard
                let anchorView,
                let hostWindow
            else { return }

            let fitting = hostingController.view.fittingSize
            let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorRectOnScreen = hostWindow.convertToScreen(anchorRectInWindow)
            let visibleFrame = hostWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            guard visibleFrame != .zero else { return }

            let contentWidth = max(fitting.width, anchorRectOnScreen.width)
            let panelWidth = min(max(80, contentWidth), visibleFrame.width - 8)

            let contentHeight: CGFloat
            if let maxHeight {
                contentHeight = min(fitting.height, maxHeight + 16)
            } else {
                contentHeight = fitting.height
            }
            let panelHeight = min(max(40, contentHeight), visibleFrame.height - 12)

            let rightAvailable = max(0, visibleFrame.maxX - hostWindow.frame.maxX)
            let leftAvailable = max(0, hostWindow.frame.minX - visibleFrame.minX)
            let minimumUsableWidth = min(panelWidth, CGFloat(180))

            let showRight: Bool
            if rightAvailable >= minimumUsableWidth {
                showRight = true
            } else if leftAvailable >= minimumUsableWidth {
                showRight = false
            } else {
                showRight = rightAvailable >= leftAvailable
            }
            attachmentSide = showRight ? .right : .left

            let sideAvailable = showRight ? rightAvailable : leftAvailable
            let resolvedPanelWidth = max(80, min(panelWidth, sideAvailable))
            let panelSize = NSSize(width: resolvedPanelWidth, height: panelHeight)

            let rawOriginX = showRight
                ? hostWindow.frame.maxX - edgeOverlap
                : hostWindow.frame.minX - panelSize.width + edgeOverlap
            let minX = visibleFrame.minX
            let maxX = visibleFrame.maxX - panelSize.width
            let originX = max(minX, min(rawOriginX, maxX))

            let desiredY = anchorRectOnScreen.midY - panelSize.height / 2
            let minY = visibleFrame.minY + 6
            let maxY = visibleFrame.maxY - panelSize.height - 6
            let originY = max(minY, min(desiredY, maxY))

            panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize), display: true)
            ensureExclusiveVisibility()

            if !panel.isVisible {
                panel.orderFront(nil)
            }
            reportVisibility(true)
            startLocalMouseMonitorIfNeeded()
        }

        private func evaluateAndCloseIfNeeded() {
            guard panel.isVisible else {
                cancelPendingClose()
                stopLocalMouseMonitor()
                return
            }
            if panelHovering {
                cancelPendingClose()
                return
            }
            let mouse = NSEvent.mouseLocation
            if isMouseInActiveArea(mouse) {
                cancelPendingClose()
                return
            }
            scheduleClose()
        }

        func closeNow() {
            cancelPendingClose()
            stopLocalMouseMonitor()
            if panel.isVisible {
                panel.orderOut(nil)
            }
            hostingController.rootView = AnyView(EmptyView())
            panelHovering = false
            reportVisibility(false)
            if Self.activeCoordinator === self {
                Self.activeCoordinator = nil
            }
        }

        private func reportVisibility(_ visible: Bool) {
            guard reportedVisible != visible else { return }
            reportedVisible = visible
            guard let onVisibilityChanged else { return }
            DispatchQueue.main.async {
                onVisibilityChanged(visible)
            }
        }

        private func ensureExclusiveVisibility() {
            if let active = Self.activeCoordinator, active !== self {
                active.anchorHovered.wrappedValue = false
                active.closeNow()
            }
            Self.activeCoordinator = self
        }

        private func scheduleClose() {
            guard closeWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWorkItem = nil

                guard self.panel.isVisible else { return }
                if self.panelHovering { return }

                let mouse = NSEvent.mouseLocation
                if self.isMouseInActiveArea(mouse) { return }

                self.closeNow()
            }
            closeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDebounce, execute: work)
        }

        private func cancelPendingClose() {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        }

        private func startLocalMouseMonitorIfNeeded() {
            guard localMouseMonitor == nil else { return }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] event in
                self?.evaluateAndCloseIfNeeded()
                return event
            }
        }

        private func stopLocalMouseMonitor() {
            guard let localMouseMonitor else { return }
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        private func isMouseInActiveArea(_ point: NSPoint) -> Bool {
            guard let rects = activityRects() else { return false }
            return rects.trigger.contains(point) || rects.panel.contains(point) || rects.bridge.contains(point)
        }

        private func activityRects() -> (trigger: NSRect, panel: NSRect, bridge: NSRect)? {
            guard panel.isVisible else { return nil }
            guard let anchorView, let hostWindow else { return nil }

            let triggerRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let triggerRect = hostWindow.convertToScreen(triggerRectInWindow)
            let panelRect = panel.frame

            let bridgeMinY = min(triggerRect.minY - bridgeVerticalPadding, panelRect.minY)
            let bridgeMaxY = max(triggerRect.maxY + bridgeVerticalPadding, panelRect.maxY)
            let bridgeHeight = max(0, bridgeMaxY - bridgeMinY)

            let bridgeRect: NSRect
            switch attachmentSide {
            case .right:
                let bridgeX = triggerRect.maxX
                let bridgeWidth = max(0, panelRect.minX - triggerRect.maxX)
                bridgeRect = NSRect(x: bridgeX, y: bridgeMinY, width: bridgeWidth, height: bridgeHeight)
            case .left:
                let bridgeX = panelRect.maxX
                let bridgeWidth = max(0, triggerRect.minX - panelRect.maxX)
                bridgeRect = NSRect(x: bridgeX, y: bridgeMinY, width: bridgeWidth, height: bridgeHeight)
            }

            return (triggerRect, panelRect, bridgeRect)
        }

        private func installTrackingAreaIfNeeded() {
            let view = hostingController.view
            if let panelTrackingArea {
                view.removeTrackingArea(panelTrackingArea)
            }
            let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
            let tracking = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            view.addTrackingArea(tracking)
            panelTrackingArea = tracking
        }

        @objc(mouseEntered:)
        func mouseEntered(_ event: NSEvent) {
            panelHovering = true
            cancelPendingClose()
        }

        @objc(mouseExited:)
        func mouseExited(_ event: NSEvent) {
            panelHovering = false
            evaluateAndCloseIfNeeded()
        }
    }
}

@MainActor
private final class SideAttachedMenuPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
