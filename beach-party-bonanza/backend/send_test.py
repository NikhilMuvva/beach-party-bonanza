"""Send fake events to Godot before webcam tracking is working.
Run: python -m backend.send_test
"""
import json
import socket
import time

DEST = ("127.0.0.1", 4242)


def main() -> None:
    print("Sending synthetic hand events to Godot on UDP 4242. Ctrl+C to stop.")
    directions = ("UP", "DOWN")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        seq = 0
        try:
            while True:
                direction = directions[seq % 2]
                hand = "L" if seq % 2 == 0 else "R"
                t = time.monotonic()
                payloads = [
                    {"v": 1, "type": "status", "ready": True, "hands": 2, "t": t},
                    {"v": 1, "type": "pose", "hand": hand, "x": 0.35 if hand == "L" else 0.65,
                     "y": 0.30 if direction == "UP" else 0.75, "t": t},
                    {"v": 1, "type": "flick", "hand": hand, "event": direction, "t": t},
                ]
                for msg in payloads:
                    sock.sendto(json.dumps(msg).encode("utf-8"), DEST)
                print(f"{hand}: {direction}")
                seq += 1
                time.sleep(1.0)
        except KeyboardInterrupt:
            print("Stopped.")


if __name__ == "__main__":
    main()
