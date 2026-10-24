# Beach Party Bonanza

HowdyHack 2026 — A first-person webcam-controlled rhythm game. Flick **UP** to defeat seagulls, flick **DOWN** to repel waves. Python + MediaPipe performs local hand tracking and sends JSON over UDP; Godot plays the game.

## Repo layout
- [`backend/`](backend/) — Python webcam / hand tracking / calibration / UDP sender
- [`frontend/`](frontend/) — Godot 4 project (starts with a UDP test scene)
- [`assets/`](assets/) — artist-owned graphics and audio
- [`beatmaps/`](beatmaps/) — example JSON rhythm events
- [`presentation/`](presentation/) — pitch / submission assets
- [`docs/UDP_PROTOCOL.md`](docs/UDP_PROTOCOL.md) — frozen backend/frontend message contract
- [`docs/TEAM.md`](docs/TEAM.md) — roles and branch strategy
- [`docs/PRD.md`](docs/PRD.md) — project requirements

## Quick start (Windows PowerShell, from repo root)

Install **Python 3.11 or 3.12**, Git, and Godot 4.x first. The tracker uses MediaPipe's current **Tasks** API; older `mp.solutions.hands` examples aren't used.

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r backend/requirements.txt
python -m backend.download_model
python -m unittest discover -s backend/tests -v
```

If `py -3.11` is unavailable, install 3.11 or replace with an available supported Python interpreter, e.g. `py -3.12`. If PowerShell blocks activation, run `Set-ExecutionPolicy -Scope Process Bypass` for that terminal only.

### Step A: Test Python ↔ Godot before using the webcam
1. In Godot Project Manager, **Import** the project at `frontend/project.godot`; click Run (F6/F5 as appropriate).
2. From repo root (with venv active):
```powershell
python -m backend.send_test
```
3. Godot should display alternating `L UP`, `R DOWN`. Stop with Ctrl+C.

### Step B: Try actual tracking
```powershell
python -m backend.tracker
```

Hold both hands still for ~2 seconds for calibration, then flick up/down and watch Godot's event labels. In OpenCV's camera preview, press `q` to quit. The preview window is separate from Godot for this starter; embedding a corner webcam preview is **not yet implemented**. No video leaves the machine.

If the camera cannot open, close Zoom/Teams and check Windows camera permissions. Try `--camera 1` if necessary. If gestures are too sensitive: `python -m backend.tracker --threshold 0.14`.

### Launch both processes (after setup)
If Godot is on PATH, `./run_demo.ps1` in PowerShell starts the tracker and Godot.
Otherwise pass the local `.exe` path: `./run_demo.ps1 -GodotExe 'C:\path\to\Godot.exe'`.
You can always run Godot and `python -m backend.tracker` separately while debugging.

### Development strategy
- Godot developer should build with keyboard input until UDP integration is working.
- Backend developer tunes threshold, calibration and latency on the actual demo laptop.
- Do not block art/presentation work on backend readiness.
- Test the combined demo early and often, particularly in poor venue lighting.

## Known limits of this starter
- This is an **integration scaffold**, not a finished rhythm game.
- Godot test scene displays incoming signals; art, audio, beat spawning, scoring and win/lose UI are not implemented.
- Default flick thresholds and handedness need real-world calibration/test on the demo laptop.
- The synchronous webcam loop may fall short of target FPS on slower hardware; profile before optimizing.
- The example beatmap is NOT generated from an audio track and includes no copyrighted song.
- The UDP `t` field is Python's clock, not Godot's audio clock. Use arrival audio time and a configurable timing offset.
