"""Fetch the official MediaPipe Hand Landmarker model (not checked into git)."""
from pathlib import Path
from urllib.request import urlretrieve

URL = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
DEST = Path(__file__).resolve().parent / "models" / "hand_landmarker.task"


def main() -> None:
    DEST.parent.mkdir(exist_ok=True, parents=True)
    if DEST.is_file() and DEST.stat().st_size > 100000:
        print(f"Model already downloaded: {DEST}")
        return
    print("Downloading official MediaPipe Hand Landmarker model ...")
    urlretrieve(URL, DEST)
    print(f"Saved {DEST} ({DEST.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
