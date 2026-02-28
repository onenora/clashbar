import AppKit
import SwiftUI

@MainActor
struct EqualWidthSegmentedTabControl: NSViewRepresentable {
    let items: [(tab: RootTab, title: String)]
    let selected: RootTab
    let onSelect: (RootTab) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ContainerView {
        let container = ContainerView()
        container.control.target = context.coordinator
        container.control.action = #selector(Coordinator.selectionChanged(_:))
        configure(container.control)
        return container
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        context.coordinator.parent = self
        configure(nsView.control)
    }

    private func configure(_ control: NSSegmentedControl) {
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.segmentDistribution = .fillEqually

        if control.segmentCount != items.count {
            control.segmentCount = items.count
        }

        for (index, item) in items.enumerated() {
            if control.label(forSegment: index) != item.title {
                control.setLabel(item.title, forSegment: index)
            }
        }

        if let selectedIndex = items.firstIndex(where: { $0.tab == selected }) {
            control.selectedSegment = selectedIndex
        } else {
            control.selectedSegment = -1
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: EqualWidthSegmentedTabControl

        init(parent: EqualWidthSegmentedTabControl) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < parent.items.count else { return }
            parent.onSelect(parent.items[index].tab)
        }
    }

    @MainActor
    final class ContainerView: NSView {
        let control: NSSegmentedControl = {
            let control = NSSegmentedControl()
            control.translatesAutoresizingMaskIntoConstraints = false
            return control
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
            NSLayoutConstraint.activate([
                control.leadingAnchor.constraint(equalTo: leadingAnchor),
                control.trailingAnchor.constraint(equalTo: trailingAnchor),
                control.topAnchor.constraint(equalTo: topAnchor),
                control.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
