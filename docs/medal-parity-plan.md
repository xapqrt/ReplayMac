# ReplayMac → "Medal for Mac": research & build plan

_Researched 2026‑09‑19 against repo state `f3df077` (v1.7.1), macOS 27.0 GA (26A428, released
2026‑09‑14) and Xcode 27 GA (27A266a, Swift 6.4)._

---

## Decisions taken (2026‑09‑19)

| Question | Decision | Consequence |
| --- | --- | --- |
| Licensing (this tree is a fork of `picccassso/ReplayMac`, whose license bars redistributing modified builds, rebranding and store upload) | **Personal use only for now** — build everything, publish nothing | Unblocks all development. No rebrand, no public releases, no MAS upload. Keep the upstream attribution + license notice in README (done) |
| Sharing / cloud scope | **Option A: local-first, no server** | Export presets (resolution / fps / aspect / size caps), Discord webhook + attachment, YouTube/TikTok/X direct upload APIs, AirDrop/share sheet, QR or "send to phone" handoff. Zero infra cost, no moderation duty, no privacy-policy rewrite. No public `replaymac.tv`-style link — revisit only if that becomes a must-have |
| Where to start | **Phase 0: macOS 27 foundation** | In progress — see §8 |
| Distribution & OS floor | **Direct/GitHub build only; keep macOS 15+ universal** | `AppStore/` wrapper marked dormant (not deleted). Sandbox stays ON for the direct build (notarization + it already works); revisit only if a feature genuinely needs to be unsandboxed. Deployment target stays 15.0, so the silent `ARCHS_STANDARD` arm64-only change at DT ≥ 27.0 cannot bite, and all 26/27-only API is gated with `#available` |

Dead-file note found during Phase 0: `Resources/ReplayCap.sandbox.entitlements` is referenced by
nothing (`build-app.sh` uses `ReplayCap.dev.entitlements` / `ReplayCap.appstore.entitlements`,
`AppStore/project.yml` uses the appstore one). Left in place deliberately; delete it when the
entitlements are next touched.

---

## 0. TL;DR

1. **Medal does not exist on macOS.** Medal's own support docs list Mac as an *unsupported*
   platform and their Mac download was retired; a Medal staff member on r/MedalTV says a port
   "would be a from-scratch build of the recorder." So "a Medal equivalent" is not catching up to
   a Mac incumbent — it is an open gap. The Mac-side competition (ClipMac, MacClipper) is thin:
   instant replay + basic trim, single audio track, no editor effects, no social layer.
2. **This repo already beats Medal on the capture half.** Dual-display, HDR 10‑bit HLG, per-app
   audio, separate mic/system tracks, display priority + wake/KVM recovery, 30‑minute disk-backed
   replay, profiles, crop/GIF export, universal binary, sandboxed App Store build. Medal has none
   of the display/HDR/dual-track sophistication on any platform.
3. **The gap is everything *after* the recording**: a real editor, an in-game overlay, share
   links/cloud, auto-highlights, voice clipping, screenshots, webcam, vertical (9:16) reframing.
4. **macOS 27 hands us three free wins**: `SCClipBufferingOutput` (system-owned instant replay),
   `SCRecordingEditor` (system-owned clip review UI), and App Intents → Siri AI / Spotlight
   "Search or Ask" (macOS 27's headline feature is only usable by apps that expose App Intents).
5. **The macOS 27 hotkey bug this repo documents as unfixable is now fixed upstream**:
   `KeyboardShortcuts` 3.1.0 (2026‑09‑11) is literally titled "Improve macOS 27 compatibility" and
   closes issue #241 "Recorder does not capture shortcuts and clear button does nothing on macOS
   26/27". The repo pins 2.4.0. That is day‑one work.
6. **One blocker to settle before writing product code**: this checkout is a *fork* of
   `picccassso/ReplayMac`, and `LICENSE.md` forbids redistributing modified versions, publishing
   renamed forks, rebranding, and App Store upload without written permission. See §7.

---

## 1. Repo audit (what we are actually working with)

**Shape.** SwiftPM package `ReplayCap`, `swift-tools-version:6.0`, `platforms: [.macOS(.v15)]`,
9 modules + 1 executable:

| Module | Contents | Notes |
| --- | --- | --- |
| `Branding` | `AppBranding` | ReplayMac (direct) vs ReplayCap (MAS) name swap |
| `Capture` | `CaptureManager`, `FrameCompositor`, `DisplayIdentity`, `CapturePermissions`, `GameAppClassifier`, health/interruption classifiers | ScreenCaptureKit; already uses `SCContentSharingPicker` + observer |
| `Encode` | `VideoEncoder`, `AudioEncoder` | VideoToolbox HEVC/H.264, HDR Main10 |
| `RingBuffer` | `VideoRingBuffer`, `AudioRingBuffer` | Hand-rolled instant replay, memory cap + eviction |
| `Save` | `ClipSaver`, `CompositionRemuxer`, `AudioTrackMixer`, `LongBufferRecorder`, `HDRVideoExport`, `FilenameTemplate` | AVFoundation export/remux path |
| `Audio` | `MicCapture`, `SystemAudioCapture`, `PerAppAudioCapture`, `AudioLevelMonitor`, `AudioLevelPreview`, stall policy, timeline | `AVAudioEngine` w/ config-change rebuild + watchdog |
| `UI` | Settings (8 tab files), ClipLibrary (1822‑line view), MenuBar, Onboarding, Theme | SwiftUI + `Defaults` |
| `Hotkeys` | `HotkeyManager`, 7 `KeyboardShortcuts.Name`s | Carbon hotkeys via dependency |
| `Feedback` | `NotificationManager`, `AudioCue` | UNUserNotificationCenter |
| `Sources/App` | `AppDelegate` + 10 extensions, `GameActivityMonitor`, `ReplayBufferGate` | AppKit lifecycle, LSUIElement menu-bar app |

~21k lines of Swift (≈15k product / ≈6k tests), 6 test targets, `swift build && swift test` CI on
`macos-latest`, `build-app.sh` producing a notarizable universal `.app`, plus an XcodeGen wrapper
(`AppStore/project.yml`) for App Store archiving.

**Health signals.** The CHANGELOG is unusually honest about root causes (main-actor corruption on
macOS 26.5, `NSSavePanel.runModal()` starving Swift concurrency, silence-chunk allocation blowing
the ring buffer cap, mic clock drift, BT.709 tagging). That is the codebase of someone who debugs
capture properly — a good foundation to build an editor on.

**Dependency staleness.**

| Dep | Pinned | Latest | Action |
| --- | --- | --- | --- |
| KeyboardShortcuts | 2.4.0 (2025‑09) | **3.1.0 (2026‑09‑11)** | Bump — carries the macOS 27 fix |
| Defaults | 9.0.8 | 9.0.9 | Bump |
| swift-collections | 1.4.1 | 1.6.0 | Bump |

**Xcode 27 hard-failure audit (already checked in this tree):**
- `PreviewProvider` — not used. ✅ (deprecated at DT 27.0)
- `-ld_classic` / `-ld64` — not used anywhere. ✅ (ld64 removed in Xcode 27)
- `@State`-assigning custom initializers — none found; `ClipLibraryView` has an empty
  `public init()`. ✅
- `ARCHS_STANDARD` dropping `x86_64` — only triggers at `MACOSX_DEPLOYMENT_TARGET >= 27.0`. We are
  at 15.0 in both `Package.swift` and `project.yml`/`pbxproj`, and `build-app.sh` passes
  `--arch arm64 --arch x86_64` explicitly. ✅ **Keep the deployment target at 15.0** and gate new
  API with `#available`.
- Stale comment to clean: `ClipLibraryView.swift` says "Swift 6.1 (still served by GitHub's
  macos-latest runners)" — `macos-latest` migrated to macOS 26 in June 2026.

---

## 2. What macOS 27 "Golden Gate" means for this repo

### 2.1 The OS itself

Released 2026‑09‑14 (build 26A428). Framed as the "Snow Leopard" release — performance/stability
over redesign: ~30% faster app launch via preloading, faster AirDrop/Spotlight/network file
browsing, smoother Mission Control.

Things that matter to us:

- **Apple silicon only.** First macOS with zero Intel support, and the **last** with
  general-purpose Rosetta (macOS 28 keeps only a games-only subset, and Rosetta is *not
  automatically restored* across the upgrade). → Our universal binary stays correct for macOS
  15/26 Intel users, but Intel is a shrinking tail; do not spend any more effort there (1.6.9's
  universal work is done, leave it).
- **Liquid Glass refinement, not replacement.** A user-facing **transparency slider** (clear ↔
  tinted) and **standardized corner radius** across system windows and apps. macOS 26's
  inconsistent radii were widely read as a bug; Apple called the fix out on stage. → Custom corner
  radii and hand-rolled materials now visibly fight the system. Adopt the real APIs (§5, Phase 0).
- **Siri AI + Spotlight "Search or Ask"** is the headline feature, and Apple is explicit that
  third-party participation requires **App Intents**: "developers need to expose their apps'
  content and capabilities through the App Intents framework." → Free distribution surface for a
  clipper ("Hey Siri, clip that", "Show my Rocket League clips").
- **External display improvements**: more resolution/refresh choices (5K@120 on some ultrawides)
  and better restoration of window positions/Spaces/screen assignments on unplug-replug. → Directly
  relevant to `DisplayIdentity` / display-priority recovery; re-test the wake/dock/KVM paths on 27.
- **Apple Intelligence AFM 3** (on-device 3B dense + 20B sparse multimodal) and the
  `FoundationModels` framework (+270 APIs in the 27 SDK: `AnyTool`, `DynamicInstructions`,
  `Attachment`). On-device, no server bill → usable for auto-titles/tags/hashtags.
- **Child safety / Screen Time** expansions — a screen recorder may see new parental-control
  interaction paths; low risk, verify during MAS submission.

### 2.2 The toolchain (Xcode 27 / Swift 6.4)

- Xcode 27 requires **macOS 26.6+ and Apple silicon**; ships Swift 6.4 and the macOS 27 SDK.
- **You do not need macOS 27 to build for it**: the 27 SDK back-deploys, and Xcode 27 runs on 26.6.
  Your machine is on 27 already, so you're fine either way.
- Minimum deployment target floor raised to **macOS 12** (we're at 15 — fine).
- `ARCHS_STANDARD` silently drops `x86_64` at DT ≥ 27.0, with **no warning**. Do not raise the DT.
- `ld64` removed; `-ld_classic` now only warns. Unique Clang module names enforced in a dependency
  scan (may error). `PreviewProvider` deprecated in favour of `#Preview`.
- Xcode 27.2 beta (2026‑09‑16) adds a **JSON project format `.xcproj`** that is "more readable,
  merge-friendly, and easier for coding agents to edit" — worth adopting for the `AppStore/`
  wrapper later, since we regenerate it with XcodeGen anyway.
- **CI**: GitHub's `macos-latest` is now macOS 26 (arm64) with Xcode 26.5/26.6 default. There is a
  dedicated **`xcode-27`** runner label (macOS 26 + Xcode 27 + the macOS 27 SDK, currently
  "preview"). To compile `SCClipBufferingOutput` & co. in CI we need a job on `xcode-27` (or
  `DEVELOPER_DIR` pinned to Xcode 27 on the macOS 26 image).

### 2.3 ScreenCaptureKit in the 27 SDK — the important part

ScreenCaptureKit gains **+72 APIs, 0 deprecations** in the 27 SDK and is now available on iOS/iPadOS/tvOS/visionOS
(it **replaces ReplayKit** for screen streaming/mirroring; ReplayKit is deprecated wholesale, 44
APIs — we don't use it, good). New on macOS 27:

| API | What it is | Why we care |
| --- | --- | --- |
| **`SCClipBufferingOutput`** + `SCClipBufferingOutputDelegate` | A **system-owned clip-buffering session** attached to an `SCStream` via `addClipBufferingOutput(_:)`. `exportClip(to:duration:)` (sync + `async throws`) writes the most recent samples to a file URL, **max duration 15 s**, export doesn't interrupt buffering | Apple has shipped *our core feature*. Buffering happens in the system capture process, not our heap → potentially a dramatic memory/CPU win for an always-on 15 s replay. Cannot replace our 30–300 s ring buffer (15 s ceiling, no control over codec/bitrate/HDR/dual-display), but is an ideal **"low-power quick replay" mode** and a great 15 s hotkey path |
| **`SCRecordingEditor`** + delegate, `Mode` | "Presents a **system-owned preview UI** for a completed recording"; `init(url:)`, `present(from: NSWindow)` | A free, native "review/trim this clip right now" sheet after every save — the exact Medal post-clip moment. Zero UI cost |
| **`SCContentSharingPicker.present(from: NSWindow)` / `presentForCurrentApplication` / `isAvailable`** | Picker presentation now first-class on macOS (we already build an observer in `CapturePermissions.swift`) | Cleaner capture-target selection UX; per-stream configuration |
| **`SCStreamError.Code` gains `insufficientStorage`, `notSupported`, `missingBackgroundMode`** (confirmed present in the 27 SDK docs; the enum itself dates back to macOS 12.3) | Three new failure causes, two of which we care about | `CaptureInterruptionClassifier` **already** matches symbolically (`SCStreamError.Code(rawValue:) == .systemStoppedStream`, with `NSUnderlyingErrorKey` unwinding) — so the work is additive, not a rewrite: map `insufficientStorage` to the existing low-disk-space messaging in `SavePreflight`/`CaptureUserMessages`, and `notSupported` to a clear "this capture configuration isn't supported on this display/OS" message instead of a generic failure |
| **`SCStreamFrameInfo` / `SCFrameStatus`** | Typed attachment keys and frame status | Already used correctly (`CaptureDelegate.frameStatus(of:)` reads `SCStreamFrameInfo.status` and builds an `SCFrameStatus`) — nothing to migrate here |
| **`SCVideoEffectOutput`** | Camera video-effect session | System camera effects (Studio Light/Portrait/Desk View-style) composited for a **webcam overlay** — Phase 5 |
| New `SCStreamConfiguration` surface | `shouldBeOpaque`, `backgroundColor`, `capturesShadowsOnly`, `ignoreShadowsDisplay/SingleWindow`, `ignoreGlobalClipDisplay/SingleWindow`, `captureDynamicRange`, `Preset` | Shadow/clip control useful for **window-scoped game capture** (record only the game window — a feature Medal has on Windows and we don't) |
| `SCRecordingOutput` (macOS 15, **unused here**) | Direct-to-file recording output on the stream | Would let the system, not our `VideoEncoder`+`AVAssetWriter`, write session recordings. Worth a spike: fewer moving parts, less app-process memory. Trade-off: less control over the container/segment rotation that `LongBufferRecorder` depends on |

Also relevant: `AVFoundation` in the 27 SDK adds **`AVAssetWritingPlanner` / `AVAssetVideoTrackPlan`
/ `AVPlannedVideoSegmentWritingRequest` / `SegmentBoundaryGuidelines`** — a *planned, resumable,
segmented* writing path with `successWithState(Data)` resumption and export `ResumptionFailureReason`
diagnostics. That is a much better substrate for both `LongBufferRecorder` (rolling segments) and
the new editor's export (resumable renders that survive sleep/quit). AVFoundation also deprecates
84 APIs in this SDK (mostly `AVAssetDownloadTask` keys + `audiovisualTypes`); **we must build once
with the 27 SDK and triage warnings** — `AVAssetExportSession` is used in 8 places and
`AVAssetWriter`/`AVAssetWriterInput` in ~48.

### 2.4 Privacy / TCC / distribution changes in 27

- **"Apps can no longer access the local TCC database directly."** We never did (we use
  `CGPreflightScreenCaptureAccess`-style checks + the picker) — no action, but don't be tempted to
  add TCC.db probing for a "permissions doctor" screen. New admin-only `tccutil list`.
- **Cross-team container access is now denied by default** (no prompt) for other developer teams'
  app data / app group containers, user-manageable in Privacy & Security; XProtect "may now
  restrict access to app data that is commonly targeted by malicious software". → `GameActivityMonitor`
  reads *other apps' bundles* (`Contents/Info.plist`) for the App Store "Games" category. App
  bundles are not app-data containers so this should be unaffected, and the code already has a
  bundle-id-only fallback path — but **re-test auto game detection on 27** and prefer the
  workspace-notification bundle id.
- **App Attest is now available on the Mac** — if we add a cloud backend, this is the clean way to
  prove "this upload came from a genuine ReplayMac install" and stop abuse of free hosting.
- `spctl` gains `purge`; installer packages with no `hostArchitecture` now **default to arm64**
  (only relevant if we ever ship a `.pkg` instead of a `.dmg`); stricter TLS (ATS-level) for select
  system processes on managed Macs — relevant if we ever talk to an MDM.
- Screen capture remains **purely TCC-gated** (no entitlement grants it); `NSScreenCaptureUsageDescription`
  is mandatory or the system kills the app at prompt time. Ours is present. Note
  `com.apple.security.screen-capture` in our entitlements is not a real Apple entitlement key —
  harmless, but it is cargo-cult and can be dropped.

### 2.5 The hotkey bug — solved upstream

README currently says: _"Some macOS versions (currently the macOS 27 'Golden Gate' betas) have a
system bug that stops the shortcut recorder from registering key presses"_, with
`docs/manual-hotkey-setup.md` teaching `defaults write` for all 7 actions.

Upstream `sindresorhus/KeyboardShortcuts` issue **#241** ("Recorder does not capture shortcuts and
clear button does nothing on macOS 26/27", closed 2026‑09‑11) diagnoses **three independent
defects** — none of them actually an Apple bug:
1. `LocalEventMonitor` held its `NSEvent.addLocalMonitorForEvents` token **weakly**, so it was
   deallocated when the autorelease pool drained — the recorder was never listening.
2. `becomeFirstResponder` set `showsCancelButton`, which mutates `cancelButtonCell`, which makes
   AppKit end+restart field editing, firing `controlTextDidEndEditing` → `endRecording()`
   microseconds after the monitor was armed (this is why it only failed when replacing an existing
   shortcut).
3. The monitor swallowed `mouseUp` inside the field, so `NSSearchFieldCell`'s `_searchFieldCancel:`
   never ran — the clear button looked pressable and did nothing.

All three are fixed in **3.1.0** (2026‑09‑11, "Improve macOS 27 compatibility", plus fixes for
function-key shortcuts not firing while a menu is open and laggy menu highlighting — both relevant
to a menu-bar app). 3.0.0's breaking changes are `Name#defaultShortcut` → `#initialShortcut` and
the `default:` parameter → `initial:`; **this repo uses neither** (all 7 names are declared bare),
so the bump is nearly free. 3.x is Swift 6 / tools 6.2, macOS 10.15+, and adds
`Shortcut#isTakenBySystem` + `Shortcut#toSwiftUI` + `repeatingKeyDownEvents(for:)` (the last one is
useful for a push-to-talk hotkey).

→ **Phase 0, task 1.** Then update README's Troubleshooting and demote
`docs/manual-hotkey-setup.md` to "if the recorder still misbehaves".

---

## 3. Medal, precisely

Medal's own platform-support page: **Web, Windows, Android, iOS. Unsupported: Mac, Linux,
Chromebook.** So "Medal for Mac" = build the whole thing ourselves. Feature inventory, from
medal.tv/features, medal.tv/about, medal.tv/editor, the Nov‑2025 "new editor" announcement and
support.medal.tv:

**Capture**
- Instant replay from a hotkey (default F8), configurable 15 s → 10 min; long recording / full
  session; screen recording (non-game); **screenshots**.
- **Game Event Detection / auto-clipping**: wins, goals, headshots, aces in Fortnite, Valorant,
  LoL, Apex, CS2, Dota 2 …; 3,000+ games recognized, manual "detect this game" for new titles.
- Multi-track audio: **game, desktop (e.g. Discord), microphone** separately; include/exclude at
  capture and strip later.
- **Webcam support**; up to 4K@144 (Premium); GPU-backed (NVIDIA/AMD/Intel).
- **Voice-activated clipping** — "Clip that", hands-free.
- **Simple game overlay** — "manage recording and clips without tabbing out".
- Per-game settings; custom hotkey sounds (Premium).

**Editor (the Nov‑2025 rewrite — this is the bar)**
- **Multi-track** video + audio timeline, **detachable audio tracks**, split/trim.
- **Playback speed 0.25×–4×** (slow-mo / fast-forward), **zoom**, **freeze frame**, **chroma key**,
  filters, **alpha/opacity** adjustments.
- **Animated captions**, text with font/colour/stroke/highlight/border/opacity + **entrance & exit
  effects with durations**, resize/rotate/move by dragging corners.
- **Image, GIF, sticker, meme overlays**; upload your own media.
- **Music + sound effects**, music timeline with volume slider and preview, multi-track audio
  balancing; voiceover recording (mobile editor).
- **Scene transitions**, multi-clip edits / montages from a blank timeline.
- **Quality & size settings**: resolution, width, height, FPS, anti-aliasing; fast renders.
- Full editor hotkeys: copy/paste, arrows, zoom, delete, undo/redo.

**Library / cloud / social**
- One library for clips + screenshots; **folders and tags**; organize by game/theme/people.
- **Instant share link** the moment you clip; auto-embeds in Discord, auto-formats for TikTok/Reddit;
  no upload step.
- **Free cloud hosting that never expires**, re-downloadable from any device; Premium: automatic
  cloud sync (auto-upload), unlimited space, up to 24 h uploads, 4K/144 uploads, watermark/outro
  removal, ad-free, animated avatar/banner + badge, subtitles, priority support.
- **Public / unlisted / private** visibility; comments, likes, friend tagging, follow, trending &
  top-clips discovery, per-game browsing; web editor; mobile apps (browse/edit/share, record on
  Android; iOS recording added 2026); Discord integration; import of clips from other recorders
  ("Sync an External Recorder"), including console captures.

### Competition on Mac

| | Medal | **ClipMac** | MacClipper | ReplayMac (us) |
| --- | --- | --- | --- | --- |
| macOS | ❌ none | ✅ native, macOS 15+ | ✅ | ✅ 15+, Apple Silicon + Intel |
| Instant replay | 15 s–10 min | up to 2 min | ✅ | **15 s–300 s + 5/10/30 min disk buffer** |
| Quality | 4K/144 (Premium) | 4K 60 | 4K | **HEVC/H.264, Retina, custom, 10‑bit HDR HLG** |
| Audio | game+desktop+mic tracks | single track | — | **system (all/none/per-app) + mic, merged or separate tracks, volumes, live meters** |
| Displays | — | — | — | **dual display (side-by-side or separate files), priority list + auto-recovery** |
| Editor | full multi-track | basic trim | "built-in editing" | trim + crop + GIF only ← **our biggest gap** |
| Overlay HUD | ✅ | ❌ | ❌ | ❌ |
| Auto-clip highlights | ✅ (per-game) | "limited" | ❌ | auto-record on game launch only |
| Voice clip | ✅ | ❌ | ✅ ("Mac Clip That") | ❌ |
| Cloud/share link | ✅ free forever | ✅ free uploads, 50 GB, $5.99/mo tiers | ✅ | ❌ share sheet / copy file only |
| Social | ✅ 12–15 M users | ❌ | ❌ | ❌ |
| Mobile/web | ✅ | ❌ | ❌ | ❌ |
| Price | free + Premium | free + $5.99/mo | free | free (GitHub) + one-time MAS purchase |

Upstream issue **#12 (opened today)** is "Export at different resolution + Discord?" — users are
already asking for exactly the two Medal pillars we lack (export presets for social, and Discord).

---

## 4. Gap analysis → workstreams

| # | Pillar | Medal has | We have | Verdict |
| --- | --- | --- | --- | --- |
| A | Instant replay + session + auto-record | ✅ | ✅ **better** | Done |
| B | Capture quality (HDR, displays, audio tracks) | partial | ✅ **better** | Done |
| C | **Editor** | ✅ full multi-track | trim/crop/GIF | **Biggest gap, biggest value** |
| D | **Overlay HUD** in-game | ✅ | ❌ | Small, high perceived value |
| E | **Share link / cloud / mobile** | ✅ | ❌ | Needs a backend decision (§7) |
| F | **Auto-clip highlights** | ✅ per-game SDK | ❌ | Needs a CV/audio approach (no game SDKs on Mac) |
| G | **Voice clipping** | ✅ | ❌ | On-device `SpeechAnalyzer` (macOS 26+) |
| H | Screenshots | ✅ | ❌ | Trivial via `SCScreenshotManager` |
| I | Webcam / facecam | ✅ | ❌ | `AVCaptureSession` or 27's `SCVideoEffectOutput` |
| J | Vertical 9:16 reframe for TikTok/Shorts | partial (size settings) | crop only | Differentiator w/ Vision subject tracking |
| K | Social/community | ✅ | ❌ | Server + moderation + DMCA; defer |
| L | **macOS 27 native feel** (Liquid Glass, Siri AI, App Intents) | n/a | ❌ | Cheap, high visibility |

---

## 5. Plan

Sequencing principle: **foundation → things that make the current app feel world-class on 27 →
the editor → sharing → intelligence.** Each phase ships independently.

### Phase 0 — macOS 27 foundation (≈1 week, mostly mechanical)

1. **Bump deps**: KeyboardShortcuts 2.4.0 → **3.1.0**, Defaults → 9.0.9, swift-collections → 1.6.0.
   Verify the Settings/Onboarding `Recorder`s now work on 27; adopt `Shortcut#isTakenBySystem` to
   warn on conflicts. Rewrite README Troubleshooting; demote `docs/manual-hotkey-setup.md`.
2. **Build against the 27 SDK** on the user's machine (`swift build`, `swift test`, `./build-app.sh`,
   XcodeGen archive) and triage every deprecation warning — especially the 84 AVFoundation ones
   around `AVAssetExportSession` / `AVAssetWriter`. Fix or explicitly accept each.
3. **CI**: add an `runs-on: xcode-27` job (keep `macos-latest` as the second leg) so 27-gated code
   compiles in CI; pin `swift --version` output in the log.
4. **Typed capture errors — smaller than first thought.** Audit found the repo already does this
   properly: `CaptureInterruptionClassifier` matches `SCStreamError.Code` symbolically and unwinds
   `NSUnderlyingErrorKey`; `CaptureDelegate.frameStatus(of:)` reads `SCStreamFrameInfo.status`.
   Remaining work is (a) handle the three new 27-only `SCStreamError.Code` cases
   (`insufficientStorage` → reuse the low-disk-space copy, `notSupported` → say *why* the
   configuration was refused, `missingBackgroundMode` → n/a for a menu-bar app), and (b) resolve the
   one magic number left in the tree: `CaptureDelegate.stream(_:didStopWithError:)` special-cases
   the literal `-3821`. **Do not guess the mapping** — Apple's docs don't publish raw values and the
   case ordering in the header differs from the docs' grouping. Confirm on-device first
   (`SCStreamError.Code(rawValue: -3821)` in a scratch playground/`swift repl`, or print it from the
   existing branch), then replace the literal with the symbolic case. Deliberately left untouched in
   the first Phase 0 commit.
5. **Drop the non-existent `com.apple.security.screen-capture` entitlement key**; add
   `com.apple.security.device.camera` + `NSCameraUsageDescription` (Phase 5) and decide the
   network entitlement for the MAS build (Phase 3) — note the MAS entitlements file currently
   forbids networking entirely.
6. **`SystemClipBuffering` (27-only)**: new small module wrapping `SCClipBufferingOutput` —
   attach to the existing `SCStream`, `exportClip(to:duration:)` up to 15 s, delegate-driven
   health. Expose as Settings → Advanced → "Quick replay engine: ReplayMac buffer (15–300 s) /
   System buffer (≤15 s, lower overhead)". Measure memory + CPU of both; ship whichever wins for
   the ≤15 s case, keep ours as default for everything longer and for macOS 15–26.
7. **`SCRecordingEditor` post-save review (27-only)**: optional "Review clip" action on the
   save notification / menu bar / hotkey that presents the system editor for the just-written file.
8. **Re-test on 27**: display priority + wake/dock/KVM/clamshell recovery (27 changed external
   display restore behaviour), auto game detection (TCC/XProtect container rules), microphone
   device-change recovery, extended disk buffer.

### Phase 1 — Liquid Glass UI overhaul + App Intents (≈1–2 weeks)

**Design system first** (`Sources/UI/Theme/AppTheme.swift` is 20 lines of teal gradients — replace
it with a real token layer):
- Adopt system materials instead of `Color(NSColor.controlBackgroundColor)` + custom gradient
  buttons: `.buttonStyle(.glass)` / `.glassProminent` for actions, `.glassEffect(_:in:)` for
  floating surfaces, `GlassEffectContainer` whenever >1 glass element, `glassEffectID` for morphs.
  Gate with `#available(macOS 26.0, *)`, keep material fallbacks for 15.x.
- AppKit surfaces (status item badge, panels, HUD) use **`NSGlassEffectView` /
  `NSGlassEffectContainerView`** (`cornerRadius`, `tintColor`, animator-driven hover).
- Respect the 27 transparency slider implicitly (it drives the system material) and verify under
  Reduce Transparency / Increase Contrast / Reduce Motion — glass adapts automatically, custom
  gradients do not.
- Remove custom corner radii that now disagree with 27's standardized window radius.
- Settings: move from the hand-rolled tab enum to the macOS 26/27 pattern — `TabView` with
  `.tabViewStyle(.sidebarAdaptable)` inside the `Settings` scene (verify API name on-device),
  unified toolbar, `.toolbarBackgroundVisibility`, searchable.
- Clip Library: sidebar (All / Favorites / Games / Tags / By date) + `Table`/grid toggle with
  thumbnail gallery, hover actions, context menus, Quick Look, inspector pane; the current
  1822-line `ClipLibraryView` gets split into subviews + a view model per surface.
- New **home window**: recent-clips grid, big Clip/Record controls, buffer status, "Open editor" —
  the Medal-style front door instead of menu-bar-only.

**App Intents module** (new SwiftPM target; Xcode 27 supports `AppIntentsPackage` in packages):
- `AppShortcutsProvider` phrases: "Save a clip", "Clip the last N seconds", "Start/stop recording",
  "Open my clip library", "Take a screenshot".
- `ClipEntity: AppEntity, IndexedEntity` over the library store → clips become searchable by
  Spotlight **"Search or Ask"** and actionable by **Siri AI**; `OpenClipIntent: OpenIntent`.
- `supportedModes` = `[.background, .foreground(.dynamic)]` so "clip that" never steals focus from
  the game; **interactive snippets** returning the clip thumbnail + Follow-up buttons (Open / Edit
  / Share) in Spotlight.
- `NSUserActivity`-based onscreen entities on the library window ("ask Siri about what's on
  screen").
- This is also the *cheapest* voice-clipping path on 27: Siri AI can invoke the intent, no
  `SpeechAnalyzer` code at all.

### Phase 2 — In-game overlay HUD + screenshots (≈1 week)

- `NSPanel` overlay: `styleMask [.borderless, .nonactivatingPanel]`, `level = .statusBar`
  (or `.mainMenu + n`), `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
  .ignoresCycle]`, `isOpaque = false`, `backgroundColor = .clear`, `hidesOnDeactivate = false`,
  `ignoresMouseEvents` toggled by an "interactive" mode, `canBecomeKey = true` only when
  interactive. SwiftUI content via `NSHostingView`, glass-styled.
- **Critical detail: exclude it from our own capture.** Set `window.sharingType = .none` on the
  overlay (and any HUD panel) *and* keep excluding our app's windows in `SCContentFilter`, so the
  HUD never ends up inside the clip.
- Surfaces: recording dot + elapsed, buffered time, "Clip saved ✓ (N s)" toast with Open/Edit/Share,
  mic/system level meters, push-to-talk state, current display + fallback warning, FPS/bitrate
  readout, recent-plays strip (Outplayed-style) letting you click a moment to save it.
- Per-display placement, drag-to-position, opacity, auto-hide when idle; a "hide overlay" hotkey.
- **Screenshots**: `SCScreenshotManager.captureImage(contentFilter:configuration:)` (27 adds HDR
  screenshot output + advanced config) into the same library with a type badge; hotkey + overlay
  button. Cheap, Medal has it, users expect it.
- **Window-scoped capture** using the new `ignoreShadows*` / `shouldBeOpaque` config surface:
  "Record only the game window" — excludes the overlay, the menu bar, and notifications for free.

### Phase 3 — Share & export (**Option A chosen: local-first, no server**, ≈2–3 weeks)

**What we build:** export presets (1080p60 / 1440p / 4K, plus 9:16, 1:1 and ≤8 MB "Discord free
tier" and ≤25 MB targets — this is literally upstream issue #12, "Export at different resolution +
Discord?"), a Discord path (webhook + attachment upload, with the size-cap preset applied
automatically), direct uploads to YouTube / TikTok / X via their APIs, the existing share sheet and
AirDrop, and a phone handoff (QR code or a short-lived local HTTP server — the sandbox already
permits `com.apple.security.network.server`, which the direct entitlements would need added).
`PRIVACY.md` gets a short "where your clips go" section: nothing leaves the Mac unless you press
upload.

Deferred alternatives, recorded so the decision is reversible with context:

- **B. CloudKit personal sync.** Private DB per user, clips + metadata sync to their own devices,
  `CKShare` for person-to-person links. Cost: free (user's iCloud quota). No public web player,
  no discovery, and video in CloudKit is awkward (asset download URLs are auth-gated). Good for
  "my clips everywhere", not for "link in Discord".
- **C. Real backend = Medal parity.** Object storage + CDN with free egress (Cloudflare R2 /
  Workers, or Supabase Storage), signed uploads, a public `replaymac.tv/<id>`-style player page
  with oEmbed for Discord/Reddit, visibility public/unlisted/private, view counts, and optional
  auto-upload. Add **App Attest** (new on the Mac in 27) so only genuine installs can upload, plus
  size/duration caps, hash-based dedupe, and a report/DMCA flow. Cost: real money + moderation
  duty + privacy policy rewrite. This is the only path to a true "instant link" — and to the social
  layer (pillar K), which stays deferred regardless.

**Auto-title** via `FoundationModels` (Phase 4) pairs well with export: the on-device model names the
clip and suggests hashtags while the render runs.

### Phase 4 — Editor: "Clip Studio" (the big one, ≈6–10 weeks)

**Document model first** (pure value types → unit-testable without a GPU):

```
EditDocument
├── settings: {width,height,fps,aspect(16:9|9:16|1:1|4:5|free),background,quality}
├── tracks: [Track]  // video + audio, orderable, detachable, mute/solo/lock
│   └── clips: [TimelineClip]  // sourceURL, in/out, timeline range, speed(0.25…4), freeze frames
│       └── keyframed transforms: position, scale(zoom), rotation, opacity(alpha), crop
├── overlays: [Overlay]  // text (font,colour,stroke,highlight,border,opacity,entrance/exit+duration),
│                        // image, GIF, sticker, webcam PiP
├── effects: [Effect]    // filters, chroma key, adjustments, transitions between clips
└── audio: [AudioTrack]  // music, SFX, voiceover, per-clip volume + ducking, fades
```
Codable, versioned, `.replayedit` sidecar + embedded in the exported MP4's metadata; undo/redo via
document snapshots; autosave.

**Renderer — one graph, two backends** (so preview == export):
- Timeline → `AVMutableComposition` (multi-source, multi-track, `scaleTimeRange` for speed) +
  `AVMutableVideoComposition` with a **custom `AVVideoCompositing`** (Metal/Core Image) instead of
  `AVVideoCompositionCoreAnimationTool`. This is Apple's `AVCustomEdit` pattern and is what gives
  us chroma key, zoom/pan keyframes, transitions, filters and overlay rasterization (CoreText →
  `CGImage` for text; `CGImageSource`/`ImageIO` for GIF frame sequences — we already ship a
  `GIFExporter` to crib from) inside the hardware-accelerated AVFoundation pipeline.
- **Export** through the same compositor into `AVAssetWriter` (reuse `Sources/Encode/VideoEncoder`),
  and evaluate 27's **`AVAssetWritingPlanner`** for resumable segmented exports so a 4‑minute
  montage survives sleep/quit instead of restarting — plus the export watchdog pattern the repo
  already has (90 s no-progress cancel).
- **Preview** via `AVPlayer` + the same composition (pause before export — a bug class the repo
  already fixed once), transport bar with glass styling, timeline scrubbing, snapping, ripple
  delete, magnetic timeline, per-track meters.
- Reuse: `HDRVideoExport` (keep HDR through renders), `CompositionRemuxer` (no-re-encode audio-only
  changes), `VideoCropSelectionView` (drag-crop UI becomes the reframe UI), `AudioTrackMixer`.

**Feature order** (each independently shippable): trim/split/speed → aspect & 9:16 reframe → text
with entrance/exit → image/GIF/sticker overlays → music/SFX/voiceover + ducking → filters/chroma
key/alpha → transitions & multi-clip montage → export presets + fast render → editor hotkeys
(copy/paste/arrows/zoom/delete/undo/redo) → templates.

**Auto-clip highlights** (Medal's Event Detection, Mac-honest version — no game SDKs exist here):
- **Audio hype detection**: `AudioLevelMonitor` already computes RMS for system + mic. Spike
  detection (sustained loudness / sudden delta / mic shouting) → auto-save the last N s with a
  cooldown. Zero extra capture cost, works in every game.
- **Kill-feed OCR**: user draws a region (or per-game preset), we sample frames from the ring buffer
  at 2–4 fps — no new capture — and run `VNRecognizeTextRequest` (27's Vision adds `OCRTool`,
  +138 APIs). Match per-game patterns ("eliminated", "+1", "VICTORY", score deltas) → auto-clip.
- **Auto metadata**: `FoundationModels` (AFM 3, on-device, macOS 26+) turns the transcript + OCR
  text + app name into a title, description and hashtags; `Evaluations` (new framework) to score
  prompts before shipping them.
- All opt-in, all on-device, per-game enable/disable in Settings → Games (which already exists).

### Phase 5 — Webcam, vertical reframe, companion (later)

- **Webcam/facecam**: `AVCaptureSession` PiP with position/size/shape/crop, or 27's
  **`SCVideoEffectOutput`** to get system camera effects composited automatically; Presenter
  Overlay interplay (`stream(_:outputEffectDidStart:)`) must be handled so we don't double-apply.
  Requires the camera entitlement + `NSCameraUsageDescription`.
- **Auto vertical reframe**: 9:16 output that follows the subject — Vision person/head detection
  drives the crop keyframes. Medal can't do this; TikTok/Shorts creators would.
- **Voice clipping**: `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+, on-device, ANE-accelerated,
  ~55% faster than Whisper in public tests, no Siri/dictation prerequisite, needs only mic
  permission + a first-run language asset download). `AnalysisContext.contextualStrings` for custom
  wake phrases ("clip that", "save that", "big play"). Fall back to `SFSpeechRecognizer` +
  `requiresOnDeviceRecognition` on macOS 15. Or skip it entirely if the Siri AI App Intent from
  Phase 1 is enough.
- **Companion**: web player (comes with Phase 3C) and/or an iOS app that reads the same CloudKit
  container. Big; only after C is chosen.

---

## 6. Cross-cutting

- **Testing.** The repo's test culture is good (pure-logic tests: gates, templates, preflight, crop
  math, HDR metadata). Keep that shape for the editor: timeline math, keyframe interpolation,
  aspect/reframe geometry, document codability/migration, export-preset selection, hype-detector
  thresholds, OCR pattern matching — all testable headless. Capture/GPU paths stay behind
  protocols with fake sample buffers (already done in `CaptureTests`).
- **Sandbox.** Everything above works sandboxed except: cross-team container access (not needed),
  TCC.db (not needed), and cloud uploads (need `network.client`, absent from the MAS entitlements
  today).
- **Performance budget.** Medal's promise is "without dropping a frame". Track our own: buffer
  memory (already capped), encode CPU/GPU, dropped-frame counters (already logged in
  `AppDelegate+BufferMonitoring`) → surface an FPS/impact readout in the overlay (Phase 2) and an
  Instruments checklist per release.
- **Docs.** README feature list is excellent and honest; keep that voice. Add: editor guide,
  overlay guide, share/privacy policy update (if C), macOS 27 notes, and refresh the screenshots
  (README already admits they pre-date the rename).
- **Versions.** Phase 0+1 ≈ 1.8.0; Phase 2 ≈ 1.9.0; editor ≈ 2.0.0 (it is the product's second
  half). Keep MAS (`ReplayCap`) and direct (`ReplayMac`) builds in lockstep via `AppBranding`.

---

## 7. Risks & decisions needed

1. **✅ Resolved — licensing / ownership.** `git remote` is `xapqrt/ReplayMac`, a fork of
   `picccassso/ReplayMac` at the identical commit, and `LICENSE.md` (© 2026 Alex / picccassso)
   permits personal use and modification but forbids redistributing modified versions, publishing
   unofficial builds, selling, App Store upload, renaming/rebranding, and using the ReplayMac
   name/icon/branding for forks or competing products without written permission.
   **Decision: personal use only.** All development proceeds; nothing is published, rebranded, or
   uploaded. README now states the fork position explicitly. If that ever changes, the options were:
   (a) confirm authorship/permission, (b) keep it personal, (c) clean-room rewrite, (d) contribute
   upstream via PRs ("Contributions submitted to the official ReplayMac repository may be used… by
   the project owner").
2. **🟠 No Swift toolchain in this workspace.** This sandbox is Linux (no `swift`, no `xcodebuild`,
   no ScreenCaptureKit), so **nothing here can be compiled or tested by me**. Workflow: I write
   code + tests + exact verification steps; you run `swift build`, `swift test`, `./build-app.sh`
   on your Mac and paste failures back; we iterate. Small, self-contained, heavily-reviewed diffs
   beat big ones. (Optionally: a GitHub Actions run on the `xcode-27` label becomes our compiler.)
3. **✅ Resolved — cloud decision.** **Option A (local-first, no server).** No infrastructure cost,
   no abuse/moderation exposure, no privacy-policy rewrite, and it fits the current entitlements.
   Concretely: export presets + Discord/YouTube/TikTok/X direct upload + AirDrop/share sheet +
   phone handoff. The trade-off we accept is no public "instant link" and no mobile library; that is
   Option C's cost profile, revisitable later if it becomes a must-have.
4. **🟡 Editor scope.** "All the features Medal's editor has" is a multi-month build. Mitigation:
   document model + compositor first, then features in the Phase 4 order; each lands shippable.
5. **🟡 `SCClipBufferingOutput` unknowns**: 15 s ceiling, unknown codec/container/bitrate control,
   unknown audio (mic?) inclusion, and it must coexist with our own stream. Spike it before
   promising it in Settings.
6. **🟡 AVFoundation deprecation wave** (84 in the 27 SDK) — needs one real Xcode 27 build to
   triage; our export/remux/HDR paths are the exposure.
7. **🟡 KeyboardShortcuts 3.x** is a major bump: verify all 7 hotkeys still fire, especially
   function keys while the menu-bar menu is open (3.1.0 fixed exactly that).
8. **🟢 Community/social (K)** deliberately deferred: server, moderation, DMCA, and a cold-start
   audience problem. Ship the link layer first; social is a company, not a feature.

---

## 8. First change set — "macOS 27 Golden Gate compatibility" (status)

| Item | State |
| --- | --- |
| KeyboardShortcuts 2.4.0 → **3.1.0** in `Package.swift` (with the rationale in a comment) | ✅ done |
| `Package.resolved` re-pinned: KeyboardShortcuts 3.1.0, Defaults 9.0.9, swift-collections 1.6.0 (swift-syntax stays 603.0.0 — inside Defaults' `600.0.0..<606.0.0` range). The committed `originHash` is now stale because the manifest changed, so SwiftPM will re-resolve once and rewrite the file; that is expected and should produce exactly these pins | ✅ done |
| API compatibility verified against the 3.1.0 source: `removeHandler(for:)`, `onKeyUp(for:action:)`, `getShortcut(for:)`, `Recorder(_:name:onChange:)` and bare `Name(_:)` are all intact; the only 3.0 renames (`defaultShortcut` → `initialShortcut`, `default:` → `initial:`) are unused here, and 3.x keeps a deprecated `default:` shim anyway | ✅ done |
| README troubleshooting rewritten to name the real cause + fix; Requirements updated (Swift 6.2+/Xcode 26, macOS 27 gating note) | ✅ done |
| `docs/manual-hotkey-setup.md` demoted from "Apple bug, until Apple fixes it" to a documented fallback + bulk-scripting reference | ✅ done |
| CI: second leg on the **`xcode-27`** runner (macOS 26 host + Xcode 27 = macOS 27 SDK + Swift 6.4), `continue-on-error: true` while GitHub marks the image preview; prints `xcodebuild -version` and `xcrun --show-sdk-version` | ✅ done |
| Dropped the non-existent `com.apple.security.screen-capture` entitlement key from `Resources/ReplayCap.dev.entitlements`, with a comment explaining that capture is TCC-gated | ✅ done (same key still sits in the unreferenced `ReplayCap.sandbox.entitlements`) |
| Stale "Swift 6.1 still served by macos-latest runners" comment in `ClipLibraryView.swift` corrected | ✅ done |
| README: this tree identified as a personal fork, direct-build only, with the license position stated | ✅ done |
| `AppStore/project.yml` marked **DORMANT** (kept, not deleted) | ✅ done |
| Resolve the `-3821` magic number in `CaptureDelegate` | ⏸ blocked on an on-device lookup (§5, Phase 0.4) |
| Triage the 84 AVFoundation 27-SDK deprecation warnings (`AVAssetExportSession` ×8, `AVAssetWriter`/`Input` ×48) | ⏳ needs one real Xcode 27 build |
| `SCClipBufferingOutput` spike + `SCRecordingEditor` post-save review | ⏳ next, once the bump is confirmed to build |

**Verify on your Mac (nothing here was compiled — this workspace is Linux with no Swift toolchain):**

```bash
cd ReplayMac
swift package resolve          # expect: rewrites Package.resolved, KeyboardShortcuts 3.1.0
swift build 2>&1 | tee /tmp/build.log
swift test
./build-app.sh                 # direct build; check codesign --verify passes with the edited entitlements
```

Then the only manual check that matters: **Settings → Hotkeys** — click a recorder, press e.g. ⌥⇧S,
confirm it registers; replace an existing shortcut (the case that used to fail); press the clear
button; and confirm a function-key hotkey still fires while the menu-bar menu is open.

**Next up:** `SCClipBufferingOutput` spike (Phase 0.6) and Liquid Glass + App Intents (Phase 1) —
the two most visible "this app is native to my Mac" wins.
