# Credits and included material

The original Python detector, music, beatmaps, scenery, wave art and 24-frame character/party animation were supplied with the project. Their attribution and rights remain with their respective owners. The new title is inspired by the user-supplied arcade reference; it does not embed that reference image.

The arcade wordmark, grid, stars, scenery shader, glints, umbrellas, dialogue UI and FF icon are original editable code/vector artwork. No new external image assets or music were downloaded.

The included DejaVu Sans and DejaVu Sans Mono Bold fonts use `assets/fonts/LICENSE.txt`.

Godot is not bundled. OpenCV, MediaPipe, NumPy and dependencies are installed by the launcher and include their own licenses/notices.


The four `frat_left_hand_*` / `frat_right_hand_*` PNGs were supplied by the user as their own artwork and are included without changing their bytes. Rendering uses a local black-matte shader, consistent scaling and wrist registration.

The countdown.mp3 and water_splash.mp3 effects were supplied by the user and are included unchanged; their rights remain with their respective owners.


Five title-playlist MP3s were supplied by the user: sweet rally (ilysam, Mc Ster), Paradise (dentist), Make U Whole (GEEMIX), Eatin' Good (Woodcamp), and Free Your Mind (Prospa, Cloonee, Sybil). Their bytes are unchanged; rights remain with their respective owners. Names/artists use embedded tags or the supplied filenames. Record decks and carousel visuals are original native GDScript drawings.


## Bob’s synthetic narration
Generated using Piper TTS with the `en_US-joe-medium` US English male voice. Voice model source: https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/joe/medium . Its model card identifies the training dataset as CC0, from https://github.com/OHF-Voice/voice-datasets . The model card is reproduced at `docs/BOB_VOICE_MODEL_CARD.md`. Bob is a fictional character; this is synthetic narration, not a recorded actor performance.

Only generated MP3 audio is included. Piper, ONNX runtime, model weights and synthesis dependencies are not distributed with the game. Dialogue is supplied by the project user. Synthesis used length scale 0.97, noise scale 0.6, noise width 0.75; output normalized to -18 LUFS / -2 dBTP and encoded as 44.1 kHz MP3 at 128 kbps.
