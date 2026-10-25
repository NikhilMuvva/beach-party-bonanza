# Frat Flicks

A one-player webcam rhythm game set at an Aggie beach party.

## Run
Extract the entire ZIP. Windows: **Start.bat**. macOS: **Start.command**. Requires Godot 4.5+ Standard, a supported Python installation and camera permission. The launcher installs the hand-tracking dependencies on first run. You can also import `project.godot` into Godot and run the main scene.

## New opening
**PRESS START → Bob’s animated beach introduction → BEGIN! → instructions → hand setup → 3–2–1 → game.**

Bob speaks through seven dialogue pages with a typewriter effect. Click **SHOW TEXT** to reveal a page, then **NEXT** to continue. Back revisits the previous page. The final **BEGIN!** button appears after the final page is revealed. Enter/Space also advances; Left goes back. The story never advances on its own. The original 24-frame character/party animation remains visible behind the dialogue box.

The arcade title uses TAMU maroon and cream, original pixel lettering, a drifting perspective grid and subtle stars. PRESS START is maroon with cream text. Best score is your real local score, saved between sessions; autoplay demos never overwrite it.

## Camera play
One person uses both hands. Rest your elbows and hold both hands still in view for **two seconds**. Initial setup is automatic; moving or hiding a hand resets the hold. No manual calibration controls are required.

Lower index and middle fingers to arm each hand, then extend them together on the beat. Both hands control matching cyan waves in separate left/right lanes. Finger ranges adapt automatically during natural movement.

If either hand leaves the frame, the song, notes, score and streak pause. Tracking continues. Once both hands reappear for half a second, a **three-second countdown** resumes the same song. Losing a hand during the countdown resets it. Manual pause and switching away from the game require a deliberate resume.

The camera stays centered above the hit rings. Its temporary JPEG preview stays on this computer and is removed when the tracker closes. The renamed launcher/profile and Godot application use the same **Frat Flicks** user-data folder.

## Scoring
Hits within 150 ms: **+1** with full accuracy credit. Near hits between 150 and 300 ms early or late: **+1**, with **90%** accuracy credit and close-hit feedback. Perfect hits within 50 ms: **+2**, with “Perfect!” feedback. Consecutive perfect hits build the perfect streak. An ordinary hit or missed target ends that streak. Each miss costs **12% vibe**, within Bob’s stated 10–15% range; hits regenerate vibe. Zero vibe ends the round unless Practice is enabled. Survive the song to win.

## Controls
- **A / L**: left/right keyboard fallback. Choose Keyboard on the title screen to play without a webcam.
- **P / Escape**: pause. **Enter / Space**: dialogue and confirmation.
- **F11**: fullscreen. **T**: optional diagnostic camera window.
- Settings: volume, timing offsets, five supplied songs and Practice mode.

## Visuals
The stick figures, “Gig ’em” sign and extra umbrella props are removed. The retro sunset now has visible water ripples and foam movement, palm sway and ocean glints. Water distortion excludes the palm silhouettes. Gameplay notes follow the song clock and hold still during pauses; ambient scenery continues softly. UI uses a four-point grid, consistent typography and a small navy/cream/cyan/gold/maroon palette.

Default window: 1920×1080; scalable 16:9 layout. Maximum requested render rate 120 FPS and camera capture 720p/60. Actual rates depend on hardware. See `docs/VALIDATION.md` for tests and the live-camera limitation.


## Your hand artwork
All four supplied `frat_left_hand_*_position.png` and `frat_right_hand_*_position.png` files are included unchanged under `assets/art/hands`. The matching flick asset is used when that hand is raised/flicked, and the matching normal asset when lowered. Each side uses its own art without mirroring. A canvas shader removes the black backdrop at render time; a shared scale and wrist anchors keep the poses aligned. The tutorial also uses these assets.


## Audio and replay update
The supplied `countdown.mp3` plays during every initial/retry/recovery countdown. Its 25 ms leading silence is skipped; the numbers follow the audible playback clock so the cues line up at 0, 1 and 2 seconds, with the song starting at the final cue around 3 seconds. Cancelling a countdown stops its sound. The final cue may ring out over the song’s beginning.

Every missed wave plays `water_splash.mp3`, including independent simultaneous misses. A miss is handled once even when it expires while processing a flick. Sound levels follow the existing volume control.

On either results screen, **TRY AGAIN** clears the round and starts the same chart/control mode with a fresh countdown, skipping the title and Bob’s introduction. If camera hands are unavailable, it waits for hand setup. **TITLE SCREEN** separately returns to the arcade title. Enter/Space/R on results retries; Escape returns to the title. The gameplay UI is unchanged.


## Title music carousel
The maroon title now has a record-player carousel with real song/artist names, spinning vinyl, playback progress and Previous/Pause/Next controls. It advances on each track’s actual ending and loops after the fifth song. Press Start stops title music immediately, before Bob’s intro. Opening title Settings keeps playback running and uses the same volume preference.

Playlist order:
1. **sweet rally** — ilysam, Mc Ster
2. **Paradise** — dentist
3. **Make U Whole** — GEEMIX
4. **Eatin' Good** — Woodcamp
5. **Free Your Mind** — Prospa, Cloonee, Sybil

These are the five MP3s supplied for the title screen. They are also selectable as full-length gameplay songs, with their own distinct beatmaps.

To change the playlist, place MP3/OGG files under `assets/audio/title_music/`, add their `name`, `artist` and `res://` path to `assets/audio/title_playlist.json`, and let Godot import the audio. No script edits are required.

The easier timing window is now **±300 ms**. If two pending waves have overlapping windows, the nearest wave is selected; earlier unhit waves remain available until their own deadline. Perfect timing stays at ±50 ms and added grace hits keep 90% accuracy credit.


## Select a song and easier camera play
Use **PLAY NEXT** on the title to choose one of five song options. **USE PREVIEW SONG** selects the song currently on the carousel. Preview playback can keep advancing without changing your chosen game song. Press Start begins Bob’s intro and the chosen track; Try Again keeps that track.

Each uploaded song has an audio-analyzed beatmap with a different left/right phrase pattern. Target gaps are at least 0.85 seconds overall and 1.3 seconds for the same hand. Targets follow selected beats rather than every beat of fast music. Songs play in full and end in the usual win/loss flow.

Waves now approach over 2.4 seconds instead of 1.6. Flick acceptance is ±300 ms; 150–300 ms grace hits earn 90% accuracy credit. Finger recognition now accepts 74% average extension with a 55% minimum for each finger and a 40% reset threshold. These are geometric thresholds, not measured recognition accuracy. Stable, percentile-based per-finger auto-calibration rejects isolated landmark spikes instead of retaining lifetime extremes. Both fingers must still lower before another upward flick.

Charts were generated from each MP3’s detected beats and nearby percussive onsets, with full-chart scoring and spacing validation. Timing can vary with your audio/camera hardware; the existing camera-delay and audio-offset controls remain available. Live webcam recognition must still be checked on your laptop.


## Bob’s spoken introduction
Bob now speaks each of the seven dialogue pages using an included synthetic male voice. Narration starts after the title transition. **SHOW TEXT** reveals the current page without cutting off its voice; **NEXT** moves to the next page and switches the audio. **BACK** replays the previous page. **BEGIN!** stops narration and continues into the instructions. Speech never advances a page automatically.

Narration follows the existing volume setting and pauses/resumes when the app loses/regains focus. All speech is pre-generated and works offline; no voice account, API key, model download or extra Python package is needed to play.

The complete spoken introduction is also available as `assets/audio/bob/Bob_Full_Intro.mp3` (about 44 seconds). Individual pages are `bob_01.mp3` through `bob_07.mp3`. The GUI and gameplay remain unchanged by this voice update.


## Selected song behind Bob
The song chosen in **PLAY NEXT** now plays quietly beneath Bob’s introduction, 18 dB below the narration’s volume setting. This uses the selected gameplay song even if the carousel is previewing something else. The background continues across dialogue pages and loops if it ends while you are reading. Both music and narration pause when the app loses focus.

**BEGIN!** stops Bob’s voice while the selected background song continues through the instructions and two-second hand setup. It also plays while waiting for hands and during retry setup. The background stops for the gameplay countdown, and gameplay starts the selected song from time zero with its beatmap. No layout changes.


## Skip Bob’s intro
**SKIP INTRO** is available on every Bob dialogue page, including while text is appearing. It stops narration and transitions directly to the instructions. Your selected song keeps playing, and the normal hand setup/countdown follows. Next, Back and Begin still work as before.


## Final playlist cleanup
The original Claps + Snares and Kick Drum tracks, their beatmaps, and their click-test audio have been removed. Only the five supplied MP3 songs are available. Saved selections for either removed track automatically fall back to sweet rally.

## Polished release
On Windows, use `Start.bat` for camera mode or `Start_Keyboard.bat` for keyboard-only play. Camera setup now includes **USE KEYBOARD** if your camera is unavailable. Setup waits while the window is unfocused. The starting window fits smaller displays; F11 toggles fullscreen.

Song choices save immediately. Old or damaged settings fall back safely. The volume slider controls all audio and is labeled **Master volume**. See `docs/FINAL_REVIEW.md` for the code review and testing record.


## Final motion and input balance
Waves pass continuously through the ring and keep moving during the late-hit allowance. Timing is now ±300 ms, with full credit within ±150 ms and 90% credit outside that band. Perfect remains ±50 ms. The 2.4-second approach and sparse song patterns remain unchanged.

A deliberate off-target or wrong-hand flick costs 3% vibe, ends the streak, and counts against accuracy. A missed wave still costs 12%. Repeated input within 180 ms on the same hand is ignored without an additional penalty; both hands remain independent. Holding a key does not generate repeat hits. Results list missed waves separately from off-beat attempts. Practice mode still allows continued play at zero vibe.
