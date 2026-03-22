import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "panel")

class SearchPanel: NSPanel {
    let viewModel = SearchViewModel()
    private var hostingView: NSHostingView<SearchView>!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 72),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow

        let searchView = SearchView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        hostingView = NSHostingView(rootView: searchView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView

        logger.warning("Panel configured")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        guard let screen = NSScreen.main else { return }
        let fittingSize = hostingView.fittingSize
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - fittingSize.width / 2
        let currentTop = frame.origin.y + frame.size.height
        let newOrigin = NSPoint(x: x, y: currentTop - fittingSize.height)
        setFrame(NSRect(origin: newOrigin, size: fittingSize), display: true, animate: false)
    }

    func show() {
        logger.warning("show() called")
        viewModel.searchText = ""
        viewModel.results = []

        guard let screen = NSScreen.main else {
            logger.error("No main screen")
            return
        }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let panelHeight: CGFloat = 72
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - 200
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        logger.warning("Panel visible=\(self.isVisible) key=\(self.isKeyWindow)")
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
}
