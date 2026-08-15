# TypingScape

A macOS menu bar app that turns the words you type today into a picture. It
tracks word frequency system-wide via the Accessibility API (not raw
keystrokes, so it correctly sees composed Hangul/IME text), then fills a
chosen silhouette — a mountain, a star, the sea, an uploaded photo — using
nothing but the words themselves, packed edge-to-edge like justified text.
No separate outline is drawn; the shape reads entirely through how densely
the words are packed.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
</p>

## How it works

- **Word tracking** — `FocusedTextTracker` reads the value of whatever UI
  element is currently focused, via `AXObserver`. This is what lets it
  capture real, composed words instead of individual keystrokes or IME jamo.
  Words reset daily at midnight; a day's finished counts are archived into
  history instead of being discarded.
- **Shape fill** — `MountainWordCloud` fills a mask row by row from the
  bottom up, spreading each row's words with even gaps so every row spans
  the mask's actual left/right edge (`ImageMask.horizontalExtents`). A word
  typed more often renders larger (log-scaled, so a handful of outliers
  don't visually dominate the whole shape) and denser/darker where a photo's
  own shadow falls.
- **Masks** — basic shapes and landscapes are hand-drawn `Shape`s rendered
  to a bitmap. Photos (a bundled album cover, or anything you upload) go
  through `SubjectMaskGenerator`: person/instance segmentation with Vision,
  falling back through background flood-fill and saliency, refined with a
  darkness threshold and hole-filling for low-contrast subjects.

## Features

- Menu bar popover with a live preview, plus a larger window for a proper
  look.
- Preset shapes (circle, star, mountain, house, river, sea — some
  animated) or any photo you pick.
- Two word-cloud styles (plain editorial serif, or a magazine-collage look
  with colored chips) and three background textures (paper, newsprint,
  dark).
- Browse past days' shapes, and a weekly/monthly stats view (daily activity
  chart + most-used words).

## Requirements

- macOS 14+
- Accessibility permission (prompted on first launch) — this is what lets
  the app see focused-element text system-wide.

## Running it

```bash
./dev-run.sh
```

This builds, ad-hoc code-signs with a fixed identifier (so macOS doesn't
re-prompt for Accessibility permission on every rebuild), and launches the
app. Only one instance runs at a time — launching again replaces the
previous one.

```bash
swift build
swift test
```

## Privacy

Everything stays on-device — word counts and history live in
`UserDefaults`, there's no network access. Secure/password text fields are
explicitly excluded from tracking. Real-word filtering (via `NSSpellChecker`)
means mashed-key gibberish never gets recorded in the first place.

## Known limitations

- Chromium-based apps (Chrome, Slack, VS Code, Discord, ...) and terminal
  apps render text in ways the Accessibility API often can't read
  reliably — tracking may miss words typed there.
- A word typed right before switching focus or apps, with no trailing
  space/enter yet, can be lost if the app quits at that exact moment.
