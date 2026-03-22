import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "panel")

class SearchPanel: NSPanel {
    let viewModel = SearchViewModel()
    private var hostingView: NSHostingView<SearchView>!
    private var isDismissing = false

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

    // MARK: - Dismiss on click outside (like Spotlight)

    override func resignKey() {
        super.resignKey()
        // When panel loses focus (user clicked elsewhere), dismiss it
        if isVisible && !isDismissing {
            DispatchQueue.main.async { [weak self] in
                self?.dismiss()
            }
        }
    }

    // MARK: - Resize without repositioning X (fix drag jump bug)

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        let fittingSize = hostingView.fittingSize

        // Keep the current X position (user may have dragged it)
        // Keep the top edge anchored (grow/shrink downward)
        let currentFrame = frame
        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newY = currentTop - fittingSize.height

        let newFrame = NSRect(
            x: currentFrame.origin.x,  // ← preserve X, don't recenter!
            y: newY,
            width: fittingSize.width,
            height: fittingSize.height
        )

        setFrame(newFrame, display: true, animate: false)
    }

    // MARK: - Show / Dismiss / Toggle

    func show() {
        logger.warning("show() called")
        isDismissing = false
        viewModel.searchText = ""
        viewModel.results = []

        guard let screen = NSScreen.main else {
            logger.error("No main screen")
            return
        }

        // Always open centered near top of screen (fresh position)
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
        guard isVisible else { return }
        isDismissing = true
        orderOut(nil)
        viewModel.searchText = ""
        viewModel.results = []
        isDismissing = false
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
