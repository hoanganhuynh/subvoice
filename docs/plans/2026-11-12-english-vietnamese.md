# English → Vietnamese speech implementation

Goal: translate English subtitles on device, then speak Vietnamese using the selected voice.
Architecture: stable full-text buffer → serial cancellable translation pipeline → existing speech queue. Apple Translation is isolated behind a SwiftUI preparation bridge; macOS 14 keeps direct reading.
Spec: docs/design/2026-11-12-english-vietnamese.md

## Constraints

- Default remains Vietnamese reading; translation requires macOS 15+ and supported en→vi models.
- Content never leaves the device. No API key, persistent transcript, audio transcription or overlay.
- Stale results after stop, pause, selection or mode change cannot reach speech.

## Review focus

- OCR fade-in must not translate suffixes without context.
- Async results must retain subtitle order and respect session cancellation.
- Model download cancellation/failure must leave a retryable UI.
- Existing macOS 14 and Intel build must remain loadable.
- Hiding the main window must not use an expired Apple translation session.

## Tasks

1. [x] Add failing tests for reading-mode persistence/defaults, full-subtitle buffering and bilingual transcript search. Implement core models.
2. [x] Add failing pipeline tests for ordered results, cancelled generations and errors. Implement serial translation and Apple preparation bridge.
3. [x] Integrate OCR language selection, lifecycle resets, translation before speech and non-English fallback prevention. Add Voice Studio/menu controls and transcript source copy.
4. [x] Run focused/full tests, Universal build, smoke tests, native model availability check; document usage and exact verification limits. Review whole diff and hand off installed build.

## Verification

- Full Swift suite: 194 tests reported across 21 suites, no failures; the opt-in live Apple translation test is skipped by default.
- Real Vision OCR: synthetic English subtitle recognized exactly.
- Regression tests cover complete/overlapping/shortened text, serial output, cancelled translations, pause/resume OCR tokens, unavailable platforms, and immediate preparation cancellation/retry.
- Universal arm64/x86_64 release built and installed; Translation and its SwiftUI bridge are weak-linked with macOS 14.0 minimum deployment. Signature verification outside the sandbox passed.
- Overlay smoke and main-window smoke passed before the final pause/buffer fixes; repeated on final installed release at handoff.
- Native Apple availability check confirmed en→vi is supported but requires language downloads on this Mac. The opt-in translation test stops at this prerequisite; translation quality, download dialog interaction, translated audio and hidden-window native translation remain unverified until languages are prepared in the app.
- Native UI automation stalled reading the main window; no automated language-download acceptance was performed.
