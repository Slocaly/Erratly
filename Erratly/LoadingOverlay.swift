import Cocoa

class LoadingOverlay: NSWindowController {
    static let shared = LoadingOverlay()

    private var iconLayer: CALayer?

    private init() {
        let size: CGFloat = 56
        let margin: CGFloat = 24

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.alphaValue = 0

        super.init(window: panel)
        setupUI(size: size)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI(size: CGFloat) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        guard let hostLayer = contentView.layer else { return }

        let iconSize: CGFloat = 44

        // Pure CALayer — anchorPoint stays (0.5, 0.5) and AppKit never touches it
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        layer.position = CGPoint(x: size / 2, y: size / 2)
        layer.contentsGravity = .resizeAspectFill
        if let image = NSImage(named: "AppIconRound") {
            var rect = NSRect(origin: .zero, size: NSSize(width: iconSize, height: iconSize))
            layer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }

        hostLayer.addSublayer(layer)
        self.iconLayer = layer
    }

    func show(near cgRect: CGRect?) {
        DispatchQueue.main.async {
            self.position(near: cgRect)
            self.startRotation()
            self.showWindow(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                self.window?.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                self.window?.animator().alphaValue = 0
            }, completionHandler: {
                self.window?.orderOut(nil)
                self.stopRotation()
            })
        }
    }

    private func startRotation() {
        guard let layer = iconLayer else { return }
        layer.removeAnimation(forKey: "spin")

        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = -CGFloat.pi * 2
        anim.duration = 0.9
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.3, 1)
        anim.repeatCount = .infinity
        layer.add(anim, forKey: "spin")
    }

    private func stopRotation() {
        iconLayer?.removeAnimation(forKey: "spin")
    }

    private func resize(to panelSize: CGFloat, iconSize: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        frame.size = NSSize(width: panelSize, height: panelSize)
        window.setFrame(frame, display: false)
        iconLayer?.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        iconLayer?.position = CGPoint(x: panelSize / 2, y: panelSize / 2)
    }

    private func position(near cgRect: CGRect?) {
        guard let cgRect, let window else {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let frame = screen.visibleFrame
            resize(to: 72, iconSize: 58)
            window?.setFrameOrigin(NSPoint(x: frame.minX + 24, y: frame.minY + 24))
            return
        }

        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 800
        let selectionRect = NSRect(
            x: cgRect.origin.x,
            y: mainScreenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )

        let screen = NSScreen.screens.first { NSPointInRect(selectionRect.origin, $0.frame) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        resize(to: 56, iconSize: 44)
        let panelSize = window.frame.size

        var x = selectionRect.midX - panelSize.width / 2
        var y = selectionRect.minY - panelSize.height - 8

        if y < visibleFrame.minY {
            y = selectionRect.maxY + 8
        }

        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - panelSize.width - 8))

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
