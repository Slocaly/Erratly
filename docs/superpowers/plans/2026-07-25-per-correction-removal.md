# Per-correction removal in DiffPanel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user hover a correction in the diff panel, see a small cross badge at its bottom-left corner, and click it to revert that one correction back to the original wording while keeping the rest of the corrections applied.

**Architecture:** `Diff.swift` gains pure, framework-free logic to group the flat `[DiffToken]` list into removable `Correction` units and to reconstruct the final text from them. `DiffPanel.swift`'s `HighlightedTextView` becomes the single owner of that grouped state, renders it, tracks mouse hover to show/hide a badge, and handles clicks on the badge to revert a correction and re-render. `DiffPanel.onAccept` changes from a no-argument closure to one that receives the final (possibly-reverted) text, which `ErratlyApp.swift`'s call site consumes instead of its own captured `corrected` constant.

**Tech Stack:** Swift, AppKit (`NSTextView`, `NSLayoutManager`, `NSTrackingArea`), no external dependencies.

## Global Constraints

- This project has **no test target** (per `CLAUDE.md`: "There are no tests"). Verification for pure logic in `Diff.swift` (no `Cocoa` import, no dependency on the Xcode project) is done with a standalone `swiftc`-compiled script, since that file can be compiled independently of the app target. Verification for AppKit rendering/interaction code is `xcodebuild build` for compile correctness, plus a manual interactive check description — there is no way to script clicks into a real accessibility-triggered system panel without a human running the app.
- **Do not create git commits.** The user handles all git operations themselves in this project. Each task ends with a note to leave the changes staged for the user's own review instead of a commit step.
- Match existing code style: hardcoded paper/ink theme colors (not semantic `NSColor`s), `NSFont.monospacedSystemFont`, and the project's convention of no comments except where a genuinely non-obvious constraint needs explaining (e.g. the flipped-coordinate note in Task 3).
- `HighlightedTextView` is a **flipped view** (`NSTextView.isFlipped` defaults to `true`), so in its coordinate system y increases *downward*. The visual bottom-left corner of a rect `r` is `(r.minX, r.maxY)`, not `(r.minX, r.minY)`. Every task below that touches badge/hover geometry must use `maxY` for "bottom".

---

### Task 1: Diff grouping & final-text reconstruction logic

**Files:**
- Modify: `Erratly/Diff.swift` (currently 63 lines; append new types and two new `static func`s)

**Interfaces:**
- Consumes: existing `DiffToken` enum (`.unchanged(String)`, `.removed(String)`, `.added(String)`) and `Diff.compute(original:corrected:)` — unchanged.
- Produces:
  - `struct Correction { let removedText: String; let addedText: String; var isReverted: Bool = false }`
  - `enum Segment { case text(String); case correction(Int) }`
  - `Diff.group(_ tokens: [DiffToken]) -> (segments: [Segment], corrections: [Correction])`
  - `Diff.finalText(segments: [Segment], corrections: [Correction]) -> String`
  - These are consumed by Task 2 (`HighlightedTextView.configure(segments:corrections:)`) and Task 5 (`HighlightedTextView.finalText`).

- [ ] **Step 1: Write the failing verification script**

Create `/tmp/erratly-diff-tests/main.swift`:

```swift
let tokens1: [DiffToken] = [
    .unchanged("Hello "),
    .removed("teh"),
    .added("the"),
    .unchanged(" world")
]
let (segments1, corrections1) = Diff.group(tokens1)
assert(segments1.count == 3, "expected 3 segments, got \(segments1.count)")
assert(corrections1.count == 1, "expected 1 correction, got \(corrections1.count)")
assert(corrections1[0].removedText == "teh")
assert(corrections1[0].addedText == "the")

let tokens2: [DiffToken] = [
    .added("Hi"),
    .unchanged(" there"),
    .removed(" friend")
]
let (segments2, corrections2) = Diff.group(tokens2)
assert(corrections2.count == 2, "expected 2 corrections, got \(corrections2.count)")
assert(corrections2[0].removedText == "" && corrections2[0].addedText == "Hi")
assert(corrections2[1].removedText == " friend" && corrections2[1].addedText == "")

let text1 = Diff.finalText(segments: segments1, corrections: corrections1)
assert(text1 == "Hello the world", "got: \(text1)")

var revertedCorrections1 = corrections1
revertedCorrections1[0].isReverted = true
let text1Reverted = Diff.finalText(segments: segments1, corrections: revertedCorrections1)
assert(text1Reverted == "Hello teh world", "got: \(text1Reverted)")

var revertedCorrections2 = corrections2
revertedCorrections2[0].isReverted = true
let text2 = Diff.finalText(segments: segments2, corrections: revertedCorrections2)
assert(text2 == " there", "got: \(text2)")

print("PASS")
```

- [ ] **Step 2: Run it and confirm it fails to compile**

```bash
mkdir -p /tmp/erratly-diff-tests
swiftc Erratly/Diff.swift /tmp/erratly-diff-tests/main.swift -o /tmp/erratly-diff-tests/run
```

Expected: compile error — `error: type 'Diff' has no member 'group'` (or similar — `Correction`/`Segment`/`finalText` don't exist yet).

- [ ] **Step 3: Implement `Correction`, `Segment`, `group`, and `finalText` in `Diff.swift`**

Insert after the `DiffToken` enum (after its closing `}`, before `enum Diff {`):

```swift
struct Correction {
    let removedText: String
    let addedText: String
    var isReverted: Bool = false
}

enum Segment {
    case text(String)
    case correction(Int)
}
```

Insert inside `enum Diff { ... }`, right after the closing brace of `compute(original:corrected:)` and before the `private static func tokenize` method:

```swift
    static func group(_ tokens: [DiffToken]) -> (segments: [Segment], corrections: [Correction]) {
        var segments: [Segment] = []
        var corrections: [Correction] = []
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .unchanged(let text):
                segments.append(.text(text))
                i += 1
            case .removed, .added:
                var removed = ""
                var added = ""
                loop: while i < tokens.count {
                    switch tokens[i] {
                    case .removed(let text):
                        removed += text
                        i += 1
                    case .added(let text):
                        added += text
                        i += 1
                    case .unchanged:
                        break loop
                    }
                }
                corrections.append(Correction(removedText: removed, addedText: added))
                segments.append(.correction(corrections.count - 1))
            }
        }
        return (segments, corrections)
    }

    static func finalText(segments: [Segment], corrections: [Correction]) -> String {
        var result = ""
        for segment in segments {
            switch segment {
            case .text(let text):
                result += text
            case .correction(let index):
                let correction = corrections[index]
                result += correction.isReverted ? correction.removedText : correction.addedText
            }
        }
        return result
    }
```

- [ ] **Step 4: Run the verification script again and confirm it passes**

```bash
swiftc Erratly/Diff.swift /tmp/erratly-diff-tests/main.swift -o /tmp/erratly-diff-tests/run && /tmp/erratly-diff-tests/run
```

Expected output: `PASS` (no assertion failures).

- [ ] **Step 5: Leave changes for review**

Do not commit. Run `git diff Erratly/Diff.swift` and leave it staged/unstaged for the user to review.

---

### Task 2: Rewire DiffPanel rendering to consume segments/corrections (visual parity)

**Files:**
- Modify: `Erratly/DiffPanel.swift`
  - `DiffPanel` class: change `private static let inkColor`/`fadedInkColor` from `private` to `fileprivate` (currently lines 120-121) so `HighlightedTextView` in the same file can reference them.
  - `HighlightedTextView` class (currently lines 81-113): replace the public `var highlights` with owned `segments`/`corrections`/`highlights`/`correctionRanges` state, a `configure(segments:corrections:)` entry point, and a private `rebuild()` that builds the attributed string (moving the logic currently in `DiffPanel.buildContent(from:)`, lines 307-338).
  - `DiffPanel.setupUI` (around lines 208-213): call `Diff.group` and `textView.configure(segments:corrections:)` instead of `buildContent(from:)` + manual `textStorage`/`highlights` assignment.
  - Remove `DiffPanel.buildContent(from:)` (lines 307-338) — superseded by the logic moved into `HighlightedTextView`.

**Interfaces:**
- Consumes: `Diff.group(_:)`, `Correction`, `Segment` (Task 1).
- Produces: `HighlightedTextView.configure(segments: [Segment], corrections: [Correction])`, `HighlightedTextView.corrections` (read via `private(set)`) — consumed by Task 4 (mutating `isReverted`) and Task 5 (`finalText`).

- [ ] **Step 1: Change the color constants' access level**

In `DiffPanel`, change:

```swift
    private static let inkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 1.0)
    private static let fadedInkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 0.55)
```

to:

```swift
    fileprivate static let inkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 1.0)
    fileprivate static let fadedInkColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.08, alpha: 0.55)
```

- [ ] **Step 2: Replace `HighlightedTextView` with segment/correction-owning state**

Replace the entire current `HighlightedTextView` class body:

```swift
private class HighlightedTextView: NSTextView {
    var highlights: [(NSRange, NSColor)] = []

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
    }
}
```

with:

```swift
private class HighlightedTextView: NSTextView {
    private(set) var corrections: [Correction] = []
    private var segments: [Segment] = []
    private var highlights: [(NSRange, NSColor)] = []
    private var correctionRanges: [Int: NSRange] = [:]

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

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
    }
}
```

- [ ] **Step 3: Update `DiffPanel.setupUI` to use the new entry point**

Replace:

```swift
        let tokens = Diff.compute(original: original, corrected: corrected)
        let (attrString, highlights) = buildContent(from: tokens)
        textView.textStorage?.setAttributedString(attrString)
        textView.highlights = highlights
        scrollView.documentView = textView
```

with:

```swift
        let tokens = Diff.compute(original: original, corrected: corrected)
        let (segments, corrections) = Diff.group(tokens)
        textView.configure(segments: segments, corrections: corrections)
        scrollView.documentView = textView
```

- [ ] **Step 4: Remove the now-superseded `DiffPanel.buildContent(from:)` method**

Delete this entire method (it duplicated the logic now living in `HighlightedTextView.buildContent(segments:corrections:)`):

```swift
    private func buildContent(from tokens: [DiffToken]) -> (NSAttributedString, [(NSRange, NSColor)]) {
        let result = NSMutableAttributedString()
        var highlights: [(NSRange, NSColor)] = []
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        for token in tokens {
            let start = result.length
            switch token {
            case .unchanged(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: Self.inkColor
                ]))
            case .removed(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: Self.fadedInkColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: Self.fadedInkColor
                ]))
                highlights.append((NSRange(location: start, length: result.length - start), NSColor.systemRed))
            case .added(let text):
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: Self.inkColor
                ]))
                highlights.append((NSRange(location: start, length: result.length - start), NSColor.systemGreen))
            }
        }

        return (result, highlights)
    }
```

- [ ] **Step 5: Build and verify visual parity**

```bash
xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

Manual check (requires a human running the app, per `CLAUDE.md` — there's no test harness): run the app, trigger a correction (double-tap Control on selected text with a typo), and confirm the diff panel renders exactly as it did before this change — struck-through red removed text, green added text, no visual regression. Nothing new is interactive yet.

- [ ] **Step 6: Leave changes for review**

Do not commit. Leave the diff for the user to review.

---

### Task 3: Hover detection and badge drawing (no click behavior yet)

**Files:**
- Modify: `Erratly/DiffPanel.swift` — `HighlightedTextView` class (add tracking area + hover state + badge painting on top of Task 2's version).

**Interfaces:**
- Consumes: `correctionRanges: [Int: NSRange]` (Task 2, already stored on `HighlightedTextView`).
- Produces: `HighlightedTextView.badgeRect(for:)` helper — consumed by Task 4's click hit-test.

- [ ] **Step 1: Add hover state and a tracking area**

Add these properties near the top of `HighlightedTextView` (alongside `corrections`/`segments`/`highlights`/`correctionRanges`):

```swift
    private var hoveredCorrection: (index: Int, rect: NSRect)?
    private var trackingArea: NSTrackingArea?
```

Add these methods to `HighlightedTextView` (anywhere after `rebuild()`, before `draw(_:)`):

```swift
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
```

- [ ] **Step 2: Paint the badge on top of the text after hover**

In `draw(_:)`, the existing body ends with `super.draw(dirtyRect)`. Add badge painting immediately after that call (so the badge draws on top of the glyphs, not underneath them):

```swift
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
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

Manual check (requires a human running the app): trigger a correction with at least one substitution. Hover the mouse over the struck-through/green text of a correction — a small paper-colored circular badge with an "×" should appear, anchored at its bottom-left corner. Move the mouse away — the badge should disappear. Hovering over plain unchanged text should never show a badge. Clicking the badge does nothing yet (that's Task 4).

- [ ] **Step 4: Leave changes for review**

Do not commit. Leave the diff for the user to review.

---

### Task 4: Click the badge to revert a correction

**Files:**
- Modify: `Erratly/DiffPanel.swift` — `HighlightedTextView` class (add `mouseDown` override).

**Interfaces:**
- Consumes: `badgeRect(for:)`, `hoveredCorrection`, `corrections` (Tasks 2-3), `rebuild()` (Task 2).
- Produces: clicking a badge sets `corrections[i].isReverted = true` and re-renders — consumed conceptually by Task 5, which reads the now-possibly-reverted `corrections` array via `finalText`.

- [ ] **Step 1: Add the click handler**

Add to `HighlightedTextView`:

```swift
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
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

Manual check (requires a human running the app): trigger a correction with at least two separate substitutions. Hover one correction's badge and click it — that correction should immediately render as plain unchanged text (no strikethrough, no red/green highlight), and re-hovering that spot should no longer show a badge. The other, non-clicked correction(s) should be unaffected. Click-and-drag over ordinary unchanged text elsewhere in the panel should still select text normally (confirming `super.mouseDown` still fires for non-badge clicks).

- [ ] **Step 3: Leave changes for review**

Do not commit. Leave the diff for the user to review.

---

### Task 5: Wire the reconstructed text through Accept

**Files:**
- Modify: `Erratly/DiffPanel.swift`:
  - `HighlightedTextView`: add a `finalText` computed property.
  - `DiffPanel`: add a `private var textView: HighlightedTextView?` property, set it in `setupUI`, change `onAccept`'s type, and update `dismiss(accepted:)`.
- Modify: `Erratly/ErratlyApp.swift` (lines 102-124) — update the `DiffPanel(...)` call site's `onAccept` closure to accept and use the final text.

**Interfaces:**
- Consumes: `Diff.finalText(segments:corrections:)` (Task 1), `HighlightedTextView.corrections`/`segments` (Task 2).
- Produces: `DiffPanel.init(..., onAccept: @escaping (String) -> Void, ...)` — this is the plan's terminal, user-visible interface change.

- [ ] **Step 1: Expose the reconstructed text from `HighlightedTextView`**

Add to `HighlightedTextView` (needs access to `segments`, already stored):

```swift
    var finalText: String {
        Diff.finalText(segments: segments, corrections: corrections)
    }
```

- [ ] **Step 2: Store the text view on `DiffPanel` and change the `onAccept` type**

Change:

```swift
class DiffPanel: NSWindowController, NSWindowDelegate {
    private var onAccept: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var isDismissed = false
```

to:

```swift
class DiffPanel: NSWindowController, NSWindowDelegate {
    private var onAccept: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var isDismissed = false
    private var textView: HighlightedTextView?
```

Change the `init` signature:

```swift
    init(original: String, corrected: String, selectionBounds: CGRect?, onAccept: @escaping () -> Void, onCancel: @escaping () -> Void) {
```

to:

```swift
    init(original: String, corrected: String, selectionBounds: CGRect?, onAccept: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
```

- [ ] **Step 3: Store the `textView` reference in `setupUI`**

Change:

```swift
        let tokens = Diff.compute(original: original, corrected: corrected)
        let (segments, corrections) = Diff.group(tokens)
        textView.configure(segments: segments, corrections: corrections)
        scrollView.documentView = textView
```

to:

```swift
        let tokens = Diff.compute(original: original, corrected: corrected)
        let (segments, corrections) = Diff.group(tokens)
        textView.configure(segments: segments, corrections: corrections)
        scrollView.documentView = textView
        self.textView = textView
```

- [ ] **Step 4: Pass the final text through `dismiss(accepted:)`**

Change:

```swift
    private func dismiss(accepted: Bool) {
        guard !isDismissed else { return }
        isDismissed = true
        let accept = onAccept
        let cancel = onCancel
        window?.close()
        if accepted { accept?() } else { cancel?() }
    }
```

to:

```swift
    private func dismiss(accepted: Bool) {
        guard !isDismissed else { return }
        isDismissed = true
        let accept = onAccept
        let cancel = onCancel
        let finalText = textView?.finalText ?? ""
        window?.close()
        if accepted { accept?(finalText) } else { cancel?() }
    }
```

- [ ] **Step 5: Update the call site in `ErratlyApp.swift`**

Change (`ErratlyApp.swift:102-123`):

```swift
                    self.diffPanel = DiffPanel(
                        original: text,
                        corrected: corrected,
                        selectionBounds: selectionBounds,
                        onAccept: { [weak self] in
                            CorrectionHistory.shared.record(original: text, corrected: corrected)
                            self?.replaceSelectedText(corrected, app: app, previousClipboard: previousClipboard)
                            Analytics.correctionAccepted(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        },
                        onCancel: { [weak self] in
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            if let previous = previousClipboard {
                                pasteboard.setString(previous, forType: .string)
                            }
                            Analytics.correctionRejected(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        }
                    )
```

to:

```swift
                    self.diffPanel = DiffPanel(
                        original: text,
                        corrected: corrected,
                        selectionBounds: selectionBounds,
                        onAccept: { [weak self] finalText in
                            CorrectionHistory.shared.record(original: text, corrected: finalText)
                            self?.replaceSelectedText(finalText, app: app, previousClipboard: previousClipboard)
                            Analytics.correctionAccepted(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        },
                        onCancel: { [weak self] in
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            if let previous = previousClipboard {
                                pasteboard.setString(previous, forType: .string)
                            }
                            Analytics.correctionRejected(language: self?.selectedLanguage)
                            app.activate()
                            self?.diffPanel = nil
                        }
                    )
```

- [ ] **Step 6: Build and verify end-to-end**

```bash
xcodebuild -project Erratly.xcodeproj -scheme Erratly -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

Manual check (requires a human running the app): trigger a correction that contains at least two separate substitutions in some real text field. In the diff panel, revert one correction by clicking its badge, then click Accept. Confirm the text actually written back into the field keeps the original wording at the reverted spot and applies the corrected wording everywhere else. Also confirm Cancel is unaffected (clipboard still restores as before) and that accepting with nothing reverted behaves exactly as it did before this feature (full corrected text applied).

- [ ] **Step 7: Leave changes for review**

Do not commit. Leave the full diff (`Erratly/Diff.swift`, `Erratly/DiffPanel.swift`, `Erratly/ErratlyApp.swift`) for the user to review together.
