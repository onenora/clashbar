import AppKit

final class StatusItemContentView: NSView {
    // Keep a 1pt optical inset to stabilize status-item width across icon/text mode switches.
    private let statusItemHorizontalPadding: CGFloat = MenuBarLayoutTokens.opticalNudge
    private let iconSize: CGFloat = 24
    private let brandIconRenderSize: CGFloat = 18
    private let iconTextSpacing: CGFloat = 1
    private let textContainerWidth: CGFloat = 42
    private let textLineHeight: CGFloat = 11

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = NSColor.labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = true
        return imageView
    }()

    private let upLabel = StatusItemContentView.makeLineLabel(
        color: NSColor.systemBlue.withAlphaComponent(0.92)
    )
    private let downLabel = StatusItemContentView.makeLineLabel(
        color: NSColor.systemGreen.withAlphaComponent(0.92)
    )

    private var currentDisplay: MenuBarDisplay?
    private lazy var brandStatusIconImage: NSImage? = Self.makeBrandStatusIconImage(size: brandIconRenderSize)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        addSubview(iconView)
        addSubview(upLabel)
        addSubview(downLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: requiredWidth, height: NSStatusBar.system.thickness)
    }

    var requiredWidth: CGFloat {
        let display = currentDisplay ?? MenuBarDisplay(mode: .iconOnly, symbolName: "bolt.slash.circle", speedLines: nil)
        switch display.mode {
        case .iconOnly:
            return statusItemHorizontalPadding * 2 + iconSize
        case .iconAndSpeed:
            return statusItemHorizontalPadding * 2 + iconSize + iconTextSpacing + textContainerWidth
        case .speedOnly:
            return statusItemHorizontalPadding * 2 + textContainerWidth
        }
    }

    func apply(display: MenuBarDisplay) {
        currentDisplay = display
        upLabel.stringValue = display.speedLines?.up ?? ""
        downLabel.stringValue = display.speedLines?.down ?? ""

        let shouldShowIcon = display.mode != .speedOnly
        if shouldShowIcon, let brandIcon = brandStatusIconImage {
            iconView.image = brandIcon
            iconView.contentTintColor = nil
        } else if let symbolName = display.symbolName {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClashBar")
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            iconView.image = image?.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.labelColor
        } else {
            iconView.image = nil
        }

        switch display.mode {
        case .iconOnly:
            iconView.isHidden = false
            upLabel.isHidden = true
            downLabel.isHidden = true
        case .iconAndSpeed:
            iconView.isHidden = false
            upLabel.isHidden = false
            downLabel.isHidden = false
        case .speedOnly:
            iconView.isHidden = true
            upLabel.isHidden = false
            downLabel.isHidden = false
        }

        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()

        let totalHeight = bounds.height
        let centerY = totalHeight / 2
        var cursorX = statusItemHorizontalPadding

        if iconView.isHidden == false {
            iconView.frame = CGRect(x: cursorX, y: centerY - iconSize / 2, width: iconSize, height: iconSize)
            cursorX += iconSize + iconTextSpacing
        } else {
            iconView.frame = .zero
        }

        if upLabel.isHidden || downLabel.isHidden {
            upLabel.frame = .zero
            downLabel.frame = .zero
            return
        }

        let stackHeight = textLineHeight * 2
        let stackOriginY = centerY - stackHeight / 2

        upLabel.frame = CGRect(x: cursorX, y: stackOriginY + textLineHeight, width: textContainerWidth, height: textLineHeight)
        downLabel.frame = CGRect(x: cursorX, y: stackOriginY, width: textContainerWidth, height: textLineHeight)
    }

    private static func makeLineLabel(color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = color
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = true
        return label
    }

    private static func makeBrandStatusIconImage(size: CGFloat) -> NSImage? {
        guard let base = BrandIcon.image?.copy() as? NSImage else { return nil }
        base.size = NSSize(width: size, height: size)
        base.isTemplate = false
        return base
    }
}
