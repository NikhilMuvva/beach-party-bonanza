#!/usr/bin/env python3
"""Local camera sidecar for Godot.

Hand state and events use loopback UDP. The embedded camera panel reads an
atomically replaced local preview JPEG; it is removed on camera shutdown.
Tracking continues during pauses and countdowns so hands can be reacquired.
T optionally opens the separate diagnostic camera window.
"""
from __future__ import annotations

import argparse
from collections import deque
import json
import math
from pathlib import Path
import signal
import socket
import sys
import time
import uuid

PROTOCOL = 1
HOST = "127.0.0.1"
EVENT_PORT = 5005
CONTROL_PORT = 5006


def valid_message(value):
    return (isinstance(value, dict) and value.get("protocol") == PROTOCOL
            and isinstance(value.get("command"), str)
            and isinstance(value.get("id"), str) and len(value["id"]) <= 100)


class Service:
    def __init__(self, args):
        self.args = args
        self.session = uuid.uuid4().hex
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        try:
            self.socket.bind((HOST, args.control_port))
        except OSError as exc:
            self.socket.close()
            raise RuntimeError("Tracker port 5006 is busy. Close other trackers.") from exc
        self.destination = (HOST, args.port)
        self.running = True
        self.detector = None
        self.error = "Starting camera..."
        self.round_active = False
        self.preview = args.preview
        self.event_id = 0
        self.frame_captured = 0.0
        self.landmarks = {}
        self.down_done = False
        self.up_done = False
        self.seen_commands = deque(maxlen=256)
        self.last_heartbeat = 0.0
        self.last_contact = time.monotonic()
        self.had_game_contact = False
        self.next_reconnect = 0.0

    def send(self, data):
        packet = dict(data, protocol=PROTOCOL, session=self.session)
        try:
            self.socket.sendto(json.dumps(packet, separators=(",", ":"), allow_nan=False).encode(), self.destination)
        except (OSError, ValueError):
            pass

    def open_camera(self):
        self.down_done = self.up_done = False
        try:
            import cv2
            import hand_tracker
            import frat_flick_test as flick

            # Keep the supplied detector's finger math and thresholds. The lite
            # landmark model reduces inference time on a demo laptop.
            flick.MODEL_COMPLEXITY = 0
            flick.SWAP_HAND_LABELS = self.args.swap_hands
            path = self.args.profile
            path.parent.mkdir(parents=True, exist_ok=True)
            hand_tracker.CALIBRATION_PATH = path
            self.detector = hand_tracker.Detector(camera_index=self.args.camera, port=self.args.port)
            self.preview_sequence = -1
            self.detector.send = self.detector_packet
            original_process = self.detector.process_hands

            def process(hands, frame, captured_at, now):
                self.frame_captured = captured_at
                self.landmarks = {}
                # Reuse exactly the same physical-label policy as the detector.
                for label, confidence, landmarks, _world in hands:
                    if label not in ("Left", "Right") or confidence < flick.MIN_HANDEDNESS_CONFIDENCE:
                        continue
                    hand = "L" if label == "Left" else "R"
                    if flick.SWAP_HAND_LABELS:
                        hand = "R" if hand == "L" else "L"
                    self.landmarks[hand] = [[round(float(p.x), 4), round(float(p.y), 4)] for p in landmarks]
                mode = self.detector.calibration.mode
                result = original_process(hands, frame, captured_at, now)
                if mode is not None and self.detector.calibration.mode is None:
                    samples = self.detector.calibration.samples
                    enough = all(len(samples[h]) >= flick.CALIBRATION_MIN_SAMPLES for h in ("L", "R"))
                    if mode == "down":
                        self.down_done = enough and all(h in self.detector.calibration.down_captured for h in ("L", "R"))
                        self.up_done = False
                    else:
                        # Each hand must have a valid captured range, not just a
                        # single "calibrated" substring from the old notice.
                        import statistics
                        ranges = []
                        if enough:
                            for h in ("L", "R"):
                                up = [statistics.median(s[i] for s in samples[h]) for i in (0, 1)]
                                down = self.detector.endpoints[h]["down"]
                                ranges.append(all(u - d >= flick.CALIBRATION_MIN_RANGE for d, u in zip(down, up)))
                        self.up_done = self.down_done and enough and all(ranges)
                    if not (self.down_done if mode == "down" else self.up_done):
                        self.detector.calibration_notice = "Both hands must finish capture. Keep both fingers visible and repeat."
                return result

            self.detector.process_hands = process
            if path.is_file():
                try:
                    saved = json.loads(path.read_text())
                    self.down_done = self.up_done = hand_tracker.valid_endpoints(saved)
                    if self.down_done:
                        self.detector.calibration.down_captured = {"L", "R"}
                except (ValueError, OSError):
                    pass
            self.down_done = self.up_done = True
            self.detector.calibration_notice = "Automatic hand setup active. Curl then extend index + middle."
            self.error = ""
            print("Tracker ready. Left = cyan wave, right = cyan wave. Video stays local.", flush=True)
        except Exception as exc:
            self.error = str(exc)
            self.close_camera()
            self.next_reconnect = time.monotonic() + 3.0
            print("Camera: " + self.error, file=sys.stderr, flush=True)

    def detector_packet(self, data):
        if "event" not in data or not self.round_active:
            return
        self.event_id += 1
        age = max(0.0, time.perf_counter() - self.frame_captured)
        self.send({"type": "flick", "id": str(self.event_id), "hand": data["hand"],
                   "event": data["event"], "captured_unix": time.time() - age})

    def commands(self):
        for _ in range(100):
            try:
                raw, address = self.socket.recvfrom(16384)
            except BlockingIOError:
                break
            if address[0] != HOST:
                continue
            try:
                data = json.loads(raw)
            except (ValueError, UnicodeError):
                continue
            if not valid_message(data) or data.get("session", self.session) != self.session:
                continue
            self.last_contact = time.monotonic()
            self.had_game_contact = True
            self.send({"type": "ack", "id": data["id"]})
            if data["id"] in self.seen_commands:
                continue
            self.seen_commands.append(data["id"])
            command = data["command"]
            if command == "shutdown":
                self.running = False
            elif command == "reconnect":
                self.close_camera()
                self.next_reconnect = 0.0
            elif command == "round":
                self.round_active = bool(data.get("active", False))
                if self.detector:
                    self.detector.reset_flicks()
            elif command == "capture" and not self.round_active and self.detector:
                mode = data.get("mode")
                if self.detector.calibration.mode is None and mode in ("down", "up"):
                    if mode == "down":
                        self.down_done = self.up_done = False
                    elif not self.down_done:
                        continue
                    self.detector.begin_calibration(mode)
            elif command == "preview":
                self.preview = bool(data.get("visible", not self.preview))
                if not self.preview:
                    try:
                        import cv2
                        cv2.destroyAllWindows()
                    except Exception:
                        pass

    def state_packet(self):
        detector = self.detector
        hands = {}
        frame_age = max(0.0, time.perf_counter() - self.frame_captured) if self.frame_captured else 999.0
        if detector and frame_age <= 0.5:
            for hand, position in detector.hand_positions.items():
                state = detector.states[hand]
                hands[hand] = {"x": round(position[0], 4), "y": round(position[1], 4),
                               "armed": state.armed, "progress": list(state.progress or (0.0, 0.0)),
                               "status": state.status, "landmarks": self.landmarks.get(hand, [])}
        return {"type": "state", "frame_age_ms": round(frame_age * 1000.0, 1), "fps": round(detector.fps, 1) if detector else 0.0,
                "camera_ready": detector is not None and not detector.error,
                "error": self.error or (detector.error if detector else ""),
                "hands": hands, "preview": self.preview,
                "calibration": {"mode": detector.calibration.mode if detector else None,
                                "down_done": self.down_done, "up_done": self.up_done,
                                "notice": detector.calibration_notice if detector else "Connect your camera."}}

    def run(self):
        self.open_camera()
        try:
            while self.running:
                self.commands()
                now = time.monotonic()
                if self.had_game_contact and now - self.last_contact > 12:
                    print("Game disconnected; closing camera.", flush=True)
                    break
                if self.detector is None and now >= self.next_reconnect:
                    self.open_camera()
                if self.detector:
                    _events, frame = self.detector.poll()
                    if self.detector.error:
                        self.error = self.detector.error
                        self.close_camera()
                        self.next_reconnect = now + 3.0
                    elif frame is not None:
                        # Local-only atomic JPEG for the embedded Godot camera panel.
                        # Keep the full face and both hands; no video leaves this computer.
                        import cv2
                        preview_path = self.args.profile.with_name("camera_preview.jpg")
                        sequence = self.detector.sequence
                        if sequence != getattr(self, "preview_sequence", -1):
                            self.preview_sequence = sequence
                            small = cv2.resize(frame, (640, 360))
                            ok, encoded = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 85])
                            if ok:
                                temp = preview_path.with_suffix(".tmp")
                                try:
                                    temp.write_bytes(encoded.tobytes())
                                    temp.replace(preview_path)
                                except OSError:
                                    pass
                    if self.preview and frame is not None:
                        import cv2
                        cv2.imshow("Frat Flicks - mirrored camera (T to close)", frame)
                        key = cv2.waitKey(1) & 0xFF
                        if key in (27, ord("t"), ord("q")):
                            self.preview = False
                            cv2.destroyAllWindows()
                if now - self.last_heartbeat >= 1 / 30:
                    self.send(self.state_packet())
                    self.last_heartbeat = now
                time.sleep(0.002 if self.detector else 0.03)
        finally:
            self.close_camera()
            self.socket.close()

    def close_camera(self):
        if self.detector:
            self.detector.close()
            self.detector = None
        self.landmarks = {}
        try:
            self.args.profile.with_name("camera_preview.jpg").unlink(missing_ok=True)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--port", type=int, default=EVENT_PORT)
    parser.add_argument("--control-port", type=int, default=CONTROL_PORT)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--swap-hands", action="store_true")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    service = Service(args)
    signal.signal(signal.SIGTERM, lambda *_: setattr(service, "running", False))
    signal.signal(signal.SIGINT, lambda *_: setattr(service, "running", False))
    service.run()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
