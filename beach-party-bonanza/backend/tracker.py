"""Camera -> MediaPipe Tasks -> gesture detector -> local UDP for Godot.
Run: python -m backend.tracker

This MVP uses synchronous VIDEO mode to keep the code simple; the first
performance upgrade, if necessary, is dropping stale camera frames and using
MediaPipe LIVE_STREAM mode.
"""
import argparse
from collections import deque
import json
from pathlib import Path
import socket
import statistics
import sys
import time

from backend.gesture import FlickDetector

MODEL_PATH = Path(__file__).resolve().parent / "models" / "hand_landmarker.task"


def send(sock, message: dict, target: tuple[str, int]) -> None:
    sock.sendto(json.dumps({"v": 1, **message}, separators=(",", ":")).encode(), target)


def parse_args():
    parser = argparse.ArgumentParser(description="Beach Party Bonanza webcam controller")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--port", type=int, default=4242)
    parser.add_argument("--no-preview", action="store_true", help="Do not display the local OpenCV preview")
    parser.add_argument("--threshold", type=float, default=0.10)
    return parser.parse_args()


def main():
    args = parse_args()
    if not MODEL_PATH.is_file():
        sys.exit("Missing model. Run: python -m backend.download_model")
    try:
        import cv2
        import mediapipe as mp
    except ImportError as exc:
        sys.exit(f"Dependency missing: {exc}. Install: pip install -r backend/requirements.txt")

    cap = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW) if sys.platform == "win32" else cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        sys.exit("Cannot open webcam. Check camera permissions and --camera 0/1.")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(MODEL_PATH)),
        running_mode=mp.tasks.vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    detector = FlickDetector(threshold=args.threshold)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = ("127.0.0.1", args.port)
    samples = {"L": deque(), "R": deque()}
    ready = False
    start = time.monotonic()
    last_status = 0.0
    frames = 0
    fps_start = start
    fps = 0.0
    print(f"Webcam -> UDP {target[0]}:{target[1]}. Press q in preview to quit; Ctrl+C otherwise.")
    print("Hold BOTH hands still for 2 seconds to calibrate. Then flick UP or DOWN.")

    try:
        with mp.tasks.vision.HandLandmarker.create_from_options(options) as landmarker:
            while True:
                ok, frame = cap.read()
                if not ok:
                    print("Camera read failed; exiting.")
                    break
                frame = cv2.flip(frame, 1)  # player sees a mirror
                now = time.monotonic()
                timestamp_ms = int((now - start) * 1000) + 1
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = landmarker.detect_for_video(
                    mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), timestamp_ms
                )
                seen = {}
                for handedness, landmarks in zip(result.handedness, result.hand_landmarks):
                    if not handedness:
                        continue
                    label = handedness[0].category_name
                    if label not in ("Left", "Right"):
                        continue
                    hand = "L" if label == "Left" else "R"
                    # Palm center is less sensitive to finger movement than fingertips.
                    x = sum(landmarks[i].x for i in (0, 5, 9, 17)) / 4
                    y = sum(landmarks[i].y for i in (0, 5, 9, 17)) / 4
                    x = max(0.0, min(1.0, x))
                    y = max(0.0, min(1.0, y))
                    seen[hand] = (x, y)
                    cx, cy = int(x * frame.shape[1]), int(y * frame.shape[0])
                    cv2.circle(frame, (cx, cy), 12, (0, 255, 0), 2)
                    cv2.putText(frame, hand, (cx + 15, cy), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

                if not ready:
                    # Require both hands continuously visible and nearly still.
                    if len(seen) != 2:
                        for queue in samples.values():
                            queue.clear()
                    else:
                        for hand, (_x, y) in seen.items():
                            samples[hand].append((now, 1.0 - y))
                        # Restart if movement exceeds tolerance during calibration.
                        for queue in samples.values():
                            if queue and max(v for _, v in queue) - min(v for _, v in queue) > 0.06:
                                queue.clear()
                        if all(len(q) >= 10 and q[-1][0] - q[0][0] >= 2.0 for q in samples.values()):
                            detector.calibrate({hand: statistics.median(v for _, v in queue) for hand, queue in samples.items()})
                            ready = True
                            print("Calibrated! Both hands ready.")
                else:
                    for hand in ("L", "R"):
                        if hand not in seen:
                            detector.forget(hand)
                    for hand, (x, y) in seen.items():
                        send(sock, {"type": "pose", "hand": hand, "x": x, "y": y, "t": now}, target)
                        event = detector.update(hand, 1.0 - y, now)
                        if event:
                            send(sock, {"type": "flick", "hand": hand, "event": event, "t": now}, target)
                            print(f"{hand} {event}")
                if now - last_status >= 0.5:
                    send(sock, {"type": "status", "ready": ready, "hands": len(seen), "t": now}, target)
                    last_status = now

                frames += 1
                if now - fps_start >= 1:
                    fps = frames / (now - fps_start)
                    frames, fps_start = 0, now
                if not args.no_preview:
                    status = "READY" if ready else "CALIBRATING: hold 2 hands still"
                    cv2.putText(frame, f"{status} | {fps:.0f} FPS", (12, 30), cv2.FONT_HERSHEY_SIMPLEX, .65, (255, 255, 255), 2)
                    cv2.imshow("Beach Party Bonanza - local webcam preview", frame)
                    if cv2.waitKey(1) & 0xFF == ord("q"):
                        break
    except KeyboardInterrupt:
        pass
    finally:
        cap.release()
        sock.close()
        if not args.no_preview:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
