# Per-correction removal in DiffPanel

## Goal

In the diff panel shown after an LLM correction, let the user remove
individual corrections before accepting. Hovering a correction shows a small
cross badge at its bottom-left corner; clicking it reverts that specific
correction back to the original wording while leaving all other corrections
applied.

## Correction granularity

A "correction" is one contiguous run of non-unchanged `DiffToken`s produced
by `Diff.compute` — i.e. everything between two unchanged runs. This covers
three shapes:

- **Substitution**: removed text immediately followed by added text (e.g.
  "teh" → "the"). Both parts share one cross / one removable unit.
- **Pure deletion**: removed text only (the correction deleted something from
  the original).
- **Pure insertion**: added text only (the correction inserted something new).

Removing (reverting) a correction always means: show what the *original*
text had at that spot. For a substitution or pure deletion that means
restoring the removed text. For a pure insertion that means contributing
nothing (the insertion never happened).

Reverting is one-way for the lifetime of the panel — no toggle-back. Closing
and reprocessing is the only way to get a reverted correction back.

## Data model

Add a grouping step on top of `Diff.compute`'s flat `[DiffToken]`:

```swift
struct Correction {
    let removedText: String   // "" if pure insertion
    let addedText: String     // "" if pure deletion
    var isReverted: Bool = false
}

enum Segment {
    case text(String)         // unchanged run
    case correction(Int)      // index into the Correction array
}
```

The segment list (built once from the diff tokens) is the single source of
truth for both rendering and reconstructing the final text.

- **Rendering**: for each segment — unchanged text renders as plain ink;
  a kept correction renders its `removedText` (struck through, faded, only
  if non-empty) followed by its `addedText` (green-highlighted); a reverted
  correction renders only its `removedText`, styled as plain unchanged text
  (no strikethrough, no highlight). Each correction's contributing
  `NSRange` within the attributed string is recorded for hover/click
  geometry.
- **Final text reconstruction** (used on Accept): walk the segments again —
  `.text` contributes its string; `.correction` contributes `addedText` if
  kept or `removedText` if reverted. This replaces the caller's previously
  captured `corrected` constant as the source of the applied text.

## Interaction

Implemented inside the existing `HighlightedTextView` (already does manual
layout-manager-based drawing for the removed/added highlights), rather than
adding real subviews per correction:

- A single `NSTrackingArea` (`.mouseMoved`, plus mouse-enter/exit) covers the
  text view.
- On `mouseMoved`, map the cursor point to a glyph index, find the enclosing
  (non-reverted) correction's recorded `NSRange`, union its line-fragment
  rects (same technique already used to paint highlights), and store it as
  `hoveredCorrection: (index: Int, rect: NSRect)?`. Triggers
  `setNeedsDisplay`. Reverted corrections are plain text and never register
  as hoverable.
- In `draw(_:)`, after painting the existing highlights, if a correction is
  hovered, draw a small badge (~14pt, ink-colored stroke on paper-colored
  fill, matching the panel's paper/ink theme — not a system icon) with an
  "×" centered on the bottom-left corner of the hovered correction's rect,
  slightly overlapping it.
- `mouseDown` computes the badge's hit rect from the current
  `hoveredCorrection`. If the click lands inside it: mark that
  `Correction.isReverted = true`, rebuild the attributed string and segment
  ranges, clear hover state, `setNeedsDisplay`, and consume the event
  (don't call `super.mouseDown`). Otherwise, fall through to
  `super.mouseDown` so normal text selection keeps working.
- Rebuilding the attributed string from scratch on every removal is cheap
  (a handful of short strings) and simpler than incremental patching.

## Accept flow wiring

`DiffPanel.init`'s `onAccept` closure type changes from `() -> Void` to
`(String) -> Void`, carrying the reconstructed final text.
`dismiss(accepted:)` passes that string through when accepted. In
`ErratlyApp.swift`, the call site's `onAccept` closure gains a `finalText`
parameter and uses it — instead of the previously captured `corrected`
constant — for `CorrectionHistory.record`, `replaceSelectedText`, and
`Analytics.correctionAccepted`. `onCancel` is unaffected.

## Edge cases

- No corrections at all: behaves exactly as today, hover/cross never
  appears.
- All corrections reverted: final text equals the original selected text;
  Accept still performs a (no-op) replacement.
- Panel size stays fixed; the existing scroll view already handles reflow
  if reverted text changes line lengths.
