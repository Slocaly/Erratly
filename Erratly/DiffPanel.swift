import Cocoa

private class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A warm, slightly grainy paper background with a hand-drawn-ish border.
/// Colors are hardcoded (not semantic) so the sheet always reads as paper,
/// regardless of system light/dark mode.
private class PaperView: NSView {
    static let paperColor = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1.0)
    static let borderColor = NSColor(calibratedRed: 0.14, green: 0.11, blue: 0.08, alpha: 1.0)
    private let cornerRadius: CGFloat = 3
    private var grainImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        grainImage = Self.makeGrain(size: frameRect.size)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeGrain(size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        let speckleCount = Int(size.width * size.height / 5)
        for _ in 0..<speckleCount {
            let x = CGFloat.random(in: 0..<size.width)
            let y = CGFloat.random(in: 0..<size.height)
            let alpha = CGFloat.random(in: 0.01...0.05)
            (Bool.random() ? NSColor.black : NSColor.white)
                .withAlphaComponent(alpha)
                .setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
        image.unlockFocus()
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        Self.paperColor.setFill()
        path.fill()
        grainImage?.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        path.lineWidth = 2
        Self.borderColor.setStroke()
        path.stroke()
    }
}

/// A small translucent strip standing in for a piece of tape holding the paper up.
private class TapeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.87, green: 0.84, blue: 0.76, alpha: 0.55).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.4).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }

    required init?(coder: NSCoder) { fatalError() }
}

private class HighlightedTextView: NSTextView {
    private(set) var corrections: [Correction] = []
    private var segments: [Segment] = []
    private var highlights: [(NSRange, NSColor)] = []
    private var correctionRanges: [Int: NSRange] = [:]
    private var hoveredCorrection: (index: Int, rect: NSRect)?
    private var trackingArea: NSTrackingArea?

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    var finalText: String {
        Diff.finalText(segments: segments, corrections: corrections)
    }

    func configure(segments: [Segment], corrections: [Correction]) {
        self.segments = segments
        self.corrections = corrections
        rebuild()
    }

    private func rebuild() {
        let (attrString, highlights, correctionRanges) = Self.buildContent(segments: segments, corrections: corrections)
        self.highlights = highlights
        self.correctionRanges = correctionRanges
        textStorage?.setAttributedString(attrString)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let found = correction(at: point)
        if found?.index != hoveredCorrection?.index {
            hoveredCorrection = found
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredCorrection != nil {
            hoveredCorrection = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let hovered = hoveredCorrection {
            let point = convert(event.locationInWindow, from: nil)
            if badgeRect(for: hovered.rect).insetBy(dx: -3, dy: -3).contains(point) {
                corrections[hovered.index].isReverted = true
                hoveredCorrection = nil
                rebuild()
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func correction(at point: NSPoint) -> (index: Int, rect: NSRect)? {
        guard let layoutManager, let textContainer else { return nil }
        for (index, range) in correctionRanges {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            if rect.insetBy(dx: -4, dy: -4).contains(point) {
                return (index, rect)
            }
        }
        return nil
    }

    // HighlightedTextView is flipped (NSTextView.isFlipped == true), so the
    // visual bottom-left corner of a rect is (minX, maxY), not (minX, minY).
    private func badgeRect(for correctionRect: NSRect) -> NSRect {
        let radius: CGFloat = 7
        let center = NSPoint(x: correctionRect.minX, y: correctionRect.maxY)
        return NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private static func buildContent(segments: [Segment], corrections: [Correction]) -> (NSAttributedString, [(NSRange, NSColor)], [Int: NSRange]) {
        let result = NSMutableAttributedString()
        var highlights: [(NSRange, NSColor)] = []
        var correctionRanges: [Int: NSRange] = [:]

        for segment in segments {
            switch segment {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: DiffPanel.inkColor
                ]))
            case .correction(let index):
                let correction = corrections[index]
                let start = result.length
                if correction.isReverted {
                    result.append(NSAttributedString(string: correction.removedText, attributes: [
                        .font: font,
                        .foregroundColor: DiffPanel.inkColor
                    ]))
                } else {
                    if !correction.removedText.isEmpty {
                        let removedStart = result.length
                        result.append(NSAttributedString(string: correction.removedText, attributes: [
                            .font: font,
                            .foregroundColor: DiffPanel.fadedInkColor,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: DiffPanel.fadedInkColor
                        ]))
                        highlights.append((NSRange(location: removedStart, length: result.length - removedStart), NSColor.systemRed))
                    }
                    if !correction.addedText.isEmpty {
                        let addedStart = result.length
                        result.append(NSAttributedString(string: correction.addedText, attributes: [
                            .font: font,
                            .foregroundColor: DiffPanel.inkColor
                        ]))
                        highlights.append((NSRange(location: addedStart, length: result.length - addedStart), NSColor.systemGreen))
                    }
                    correctionRanges[index] = NSRange(location: start, length: result.length - start)
                }
            }
        }

        return (result, highlights, correctionRanges)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layoutManager = layoutManager else {
            super.draw(dirtyRect)
            return
        }

        for (range, color) in highlights {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            color.withAlphaComponent(0.15).setFill()
            color.withAlphaComponent(0.35).setStroke()

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] (_, _, container, lineGlyphRange, _) in
                guard let self else { return }
                let start = max(lineGlyphRange.location, glyphRange.location)
                let end = min(NSMaxRange(lineGlyphRange), NSMaxRange(glyphRange))
                guard start < end else { return }
                let subRange = NSRange(location: start, length: end - start)
                var rect = layoutManager.boundingRect(forGlyphRange: subRange, in: container)
                rect = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                let inflated = rect.insetBy(dx: -2, dy: -1)
                let path = NSBezierPath(roundedRect: inflated, xRadius: 3, yRadius: 3)
                path.fill()
                path.lineWidth = 0.5
                path.stroke()
            }
        }

        super.draw(dirtyRect)

        if let hovered = hoveredCorrection {
            let rect = badgeRect(for: hovered.rect)
            let path = NSBezierPath(ovalIn: rect)
            NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.85, alpha: 1.0).setFill()
            path.fill()
            DiffPanel.inkColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let inset = rect.width * 0.28
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
            cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            cross.move(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
            cross.line(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
            cross.lineWidth = 1.3
            DiffPanel.inkColor.setStroke()
            cross.stroke()
        }
    }
}

class DiffPanel: NSWindowController, NSWindowDelegate {
    private var onAccept: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var isDismissed = false
    private var textView: HighlightedTextView?

    fileprivate static let inkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 1.0)
    fileprivate static let fadedInkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 0.55)

    init(original: String, corrected: String, selectionBounds: CGRect?, onAccept: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
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
        panel.appearance = NSAppearance(named: .aqua)

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
        let outerMargin: CGFloat = 14
        let tapeHeadroom: CGFloat = 26

        // The paper sheet, inset from the (invisible) window bounds so its
        // slight rotation and drop shadow have room to breathe without clipping.
        let cardFrame = NSRect(
            x: outerMargin,
            y: outerMargin,
            width: bounds.width - outerMargin * 2,
            height: bounds.height - outerMargin - tapeHeadroom
        )
        let card = PaperView(frame: cardFrame)
        card.frameCenterRotation = -1.4
        contentView.addSubview(card)

        // A separate, unrotated container laid over the paper so the diff text
        // and buttons stay upright while the paper sheet itself sits at an angle.
        let content = NSView(frame: cardFrame)
        contentView.addSubview(content)

        let padding: CGFloat = 14
        let buttonH: CGFloat = 24
        let spacing: CGFloat = 10
        let separatorH: CGFloat = 1
        let textAreaW = cardFrame.width - padding * 2
        let textAreaH = cardFrame.height - padding * 2 - buttonH - spacing - separatorH

        // Scroll view + text view
        let scrollView = NSScrollView(frame: NSRect(x: padding, y: padding + buttonH + spacing + separatorH, width: textAreaW, height: textAreaH))
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = HighlightedTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
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
        let (segments, corrections) = Diff.group(tokens)
        textView.configure(segments: segments, corrections: corrections)
        scrollView.documentView = textView
        self.textView = textView
        content.addSubview(scrollView)

        // Thin separator, hand-drawn-ish ink tone rather than a system divider
        let separator = NSBox(frame: NSRect(x: padding, y: padding + buttonH + spacing, width: textAreaW, height: separatorH))
        separator.boxType = .custom
        separator.fillColor = Self.inkColor.withAlphaComponent(0.25)
        content.addSubview(separator)

        // Buttons, flat and outlined to match the paper/typewriter look
        let cancelBtn = makeButton(title: "Cancel", primary: false, target: self, action: #selector(cancelAction))
        cancelBtn.keyEquivalent = "\u{1B}"

        let acceptBtn = makeButton(title: "Accept", primary: true, target: self, action: #selector(acceptAction))
        acceptBtn.keyEquivalent = "\r"

        let totalBtnW = cancelBtn.frame.width + 8 + acceptBtn.frame.width
        let rightEdge = cardFrame.width - padding
        cancelBtn.frame = NSRect(x: rightEdge - totalBtnW, y: padding, width: cancelBtn.frame.width, height: buttonH)
        acceptBtn.frame = NSRect(x: rightEdge - acceptBtn.frame.width, y: padding, width: acceptBtn.frame.width, height: buttonH)

        content.addSubview(cancelBtn)
        content.addSubview(acceptBtn)

        // A strip of tape holding the paper to the screen, overlapping the top edge.
        let tapeFrame = NSRect(
            x: cardFrame.maxX - 106,
            y: cardFrame.maxY - 14,
            width: 60,
            height: 28
        )
        let tape = TapeView(frame: tapeFrame)
        tape.frameCenterRotation = -5
        contentView.addSubview(tape)
    }

    private func makeButton(title: String, primary: Bool, target: AnyObject, action: Selector) -> NSButton {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let textColor = primary ? NSColor(calibratedWhite: 0.98, alpha: 1.0) : Self.inkColor
        let attrTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: font,
            .foregroundColor: textColor,
            .kern: 0.6
        ])

        let button = NSButton(frame: .zero)
        button.attributedTitle = attrTitle
        button.isBordered = false
        button.target = target
        button.action = action
        button.wantsLayer = true
        button.layer?.borderWidth = 1
        button.layer?.borderColor = Self.inkColor.cgColor
        button.layer?.cornerRadius = 2
        button.layer?.backgroundColor = primary ? Self.inkColor.cgColor : NSColor.clear.cgColor

        let textSize = attrTitle.size()
        button.frame = NSRect(x: 0, y: 0, width: ceil(textSize.width) + 22, height: 24)
        return button
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

    // MARK: - Actions

    @objc private func acceptAction() { dismiss(accepted: true) }
    @objc private func cancelAction() { dismiss(accepted: false) }

    private func dismiss(accepted: Bool) {
        guard !isDismissed else { return }
        isDismissed = true
        let accept = onAccept
        let cancel = onCancel
        let finalText = textView?.finalText ?? ""
        window?.close()
        if accepted { accept?(finalText) } else { cancel?() }
    }
}
