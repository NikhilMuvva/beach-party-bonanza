# UDP Protocol v1 — freeze this interface now

**Transport:** UDP IPv4 to `127.0.0.1:4242`; one UTF-8 JSON object per datagram.
Godot listens, Python sends. No webcam frames transmitted.

## Hand position (continuous while detected)
```json
{"v":1,"type":"pose","hand":"L","x":0.35,"y":0.65,"t":123.456}
```
- `hand`: `L` or `R` relative to the PLAYER (mirror image). Validate with real test.
- `x`: 0 at left of mirrored webcam preview, 1 at right.
- `y`: 0 at top of mirrored webcam preview, 1 at bottom.
- Values refer to estimated palm center, not fingertip.
- `t`: Python monotonic time in seconds; diagnostic ONLY, not audio playback time.
- Godot may interpolate hand sprites between position messages.

## Flick event (one event per intentional movement)
```json
{"v":1,"type":"flick","hand":"R","event":"UP","t":123.456}
```
- `event`: `UP` or `DOWN`. One flick = one event. Detector requires return to neutral to rearm.
- UP should hit a seagull, DOWN should hit a wave, when beat timing/lane match.
- Score in Godot on packet receipt using Godot's AUDIO CLOCK plus a tuneable calibration offset. Python and Godot monotonic clock origins are unrelated.
- UDP is not guaranteed delivery. Local UDP is low-overhead but errors/loss remain possible.

## Tracker status (every 0.5 s)
```json
{"v":1,"type":"status","ready":true,"hands":2,"t":123.456}
```
- `ready` means initial 2-second calibration finished.
- `hands` is the currently visible hand count (0, 1, 2).
- If status stops arriving, Godot should show `tracker disconnected` after a short timeout.

## Godot integration
`UDPBridge` is an Autoload Node with these signals:
- `flick_received(hand: String, direction: String)`
- `pose_received(hand: String, position: Vector2)`
- `status_received(is_ready: bool, hands_visible: int)`

Frontend can build the entire gameplay loop with keyboard `UP/DOWN` stand-in before connecting to UDP.
**Do not change keys/port without telling the backend developer.**
