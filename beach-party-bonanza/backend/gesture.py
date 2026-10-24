"""Simple flick detector that does not depend on the webcam or MediaPipe.

Inputs are normalized hand HEIGHTS (0 = bottom of frame, 1 = top).
The neutral position is established by the separate calibration step.
"""
from dataclasses import dataclass


@dataclass
class HandState:
    baseline: float
    armed: bool = True
    last_event_at: float = -1e9
    previous_height: float | None = None
    previous_time: float | None = None


class FlickDetector:
    """Threshold + direction + cooldown + neutral rearming.

    This is intentionally tunable and conservative: holding a hand up cannot
    repeatedly score. Calibrate first, then provide a sample per detected hand.
    """

    def __init__(self, threshold: float = 0.10, neutral_zone: float = 0.045,
                 min_velocity: float = 0.20, cooldown_seconds: float = 0.35):
        self.threshold = threshold
        self.neutral_zone = neutral_zone
        self.min_velocity = min_velocity
        self.cooldown_seconds = cooldown_seconds
        self.states: dict[str, HandState] = {}

    def calibrate(self, baselines: dict[str, float]) -> None:
        self.states = {hand: HandState(float(height)) for hand, height in baselines.items()}

    def forget(self, hand: str) -> None:
        """Reset motion history after tracking loss; preserve resting baseline."""
        if hand in self.states:
            state = self.states[hand]
            state.armed = False
            state.previous_height = None
            state.previous_time = None

    def update(self, hand: str, height: float, now: float) -> str | None:
        """Return UP/DOWN for a new flick, or None."""
        state = self.states.get(hand)
        if state is None:
            return None
        offset = height - state.baseline
        if abs(offset) <= self.neutral_zone:
            state.armed = True

        velocity = 0.0
        if state.previous_time is not None and now > state.previous_time:
            dt = now - state.previous_time
            if dt <= 0.25:
                velocity = (height - state.previous_height) / dt
        state.previous_height = height
        state.previous_time = now

        if not state.armed or now - state.last_event_at < self.cooldown_seconds:
            return None
        if offset >= self.threshold and velocity >= self.min_velocity:
            event = "UP"
        elif offset <= -self.threshold and velocity <= -self.min_velocity:
            event = "DOWN"
        else:
            return None
        state.armed = False
        state.last_event_at = now
        return event
