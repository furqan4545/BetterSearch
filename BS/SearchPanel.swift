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

        // ── Container ──
        containerView = NSView()
        containerView.wantsLayer = true

        // ── Vibrancy (frosted glass) ──
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.isEmphasized = true
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 24
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        // ── Gradient border (separate view on top) ──
        let borderView = GradientBorderView()
        borderView.translatesAutoresizingMaskIntoConstraints = false

        // ── SwiftUI content ──
        let searchView = SearchView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        hostingView = NSHostingView(rootView: AnyView(searchView.frame(width: 680)))
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // ── Assemble ──
        visualEffect.addSubview(hostingView)
        containerView.addSubview(visualEffect)
        containerView.addSubview(borderView)

        NSLayoutConstraint.activate([
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            borderView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        contentView = containerView
        logger.warning("Panel configured")
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

    // MARK: - Resize

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

    // MARK: - Show with liquid glass animation

    func show() {
        isDismissing = false
        viewModel.searchText = ""
        viewModel.results = []

        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let panelHeight: CGFloat = 72
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.maxY - 350
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)

        // Start invisible and scaled down
        alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        // Animate the whole window: scale from center + fade in
        if let layer = contentView?.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.92
            spring.toValue = 1.0
            spring.mass = 0.6
            spring.stiffness = 300
            spring.damping = 18
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "openScale")
        }

        // Window-level fade (covers EVERYTHING uniformly)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    // MARK: - Dismiss with liquid glass animation

    func dismiss() {
        guard isVisible else { return }
        isDismissing = true

        // Scale down from center
        if let layer = contentView?.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.95
            shrink.duration = 0.1
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            shrink.isRemovedOnCompletion = false
            shrink.fillMode = .forwards
            layer.add(shrink, forKey: "closeScale")
        }

        // Window-level fade out (ENTIRE window — content, border, everything at once)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.contentView?.layer?.removeAllAnimations()
            self.contentView?.layer?.transform = CATransform3DIdentity
            self.alphaValue = 1.0
            self.viewModel.searchText = ""
            self.viewModel.results = []
            self.isDismissing = false
        })
    }

    func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

// MARK: - Gradient Border View

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
        shapeLayer.path = CGPath(roundedRect: inset, cornerWidth: 24, cornerHeight: 24, transform: nil)
    }
}
