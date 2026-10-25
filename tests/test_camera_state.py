"""Heartbeat freshness tests without opening a real camera."""
from pathlib import Path
import sys
import time
from types import SimpleNamespace
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tracker'))
from service import Service

class CameraStateTests(unittest.TestCase):
    def service(self):
        service = Service.__new__(Service)
        service.detector = SimpleNamespace(
            hand_positions={'L': (.25, .5), 'R': (.75, .5)},
            states={h: SimpleNamespace(armed=True, progress=(0., 0.), status='ready') for h in ('L', 'R')},
            fps=30., error='', calibration=SimpleNamespace(mode=None), calibration_notice='Automatic')
        service.frame_captured = time.perf_counter()
        service.landmarks = {}
        service.error = ''
        service.preview = False
        service.down_done = service.up_done = True
        return service

    def test_fresh_frame_keeps_independent_hands(self):
        packet = self.service().state_packet()
        self.assertEqual(set(packet['hands']), {'L', 'R'})
        self.assertLess(packet['frame_age_ms'], 500)

    def test_stale_frame_clears_hands(self):
        service = self.service()
        service.frame_captured -= 1.
        packet = service.state_packet()
        self.assertEqual(packet['hands'], {})
        self.assertGreater(packet['frame_age_ms'], 500)

    def test_closed_camera_has_no_ready_hands(self):
        service = self.service()
        service.detector = None
        packet = service.state_packet()
        self.assertFalse(packet['camera_ready'])
        self.assertEqual(packet['hands'], {})

if __name__ == '__main__':
    unittest.main()
