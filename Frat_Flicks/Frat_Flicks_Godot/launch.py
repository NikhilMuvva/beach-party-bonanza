#!/usr/bin/env python3
"""One-command Godot + Python launcher. Safe to invoke from Python 3.14.

python3 launch.py                    # camera + Godot
python3 launch.py --keyboard         # Godot only; no Python packages required
python3 launch.py --godot /path/to/Godot
python3 launch.py --tracker-only     # for a project opened in Godot's editor
"""
from __future__ import annotations

import argparse
import importlib.metadata
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
REQUIREMENTS = ROOT / "tracker" / "requirements.txt"
SUPPORTED = {(3, 11), (3, 12)}


def python_version(executable):
    try:
        result = subprocess.run([str(executable), "-c", "import sys;print('%d.%d'%sys.version_info[:2])"],
                                capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            return tuple(map(int, result.stdout.strip().split(".")))
    except (ValueError, OSError, subprocess.SubprocessError):
        pass
    return None


def environment_python(folder):
    return folder / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def packages_ready(executable):
    code = """import importlib.metadata as m,sys
try:
 pairs=[line.strip().split('==') for line in open(sys.argv[1]) if line.strip() and not line.startswith('#')]
 sys.exit(0 if all(m.version(name)==version for name,version in pairs) else 1)
except m.PackageNotFoundError:
 sys.exit(1)
"""
    try:
        return subprocess.run([str(executable), "-c", code, str(REQUIREMENTS)],
                              capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def windows_python_candidates():
    """Discover side-by-side installs even when only the Python launcher is on PATH."""
    launcher = shutil.which("py")
    if not launcher:
        return []
    found = []
    for version in ("3.11", "3.12"):
        try:
            result = subprocess.run([launcher, "-" + version, "-c", "import sys;print(sys.executable)"], capture_output=True, text=True, timeout=15)
            if result.returncode == 0 and result.stdout.strip():
                found.append(Path(result.stdout.strip()))
        except (OSError, subprocess.SubprocessError):
            pass
    return found


def tracker_python():
    candidates = [environment_python(ROOT / ".venv311"), environment_python(ROOT / ".venv"), Path(sys.executable)]
    for version in ("3.11", "3.12"):
        executable = shutil.which("python" + version)
        if executable:
            candidates.append(Path(executable))
        for prefix in ("/usr/local/bin", "/opt/homebrew/bin", "/Library/Frameworks/Python.framework/Versions/" + version + "/bin"):
            candidates.append(Path(prefix) / ("python" + version))
    if os.name == "nt":
        candidates.extend(windows_python_candidates())
    supported = [p for p in dict.fromkeys(candidates) if p.is_file() and python_version(p) in SUPPORTED]
    for executable in supported:
        if packages_ready(executable):
            return executable
    if not supported:
        raise RuntimeError("Camera tracking needs Python 3.11 or 3.12. Install Python 3.11, then rerun. Keyboard mode works with --keyboard.")
    folder = ROOT / ".venv311"
    if folder.exists() and python_version(environment_python(folder)) not in SUPPORTED:
        raise RuntimeError("The existing .venv311 uses an unsupported Python. Rename that folder, then rerun the launcher.")
    executable = environment_python(folder)
    if not executable.is_file():
        print("Creating the camera environment...", flush=True)
        subprocess.run([str(supported[0]), "-m", "venv", str(folder)], check=True)
    print("Installing pinned camera packages (first setup only)...", flush=True)
    subprocess.run([str(executable), "-m", "pip", "install", "--disable-pip-version-check", "-r", str(REQUIREMENTS)], check=True)
    if not packages_ready(executable):
        raise RuntimeError("Camera dependency setup was incomplete. Keep the terminal error and rerun.")
    return executable


def normalize_godot(value):
    path = Path(value).expanduser()
    if path.suffix == ".app":
        path = path / "Contents" / "MacOS" / "Godot"
    return path


def find_godot(explicit=None):
    candidates = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("GODOT_BIN"):
        candidates.append(os.environ["GODOT_BIN"])
    for name in ("godot", "godot4", "Godot"):
        found = shutil.which(name)
        if found:
            candidates.append(found)
    candidates.extend(["/Applications/Godot.app", str(Path.home() / "Applications/Godot.app")])
    for p in (ROOT, ROOT / "bin", Path.home() / "Downloads"):
        for pattern in ("Godot*.app", "Godot*_win64.exe", "Godot*_linux.x86_64"):
            candidates.extend(str(item) for item in p.glob(pattern))
    for value in dict.fromkeys(candidates):
        path = normalize_godot(value)
        if not path.is_file():
            continue
        try:
            result = subprocess.run([str(path), "--headless", "--version"], capture_output=True, text=True, timeout=20)
            version = result.stdout.strip().split(".")
            if result.returncode == 0 and len(version) >= 2 and (int(version[0]), int(version[1])) >= (4, 5) and int(version[0]) == 4:
                return path.resolve()
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    raise RuntimeError("Godot 4.5+ Standard was not found. Put Godot.app in Applications, or run python3 launch.py --godot /path/to/Godot.app. You can also import project.godot in Godot directly.")


def default_profile():
    if sys.platform == "darwin":
        base = Path.home() / "Library/Application Support/Godot/app_userdata"
    elif os.name == "nt":
        base = Path(os.environ.get("APPDATA", str(Path.home() / "AppData/Roaming"))) / "Godot/app_userdata"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot/app_userdata"
    return base / "Frat Flicks/flick_calibration.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keyboard", action="store_true")
    parser.add_argument("--tracker-only", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--profile", type=Path, default=default_profile())
    parser.add_argument("--swap-hands", action="store_true")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--practice", action="store_true")
    parser.add_argument("--chart", choices=("sweet_rally", "paradise", "make_u_whole", "eatin_good", "free_your_mind"))
    parser.add_argument("--autoplay", action="store_true")
    parser.add_argument("--quit-after-round", action="store_true")
    args = parser.parse_args()
    camera_command = None
    if args.tracker_only or not (args.keyboard or args.autoplay):
        executable = tracker_python()
        camera_command = [str(executable), str(ROOT / "tracker/service.py"), "--camera", str(args.camera), "--profile", str(args.profile)]
        if args.swap_hands:
            camera_command.append("--swap-hands")
        if args.preview:
            camera_command.append("--preview")
    if args.tracker_only:
        return subprocess.call(camera_command, cwd=ROOT)
    godot = find_godot(args.godot)
    logs = ROOT / "logs"
    logs.mkdir(exist_ok=True)
    (logs / ".gdignore").touch()
    print("Checking Godot resources...", flush=True)
    with (logs / "import.log").open("w") as log:
        result = subprocess.run([str(godot), "--headless", "--editor", "--path", str(ROOT), "--import", "--quit"],
                                stdout=log, stderr=subprocess.STDOUT, timeout=180)
    import_text = (logs / "import.log").read_text(errors="replace")
    if result.returncode or "SCRIPT ERROR:" in import_text or "Parse Error:" in import_text:
        raise RuntimeError("Godot import failed. See logs/import.log for the exact error.")
    game_command = [str(godot), "--path", str(ROOT), "--"]
    if camera_command:
        game_command.append("--external-tracker")
    for name in ("keyboard", "practice", "autoplay", "quit_after_round"):
        if getattr(args, name):
            game_command.append("--" + name.replace("_", "-"))
    if args.chart:
        game_command.append("--chart=" + args.chart)
    tracker = None
    game = None
    try:
        print("Starting Frat Flicks...", flush=True)
        game = subprocess.Popen(game_command, cwd=ROOT)
        if camera_command:
            tracker = subprocess.Popen(camera_command, cwd=ROOT)
        return game.wait()
    except KeyboardInterrupt:
        return 0
    finally:
        for process in (tracker, game):
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print("\nStartup: " + str(exc), file=sys.stderr)
        sys.exit(1)
