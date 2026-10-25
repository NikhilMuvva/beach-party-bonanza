#!/usr/bin/env python3
"""Starts Godot and a synthetic sidecar in one process namespace; no camera.

python tests/test_udp_roundtrip.py --godot /path/to/godot
"""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 5006))
    sock.setblocking(False)
    session = uuid.uuid4().hex
    process = subprocess.Popen([str(args.godot.resolve()), "--headless", "--path", str(root), "--script", "tests/udp_roundtrip.gd"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sent_events = False
    command_seen = False
    deadline = time.monotonic() + 8

    def send(data):
        packet = dict(data, protocol=1, session=session)
        sock.sendto(json.dumps(packet).encode(), ("127.0.0.1", 5005))

    try:
        while process.poll() is None and time.monotonic() < deadline:
            send({"type": "state", "hands": {}, "calibration": {}})
            try:
                raw, address = sock.recvfrom(16384)
                command = json.loads(raw)
                if command.get("command") == "round" and command.get("active"):
                    command_seen = True
                send({"type": "ack", "id": command["id"]})
            except BlockingIOError:
                pass
            if command_seen and not sent_events:
                now = time.time()
                left = {"type": "flick", "id": "1", "hand": "L", "captured_unix": now}
                send(left)
                send(left)  # Deliberate duplicate must not become a second hit.
                send({"type": "flick", "id": "2", "hand": "R", "captured_unix": now})
                send({"type": "flick", "id": "old", "hand": "L", "captured_unix": now - 3})
                sent_events = True
            time.sleep(.02)
        output, _ = process.communicate(timeout=2)
        print(output, end="")
        if process.returncode or not command_seen or '"success":true' not in output:
            raise RuntimeError("Godot/sidecar UDP integration failed")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        sock.close()


if __name__ == "__main__":
    main()
