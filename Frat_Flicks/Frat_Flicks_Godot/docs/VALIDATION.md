# Frat Flicks validation

Validated with Godot 4.5.1 Standard.

- Core Godot suite: **1,025 checks passed** for scoring, protocol and scene flow.
- Hand-loss recovery suite: **78 checks passed**, including frozen score/song/notes, three-second resume, cancellation/retry, stale input rejection, camera recovery, focus loss and keyboard fallback.
- New intro suite: **49 checks passed**, covering Press Start, transition/input locking, all seven authored dialogue pages, typewriter reveal, Back/Next, final BEGIN! gating, instructions, the two-second baseline and its motion/loss reset, actual camera-route gameplay, intro replay, keyboard fallback and atlas looping.
- Python suite: **13 tests passed**, including synthetic hand tracking, stale-camera heartbeats and renamed launcher/profile consistency.
- Godot/Python loopback UDP integration passed for both hands, duplicate/stale events and acknowledgements.
- Native OpenGL screenshots were inspected for the title, every dialogue page, instructions, calibration, countdown, gameplay, pause, results and settings. The scenery shader compiled and rendered successfully. Updated screenshots are included.
- Source ZIP uses explicit parent-first directory entries for Godot Project Manager. ZIP integrity, extraction and a fresh source import are checked before delivery.

The game remains a source project requiring Godot and the launcher’s Python dependencies. No physical webcam is available in this environment; camera permission prompts, detection quality and real hardware frame rates require testing on the target computer. Bob’s dialogue is text with a typewriter effect, not synthesized audio.


## Current visual update
- Seventeen new visual-asset checks passed: matching left/right normal/flick assets, camera-progress and flick-event pose changes, fixed wrist registration, original handedness, render matting and TAMU maroon button contrast.
- Existing suites passed: 1,025 core checks, 78 recovery checks and 49 intro checks.
- Native OpenGL screenshots inspected for normal, both-flick and mixed hand poses, matching cyan waves, maroon title/button and updated instructions.
- Rendered frames 0.8 seconds apart were compared with song time/notes held fixed; water-region movement was verified. Shader compilation succeeded.
- SHA-256 comparisons confirmed that all four supplied PNG files are included byte-for-byte unchanged. Their black backgrounds are removed only at render time.


## Current audio/replay update
- Thirty-nine new checks passed for near-hit boundary acceptance, 90% accuracy credit, unchanged Perfect scoring, exactly-once miss sound delivery, both win/loss retry routes, title navigation, camera wait and countdown cancellation.
- A production audio-clock test used deliberately incorrect frame deltas. Onscreen 2 appeared at 1.007 audio seconds, 1 at 2.004 seconds, and the song started at 3.001 seconds. Recorded output cues were measured at 0, 1, 2 and 3 seconds.
- Existing suites passed: 1,025 core checks, 78 hand recovery checks, 49 intro checks and 17 visual-asset checks.
- Native rendered win/loss screens were inspected with the two new buttons. Existing title, intro, tutorial, setup, HUD, pause and settings layout functions were compared against the previous delivered ZIP and are unchanged.
- Both supplied MP3 files are included byte-for-byte unchanged. Timing alignment skips only leading silence at playback, not by editing the stored recording.


## Five-song carousel update
- Thirty-one new checks passed for ±350 ms boundaries, nearest-wave selection with overlapping windows, pending-note preservation, predictable ties, playlist startup, rotating vinyl, Pause/Play, Previous/Next, carousel settling and title exit/re-entry.
- Every actual MP3 decoder was sought to its ending in sequence. All five completion events advanced correctly, including last-to-first looping. Music stopped immediately on Press Start and stayed stopped throughout Bob’s intro.
- Existing checks passed: 1,025 core, 78 tracking recovery, 49 intro, 39 audio/retry and 17 asset checks (timing-boundary assertions updated for the new requested range).
- Native title renders inspected at rest, during a slide and after track change; song names, artists, cards, controls and Press Start were checked.
- SHA-256 comparisons confirmed all five supplied MP3s are included unchanged. The earlier “game sounds” ZIP contained only the already-installed identical splash effect.
- Gameplay HUD, intro, setup, tutorial, countdown, pause, results and settings construction functions match the prior delivered ZIP; only the title layout is extended.


## Final song-selection / easier-camera update
- Godot base suite: 1,025 checks passed; recovery: 78; intro: 49; artwork: 17; audio/retry: 39; jukebox: 32.
- New playable-song suite: 2,250 checks passed across all five supplied songs, validating loads, selection, duration bounds, minimum spacing, proximity to detected beats, complete exact-hit runs, retry retention and return-to-title behavior.
- Python integration suite: 18 tests passed. Standalone detector state/geometry suite: 11 passed.
- Latest uploaded ZIP matches all five included MP3s byte-for-byte.
- Native Godot rendering inspected for title, song selection, settings and gameplay; screenshots updated. Headless tests use dummy audio. MP3 completion tests run the actual decoders with end-of-stream seeking.
- Audio beat alignment is based on offline beat/onset analysis, not hand-authored timing or manual listening claims. Physical webcam accuracy and hardware latency were not measured in this environment.
- Native capture shutdown reports one resource still in use; no script/runtime errors occurred during the capture flow.


## Bob narration update
- New Bob voice suite: 38 checks passed, covering all seven decoded clips, exact script text, start-after-fade, Show Text, Next, Back, focus pause/resume, volume, actual clip completion, Begin, title exit and re-entry.
- Related regression suites rerun: intro 49, jukebox 32, audio/retry 39; all passed.
- Every MP3 decodes successfully, contains non-silent audio and stays below digital full scale. Full narration duration: 43.94 seconds.
- Voice is synthetic; no live speaker performance or subjective listening review is claimed.

## Selected-song narration background
- 84 checks passed across all seven choices: correct selected audio, quiet mix, no carousel/gameplay overlap, uninterrupted page navigation, focus pause/resume, actual decoder end looping, Begin/exit cleanup, silent countdown bed and fresh gameplay start.
- Bob narration (38), intro (49), jukebox (32) and audio/retry (39) regressions passed.
- No visual layout or wave/scoring changes.

## Hand-setup background music
Selected-song music suite expanded to 112 passing checks, including all seven songs continuing through instructions and calibration, looping during hand setup, direct/retry setup playback, countdown stop and gameplay restart. Bob voice (38), recovery (78) and audio/retry (39) regression checks passed. No GUI changes.


## Skip intro
51 checks passed, including actual mouse clicks on every dialogue page, skipping during text reveal, immediate voice stop, uninterrupted background music, transition guards, preserved song/control choices and normal countdown continuation. Intro (49) and voice (38) regression checks passed.


## Final five-song playlist
All checks passed: core scoring/UI 2,872; five song charts 2,250; selected background music 80; recovery 78; audio/retry 39; Skip Intro 51. Legacy-selection fallback and removed-file checks passed. Python suite: 18 tests passed. Native title/settings screenshots updated. Removed tracks are no longer packaged.
