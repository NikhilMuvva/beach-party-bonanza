"""Two-finger upward frat flicks -> fixed L/WAVE and R/SEAGULL lanes.

Settings and the unchanged standalone detector live in frat_flick_test.py.
D/U calibration is available between rounds. No arm-motion scoring path.
"""
from __future__ import annotations
from pathlib import Path
import json
from collections import deque
import math
import socket
import sys
import threading
import time
import cv2
import mediapipe as mp
import numpy as np
import frat_flick_test as flick

CAM_WIDTH, CAM_HEIGHT, CAM_FPS = 1280, 720, 60
TASK_MODEL_PATH = Path(__file__).resolve().parent / "hand_landmarker.task"
CALIBRATION_PATH = Path(__file__).resolve().parent / "flick_calibration.json"

class LatestFrameCamera:
    """Continuously overwrite a single frame slot, never enqueue old frames."""

    def __init__(self, capture: cv2.VideoCapture):
        self.capture = capture
        self.condition = threading.Condition()
        self.frame = None
        self.sequence = 0
        self.captured_at = 0.0
        self.stopped = False
        self.thread = threading.Thread(target=self._read_loop, daemon=True)

    def start(self) -> None:
        self.thread.start()

    def _read_loop(self) -> None:
        while True:
            with self.condition:
                if self.stopped:
                    return
            ok, frame = self.capture.read()
            captured_at = time.perf_counter()
            if not ok:
                with self.condition:
                    self.stopped = True
                    self.condition.notify_all()
                return
            with self.condition:
                if self.stopped:
                    return
                self.frame = frame
                self.captured_at = captured_at
                self.sequence += 1
                self.condition.notify_all()

    def latest(self, last_sequence: int):
        with self.condition:
            self.condition.wait_for(
                lambda: self.sequence != last_sequence or self.stopped,
                timeout=0.5,
            )
            return self.frame, self.sequence, self.stopped, self.captured_at

    def close(self) -> None:
        with self.condition:
            self.stopped = True
            self.condition.notify_all()
        self.capture.release()
        if self.thread.ident is not None:
            self.thread.join(timeout=1.0)


def _make_tracker():
    legacy = getattr(getattr(mp, "solutions", None), "hands", None)
    if legacy is not None and hasattr(legacy, "Hands"):
        return legacy.Hands(
            max_num_hands=2, model_complexity=flick.MODEL_COMPLEXITY,
            min_detection_confidence=flick.MIN_DETECTION_CONFIDENCE,
            min_tracking_confidence=flick.MIN_TRACKING_CONFIDENCE,
        ), "legacy"
    if not TASK_MODEL_PATH.is_file():
        raise FileNotFoundError("MediaPipe Hands unavailable. Run launch.py to install the pinned MediaPipe 0.10.21, or supply hand_landmarker.task.")
    options = mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(TASK_MODEL_PATH)),
        running_mode=mp.tasks.vision.RunningMode.VIDEO, num_hands=2,
        min_hand_detection_confidence=flick.MIN_DETECTION_CONFIDENCE,
        min_hand_presence_confidence=flick.MIN_DETECTION_CONFIDENCE,
        min_tracking_confidence=flick.MIN_TRACKING_CONFIDENCE,
    )
    return mp.tasks.vision.HandLandmarker.create_from_options(options), "tasks"


def _tracked_hands(tracker, backend, rgb, timestamp_ms):
    if backend == "legacy":
        result = tracker.process(rgb)
        return [(label.classification[0].label, label.classification[0].score,
                 hand.landmark, world.landmark)
                for label,hand,world in zip(result.multi_handedness or [],
                                           result.multi_hand_landmarks or [],
                                           result.multi_hand_world_landmarks or [])]
    result = tracker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb),timestamp_ms)
    return [(label[0].category_name,label[0].score,hand,world)
            for label,hand,world in zip(result.handedness,result.hand_landmarks,result.hand_world_landmarks)]


def _draw_hand(frame, landmarks):
    h,w = frame.shape[:2]
    points = [(int(p.x*w),int(p.y*h)) for p in landmarks]
    for a,b in flick.CONNECTIONS:
        cv2.line(frame,points[a],points[b],(60,180,120),1)
    for i in (5,6,7,8,9,10,11,12):
        cv2.circle(frame,points[i],3,(90,230,130),-1)


def valid_endpoints(data):
    """Validate optional saved calibration before it can affect tracking."""
    try:
        for hand in ("L","R"):
            down,up=data[hand]['down'],data[hand]['up']
            if len(down)!=2 or len(up)!=2:
                return False
            for d,u in zip(down,up):
                if not all(isinstance(v,(float,int)) and math.isfinite(v) for v in (d,u)):
                    return False
                if u-d < flick.CALIBRATION_MIN_RANGE:
                    return False
        return True
    except (KeyError,TypeError):
        return False


class Detector:
    def __init__(self, camera_index=0, pose=True, port=5005):
        if not pose:
            raise RuntimeError("Arm-motion inputs are disabled. Use two-finger upward flicks.")
        flick.validate_settings()
        self.states = {h:flick.FlickState() for h in ("L","R")}
        self.endpoints = {h:dict(e) for h,e in flick.POSE_ENDPOINTS.items()}
        self.calibration = flick.Calibration()
        self.calibration_notice = "D: capture lowered fingers, then U: capture raised fingers."
        if CALIBRATION_PATH.is_file():
            try:
                saved=json.loads(CALIBRATION_PATH.read_text())
                if not valid_endpoints(saved):
                    raise ValueError("invalid pose ranges")
                self.endpoints=saved
                self.calibration_notice="Saved finger calibration loaded. D/U to recalibrate."
            except (OSError,ValueError) as exc:
                print(f"Ignoring invalid flick_calibration.json: {exc}",file=sys.stderr)
        self.auto_ranges = {}
        self.hand_positions={}
        self.last_y_sent={h:0.0 for h in self.states}
        self.sequence=0
        self.last_frame=None
        self.last_task_ms=-1
        self.started_at=time.perf_counter()
        self.previous_at=self.started_at
        self.fps=0.0
        self.error=""
        self.address=("127.0.0.1",port)
        self.socket=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        capture=cv2.VideoCapture(camera_index)
        if not capture.isOpened():
            capture.release();self.socket.close()
            raise RuntimeError("Camera unavailable. Allow camera access or try --camera 1.")
        capture.set(cv2.CAP_PROP_FRAME_WIDTH,CAM_WIDTH)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT,CAM_HEIGHT)
        capture.set(cv2.CAP_PROP_FPS,CAM_FPS)
        capture.set(cv2.CAP_PROP_BUFFERSIZE,1)
        self.camera=LatestFrameCamera(capture)
        try:
            self.tracker,self.backend=_make_tracker()
        except Exception:
            self.camera.close();self.socket.close()
            raise
        self.camera.start()

    def send(self,payload):
        try:
            self.socket.sendto(json.dumps(payload,separators=(",",":")).encode('utf-8'),self.address)
        except OSError:
            pass

    def reset_flicks(self):
        # A held UP pose from the menu/retry cannot score the first target.
        for state in self.states.values():
            state.disarm()

    def begin_calibration(self,mode):
        if mode not in ("down","up"):
            raise ValueError("Calibration mode must be down or up")
        self.calibration.begin(mode,time.perf_counter(),self.states)
        self.calibration_notice=f"Hold BOTH fingers {mode.upper()} through the capture."

    def hand_status(self,hand):
        if hand not in self.hand_positions:
            return f"{hand}: show hand"
        state=self.states[hand]
        if state.armed:
            return f"{hand}: READY / flick up"
        return f"{hand}: lower both fingers"

    def process_hands(self,hands,frame,captured_at,now):
        """One captured frame -> zero/one event per physical hand. Testable."""
        candidates={}
        for label,confidence,landmarks,world in hands:
            if label not in ("Left","Right") or not math.isfinite(confidence) or confidence < flick.MIN_HANDEDNESS_CONFIDENCE:
                continue
            hand="L" if label=="Left" else "R"
            if flick.SWAP_HAND_LABELS:
                hand="R" if hand=="L" else "L"
            if hand not in candidates or confidence>candidates[hand][0]:
                candidates[hand]=(confidence,landmarks,world)
        observed={}
        self.hand_positions={}
        events=[]
        h,w=frame.shape[:2]
        for hand,(_,landmarks,world) in candidates.items():
            if len(landmarks) != 21 or len(world) != 21 or not all(math.isfinite(v) for point in landmarks for v in (point.x,point.y,point.z)):
                continue
            palm_pixels=math.hypot((landmarks[5].x-landmarks[17].x)*w,
                                   (landmarks[5].y-landmarks[17].y)*h)
            if palm_pixels < flick.MIN_PALM_PIXELS:
                continue
            raw=flick.raw_finger_scores([(p.x,p.y,p.z) for p in world])
            if raw is None:
                continue
            observed[hand]=raw
            if not hasattr(self, "auto_ranges"):
                self.auto_ranges = {}
            if hand not in self.auto_ranges:
                self.auto_ranges[hand] = deque(maxlen=240)
            history = self.auto_ranges[hand]
            history.append(raw)
            # Quantiles reject isolated landmark spikes (especially middle DIP).
            # Learn each finger independently; one occluded finger cannot block
            # the other. Rate limiting prevents a calibration jump from firing.
            if len(history) >= 24:
                low = np.quantile(history, 0.15, axis=0)
                high = np.quantile(history, 0.85, axis=0)
                down = list(self.endpoints[hand]["down"])
                up = list(self.endpoints[hand]["up"])
                for i in (0, 1):
                    if high[i] - low[i] >= flick.CALIBRATION_MIN_RANGE:
                        down[i] += float(np.clip(low[i] - down[i], -0.002, 0.002))
                        up[i] += float(np.clip(high[i] - up[i], -0.002, 0.002))
                self.endpoints[hand] = {"down": tuple(down), "up": tuple(up)}
            self.hand_positions[hand]=(float(landmarks[0].x),float(landmarks[0].y))
            if self.calibration.mode is None:
                progress=flick.normalize_scores(raw,self.endpoints[hand])
                if self.states[hand].update(progress,captured_at):
                    # UP is the physical gesture on BOTH hands. DOWN here is
                    # only the game's existing WAVE lane event, never a lowering gesture.
                    event="DOWN" if hand=="L" else "UP"
                    payload={"hand":hand,"event":event}
                    self.send(payload)
                    print(json.dumps(payload),flush=True)
                    events.append((event,hand))
            y=float(np.mean([landmarks[i].y for i in (0,5,9,13,17)]))
            if now-self.last_y_sent[hand]>=1/30:
                self.send({"hand":hand,"y":round(flick.clamp(y),4)})
                self.last_y_sent[hand]=now
            _draw_hand(frame,landmarks)
        for hand,state in self.states.items():
            if hand not in observed:
                state.missing(captured_at)
        mode_before=self.calibration.mode
        self.calibration.tick(now,observed,self.endpoints,self.states)
        if mode_before is not None:
            self.calibration_notice=self.calibration.notice
        if (mode_before=="up" and self.calibration.mode is None
                and all(f"{hand}: calibrated" in self.calibration.notice for hand in ("L","R"))):
            try:
                # Write atomically so an interrupted save cannot truncate a profile.
                pending=CALIBRATION_PATH.with_suffix('.json.tmp')
                pending.write_text(json.dumps(self.endpoints,indent=2)+"\n")
                pending.replace(CALIBRATION_PATH)
                self.calibration_notice="Finger calibration saved. Lower both fingers, then Space to start."
            except OSError as exc:
                self.calibration_notice="Calibration active this session; could not save it."
                print(f"Could not save calibration: {exc}",file=sys.stderr)
        return events

    def poll(self):
        with self.camera.condition:
            raw=self.camera.frame
            sequence=self.camera.sequence
            stopped=self.camera.stopped
            captured_at=self.camera.captured_at
        if stopped:
            self.error="Camera stopped. Check access, then press R to reconnect."
        if raw is None or sequence==self.sequence:
            return [],self.last_frame
        self.sequence=sequence
        frame=cv2.flip(raw,1) if flick.MIRROR_IMAGE else raw.copy()
        rgb=cv2.cvtColor(frame,cv2.COLOR_BGR2RGB)
        rgb.flags.writeable=False
        timestamp_ms=max(self.last_task_ms+1,int((captured_at-self.started_at)*1000))
        self.last_task_ms=timestamp_ms
        hands=_tracked_hands(self.tracker,self.backend,rgb,timestamp_ms)
        now=time.perf_counter()
        elapsed=now-self.previous_at
        self.previous_at=now
        if elapsed>0:
            self.fps=1/elapsed if self.fps==0 else .85*self.fps+.15/elapsed
        events=self.process_hands(hands,frame,captured_at,now)
        self.last_frame=frame
        return events,frame

    def close(self):
        self.camera.close()
        self.tracker.close()
        self.socket.close()
