import AppKit

final class StatusItemContentView: NSView {
    // Keep a 1pt optical inset to stabilize status-item width across icon/text mode switches.
    private let statusItemHorizontalPadding: CGFloat = MenuBarLayoutTokens.opticalNudge
    private let iconSize: CGFloat = 24
    private let brandIconRenderSize: CGFloat = 24
    private let symbolPointSize: CGFloat = 20
    private let iconTextSpacing: CGFloat = 1
    private let textContainerWidth: CGFloat = 42
    private let textLineHeight: CGFloat = 11

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = NSColor.labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = true
        return imageView
    }()

    private var currentDisplay: MenuBarDisplay?
    private var cachedUpLine: String = ""
    private var cachedDownLine: String = ""
    private lazy var brandStatusIconImage: NSImage? = Self.makeBrandStatusIconImage(size: brandIconRenderSize)
    private static let speedTextAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingHead
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }()

    var usesBrandIcon: Bool {
        self.brandStatusIconImage != nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        self.addSubview(self.iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: self.requiredWidth, height: NSStatusBar.system.thickness)
    }

    var requiredWidth: CGFloat {
        let display = self.currentDisplay ?? MenuBarDisplay(
            mode: .iconOnly,
            symbolName: "bolt.slash.circle",
            speedLines: nil)
        switch display.mode {
        case .iconOnly:
            return self.statusItemHorizontalPadding * 2 + self.iconSize
        case .iconAndSpeed:
            return self.statusItemHorizontalPadding * 2 + self.iconSize + self.iconTextSpacing + self.textContainerWidth
        case .speedOnly:
            return self.statusItemHorizontalPadding * 2 + self.textContainerWidth
        }
    }

    func apply(display: MenuBarDisplay) {
        let previousMode = self.currentDisplay?.mode
        let previousSymbolName = self.currentDisplay?.symbolName
        let previousIconHidden = self.iconView.isHidden
        let previousUpLine = self.cachedUpLine
        let previousDownLine = self.cachedDownLine

        self.currentDisplay = display
        self.cachedUpLine = display.speedLines?.up ?? ""
        self.cachedDownLine = display.speedLines?.down ?? ""

        let shouldShowIcon = display.mode != .speedOnly
        if shouldShowIcon, let brandIcon = brandStatusIconImage {
            if self.iconView.image !== brandIcon {
                self.iconView.image = brandIcon
            }
            // Avoid per-frame tint recomposition for custom PNG icon snapshots.
            self.iconView.contentTintColor = nil
        } else if let symbolName = display.symbolName {
            if self.iconView.image == nil ||
                previousSymbolName != symbolName ||
                self.currentDisplay?.mode != previousMode
            {
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClashBar")
                let config = NSImage.SymbolConfiguration(pointSize: self.symbolPointSize, weight: .semibold)
                self.iconView.image = image?.withSymbolConfiguration(config)
            }
            self.iconView.contentTintColor = NSColor.labelColor
        } else {
            self.iconView.image = nil
            self.iconView.contentTintColor = nil
        }

        switch display.mode {
        case .iconOnly:
            self.iconView.isHidden = false
        case .iconAndSpeed:
            self.iconView.isHidden = false
        case .speedOnly:
            self.iconView.isHidden = true
        }

        let modeChanged = previousMode != display.mode
        let iconVisibilityChanged = previousIconHidden != self.iconView.isHidden
        let speedTextChanged = previousUpLine != self.cachedUpLine || previousDownLine != self.cachedDownLine

        if modeChanged || iconVisibilityChanged {
            self.needsLayout = true
        }
        if modeChanged || speedTextChanged {
            self.needsDisplay = true
        }
        if modeChanged {
            self.invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()

        let totalHeight = bounds.height
        let centerY = floor(totalHeight / 2)
        let iconOriginX = floor(self.statusItemHorizontalPadding)

        if self.iconView.isHidden == false {
            self.iconView.frame = CGRect(
                x: iconOriginX,
                y: floor(centerY - self.iconSize / 2),
                width: self.iconSize,
                height: self.iconSize)
        } else {
            self.iconView.frame = .zero
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let display = self.currentDisplay else { return }
        guard display.mode != .iconOnly else { return }

        let originX = floor(
            self.statusItemHorizontalPadding +
                (display.mode == .iconAndSpeed ? (self.iconSize + self.iconTextSpacing) : 0))
        let centerY = floor(self.bounds.height / 2)
        let stackHeight = self.textLineHeight * 2
        let stackOriginY = floor(centerY - stackHeight / 2)

        let upRect = CGRect(
            x: originX,
            y: floor(stackOriginY + self.textLineHeight),
            width: self.textContainerWidth,
            height: self.textLineHeight)
        let downRect = CGRect(
            x: originX,
            y: stackOriginY,
            width: self.textContainerWidth,
            height: self.textLineHeight)

        if !dirtyRect.intersects(upRect), !dirtyRect.intersects(downRect) {
            return
        }

        (self.cachedUpLine as NSString).draw(
            in: upRect,
            withAttributes: Self.speedTextAttributes)
        (self.cachedDownLine as NSString).draw(
            in: downRect,
            withAttributes: Self.speedTextAttributes)
    }

    private static func makeBrandStatusIconImage(size: CGFloat) -> NSImage? {
        guard let source = BrandIcon.image else { return nil }
        let targetSize = NSSize(width: size, height: size)
        let rendered = NSImage(size: targetSize)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high])
        rendered.unlockFocus()
        rendered.isTemplate = false
        return rendered
    }
}
