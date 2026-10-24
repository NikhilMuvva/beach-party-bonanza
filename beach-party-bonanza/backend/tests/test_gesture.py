import unittest
from backend.gesture import FlickDetector


class FlickDetectorTests(unittest.TestCase):
    def setUp(self):
        self.detector = FlickDetector()
        self.detector.calibrate({"L": 0.50, "R": 0.50})

    def test_up_flick_once_until_rearmed(self):
        self.assertIsNone(self.detector.update("L", 0.50, 1.00))
        self.assertEqual(self.detector.update("L", 0.64, 1.10), "UP")
        self.assertIsNone(self.detector.update("L", 0.70, 1.20))
        self.assertIsNone(self.detector.update("L", 0.50, 1.50))
        self.assertEqual(self.detector.update("L", 0.64, 1.60), "UP")

    def test_down_flick(self):
        self.assertIsNone(self.detector.update("R", 0.50, 1.0))
        self.assertEqual(self.detector.update("R", 0.36, 1.1), "DOWN")

    def test_slow_movement_does_not_trigger(self):
        self.detector.update("L", 0.50, 1.0)
        self.assertIsNone(self.detector.update("L", 0.52, 1.3))
        self.assertIsNone(self.detector.update("L", 0.54, 1.6))
        self.assertIsNone(self.detector.update("L", 0.56, 1.9))
        self.assertIsNone(self.detector.update("L", 0.58, 2.2))
        self.assertIsNone(self.detector.update("L", 0.60, 2.5))

    def test_left_and_right_independent(self):
        self.detector.update("L", 0.50, 1.0)
        self.detector.update("R", 0.50, 1.0)
        self.assertEqual(self.detector.update("L", 0.64, 1.1), "UP")
        self.assertEqual(self.detector.update("R", 0.36, 1.1), "DOWN")

    def test_tracking_loss_requires_neutral_before_next_flick(self):
        self.detector.update("R", 0.50, 1.0)
        self.detector.forget("R")
        self.assertIsNone(self.detector.update("R", 0.65, 1.3))
        self.detector.update("R", 0.50, 1.5)
        self.assertEqual(self.detector.update("R", 0.65, 1.6), "UP")


if __name__ == "__main__":
    unittest.main()
