# Frat Flicks — final review

## Scope
Reviewed the game controller, scoring judge, tracker bridge, Python camera service and detector, launcher and platform entry points, song carousel, rendering and hand artwork, camera preview, project configuration, chart generator, packaging tool, and regression tests. The five supplied songs, retro TAMU styling, Bob narration and Skip Intro, background music during setup, easier timing, and automatic hand recovery are retained.

## Corrections made
- Hand setup cannot complete while the app is unfocused. Returning requires a fresh stable hold.
- Losing focus during the title-to-Bob fade cannot unexpectedly start narration or background music.
- A tracker session restart now clears obsolete commands and pauses for clean hand reacquisition, even if the restart happens before the heartbeat timeout.
- Heartbeat age is included when judging whether hand data is fresh; old packets no longer keep the game running with stale hands.
- Keyboard launch mode is respected by Enter on the title. Hand setup now offers a direct Use Keyboard fallback, replacing a redundant Continue button that automatic setup made effectively unusable.
- Keyboard countdown instructions show A/L controls instead of asking for visible hands.
- Invalid/non-finite saved values fall back to safe defaults. Song selection is saved when changed; settings writes use a temporary file followed by a rename.
- Invalid landmark coordinates and confidence values are rejected before tracking math or drawing.
- Windows launcher discovers Python 3.11/3.12 through the `py` launcher, and includes a dedicated `Start_Keyboard.bat`.
- Oversized starting windows fit the monitor’s usable area while preserving 16:9. Fullscreen remains available with F11.
- Audio shutdown is given a short drain period; duplicate quit requests are ignored. The preview carousel correctly labels the previous track.
- Volume is labeled Master volume because it controls speech, effects and music.

## Validation
All listed checks passed in this environment:

| Area | Result |
| --- | --- |
| Core scoring and interface | 2,872 checks |
| Five complete chart validations | 2,250 checks |
| New release edge cases | 15 checks |
| Background music and hand setup | 80 checks |
| Bob narration | 38 checks |
| Intro flow | 49 checks |
| Carousel and actual MP3 endings | 32 checks |
| Tracking loss and recovery | 78 checks |
| Miss sound, countdown and retry | 39 checks |
| Hand artwork and scene animation | 17 checks |
| Skip Intro mouse clicks | 51 checks |
| Python integration | 21 tests |
| Standalone detector geometry/state | 11 tests |
| Real loopback UDP sidecar protocol | Passed |
| Removed-track fallback and file removal | Passed |

All five full songs completed through their real MP3 decoders and the production game loop at 4× test playback speed: sweet rally 61 hits, Paradise 81, Make U Whole 22, Eatin’ Good 203, Free Your Mind 185; zero misses and a win for every run. A real no-input run reached the loss screen on the ninth miss. Accelerated playback is only in the test script; normal play remains 1×.

Production countdown timing was checked against the actual audio playback clock: 2 appeared at approximately 1.007 s, 1 at 2.004 s, gameplay at 3.001 s. This test uses dummy output and records the mix; it does not measure a physical speaker’s latency.

Title, Bob dialogue, instructions, calibration, countdown, gameplay, pause, results and settings were rendered in native Godot for visual inspection. Tests cover the source-project ZIP’s direct Godot extraction. Window fitting and graceful quit were exercised on a simulated 1366×768 display.

## Limits
This is a tested source-project release, not a guarantee of zero possible bugs. No physical webcam, Windows desktop or macOS desktop was available here. Camera recognition across different lighting, skin tones, hand poses and hardware, actual speaker latency, and platform permission prompts require a device check. Python discovery is unit-tested; native Windows/macOS launch behavior is not claimed as physically tested. The game requires Godot 4.5+ Standard; camera mode needs Python 3.11/3.12 and the pinned packages. Keyboard mode does not require camera packages.


## Final motion and balance revision
The wave path now extrapolates continuously through the target instead of clamping there. The scoring window was tuned from ±450 to ±300 ms, with unchanged Perfect timing and a 2.4-second approach. Off-target flicks cost 3% vibe, reset streaks, and reduce accuracy; duplicates within 180 ms per hand are ignored.

70 new motion/balance checks passed. Every chart can still be completed with each intended flick 220 ms late; blind rapid input loses rather than clearing songs. The core suite (2,872), chart suite (2,250), carousel (32), audio/retry (39) and recovery (78) passed with the new tuning. Earlier full-decoder playthroughs above were performed before this final scoring adjustment; the updated scoring is validated on every chart directly.
