import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "panel")

class SearchPanel: NSPanel {
    let viewModel = SearchViewModel()
    private var hostingView: NSHostingView<AnyView>!
    private var isDismissing = false
    private var containerView: NSView!

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
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

        // ── Outer container (transparent, holds shadow + border + vibrancy) ──
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = nil

        // No shadow on container — we use the window's native shadow instead

        // ── Vibrancy (frosted glass blur) ──
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = true
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // ── Gradient border layer ──
        let borderView = GradientBorderView()
        borderView.translatesAutoresizingMaskIntoConstraints = false

        // ── SwiftUI search content ──
        let searchView = SearchView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        hostingView = NSHostingView(rootView: AnyView(searchView.frame(width: 680)))
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // ── Assemble layers ──
        // containerView → visualEffect → hostingView (content)
        //               → borderView (gradient border on top)
        visualEffect.addSubview(hostingView)
        containerView.addSubview(visualEffect)
        containerView.addSubview(borderView)

        NSLayoutConstraint.activate([
            // Vibrancy fills container edge to edge
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Content fills vibrancy
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            // Border overlay matches vibrancy exactly
            borderView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        contentView = containerView
        logger.warning("Panel configured (borderless, vibrancy, gradient border)")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Dismiss on click outside

    override func resignKey() {
        super.resignKey()
        if isVisible && !isDismissing {
            DispatchQueue.main.async { [weak self] in
                self?.dismiss()
            }
        }
    }

    // MARK: - Resize keeping X position

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        resizeToFitContent()
    }

    private func resizeToFitContent() {
        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0 && fittingSize.height > 0 else { return }

        let currentFrame = frame
        let currentTop = currentFrame.origin.y + currentFrame.size.height
        let newY = currentTop - fittingSize.height

        setFrame(NSRect(x: currentFrame.origin.x, y: newY, width: fittingSize.width, height: fittingSize.height),
                 display: true, animate: false)
        invalidateShadow()
    }

    // MARK: - Show / Dismiss / Toggle

    func show() {
        logger.warning("show() called")
        isDismissing = false
        viewModel.searchText = ""
        viewModel.results = []

        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let panelHeight: CGFloat = 72
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - 200
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
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
        if isVisible { dismiss() } else { show() }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

// MARK: - Gradient Border View (CAGradientLayer masked to a stroke path)

class GradientBorderView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let shapeLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        gradientLayer.colors = [
            NSColor.white.withAlphaComponent(0.5).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.4).cgColor,
            NSColor.systemBlue.withAlphaComponent(0.35).cgColor,
            NSColor.systemCyan.withAlphaComponent(0.3).cgColor,
            NSColor.white.withAlphaComponent(0.15).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)

        shapeLayer.lineWidth = 1.5
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = NSColor.white.cgColor

        gradientLayer.mask = shapeLayer
        layer?.addSublayer(gradientLayer)
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        let inset = bounds.insetBy(dx: 0.75, dy: 0.75)
        shapeLayer.path = CGPath(roundedRect: inset, cornerWidth: 16, cornerHeight: 16, transform: nil)
    }
}
