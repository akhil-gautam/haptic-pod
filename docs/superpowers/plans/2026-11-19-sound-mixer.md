# Sound Mixer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 24 built-in ambient sounds (19 CC0 recordings, 5 generated) that layer in a wheel-driven
mixer with per-sound levels and a sleep timer.

**Architecture:**
- An offline bash/ffmpeg script turns the Freesound previews into seamless, loudness-matched
  `.m4a` loops that are committed as bundle resources.
- `SoundMixer` runs its own `AVAudioEngine`, with one node per active sound:
  - a looping `AVAudioPlayerNode` for recordings,
  - a re-struck player for bells,
  - an `AVAudioSourceNode` for generators.
- `SleepTimer` fades and pauses both the music and the mix.
- `PlayerService` keeps a last-started `owner` that routes the lock-screen controls.
- A new `Screen.sounds` list is driven by `Navigator`, with an adjust mode for the wheel.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, xcodegen, bash and ffmpeg (offline asset prep).

**Spec:** `docs/superpowers/specs/2026-11-19-sound-mixer-design.md`

## Global Constraints

- Every bundled file is CC0, confirmed on its own Freesound page, and listed in
  `HapticPod/Resources/Sounds/CREDITS.md`.
- Loops: 50 s, or 75 s for FOREST BIRDS. Strikes: the full ring-out, up to 20 s.
- Audio: AAC-LC 128 kbps, 44.1 kHz stereo, about −24 LUFS. Bundled total about 17 MB, never
  more than 30 MB.
- At most 6 active sounds. The 7th is refused with `.thud` and "MAX 6".
- A sound turned on starts at level 0.5. The wheel steps by 1/32. Fade-in 1.5 s, fade-out 1 s.
  Adjust mode exits after 4 s idle.
- Sleep timer cycles OFF/15/30/45/60/90 minutes and fades over the last 30 s.
- `UserDefaults` key `soundMix` stores `[soundID: level]`. The mix is restored paused and never
  auto-plays.
- No test target exists. Verification is by script checks, `xcodebuild`, and on-device runs with
  `-screen sounds`.

## Review Focus

- **Engine configuration change** (AirPods connect or disconnect) while the mix plays: every
  active channel resumes. A silent engine is wrong.
- **Turning a sound on while its buffer is still decoding, then off again:** no orphan node
  playing and no crash. Task 3 guards this with a per-sound generation token.
- **Music started while the mix plays, with the session in `.mixWithOthers`:** the music session
  switch must not stop the mix engine. Task 3 restarts the engine if the switch stopped it.
- **Lock-screen Play after a "pause both":** both resume, not just the music.
- **Sleep timer fires while the app is backgrounded and the screen is locked:** both fade out and
  pause, and their levels come back for next time.

---

### Task 1: Asset pipeline and bundled sounds

**Files:**
- Create: `scripts/prepare-sounds.sh`, `scripts/sounds.tsv` (id, Freesound id, HQ preview URL,
  kind, title, author).
- Create: `HapticPod/Resources/Sounds/*.m4a` (19 files), `HapticPod/Resources/Sounds/CREDITS.md`.
- Modify: `project.yml`, to add `HapticPod/Resources/Sounds` as a folder resource.

**Produces:** the bundle path `Sounds/<id>.m4a`. The ids are `lightRain`, `heavyRain`,
`rainWindow`, `thunder`, `ocean`, `stream`, `waterfall`, `birds`, `windTrees`, `field`,
`crickets`, `frogs`, `nightForest`, `campfire`, `bowl`, `chimes`, `gong`, `fountain` and `cabin`.

- [ ] **Step 1:** Write the script.
  - Download into `$SCRATCH/raw` (skip a file if it already exists).
  - Scan with `ebur128`/`astats` per 1 s window, then pick the 50 s (75 s) window with the lowest
    loudness variance whose peak is no more than 12 dB above the clip median.
  - Loops: cut the window plus 3 s, then crossfade the extra 3 s onto the head (`acrossfade`
    tail→head), producing exactly 50 s.
  - Strikes: from the onset to min(ring-out, 20 s), with a 2 s fade at the tail.
  - Run `loudnorm` to I=−24, then encode `aac -b:a 128k -ar 44100 -ac 2`.
  - Write CREDITS.md from the tsv.
- [ ] **Step 2:** Run the script.
  - Expected: 19 files, a total size of 30 MB or less, and no window flagged.
  - If a window is flagged, switch to the backup id after checking its page for CC0.
- [ ] **Step 3:** Seam check.
  - For each loop, decode the last 20 ms and the first 20 ms.
  - Expected: the RMS difference is under 3 dB and the sample jump at the wrap is under 0.05.
- [ ] **Step 4:** Run `xcodegen generate` and build. Confirm the `.app` contains `Sounds/*.m4a`.
- [ ] **Step 5:** Commit.

### Task 2: Catalogue and generators

**Files:**
- Create: `HapticPod/Sounds/SoundCatalog.swift`, `HapticPod/Sounds/Generators.swift`.

**Produces:**
- `struct AmbientSound: Identifiable, Sendable { id: String; title: String; group: String; kind: Kind }`
- `enum Kind { case loop(String), struck(String, every: ClosedRange<Double>), generated(Generator) }`
- `enum Generator: Sendable { case white, pink, brown, drone, theta }`
- `static let all: [AmbientSound]`, holding 24 sounds in spec catalogue order.
- `func makeRenderer(_ g: Generator, sampleRate: Double) -> @Sendable (UnsafeMutableAudioBufferListPointer, AVAudioFrameCount) -> Void`
  - The renderer writes stereo float and owns its state.
  - pink: Paul Kellet's filter.
  - brown: leaky integrator, `b = (b + 0.02·w) / 1.02`, scaled ×3.5.
  - drone: sines at 55, 110 and 165 Hz, detuned by ±0.3 Hz, with a 0.05 Hz swell.
  - theta: 200 Hz left and 206 Hz right, plus pink noise at 0.15.
- Struck intervals: SINGING BOWL 18…40 s, TEMPLE GONG 25…55 s.

- [ ] **Step 1:** Implement and build.
- [ ] **Step 2:** Confirm `all.count == 24` and that every `.loop` or `.struck` file exists in the
  bundle, with a `DEBUG` `assert` at mixer init.
- [ ] **Step 3:** Commit.

### Task 3: SoundMixer engine

**Files:**
- Create: `HapticPod/Sounds/SoundMixer.swift`.

**Consumes:** Task 2.

**Produces:**
- `@MainActor @Observable final class SoundMixer`, with:
  - `levels: [String: Float]` (active sounds only)
  - `isPlaying: Bool`
  - `var activeTitles: [String]`
  - `static let maxActive = 6`
- `func toggle(_ id: String) -> ToggleResult`, where `enum ToggleResult { on, refused }` (turning
  off happens through `setLevel(0)`).
- `func setLevel(_ id: String, _ level: Float)`: 0 removes the sound.
- `func play()`, `func pause()`, `func clear()`.
- `func fade(to gain: Float, over seconds: Double) async`: master gain for the sleep timer.
- `var onStateChange: (() -> Void)?`: lets the player refresh Now Playing.

Implementation notes:
- **Channels:** each channel has its own `AVAudioMixerNode` gain. Levels are ramped in 10 ms steps
  over 50 ms by a main-actor task.
- **Decoding:** a `Task.detached` reads `AVAudioFile` into an `AVAudioPCMBuffer`. Results carry a
  per-sound generation token, and stale ones are dropped.
- **Struck sounds:** a main-actor task sleeps a random interval and calls `scheduleBuffer`.
- **Session:**
  - If `isOtherAudioPlaying` and our music isn't playing, use `.mixWithOthers`.
  - Otherwise use `.playback` with no options.
- **Observers:**
  - Interruption: pause, and resume on `shouldResume`.
  - Route change `oldDeviceUnavailable`: pause.
  - `.AVAudioEngineConfigurationChange` on its engine: restart and reschedule everything active.
  - After the music switches the session category (Review Focus), restart if the engine stopped.
- **Persistence:** save `levels` to `soundMix` on change, and load it at init, paused.

- [ ] **Step 1:** Implement and build.
- [ ] **Step 2:** On device, with a temporary `-mixTest` launch arg that turns on rain and pink
  noise and plays them: rain and noise are heard, and the loop wraps at 50 s with no click.
  Remove the arg afterwards.
- [ ] **Step 3:** Commit.

### Task 4: Owner routing and sleep timer

**Files:**
- Modify: `HapticPod/Playback/PlayerService.swift` (handle, updateNowPlaying, owner, fade).
- Create: `HapticPod/Sounds/SleepTimer.swift`.
- Modify: `HapticPod/App/HapticPodApp.swift`, to create the mixer and timer, wire them up, and
  inject the environment.

**Produces:**
- In `PlayerService`:
  - `enum Owner { case music, mix }`
  - `@ObservationIgnored var owner: Owner`, set to `.music` in `play(queue:)` and `resume()`
  - `weak var mixer: SoundMixer?`
  - `func refreshNowPlaying()`
  - `func fadeOut(over: Double) async`, which ramps the main mixer output to 0, pauses, then
    restores it to 1
- `SoundMixer.play()` sets `player.owner = .mix`.
- Remote routing:
  - `.pause` pauses everything playing and remembers that set.
  - `.play` resumes the remembered set, or the owner if there is none.
  - `.toggle` pauses everything if anything plays, otherwise plays.
  - next, previous and seek act only when the owner is music.
- With owner `.mix`, the info is title "Sounds" with the subtitle being the active titles joined
  by " · ", and next/previous `isEnabled = false`.
- `@MainActor @Observable final class SleepTimer`:
  - `minutes: Int?` and `remaining: TimeInterval?`
  - `func cycle()` (OFF→15→30→45→60→90→OFF)
  - It ticks every 1 s. At 30 s left it fades both, then pauses.

- [ ] **Step 1:** Implement and build.
- [ ] **Step 2:** On device:
  - Lock-screen pause while the mix plays shows "Sounds", and Play resumes the mix.
  - With music and the mix both playing, Pause stops both and Play resumes both.
- [ ] **Step 3:** Commit.

### Task 5: SOUNDS screen and wheel

**Files:**
- Modify:
  - `HapticPod/Models/Screen.swift`: add `Screen.sounds`, `MenuItem.sounds` ("SOUNDS", after
    shuffleSongs), and `ListContent.sounds(Int)` (a count of 3 control rows plus 24).
  - `HapticPod/Navigation/Navigator.swift`: add `adjusting: String?`, select, wheel, and back,
    plus `-screen sounds`.
  - `HapticPod/Views/WheelView.swift`: in adjust mode, tick per step and play `.home` at 100%.
    The bottom zone toggles the mix on SOUNDS, or when no song is loaded.
  - `HapticPod/Views/DisplayView.swift`.
- Create: `HapticPod/Sounds/SoundsView.swift`.

**Consumes:** `SoundMixer` and `SleepTimer` from Tasks 3 and 4.

Behaviour (from the spec):
- Row 0: PLAY MIX / PAUSE MIX, with the value "n ON".
- Row 1: SLEEP TIMER, with the value "OFF", "30 MIN" or the remaining "mm:ss".
- Row 2: CLEAR MIX.
- Rows 3 and up are the sounds. A sound that's on shows a 36 pt level bar on the right.
- The header shows `SOUNDS · <GROUP>` of the selected row.
- Centre press: on an off sound, `toggle`, and start the mix if it's paused. On an on sound, enter
  adjust.
- While adjusting:
  - The wheel calls `setLevel(id, level + delta/32)`. Reaching 0 turns the sound off and exits
    adjust.
  - Centre press, MENU, or 4 s idle exits adjust.
  - The row is inverted and the bar shows a percentage.
- A refused toggle plays `.thud` and shows "MAX 6" on that row for 1.2 s.

- [ ] **Step 1:** Implement and build.
- [ ] **Step 2:** Install on device. Take screenshots of `-screen sounds` with a few sounds on;
  they must show the rows, bars and header.
- [ ] **Step 3:** README "Sounds" section linking CREDITS.md. Commit.
