# Frat Flicks
### Project made for TAMU HowdyHack 2026

Frat Flicks is a single-player, webcam-controlled rhythm game set at a retro, Aggie-inspired beach party. Flick your **index and middle fingers** upward in time with the music to stop incoming waves, build combos, and keep the party's vibe meter from reaching zero.

Built with **Godot 4, Python, MediaPipe, and OpenCV**, the game also includes a keyboard mode so you can play without a webcam.

 ### Features
- **Webcam-powered controls** — two independent hands, each activated by raising the index and middle fingers together.
- **Rhythm-based scoring** — Perfect, full-credit, and grace-window hits, plus streaks, combos, and accuracy feedback.
- **Vibe meter** — gain vibe on successful hits and lose it on missed waves or off-beat flicks.
- **Five playable songs** — each with a separate, precomputed beatmap.
- **Arcade presentation** — animated beach scenery, pixel-art hand sprites, a title-screen music carousel, and a spoken introduction from Bob.
- **Automatic hand setup and recovery** — a two-second baseline calibration; if a hand disappears, gameplay pauses and resumes after both hands return and a countdown finishes.
- **Keyboard and Practice modes** — playable even without a webcam, with an option to keep going when the vibe meter empties.
- **Local hand tracking** — tracking runs on your computer, with events passed to Godot over loopback UDP.

## Getting started
### 1. Requirements
- **Godot 4.5+ Standard** (the repository's current `project.godot` also records a `4.7` feature tag; use a matching/newer compatible Godot 4 version if an older editor reports compatibility issues).
- **Windows or macOS** with access to the extracted project folder.
- **Python 3.11** for webcam tracking and its pinned dependencies.
- A webcam and camera permissions for camera mode. **Keyboard mode does not require webcam/Python tracking packages.**

### 2. Get the project
Clone the repository (do this in Command Prompt):
```powershell
git clone https://github.com/NikhilMuvva/frat-flick.git
cd frat-flick/Frat_Flicks/Frat_Flicks_Godot
```
Alternatively, select **Code → Download ZIP** on GitHub, extract the entire ZIP, and open the nested folder:
```text
frat-flick/
└── Frat_Flicks/
    └── Frat_Flicks_Godot/    ← Godot project folder
        └── project.godot
```
**Important:** The GitHub repository root is not the Godot `project root`. Select the project.godot inside `Frat_Flicks/Frat_Flicks_Godot`.

**Windows (VS Code PowerShell terminal):**
1. Install Python **3.11** and Godot.
2. In VS Code, choose **File → Open Folder** and open `Frat_Flicks/Frat_Flicks_Godot`.
3. Open **Terminal → New Terminal** and verify that `launch.py` is in the current folder.
4. Run:
   ```powershell
   py -3.11 launch.py
   ```
   If Godot is not found automatically, give the actual path to your Godot executable:
   ```
   py -3.11 launch.py --godot "C:\Path\To\Godot.exe"
   ```
**macOS:** From the Godot project folder, run `python3 launch.py` in Terminal, or use the included `Start.command` after reviewing it. If necessary, pass `--godot /Applications/Godot.app`.

The launcher supports `--camera 1` for an alternate webcam, `--swap-hands` if left/right labels are reversed, and `--preview` for a diagnostic camera window. Run `python launch.py --help` to see additional options.

### 3. Webcam Calibration and Gameplay
1. From the title screen, select a song and begin **Camera** play.
2. Follow Bob's introduction and the in-game instructions (or use Skip Intro).
3. Keep **both hands visible and still** for the **two-second automatic baseline.**
4. Lower both your index and middle fingers to arm each hand.
5. When a wave approaches the hit ring, raise **both fingers together** on the corresponding hand.
6. Lower those fingers again before attempting another flick.
Left-hand input targets the **left wave lane**; right-hand input targets the **right wave lane**. **Moving your entire arm without the two-finger gesture is not an intended hit.**

If either hand leaves view during the song, the game pauses without discarding progress. Once both hands return and stabilize, a three-second countdown resumes play. A separate standalone detector under `tracker/frat_flick_test.py` provides manual **D/U** calibration/testing controls; the normal game uses automatic setup.

## Controls

| Input | Action |
|-------|--------|
| **Left Hand** (index + middle fingers up) | Flick the left wave |
| **Right Hand** (index + middle fingers up) | Flick the right wave |
| `A` | Left-hand flick (Keyboard Mode) |
| `L` | Right-hand flick (Keyboard Mode) |
| `P` or `Esc` | Pause the game |
| `Enter` or `Space` | Continue dialogue / Confirm |
| `Left Arrow` | Previous dialogue page |
| `F11` | Toggle fullscreen |
| `T` | Toggle webcam preview |
| `R` | Restart from results screen |

The title screen also provides song selection, settings, and the option to switch to keyboard play when the camera is unavailable.

## Project structure
```text
frat-flick/
├── Frat_Flicks.zip                    # Additional packaged project archive
└── Frat_Flicks/
    └── Frat_Flicks_Godot/           # Godot project root
        ├── project.godot            # Godot configuration
        ├── launch.py                # Godot + Python launcher
        ├── Start.bat                # Windows camera launcher
        ├── Start_Keyboard.bat       # Windows keyboard launcher
        ├── Start.command            # macOS launcher
        ├── scenes/
        │   └── main.tscn            # Main game scene
        ├── scripts/
        │   ├── main.gd              # Game flow, UI, audio, round state
        │   ├── beach_world.gd       # Beach rendering and note animation
        │   ├── rhythm_judge.gd      # Timing and scoring rules
        │   ├── tracker_bridge.gd    # Local UDP connection
        │   └── ...                  # UI and hand-rendering helpers
        ├── tracker/
        │   ├── service.py           # Camera sidecar process
        │   ├── hand_tracker.py      # Hand landmark tracking
        │   ├── frat_flick_test.py   # Standalone gesture/calibration tester
        │   └── requirements.txt    # Pinned Python dependencies
        ├── assets/
        │   ├── art/                 # Beach, waves, animations, hand art
        │   ├── audio/               # Music, Bob narration, sound effects
        │   └── beatmaps/            # Song-specific note charts
        └── docs/
            ├── VALIDATION.md        # Testing notes and limitations
            └── FINAL_REVIEW.md      # Release review
```
Some generated or auxiliary files are omitted from this overview.

## How it works
```text
Webcam
   │
   ▼
Python + MediaPipe + OpenCV
   │   Hand states and discrete flick events
   │   127.0.0.1:5005 (UDP)
   ▼
Godot tracker_bridge.gd
   │
   ▼
Rhythm judge + music clock
   │
   ▼
Wave hit/miss effects, combo, score, and vibe meter
```
Godot sends tracker control messages over **127.0.0.1:5006**. Webcam processing happens locally; the tracker sends hand-state metadata and gesture events, not a video stream, over UDP. An optional preview image is written locally for the game's camera interface and removed when tracking stops.
