import AppKit
import SwiftUI

class SearchPanel: NSPanel {
    let viewModel = SearchViewModel()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let searchView = SearchView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        contentView = NSHostingView(rootView: searchView)
    }

    override var canBecomeKey: Bool { true }

    func show() {
        viewModel.searchText = ""
        viewModel.results = []

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - 200
        setFrameOrigin(NSPoint(x: x, y: y))

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        viewModel.searchText = ""
        viewModel.results = []
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}
