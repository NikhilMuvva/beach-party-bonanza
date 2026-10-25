# Runtime integration

Godot owns rendering, song time, scoring and the recovery state machine. `tracker/service.py` owns webcam capture, MediaPipe hand tracking and automatic geometry adaptation from `tracker/hand_tracker.py`.

The service continuously polls the camera, including while a round is inactive. State heartbeats and captured-time flick events use loopback UDP ports 5005/5006. `round=false` disables scoring events without stopping detection. `round=true` resets gesture arming. The bridge cancels superseded round-command retries.

Preview JPEGs are atomically replaced locally beside the launch profile, never transmitted, and removed when the camera closes. The service includes frame age in its state heartbeat and suppresses stale hand positions after 500 ms. The UI reads the camera only when its panel is visible.

Recovery uses the same chart and music stream: pause → track both hands for 0.5 seconds → three-second countdown → unpause. Hand loss during the countdown returns to waiting. Captured input from before unpause is rejected. Manual pause/focus loss never auto-resumes.

Tests exercise scoring, protocol, scene flow, stale frames, recovery cancellation, keyboard fallback and symmetric wave anchors. Native rendered screenshots live in `docs/screenshots`.


## Frat Flicks opening
`arcade_wordmark.gd` draws the original code-native pixel title. `main.gd` controls a 0.64-second fade, the seven-page authored Bob dialogue and typewriter reveal. `beach_world.gd` plays the supplied 24-frame atlas without the old title scrim. BEGIN! transitions to instructions; camera play then requires a fresh two-second stable-hand baseline. Movement beyond the anchor tolerance or missing hands resets that baseline. Subsequent recovery retains the half-second settle and three-second countdown.

The Godot app and launcher profile are both named Frat Flicks so camera JPEG writes and reads remain colocated. Displayed high score is actual local data saved by the existing settings path; demo scores are excluded. The procedural title and mild sunset shader/glints have no extra downloads or external asset dependencies. The stick figures/sign and extra umbrella props are removed.


`hand_art.gd` maps the four supplied left/right normal/flick PNGs. Canvas matting removes the black backdrop without altering stored assets. Full source-image wrist anchors, rather than changing image bounds, register each pose consistently. Both wave lanes now use identical cyan modulation. The scenery’s stronger water shader excludes the palm region, and moving foam/glints make continuous animation visible while the HUD/camera stay fixed.


## Audio and retry
`main.gd` creates dedicated countdown/miss AudioStreamPlayers. The countdown seeks past its 25.1 ms encoder silence and uses audible playback position (including mixer/output-latency correction), rather than frame delta, for number changes and the start cue. Test mode can inject delta for deterministic state-machine checks; `test_countdown_clock.gd` independently exercises the production clock and records its mix to scratch.

`rhythm_judge.gd` owns an exactly-once pending-miss queue because expiry can happen inside both frame judging and flick handling. The app drains it for the existing splash graphic and supplied miss sound. The wider ±450 ms window returns 0.90 quality for the added 150–450 ms range; accuracy sums quality credit over resolved targets.

Results retry preserves chart, practice and control settings, clears round state, and begins a new countdown or waits for camera setup. It never re-enters the title or dialogue. Existing GUI construction is unchanged except for splitting the results action into Title Screen and Try Again.


## Title jukebox
`title_jukebox.gd` reads `assets/audio/title_playlist.json` and owns a separate title AudioStreamPlayer. Actual `finished` events advance the playlist modulo its length. Native deck drawings slide with a 0.52-second cubic tween, while only the active vinyl rotates; pause suspends both playback and its spin. Leaving title stops its audio/tween, and title Settings can keep it playing. A completed track during an existing slide is queued until settling.

The interactive native Press Start Button retains keyboard/mouse behavior, while its artwork is drawn on the continuously refreshed carousel canvas to keep the primary action visible through animated redraws. Gameplay screens retain their prior geometry.

The widened judge window now selects the nearest eligible pending note in a lane, keeps earlier pending notes accessible, and breaks equal-distance ties by chart order.


## Playable song expansion
`SONG_KEYS` / `SONG_NAMES` bind title and settings selectors. Uploaded chart JSON includes its original MP3 resource path; original charts retain their original OGG/click-check fallback. Preview carousel state and selected gameplay song are intentionally independent. `tools/build_song_charts.py` reproduces the five maps with librosa 0.11.0; runtime needs no librosa. Onset-snapped beat times are thinned to camera-friendly spacing and each song uses a distinct repeating lane phrase. The renderer uses `Judge.TRAVEL_TIME` directly (2.4 s), avoiding divergent visual/scoring constants.

The finger detector keeps 240 recent samples per hand, learns 15th/85th percentiles independently per finger only after 24 samples and adequate range, and limits endpoint movement to 0.002 per frame. This replaces permanent min/max extremes. Index/middle world landmarks remain 5–8 and 9–12; synthetic independent-finger checks confirm the mapping.
