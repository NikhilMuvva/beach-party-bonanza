"""Synthetic world landmarks exercise the real detector without a webcam."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace as NS
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tracker"))
import numpy as np
import frat_flick_test as flick
import hand_tracker as ht
from service import valid_message


def observation(label, raised=False, translate=0):
    image = [NS(x=.5, y=.65, z=0) for _ in range(21)]
    image[5].x = .35
    image[17].x = .65
    points = [(0., 0., 0.)] * 21
    for m, p, d, t, x in ((5, 6, 7, 8, -.02), (9, 10, 11, 12, .02)):
        points[m] = (x, .06, 0)
        if raised:
            points[p], points[d], points[t] = (x, .09, 0), (x, .11, 0), (x, .13, 0)
        else:
            points[p], points[d], points[t] = (x, .08, 0), (x + .01, .08, 0), (x + .02, .06, 0)
    world = [NS(x=x + translate, y=y + translate, z=z + translate) for x, y, z in points]
    return label, .99, image, world


def make_detector():
    detector = ht.Detector.__new__(ht.Detector)
    detector.states = {h: flick.FlickState() for h in ("L", "R")}
    detector.endpoints = {h: dict(e) for h, e in flick.POSE_ENDPOINTS.items()}
    detector.calibration = flick.Calibration()
    detector.calibration_notice = ""
    detector.hand_positions = {}
    detector.last_y_sent = {"L": 0, "R": 0}
    detector.packets = []
    detector.send = detector.packets.append
    return detector


class TrackerTests(unittest.TestCase):
    def setUp(self):
        self.detector = make_detector()
        self.frame = np.zeros((480, 640, 3), dtype=np.uint8)

    def frame_at(self, t, raised=False, translate=0, labels=("Left", "Right")):
        hands = [observation(label, raised, translate) for label in labels]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return self.detector.process_hands(hands, self.frame, t, t)

    def arm(self):
        self.frame_at(0)
        self.frame_at(.1)

    def test_both_upward_flicks_route_independently_once(self):
        self.arm()
        self.assertEqual(set(self.frame_at(.2, True)), {("DOWN", "L"), ("UP", "R")})
        self.assertEqual(self.frame_at(.3, True), [])
        self.assertEqual([p for p in self.detector.packets if "event" in p],
                         [{"hand": "L", "event": "DOWN"}, {"hand": "R", "event": "UP"}])

    def test_raised_start_and_arm_translation_are_ignored(self):
        for i in range(8):
            self.assertEqual(self.frame_at(i * .03, True, i * .1), [])
        self.frame_at(.3)
        self.frame_at(.4)
        for i in range(8):
            self.assertEqual(self.frame_at(.45 + i * .03, False, i * .2), [])

    def test_lowering_rearms_without_emitting(self):
        self.arm()
        self.assertEqual(len(self.frame_at(.2, True)), 2)
        self.assertEqual(self.frame_at(.3), [])
        self.assertEqual(self.frame_at(.4), [])
        self.assertEqual(len(self.frame_at(.5, True)), 2)

    def test_tracking_loss_and_restart_disarm_held_up(self):
        self.arm()
        self.frame_at(.4, labels=())
        self.assertEqual(self.frame_at(.5, True), [])
        self.frame_at(.6)
        self.frame_at(.7)
        self.detector.reset_flicks()
        self.assertEqual(self.frame_at(.8, True), [])

    def capture(self, mode, base, raised, labels=("Left", "Right")):
        self.detector.calibration.begin(mode, base, self.detector.states)
        for i in range(8):
            self.assertEqual(self.frame_at(base + 1.55 + i * .08, raised, labels=labels), [])
        self.assertEqual(self.frame_at(base + 2.4, raised, labels=labels), [])

    def test_complete_calibration_suppresses_flicks_and_saves(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(ht, "CALIBRATION_PATH", Path(folder) / "profile.json"):
            self.capture("down", 0, False)
            self.capture("up", 3, True)
            self.assertTrue(ht.CALIBRATION_PATH.is_file())
            self.assertTrue(ht.valid_endpoints(json.loads(ht.CALIBRATION_PATH.read_text())))
            self.assertEqual(self.frame_at(5.5, True), [])

    def test_partial_calibration_never_overwrites_profile(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(ht, "CALIBRATION_PATH", Path(folder) / "profile.json"):
            original = json.dumps(flick.POSE_ENDPOINTS)
            ht.CALIBRATION_PATH.write_text(original)
            self.capture("down", 0, False)
            self.capture("up", 3, True, labels=("Left",))
            self.assertEqual(ht.CALIBRATION_PATH.read_text(), original)

    def test_duplicate_handedness_cannot_double_fire(self):
        self.arm()
        self.assertEqual(self.frame_at(.2, True, labels=("Left", "Left")), [("DOWN", "L")])

    def test_corrupted_profiles_rejected(self):
        for bad in (None, {}, {"L": {"down": [0, 0], "up": [float("nan"), 1]}, "R": {"down": [0, 0], "up": [1, 1]}}):
            self.assertFalse(ht.valid_endpoints(bad))

    def test_command_schema(self):
        self.assertTrue(valid_message({"protocol": 1, "command": "capture", "id": "one"}))
        for bad in ([], None, {}, {"protocol": 2, "command": "round", "id": "one"}, {"protocol": 1, "command": 5, "id": "one"}):
            self.assertFalse(valid_message(bad))


if __name__ == "__main__":
    unittest.main()

class ForgivingTrackingTests(unittest.TestCase):
    def test_partial_middle_extension_counts_once(self):
        state = flick.FlickState()
        state.update((.1, .1), 0)
        state.update((.1, .1), .1)
        self.assertTrue(state.update((.95, .58), .2))
        self.assertFalse(state.update((.95, .58), .3))

    def test_index_only_still_cannot_fire(self):
        state = flick.FlickState()
        state.update((0, 0), 0)
        state.update((0, 0), .1)
        for i in range(8):
            self.assertFalse(state.update((1, .4), .2+i*.03))

    def test_stable_partial_lowering_rearms(self):
        state = flick.FlickState()
        state.update((.35, .35), 0)
        state.update((.35, .35), .1)
        self.assertTrue(state.armed)
        self.assertTrue(state.update((.80, .80), .2))

    def test_isolated_middle_outlier_cannot_poison_calibration(self):
        detector = make_detector()
        frame = np.zeros((480,640,3),dtype=np.uint8)
        before = dict(detector.endpoints['L'])
        with patch.object(flick, 'raw_finger_scores', return_value=(.2,.2)):
            for i in range(30):
                detector.process_hands([observation('Left')],frame,i*.03,i*.03)
        with patch.object(flick, 'raw_finger_scores', return_value=(.2,100.0)):
            detector.process_hands([observation('Left')],frame,.91,.91)
        self.assertEqual(detector.endpoints['L'],before)
        self.assertEqual(detector.states['L'].count,0)

    def test_middle_landmarks_are_independent(self):
        low = observation('Left')[3]
        high = observation('Left',True)[3]
        mixed = list(high)
        mixed[9:13] = low[9:13]
        score = flick.raw_finger_scores([(p.x,p.y,p.z) for p in mixed])
        raised = flick.raw_finger_scores([(p.x,p.y,p.z) for p in high])
        self.assertAlmostEqual(score[0],raised[0])
        self.assertLess(score[1],raised[1]-.3)

class InvalidLandmarkTests(unittest.TestCase):
    def test_bad_world_coordinates_rejected(self):
        points=[(0.,0.,0.)]*21
        for value in [float('nan'),float('inf')]:
            bad=list(points);bad[10]=(value,0.,0.)
            self.assertIsNone(flick.raw_finger_scores(bad))
        self.assertIsNone(flick.raw_finger_scores(points[:10]))

    def test_bad_camera_coordinates_do_not_crash_or_emit(self):
        detector=make_detector()
        label,confidence,landmarks,world=observation('Left')
        landmarks[10].x=float('nan')
        result=detector.process_hands([(label,confidence,landmarks,world)],np.zeros((480,640,3),dtype=np.uint8),0.,0.)
        self.assertEqual(result,[])
        self.assertEqual(detector.hand_positions,{})
