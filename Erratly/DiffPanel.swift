import Cocoa

private class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class DiffPanel: NSWindowController, NSWindowDelegate {
    private var onAccept: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var isDismissed = false

    init(original: String, corrected: String, selectionBounds: CGRect?, onAccept: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        super.init(window: panel)

        self.onAccept = onAccept
        self.onCancel = onCancel
        panel.delegate = self
        setupUI(original: original, corrected: corrected)
        position(near: selectionBounds)
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        dismiss(accepted: false)
    }

    // MARK: - UI

    private func setupUI(original: String, corrected: String) {
        guard let contentView = window?.contentView else { return }

        let bounds = contentView.bounds
        let padding: CGFloat = 12
        let buttonH: CGFloat = 32
        let spacing: CGFloat = 8
        let textAreaH = bounds.height - padding * 2 - buttonH - spacing
        let textAreaW = bounds.width - padding * 2

        // Frosted glass background with rounded corners
        let effectView = NSVisualEffectView(frame: bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.blendingMode = .behindWindow
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        contentView.addSubview(effectView)

        // Scroll view + text view
        let scrollView = NSScrollView(frame: NSRect(x: padding, y: padding + buttonH + spacing, width: textAreaW, height: textAreaH))
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)

        let tokens = Diff.compute(original: original, corrected: corrected)
        textView.textStorage?.setAttributedString(buildAttributedString(from: tokens))
        scrollView.documentView = textView
        effectView.addSubview(scrollView)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1B}"
        cancelBtn.sizeToFit()

        let acceptBtn = NSButton(title: "Accept", target: self, action: #selector(acceptAction))
        acceptBtn.bezelStyle = .rounded
        acceptBtn.keyEquivalent = "\r"
        acceptBtn.sizeToFit()

        let totalBtnW = cancelBtn.frame.width + 8 + acceptBtn.frame.width
        let rightEdge = bounds.width - padding
        cancelBtn.frame = NSRect(x: rightEdge - totalBtnW, y: padding, width: cancelBtn.frame.width, height: buttonH)
        acceptBtn.frame = NSRect(x: rightEdge - acceptBtn.frame.width, y: padding, width: acceptBtn.frame.width, height: buttonH)

        effectView.addSubview(cancelBtn)
        effectView.addSubview(acceptBtn)
    }

    // Converts a CG-space rect (top-left origin) to AppKit-space and positions
    // the panel just below the selection, flipping above if it would go off-screen.
    private func position(near cgRect: CGRect?) {
        guard let cgRect, let window else {
            window?.center()
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
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let panelSize = window.frame.size

        var x = selectionRect.midX - panelSize.width / 2
        var y = selectionRect.minY - panelSize.height - 8

        if y < visibleFrame.minY {
            y = selectionRect.maxY + 8
        }

        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - panelSize.width - 8))

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func buildAttributedString(from tokens: [DiffToken]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 14)

        for token in tokens {
            switch token {
            case .unchanged(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]))
            case .removed(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.systemRed,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed
                ]))
            case .added(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.systemGreen
                ]))
            }
        }

        return result
    }

    // MARK: - Actions

    @objc private func acceptAction() { dismiss(accepted: true) }
    @objc private func cancelAction() { dismiss(accepted: false) }

    private func dismiss(accepted: Bool) {
        guard !isDismissed else { return }
        isDismissed = true
        let accept = onAccept
        let cancel = onCancel
        window?.close()
        if accepted { accept?() } else { cancel?() }
    }
}
