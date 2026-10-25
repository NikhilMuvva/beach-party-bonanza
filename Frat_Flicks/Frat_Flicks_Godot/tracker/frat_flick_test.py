#!/usr/bin/env python3
"""Standalone two-finger frat-flick tester. No game, music, scoring or UDP.

Mac setup (once, in the folder containing this file):
    python3.11 -m venv .venv311
    source .venv311/bin/activate
    python -m pip install numpy==1.26.4 opencv-contrib-python==4.11.0.86 mediapipe==0.10.21
    python frat_flick_test.py

Later: activate that same environment and run this file again.
Use Python 3.11 or 3.12, not 3.14, for these pinned dependencies.

Controls: D = capture lowered pose; U = capture raised pose; R = clear counts
and require a fresh lowered pose; Q/Esc = quit. Capture D first, then U.
Calibration is session-only. The resulting values print to the terminal so
that you can paste them into POSE_ENDPOINTS below if you want to keep them.

A physical LEFT upward flick emits WAVE; RIGHT upward flick emits SEAGULL.
Both fingers must lower to rearm. Holding UP, lowering, moving the arm, and
first appearing with fingers UP do not emit inputs. Each hand is independent.
The 55% pose match and 74% travel values are geometric tuning scores, not
statistically measured recognition accuracy. Camera confidence is separate.

Optional: --camera 1, --swap-hands (if physical hand labels are reversed),
--video path.mp4, --headless (video only), --self-test (no packages required).
"""
from __future__ import annotations

# =========================== EDIT VALUES HERE ============================
CAMERA_INDEX = 0
CAMERA_WIDTH = 960
CAMERA_HEIGHT = 540
CAMERA_FPS = 30
MIRROR_IMAGE = True              # Mirror BEFORE MediaPipe for physical L/R.
SWAP_HAND_LABELS = False         # Only change if the physical L/R labels are wrong.

TRIGGER_PROGRESS = 0.74          # Average index+middle progress; forgiving camera input.
MIN_EACH_FINGER_MATCH = 0.55      # BOTH fingers must individually reach this.
RESET_PROGRESS = 0.40            # BOTH fingers below this = lowered/reset.
RESET_HOLD_MS = 60               # Brief stable reset; rejects one-frame glitches.
UP_CONFIRM_MS = 0               # 0 = fire at crossing, no extra pose-hold delay.
COOLDOWN_MS = 180                # Independent per hand; still requires reset.
TRACKING_GAP_MS = 180            # Longer loss disarms; must lower again.
MAX_FLICK_SECONDS = 1.0          # Raise time after leaving reset; 0 disables timeout.
SMOOTHING_MS = 18               # Small time-based filter; 0 disables it.

MIN_DETECTION_CONFIDENCE = 0.60
MIN_TRACKING_CONFIDENCE = 0.60
MIN_HANDEDNESS_CONFIDENCE = 0.65
MIN_PALM_PIXELS = 24             # Reject hands too small for useful measurements.
MODEL_COMPLEXITY = 1

# Each tuple contains (INDEX score, MIDDLE score). These are raw geometric
# measurements, NOT percentages. D/U captures show your personalized values.
# World-space palm-relative measurements reject translation/rotation/scale
# of the whole hand. Thumb, ring and pinky positions do not gate the input.
POSE_ENDPOINTS = {
    "L": {"down": (0.08, 0.00), "up": (0.70, 0.70)},
    "R": {"down": (0.08, 0.00), "up": (0.70, 0.70)},
}
CALIBRATION_COUNTDOWN_SEC = 1.5
CALIBRATION_CAPTURE_SEC = 0.8
CALIBRATION_MIN_SAMPLES = 6
CALIBRATION_MIN_RANGE = 0.25     # Reject similar down/up captures.
# =========================================================================

import argparse
from dataclasses import dataclass
import json
import math
from pathlib import Path
import statistics
import sys
import time

ACTIONS = {"L": "WAVE", "R": "SEAGULL"}
CONNECTIONS = ((0,1),(1,2),(2,3),(3,4),(0,5),(5,6),(6,7),(7,8),
               (5,9),(9,10),(10,11),(11,12),(9,13),(13,14),(14,15),
               (15,16),(13,17),(17,18),(18,19),(19,20),(0,17),(5,17))


def clamp(x, low=0.0, high=1.0):
    return max(low, min(high, x))


def subtract(a, b):
    return tuple(x-y for x,y in zip(a,b))


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def norm(v):
    return math.sqrt(dot(v,v))


def raw_finger_scores(points):
    """Measure BOTH fingers in the hand's own coordinate system.

    Points are MediaPipe WORLD landmarks in metres. Each score combines the
    fingertip's projection along wrist->knuckle (65%) with PIP straightness
    (35%). All lengths are normalized to finger length. No screen-y velocity
    is used, so moving the arm alone cannot cause an input mathematically.
    """
    if len(points) != 21 or any(len(point) != 3 or not all(math.isfinite(v) for v in point) for point in points):
        return None
    scores = []
    for mcp, pip, dip, tip in ((5,6,7,8), (9,10,11,12)):
        axis = subtract(points[mcp], points[0])
        axis_length = norm(axis)
        chain = sum(norm(subtract(points[b],points[a]))
                    for a,b in ((mcp,pip),(pip,dip),(dip,tip)))
        a, b = subtract(points[mcp], points[pip]), subtract(points[dip],points[pip])
        denom = norm(a)*norm(b)
        if min(axis_length, chain, denom) < 1e-9:
            return None
        projection = dot(subtract(points[tip], points[mcp]), axis) / axis_length / chain
        angle = math.degrees(math.acos(clamp(dot(a,b)/denom, -1, 1)))
        straightness = clamp((angle-45.0)/135.0)
        scores.append(0.65*projection + 0.35*straightness)
    return tuple(scores)


def normalize_scores(raw, endpoints):
    return tuple(clamp((value-down)/(up-down))
                 for value,down,up in zip(raw,endpoints['down'],endpoints['up']))


@dataclass
class FlickState:
    count: int = 0
    armed: bool = False
    down_since: float | None = None
    up_since: float | None = None
    rise_since: float | None = None
    last_seen: float | None = None
    last_fire: float = -1000.0
    progress: tuple | None = None
    status: str = "LOWER BOTH FINGERS"
    flash_until: float = 0.0

    def disarm(self, message="LOWER BOTH FINGERS"):
        self.armed = False
        self.down_since = self.up_since = self.rise_since = None
        self.progress = None
        self.last_seen = None
        self.status = message

    def missing(self, now):
        if self.last_seen is None or now-self.last_seen > TRACKING_GAP_MS/1000:
            self.disarm("HAND NOT VISIBLE")

    def update(self, progress, now):
        previous = self.last_seen
        if previous is not None and now-previous > TRACKING_GAP_MS/1000:
            self.disarm()
            previous = None
        if self.progress is None or previous is None or SMOOTHING_MS <= 0:
            self.progress = progress
        else:
            alpha = 1-math.exp(-max(0,now-previous)/(SMOOTHING_MS/1000))
            self.progress = tuple(a+alpha*(b-a) for a,b in zip(self.progress,progress))
        self.last_seen = now
        index, middle = self.progress
        if max(index,middle) <= RESET_PROGRESS:
            self.up_since = self.rise_since = None
            if self.down_since is None:
                self.down_since = now
            if now-self.down_since+1e-9 >= RESET_HOLD_MS/1000:
                self.armed = True
                self.status = "ARMED - FLICK UP"
            else:
                self.status = "RESETTING"
            return False
        self.down_since = None
        if not self.armed:
            self.status = "LOWER BOTH TO RESET"
            return False
        if self.rise_since is None:
            self.rise_since = now
        if MAX_FLICK_SECONDS > 0 and now-self.rise_since > MAX_FLICK_SECONDS:
            self.disarm("TOO SLOW - LOWER TO RESET")
            # Keep last_seen current but discard filter/history across disarm.
            self.last_seen = now
            return False
        match = min(index,middle) >= MIN_EACH_FINGER_MATCH
        raised = (index+middle)/2 >= TRIGGER_PROGRESS
        self.status = "RAISING BOTH FINGERS"
        if not (match and raised):
            self.up_since = None
            return False
        if self.up_since is None:
            self.up_since = now
        if now-self.up_since+1e-9 < UP_CONFIRM_MS/1000:
            return False
        # Consume the upward transition even inside cooldown. It must not fire
        # later just because the fingers stayed raised until cooldown expired.
        self.armed = False
        self.up_since = self.rise_since = None
        if now-self.last_fire < COOLDOWN_MS/1000:
            self.status = "COOLDOWN - LOWER TO RESET"
            return False
        self.last_fire = now
        self.flash_until = now+0.45
        self.count += 1
        self.status = "FLICK UP - INPUT"
        return True


class Calibration:
    def __init__(self):
        self.mode = None
        self.start = 0.0
        self.samples = {h: [] for h in ACTIONS}
        self.down_captured = set()
        self.notice = "D: capture DOWN, then U: capture UP (optional)"

    def begin(self, mode, now, states):
        self.mode, self.start = mode, now
        self.samples = {h: [] for h in ACTIONS}
        self.notice = ""
        for state in states.values():
            state.disarm()

    def tick(self, now, observed, endpoints, states):
        if self.mode is None:
            return
        elapsed = now-self.start
        if elapsed < CALIBRATION_COUNTDOWN_SEC:
            self.notice = f"HOLD BOTH FINGERS {self.mode.upper()} - capture in {CALIBRATION_COUNTDOWN_SEC-elapsed:.1f}s"
            return
        if elapsed < CALIBRATION_COUNTDOWN_SEC+CALIBRATION_CAPTURE_SEC:
            self.notice = f"CAPTURING {self.mode.upper()} - keep fingers still"
            for hand,raw in observed.items():
                self.samples[hand].append(raw)
            return
        notes = []
        for hand, samples in self.samples.items():
            if len(samples) < CALIBRATION_MIN_SAMPLES:
                notes.append(f"{hand}: too few samples; repeat {self.mode.upper()}")
                continue
            values = tuple(statistics.median(s[i] for s in samples) for i in (0,1))
            if self.mode == "down":
                # Keep valid ranges while capturing a new down endpoint.
                endpoints[hand]['down'] = values
                endpoints[hand]['up'] = tuple(max(old,v+0.5) for old,v in zip(endpoints[hand]['up'],values))
                self.down_captured.add(hand)
                notes.append(f"{hand}: DOWN saved; now capture U")
            elif hand not in self.down_captured:
                notes.append(f"{hand}: capture D first")
            elif any(up-down < CALIBRATION_MIN_RANGE for up,down in zip(values,endpoints[hand]['down'])):
                notes.append(f"{hand}: poses too similar; repeat D then U")
            else:
                endpoints[hand]['up'] = values
                notes.append(f"{hand}: calibrated")
        self.notice = " | ".join(notes)
        print(self.notice, file=sys.stderr)
        print("# Session POSE_ENDPOINTS (paste at top to keep):\nPOSE_ENDPOINTS = " + repr(endpoints), file=sys.stderr, flush=True)
        self.mode = None
        for state in states.values():
            state.disarm()


def validate_settings():
    if not (0 <= RESET_PROGRESS < MIN_EACH_FINGER_MATCH <= TRIGGER_PROGRESS <= 1):
        raise ValueError("Require RESET_PROGRESS < MIN_EACH_FINGER_MATCH <= TRIGGER_PROGRESS <= 1")
    for hand,endpoints in POSE_ENDPOINTS.items():
        if len(endpoints['down']) != 2 or len(endpoints['up']) != 2:
            raise ValueError(f"{hand}: supply exactly two values: index and middle")
        if any(u-d < CALIBRATION_MIN_RANGE for d,u in zip(endpoints['down'],endpoints['up'])):
            raise ValueError(f"{hand}: each UP endpoint must exceed DOWN by at least {CALIBRATION_MIN_RANGE}")


def load_dependencies():
    try:
        import cv2
        import mediapipe as mp
        import numpy as np
    except ImportError as exc:
        raise RuntimeError(
            f"Missing camera dependencies in {sys.executable}.\n"
            "Use Python 3.11/3.12 and the setup commands at the top of this file.\n"
            "Install: python -m pip install numpy==1.26.4 opencv-contrib-python==4.11.0.86 mediapipe==0.10.21"
        ) from exc
    if not hasattr(mp, 'solutions') or not hasattr(mp.solutions, 'hands'):
        raise RuntimeError("This single-file tester uses MediaPipe 0.10.21. Install the pinned versions shown at the top of the file.")
    return cv2, mp, np


def draw_ui(cv2, np, frame, states, labels, fps, notice):
    # An intentionally simple test monitor; no game UI/assets are required.
    h,w = frame.shape[:2]
    scale = min(960/w,540/h)
    size = (max(1,round(w*scale)),max(1,round(h*scale)))
    camera = np.full((540,960,3),(12,12,12),np.uint8)
    x,y = (960-size[0])//2,(540-size[1])//2
    camera[y:y+size[1],x:x+size[0]] = cv2.resize(frame,size)
    canvas = np.full((800,960,3), (24,20,16), np.uint8)
    canvas[80:620] = camera
    font = cv2.FONT_HERSHEY_SIMPLEX
    def text(s,x,y,size=.55,color=(230,232,234)):
        cv2.putText(canvas,s,(x,y),font,size,color,1,cv2.LINE_AA)
    text("TWO-FINGER FLICK TEST",24,32,.75)
    text("LEFT = WAVE     RIGHT = SEAGULL     UPWARD FLICKS ONLY",24,60)
    text(f"{fps:.0f} FPS",856,32)
    now = labels['now']
    for hand,x in (("L",24),("R",496)):
        state = states[hand]
        color = (166,220,137) if now<state.flash_until else (213,203,113)
        text(f"{hand} / {ACTIONS[hand]}    INPUTS {state.count}",x,652,.62,color)
        text(state.status,x,680,.48)
        values = state.progress or (0,0)
        for i,name in enumerate(("INDEX","MIDDLE")):
            y=700+i*24
            text(name,x,y+12,.42)
            cv2.rectangle(canvas,(x+72,y),(x+344,y+12),(65,65,65),-1)
            cv2.rectangle(canvas,(x+72,y),(x+72+round(272*values[i]),y+12),color,-1)
            # Per-finger 55% line; average 74% still gates the final event.
            marker=x+72+round(272*MIN_EACH_FINGER_MATCH)
            cv2.line(canvas,(marker,y-2),(marker,y+14),(230,232,234),1)
            text(f"{values[i]*100:3.0f}%",x+360,y+12,.42)
    text(f"Trigger: avg {TRIGGER_PROGRESS:.0%} + each {MIN_EACH_FINGER_MATCH:.0%} | D: down  U: up  R: reset  Q: quit",24,768,.46)
    text(notice[:125],24,792,.42,(170,180,195))
    return canvas


def run(args):
    cv2,mp,np = load_dependencies()
    capture = cv2.VideoCapture(str(args.video) if args.video else args.camera)
    if not capture.isOpened():
        capture.release()
        raise RuntimeError("Camera/video unavailable. On Mac, allow Terminal or VS Code in System Settings > Privacy & Security > Camera. Try --camera 1 for another camera.")
    if not args.video:
        capture.set(cv2.CAP_PROP_FRAME_WIDTH,CAMERA_WIDTH)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT,CAMERA_HEIGHT)
        capture.set(cv2.CAP_PROP_FPS,CAMERA_FPS)
        capture.set(cv2.CAP_PROP_BUFFERSIZE,1)
    tracker = None
    states = {h:FlickState() for h in ACTIONS}
    endpoints = {h:dict(e) for h,e in POSE_ENDPOINTS.items()}
    calibration = Calibration()
    frame_number = 0
    source_fps = capture.get(cv2.CAP_PROP_FPS) or 30
    previous = time.perf_counter()
    session_start = previous
    fps = 0.0
    try:
        tracker = mp.solutions.hands.Hands(max_num_hands=2,model_complexity=MODEL_COMPLEXITY,
                    min_detection_confidence=MIN_DETECTION_CONFIDENCE,
                    min_tracking_confidence=MIN_TRACKING_CONFIDENCE)
        if not args.headless:
            cv2.namedWindow("Frat Flick Test",cv2.WINDOW_NORMAL)
            cv2.resizeWindow("Frat Flick Test",960,800)
        while True:
            frame_start = time.perf_counter()
            ok, frame = capture.read()
            if not ok:
                if not args.video:
                    raise RuntimeError("Camera stopped returning frames. Close other camera apps and run again.")
                break
            now = frame_number/source_fps if args.video else time.perf_counter()-session_start
            frame_number += 1
            if MIRROR_IMAGE:
                frame = cv2.flip(frame,1)
            rgb = cv2.cvtColor(frame,cv2.COLOR_BGR2RGB)
            rgb.flags.writeable = False
            result = tracker.process(rgb)
            # Reject duplicate labels: one physical hand must never be counted
            # twice because the model mislabeled the other hand in this frame.
            candidates = {}
            for j,label in enumerate(result.multi_handedness or []):
                classified = label.classification[0]
                hand = 'L' if classified.label=='Left' else 'R'
                if args.swap_hands:
                    hand = 'R' if hand=='L' else 'L'
                if classified.score < MIN_HANDEDNESS_CONFIDENCE:
                    continue
                if hand not in candidates or classified.score > candidates[hand][0]:
                    candidates[hand] = (classified.score,j)
            observed = {}
            for hand,(_,j) in candidates.items():
                lm = result.multi_hand_landmarks[j].landmark
                world = result.multi_hand_world_landmarks[j].landmark
                h,w = frame.shape[:2]
                palm_pixels = math.hypot((lm[5].x-lm[17].x)*w,(lm[5].y-lm[17].y)*h)
                if palm_pixels < MIN_PALM_PIXELS:
                    continue
                raw = raw_finger_scores([(p.x,p.y,p.z) for p in world])
                if raw is None:
                    continue
                observed[hand] = raw
                if calibration.mode is None:
                    if states[hand].update(normalize_scores(raw,endpoints[hand]),now):
                        print(json.dumps({'hand':hand,'gesture':'UP','action':ACTIONS[hand],
                                          'count':states[hand].count,'time_sec':round(now,3)}),flush=True)
                points = [(int(p.x*w),int(p.y*h)) for p in lm]
                for a,b in CONNECTIONS:
                    cv2.line(frame,points[a],points[b],(90,170,170),1)
                for p in (5,6,7,8,9,10,11,12):
                    cv2.circle(frame,points[p],4,(130,225,150),-1)
                x,y=points[0]
                x=max(0,min(w-180,x));y=max(24,min(h-12,y+24))
                cv2.putText(frame,f"{hand} / {ACTIONS[hand]}",(x,y),cv2.FONT_HERSHEY_SIMPLEX,.6,(0,0,0),3,cv2.LINE_AA)
                cv2.putText(frame,f"{hand} / {ACTIONS[hand]}",(x,y),cv2.FONT_HERSHEY_SIMPLEX,.6,(240,240,240),1,cv2.LINE_AA)
            for hand in states:
                if hand not in observed:
                    states[hand].missing(now)
            calibration.tick(now,observed,endpoints,states)
            current = time.perf_counter()
            instant = 1/max(1e-6,current-previous)
            fps = instant if not fps else .9*fps+.1*instant
            previous = current
            if not args.headless:
                panel = draw_ui(cv2,np,frame,states,{'now':now},fps,calibration.notice)
                cv2.imshow("Frat Flick Test",panel)
                key = cv2.waitKey(max(1,round(1000/source_fps-(time.perf_counter()-frame_start)*1000)) if args.video else 1) & 0xff
                if key in (ord('q'),27):
                    break
                if cv2.getWindowProperty("Frat Flick Test",cv2.WND_PROP_VISIBLE)<1:
                    break
                if key in (ord('d'),ord('u')):
                    calibration.begin('down' if key==ord('d') else 'up',now,states)
                if key==ord('r'):
                    for state in states.values():
                        state.disarm();state.count=0;state.last_fire=-1000;state.flash_until=0
        print("Inputs: "+", ".join(f"{h}/{ACTIONS[h]}={s.count}" for h,s in states.items()),file=sys.stderr)
    finally:
        capture.release()
        if tracker is not None:
            tracker.close()
        if not args.headless:
            cv2.destroyAllWindows()


def self_test():
    """Real state-machine + geometry checks; uses only the standard library."""
    import unittest
    class Tests(unittest.TestCase):
        def arm(self,s,t=0):
            s.update((0,0),t);s.update((0,0),t+.1)
            self.assertTrue(s.armed)
        def test_start_up_does_not_trigger(self):
            s=FlickState()
            for i in range(20):self.assertFalse(s.update((1,1),i*.05))
            self.assertEqual(s.count,0)
        def test_one_per_cycle_and_no_down_event(self):
            s=FlickState();self.arm(s)
            self.assertTrue(s.update((1,1),.2))
            for i in range(10):self.assertFalse(s.update((1,1),.3+i*.1))
            self.assertFalse(s.update((0,0),1.5));self.assertFalse(s.update((0,0),1.6))
            self.assertTrue(s.update((1,1),1.75));self.assertEqual(s.count,2)
        def test_both_fingers_required(self):
            s=FlickState();self.arm(s)
            self.assertFalse(s.update((1,.4),.3));self.assertEqual(s.count,0)
        def test_partial_reset_does_not_rearm(self):
            s=FlickState();self.arm(s);s.update((1,1),.2)
            for i in range(8):s.update((0,1),.3+i*.05)
            self.assertFalse(s.armed);self.assertFalse(s.update((1,1),.8))
        def test_loss_requires_reset(self):
            s=FlickState();self.arm(s);s.missing(.5)
            self.assertFalse(s.update((1,1),.6));self.assertFalse(s.armed)
        def test_independent_simultaneous_hands(self):
            l,r=FlickState(),FlickState();self.arm(l);self.arm(r)
            self.assertTrue(l.update((1,1),.25));self.assertTrue(r.update((1,1),.25))
            self.assertEqual(ACTIONS,{'L':'WAVE','R':'SEAGULL'})
        def test_cooldown_does_not_emit_later(self):
            s=FlickState();self.arm(s);s.update((1,1),.2)
            s.update((0,0),.22);s.update((0,0),.30)
            self.assertFalse(s.update((1,1),.32));self.assertFalse(s.update((1,1),.6))
            self.assertEqual(s.count,1)
        def test_timeout_requires_lowering(self):
            s=FlickState();self.arm(s);s.update((.5,.5),.2)
            self.assertFalse(s.update((1,1),1.3));self.assertFalse(s.armed)
        def test_early_threshold_without_perfect_pose(self):
            s=FlickState();self.arm(s)
            self.assertTrue(s.update((.90,.90),.25))
        def test_geometry_translation_rotation_scale_invariance(self):
            points=[(0.,0.,0.)]*21
            for m,p,d,t,x in ((5,6,7,8,-.02),(9,10,11,12,.02)):
                points[m]=(x,.06,0);points[p]=(x,.09,0)
                points[d]=(x,.11,.005);points[t]=(x,.13,.008)
            base=raw_finger_scores(points)
            transformed=[(3-2*y,4+2*x,5+2*z) for x,y,z in points]
            for a,b in zip(base,raw_finger_scores(transformed)):
                self.assertAlmostEqual(a,b,places=10)
        def test_static_arm_motion_never_fires(self):
            s=FlickState();self.arm(s)
            for i in range(30):self.assertFalse(s.update((0,0),.2+i*.02))
            self.assertEqual(s.count,0)
    outcome=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    return 0 if outcome.wasSuccessful() else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--camera',type=int,default=CAMERA_INDEX)
    parser.add_argument('--swap-hands',action='store_true',default=SWAP_HAND_LABELS)
    parser.add_argument('--video',type=Path)
    parser.add_argument('--headless',action='store_true')
    parser.add_argument('--self-test',action='store_true')
    args=parser.parse_args()
    if args.headless and not args.video:
        parser.error('--headless is for --video testing; webcam mode shows the monitor')
    try:
        validate_settings()
        if args.self_test:
            return self_test()
        run(args)
        return 0
    except (RuntimeError,ValueError) as exc:
        print(str(exc),file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0


if __name__=='__main__':
    raise SystemExit(main())
