# ReplayMac → "Medal for macOS" — Research & Plan

_Written 2026-09-19 against ReplayMac 1.7.1 (commit `f3df077`). Target machine: macOS 27 "Golden Gate" (released 2026-09-14; 27.2 beta 1 seeded 2026-09-16)._

Goal: everything Medal does on desktop, **truly free** (no accounts, no servers, no premium tier, no ads, no telemetry), **macOS only**, with a UI that feels like a modern native gaming app rather than a utility.

---

## 1. Where the repo stands today

ReplayMac is already a serious instant-replay clipper (~16.9k lines of Swift 6, strict concurrency, SwiftPM, 204 unit tests). Module layout:

| Module | Role |
|---|---|
| `Capture` | ScreenCaptureKit streams, display identity/priorities, dual display compositing, HDR, game classifier |
| `Encode` | VideoToolbox HEVC/H.264, AAC |
| `RingBuffer` | Memory-capped video/audio ring buffers |
| `Save` | Clip saver, passthrough remux, audio mixing, long-buffer (disk) recorder, filename templates |
| `Audio` | System audio, per-app audio, mic (`AVAudioEngine` with rebuild/watchdog), level meters |
| `Hotkeys` | `KeyboardShortcuts` wrapper |
| `Feedback` | Notifications, sound cues |
| `UI` | Settings (6 tabs), Clip Library (table), Onboarding, Menu bar badge, Theme |
| `App` | `AppDelegate` split into extensions (pipeline, saving, session, game auto-record, runtime settings) |

What it already covers from Medal's list: instant replay (15 s–300 s + 5/10/30 min extended), session recording, auto-record on game launch, 4K/HDR/high fps, HEVC/H.264, system + mic audio (merged or separate tracks), per-app audio, quality presets, capture profiles, hotkeys, library with search/tags/favorites/notes, trim + crop + GIF export, share sheet, storage cleanup, notifications, launch at login, update check.

**Hard constraints discovered**

1. **License.** `LICENSE.md` is "free, source-available": personal use and modification are fine, PRs to the official repo are fine, but *redistributing modified builds, renamed forks, or publishing it as a separate product is not allowed without written permission*. This fork (`xapqrt/ReplayMac`) can legally be a personal build or a stream of upstream PRs — it cannot be shipped as "our Medal" without the author's permission. This must be decided up front (see §7).
2. **This sandbox is Linux with no Swift toolchain.** Nothing can be compiled here. Verification happens (a) on your Mac via `./scripts/install-dev.sh`, and/or (b) on GitHub Actions (`macos-latest`) — Actions are currently **not enabled on the fork**; enabling them gives us a free macOS build+test loop for every push.
3. Upstream keeps a **macOS 15 deployment target** and a universal (arm64 + x86_64) binary. Everything new for macOS 26/27 has to sit behind `#available` gates unless we deliberately raise the floor.

---

## 2. Medal — full desktop feature inventory vs. ReplayMac

Sources: medal.tv/features, Medal's "Getting to Know Medal's Settings" support article, Medal Premium FAQ, Medal's own "Medal vs ClipMac" comparison page.

Legend: ✅ have · 🟡 partial · ❌ missing · 🚫 cloud/social (replaced with a free, local equivalent — see §5)

### Capture
| Medal | ReplayMac 1.7.1 | Notes |
|---|---|---|
| Instant replay 15 s → 10 min, hotkey (F8) | ✅ 15–300 s + 5/10/30 min extended | Extended buffer is disk-backed; fine |
| Multiple clip hotkeys with different lengths (15 s–5 m or custom) | 🟡 fixed set: save, last 15 s, last 60 s, extended | Need a user-defined list of (length → hotkey) |
| Long/session recording start–stop hotkey | ✅ | |
| **Bookmarks** (hotkey drops a marker in a long recording) | ❌ | Store timestamps in sidecar metadata, show as markers on the trim timeline |
| Auto-record entire game session | ✅ (game auto-record) | |
| **Screenshots** hotkey | ❌ | `SCScreenshotManager` — cheap |
| Game switch hotkey | n/a | macOS has no per-game capture; we capture displays |
| **Voice clipping** ("Medal, clip that!") | ❌ | On-device: `SpeechAnalyzer` (macOS 26+) with `SFSpeechRecognizer` on-device fallback for 15 |
| Game detection + manual game list | ✅ App Store category + bundle-ID list + exclusions | |
| Quality presets Low/Standard/High/Custom; up to 4K, 24–144 fps, 3–100 Mbps | ✅ Performance/Quality/Ultra/Custom; 4K; fps; bitrate | fps ceiling should follow display refresh (120 Hz ProMotion) |
| Encoder GPU/CPU, codec H.264/H.265/AV1 | 🟡 HEVC/H.264 via VideoToolbox | AV1 hardware *encode* isn't exposed on Apple Silicon (decode only on M3+) — skip |
| **Webcam overlay** (camera toggle, device picker, preview) | ❌ | `AVCaptureDevice` → composite in `FrameCompositor` |
| Keyboard overlay | ❌ | Low priority |
| All-PC audio vs specific apps with **per-app volume** | 🟡 all / one app | Add multi-app selection + per-track volume |
| **Multi-track: game / mic / Discord separate** | 🟡 system + mic separate | Add a third "voice chat" track (Discord/TeamSpeak/FaceTime/Slack picked from running apps) |
| Mic test, **noise suppression**, **push-to-talk**, **mono input** | 🟡 meters only | `AVAudioEngine` voice-processing I/O gives noise suppression + echo cancel; PTT = gate mic on a hotkey |
| Monitor selection, record on app start, switch to game on launch | ✅ display priorities, auto-start, game auto-record | |
| **Per-game custom settings** (mode, hotkeys, quality, audio) | 🟡 profiles exist but are manual | Bind a profile to a game bundle ID and auto-apply on launch |
| **Auto clipping** (kills/wins in supported games, configurable length) | ❌ | No game SDK exists on Mac; see §4 Phase 5 for what's realistically possible |
| Simple in-game overlay (recording status, "clip saved") | ❌ | Non-activating floating `NSPanel` at screen-saver level, all spaces; shows over most fullscreen games |
| Lightweight (100–400 MB RAM) | ✅ configurable memory cap | |

### Library & storage
| Medal | ReplayMac 1.7.1 | Notes |
|---|---|---|
| **Card grid** with thumbnails, duration badge, game icon, title, size/date | ❌ table view | Core of the UI rewrite |
| Filter by game, date, tags, people, folders | 🟡 search/tags/favorites | Need "game" (source app) stored per clip + folder/collection concept |
| Sort options | ✅ date/name/duration/size | |
| Import clips; sync external recorder folders (OBS etc.) | ❌ | Watch folders → appear in library |
| Storage limit (1 GB…500 GB / custom) with "only delete full-length recordings" | 🟡 manual cleanup by age/bulk | Add background auto-enforcement policy |
| Capture folder location + drive info | ✅ | |
| Recycle bin on delete | ✅ (Trash) | |
| Titles / rename | ✅ | |

### Editor
| Medal | ReplayMac 1.7.1 | Notes |
|---|---|---|
| Trim | ✅ passthrough (no re-encode) | |
| **Export at other resolutions/bitrates with file-size estimate** | ❌ | Requested today in upstream issue #12 |
| Text overlays / captions | ❌ | `AVVideoCompositionCoreAnimationTool` (text) + `SpeechAnalyzer` (auto-captions) |
| Slow-mo / speed | ❌ | `AVMutableComposition.scaleTimeRange` |
| Zoom / pan | ❌ | Keyframed `AVVideoComposition` transform |
| Music / SFX / memes / GIF stickers | ❌ | Extra audio track + image layers; ship user-provided files, no built-in licensed library |
| Multi-track audio mixing (per-track volume/mute) | 🟡 solo for playback only | Per-track gain at export |
| Crop / vertical 9:16 for TikTok/Shorts | ✅ crop + presets | Add "vertical reframe" template (game + cam stacked) |
| GIF export | ✅ | |
| Combine multiple clips (montage) | ❌ | Phase 3b — simple sequential timeline |

### Sharing / cloud / social (🚫 — replaced, never cloned)
| Medal | Free local equivalent |
|---|---|
| Auto-upload to Medal cloud, instant share links, 14-day links, Premium permanent links | **Discord-target export** (auto-fit under the 20 MB free limit — Discord raised it from 10 → 20 MB on 2026-09-08; 50 MB Nitro Basic, 500 MB Nitro) + optional **Discord webhook post** (user pastes their own webhook), AirDrop, share sheet, copy-file, drag-and-drop, iCloud Drive/Files share links via the system share sheet |
| Social feed, follows, "clips you're in", quests, ads, Premium badges | Not doing. No accounts, no server, ever |
| Mobile app + cross-device sync | iCloud Drive as output folder = clips appear on iPhone Files app; no app of our own |
| Author watermark on free downloads | Never |

---

## 3. macOS 27 "Golden Gate" — what it means for this repo

Verified against Apple's macOS 27 release notes, the Xcode 27 release notes, MacRumors/9to5Mac coverage, and the affected open-source projects.

### 3.1 Must-fix now
1. **Hotkey recorder is broken on macOS 26/27 with our pinned `KeyboardShortcuts 2.4.0`.** Root causes (documented in sindresorhus/KeyboardShortcuts#241): the local event monitor token was held weakly and deallocated, and toggling `showsCancelButton` ended the editing session microseconds after arming. Fixed upstream in **3.1.0 (released 2026-09-11, "Improve macOS 27 compatibility")**. Our `Package.swift` says `from: "2.2.0"`, which can never resolve to 3.x. Fix = bump to `from: "3.1.0"`. Source impact is nil for us (3.0 only renamed `default:` → `initial:` on `Name`, which we never pass). This retires `docs/manual-hotkey-setup.md` as a workaround (keep it as a reference).
2. **Menu item images are hidden when linked against the macOS 27 SDK** (both symbol and non-symbol, AppKit *and* SwiftUI). We have one affected item (`arrow.down.circle.fill` on the update item) — harmless — but every icon in the new UI's menus/context menus needs `preferredImageVisibility` / `.labelStyle(.titleAndIcon)` where the icon carries meaning.

### 3.2 Design language changes we should follow (the "good UI" brief)
- Liquid Glass got an opacity slider and better diffusion; **uniform toolbars**, **edge-to-edge (non-floating) sidebars**, **fixed corner radii** (macOS 26's content-dependent radii were reverted), Liquid-Glass traffic lights, consistent window placement across displays.
- New SwiftUI on 27: `TabsPickerStyle` (segmented look that VoiceOver reads as tabs — our library's Date/Name/Duration/Size and settings pickers), `TextInputBorderShape` + `.bordered` text field style (`.roundedBorder` soft-deprecated — we use it 7×), `Slider` no longer backed by `NSSlider`, bordered `Menu`/`Picker` no longer `NSPopUpButton`, `AsyncImage` caching, `NSRefreshController` (pull-to-refresh) in AppKit.
- Available since macOS 26 and unused by us today: `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)` (hover state outside toolbars was fixed in 27). All gated with `if #available(macOS 26, *)`.
- `@State` is now a macro in Xcode 27 (back-deploys): don't assign `@State` in `init` when a default is also declared. Audited: **no occurrences** in our code. `PreviewProvider` deprecated: **none used**.

### 3.3 Platform signals that shape the roadmap
- **On-device AI stack is now solid:** `SpeechAnalyzer`/`SpeechTranscriber`/`SpeechDetector` (26+, offline after a one-time model download), Foundation Models (26+, fixed tool-calling bugs in 27), Vision text recognition. These power voice clipping, auto-captions, auto-titles and "hype" detection with zero servers.
- **Intel is ending:** macOS 27 flags Intel apps that won't run on macOS 28. Keep the universal build for now, design arm64-first (Neural Engine features can be Apple-silicon-only).
- **Built-in Screen Recording now captures system audio** — Apple's own tool got closer; our edge is the buffer, the library and the editor.
- **TCC database can no longer be read directly** — irrelevant to us (`tccutil reset` in `scripts/install-dev.sh` is the supported CLI and still works).
- **Background App Monitoring** marks background apps in the Dock — verify how our accessory-policy menu bar app is presented on 27.
- `NSApplication.presentationOptions.disableScreenCornerInteractions` — nice-to-have for an in-game overlay (disable hot corners while recording a game).

---

## 4. The plan (phased, each phase ships on its own)

### Phase 0 — macOS 27 hardening + foundations (small, first)
- Bump `KeyboardShortcuts` to 3.1.0; update `Package.resolved`; re-test hotkey recording on 27.
- Menu-item image visibility audit (`preferredImageVisibility`).
- Availability helper (`if #available(macOS 26, *)`) + `AppTheme` v2 (dark-first palette, glass on 26+, plain materials on 15).
- Per-clip **sidecar metadata v2**: source app bundle ID + name + icon cache, capture kind (replay / session / screenshot / auto), bookmarks, trigger (hotkey / voice / auto), resolution/fps/codec. Migrates the existing `.ReplayCapClipLibrary.json`.
- Enable GitHub Actions on the fork; add `swift build` + `swift test` on every push to this branch.

### Phase 1 — The new UI shell (Medal layout, native macOS)
- **Main window** (`NavigationSplitView`): edge-to-edge sidebar — Library, Sessions, Screenshots, Favorites, Games (auto-grouped by source app), Collections/Tags, Trash; footer with storage ring (used / limit) and Settings.
- **Top status strip** like Medal's: recording state pill (● Buffering 30 s · display name), hotkey pill (e.g. `F8 · Clip 30s ▾` with quick length switch), quality pill (`1440p 60fps ▾` = quality preset switcher), mic/system audio indicators, Start/Stop.
- **Card grid**: 16:9 thumbnails with hover-scrub (frame strip), duration badge, game icon + name, title, size · date, quick actions (Play, Trim, Share, Export for Discord), multi-select, keyboard navigation, context menus, drag-out to Finder/Discord.
- **Detail/editor pane** (right side or sheet): player, per-track audio toggles, title/tags/notes, bookmarks list, timeline with markers.
- Filters bar: game, date range, tags, kind, duration; sort; search.
- Settings redesigned as a sidebar-based window (Recording · Clips & Hotkeys · Quality · Audio · Overlays · Games · Storage · Advanced), same content, better grouping; segmented → `.tabs` on 27.
- Onboarding refresh (permissions, hotkey, storage folder, quick test clip).
- Menu bar stays (it's the lightweight path), gains "Open ReplayMac" and a live mini-status.

### Phase 2 — Capture parity
- Custom list of clip-length hotkeys (Medal's 15 s–5 m + custom).
- Screenshot hotkey (`SCScreenshotManager`, PNG/HEIC, shows in library under Screenshots).
- Bookmarks hotkey during session/extended recording; markers on the trim timeline; "save clip around bookmark".
- Webcam overlay (device picker, position/size/shape, preview in Settings, burned into capture or kept as a separate track — start with burned-in).
- Third audio track for voice chat (pick Discord/other running app); per-track volume; multi-app selection.
- Mic: noise suppression + echo cancel (voice-processing I/O), push-to-talk hotkey, mono input, mic test.
- Per-game profiles: attach a capture profile to a game bundle ID; auto-apply on launch, restore on quit.
- Storage limit auto-enforcement (1 GB…500 GB / custom, "only delete full-length recordings", never delete favorites).
- Watch folders / import (OBS, QuickTime, console captures) → library.
- In-game overlay toasts ("Clip saved", "Bookmark added", "Recording started") as a non-activating panel; optional persistent mini HUD.

### Phase 3 — Editor
- **Export panel**: resolution (source/1440p/1080p/720p), fps, codec, bitrate, **live file-size estimate**, and **target presets: Discord Free ≤ 20 MB, Nitro Basic ≤ 50 MB, Nitro ≤ 500 MB, custom MB** → two-pass bitrate solve to hit the size (this closes upstream issue #12).
- Speed ramps / slow-mo, zoom/pan keyframes, text overlays with presets, stickers/images, extra music/SFX track with ducking, per-track gain/mute at export.
- Auto-captions via `SpeechAnalyzer` (26+) with styled caption presets; burned-in or sidecar `.srt`.
- Vertical reframe template (9:16 with game + cam stacked) for TikTok/Shorts.
- Montage: sequence multiple clips into one export.

### Phase 4 — Free sharing (no accounts)
- "Export for Discord" one-click (uses Phase 3 sizing) → copies file to clipboard + reveals.
- Optional Discord webhook posting (user supplies webhook URL; stored in Keychain).
- AirDrop / share sheet / iCloud Drive as output folder documented as the cross-device path.

### Phase 5 — Auto-clipping, the Mac way (no game SDK exists)
1. **Voice clip**: always-on, on-device keyword spotting for a configurable phrase ("clip that" / "ReplayMac clip that"); `SpeechAnalyzer` + `SpeechDetector` on 26+, `SFSpeechRecognizer(requiresOnDeviceRecognition: true)` fallback on 15; mic-only, never leaves the machine; visible indicator while listening.
2. **Hype detection**: mic loudness/laughter/scream spikes (energy + on-device sound classification via `SNClassifySoundRequest`) → suggest/auto-save with a "why" tag; adjustable sensitivity.
3. **On-screen event detection**: Vision text recognition on a downscaled frame at ~2 fps against per-game JSON rule packs (e.g. Valorant "ACE"/"CLUTCH", Rocket League "GOAL"/"MVP", Fortnite "VICTORY ROYALE", Minecraft death screen). Opt-in, per-game, community-editable rule files, thumbnails of what triggered.
4. Never auto-clip without showing what triggered it; every auto-clip is tagged and reviewable in an "Auto" smart folder.

### Phase 6 — Polish
- App Intents / Shortcuts / Siri: "Save clip", "Start session", "Take screenshot" (also enables Stream Deck-style automation).
- Spotlight indexing of clips (title, game, tags).
- Per-game stats page (clips, hours recorded).
- Localizations, accessibility pass, Sparkle-free updater stays as is.

---

## 5. What we deliberately will not build
Cloud storage, share-link hosting, social feed, accounts, ads, premium tiers, watermarks, telemetry, a mobile app. Each has a free local substitute listed in §2.

---

## 6. How we'll work given the constraints
- Small, reviewable PRs per feature on `arena/01a0b90a-replaymac`; each phase independently shippable.
- Since this sandbox can't compile Swift: you build locally (`./scripts/install-dev.sh`) or we rely on GitHub Actions on the fork; paste compiler output back and we iterate. I'll keep Swift 6 strict-concurrency discipline and write unit tests alongside logic (metadata store v2, size estimator, rule-pack matcher, hotkey-length list, storage policy).
- UI work is verified with your screenshots on macOS 27.

---

## 7. Decisions needed before coding
1. **License / intent** — personal fork + upstream PRs (allowed as-is), or ask the author (Alex / picccassso) for written permission to publish a rebranded build? This decides naming, icon, and whether the new UI can diverge freely from upstream.
2. **Minimum macOS** — stay on 15 (upstream-compatible, everything 26+ behind `#available`) or raise to 26 (much simpler Liquid Glass + SpeechAnalyzer code; drops older Macs).
3. **UI direction** — full main window (Medal-style, recommended) while keeping the menu bar as the lightweight path.
4. **Order** — Phase 0 → 1 (UI shell) first, then 2/3 in parallel, or features (2/3) before the UI?
5. **Always-on mic for voice clipping** — acceptable as an opt-in default-off feature with a visible listening indicator?

---

## 8. Progress log (branch `arena/01a0b90a-replaymac`)

Decisions taken (2026-09-19): personal build for one M4 MacBook Air on macOS 27 → target macOS 26+, Apple silicon only; fundamentals first, UI (Phase 1) afterwards; CI on the fork.

| Commit | What | Status |
|---|---|---|
| `a835c8f` | macOS 26+/arm64 target, KeyboardShortcuts 3.1.0 (macOS 26/27 recorder fix), `HotkeyManager` main-actor rewrite, CI on `xcode-27` + `macos-26`, `.app` artifact | ⏳ unverified — GitHub refused to start jobs ("account locked due to a billing issue") |
| `0ddb357` | **Metadata v2**: per-clip capture record (kind, trigger, source app, time, requested length) + bookmarks list; locked read-modify-write store, library merges instead of overwriting; Source column; tests | ⏳ unverified |
| `47bb8d6` | **Quick-preset hotkeys** with configurable lengths (5 s – 5 min) + third preset; tests | ⏳ unverified |
| `ef14463` | **Bookmarks**: hotkey + menu item, ledger with debounce, attached to replays/sessions on save, jump chips in preview; tests | ⏳ unverified |
| `2e62dfc` | **Storage limit**: cap output folder, oldest-first to Trash, favorites protected, "only full-length recordings" mode; tests | ⏳ unverified |
| `206683a` | **Screenshot** hotkey + menu item (SCScreenshotManager, native pixels, `<output>/Screenshots`) | ⏳ unverified |
| `adeb45c` | **Size-targeted export** (20/50/100/500 MB) with live estimate, planner + AVAssetReader/Writer H.264 transcode, progress/cancel; tests | ⏳ unverified |

### Verifying locally (until Actions is unlocked)
```sh
git fetch origin && git checkout arena/01a0b90a-replaymac
swift build 2>&1 | tail -40          # Xcode 26.2+ or 27
swift test 2>&1 | tail -40
./build-app.sh && open dist/ReplayMac.app
```
Paste any compiler output back into the session; nothing in this branch has been compiled yet (the sandbox has no Swift toolchain).

### Next fundamentals (in order)
1. Voice clipping ("clip that") via `SpeechAnalyzer` (macOS 26+), opt-in with a listening indicator.
2. Webcam overlay (AVCaptureDevice → composited corner PiP) and per-track mic processing (noise suppression / PTT / mono).
3. Per-game auto profiles (bind a capture profile to bundle IDs; switch on game launch).
4. Watch folders / import (`imported` capture kind) and the library's Screenshots tab.
5. Discord webhook / share-sheet targets for the sized export.
Then Phase 1: the Medal-style main window (card grid, sidebar, per-game groups from the new metadata).
