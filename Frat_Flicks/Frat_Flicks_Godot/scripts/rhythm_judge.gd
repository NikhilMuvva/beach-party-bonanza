extends RefCounted
## The only scoring authority. All times are seconds on the audible music clock.
## Hand identity, rather than arm direction, selects the lane.

const HIT_WINDOW := 0.300
const FULL_CREDIT_WINDOW := 0.150
const CLOSE_HIT_CREDIT := 0.90
const TRAVEL_TIME := 2.4
const MISS_COST := 0.12
const HIT_GAIN := 0.02
const STRAY_COST := 0.03
const INPUT_COOLDOWN := 0.18
const HAND_LANES := {"L": "down", "R": "up"}

var beats: Array = []
var status := PackedByteArray() # 0 pending; 1 hit; 2 missed
var lane_indices := {"down": [], "up": []}
var heads := {"down": 0, "up": 0}
var miss_pointer := 0
const PERFECT_WINDOW := 0.050
var score := 0
var lane_scores := {"L": 0, "R": 0}
var perfect_streak := 0
var accuracy_credit := 0.0
var pending_misses: Array[int] = []
var stray_flicks := 0
var last_attempt := {"L": -1000.0, "R": -1000.0}
var last_attempt_penalized := false
var hits := 0
var misses := 0
var combo := 0
var best_combo := 0
var vibe := 1.0
var lost := false
var practice := false
var offsets: Array[float] = []

func configure(chart: Array, practice_mode: bool = false) -> bool:
	# Reject the entire chart if any note is malformed; never silently retime it.
	if chart.is_empty():
		return false
	var previous := -1.0
	for value in chart:
		if not value is Dictionary:
			return false
		var time_value: Variant = value.get("t", null)
		if not (time_value is float or time_value is int):
			return false
		var t := float(time_value)
		if not is_finite(t) or t < 0.0 or t < previous or value.get("lane", "") not in ["up", "down"]:
			return false
		previous = t
	beats = chart.duplicate(true)
	practice = practice_mode
	status.resize(beats.size())
	status.fill(0)
	lane_indices = {"down": [], "up": []}
	heads = {"down": 0, "up": 0}
	for i in beats.size():
		lane_indices[beats[i]["lane"]].append(i)
	miss_pointer = 0
	score = 0
	lane_scores = {"L": 0, "R": 0}
	perfect_streak = 0
	accuracy_credit = 0.0
	pending_misses.clear()
	stray_flicks = 0
	last_attempt = {"L": -1000.0, "R": -1000.0}
	last_attempt_penalized = false
	hits = 0
	misses = 0
	combo = 0
	best_combo = 0
	vibe = 1.0
	lost = false
	offsets.clear()
	return true

func expire(judge_time: float) -> Array[int]:
	var expired: Array[int] = []
	if lost:
		return expired
	while miss_pointer < beats.size() and judge_time > float(beats[miss_pointer]["t"]) + HIT_WINDOW + 0.000001:
		var i := miss_pointer
		miss_pointer += 1
		if status[i] != 0:
			continue
		status[i] = 2
		misses += 1
		combo = 0
		perfect_streak = 0
		vibe = maxf(0.0, vibe - MISS_COST)
		expired.append(i)
		pending_misses.append(i)
		if vibe < 0.000001 and not practice:
			lost = true
			break
	return expired

func flick(hand: String, judge_time: float) -> Dictionary:
	last_attempt_penalized = false
	if hand not in HAND_LANES or lost or not is_finite(judge_time):
		return {}
	expire(judge_time)
	if lost:
		return {}
	if judge_time - float(last_attempt[hand]) < INPUT_COOLDOWN - 0.000001:
		return {}
	last_attempt[hand] = judge_time
	var lane: String = HAND_LANES[hand]
	var indices: Array = lane_indices[lane]
	var head: int = heads[lane]
	while head < indices.size() and status[indices[head]] != 0:
		head += 1
	heads[lane] = head
	if head >= indices.size():
		_penalize_stray()
		return {}
	# Wider windows overlap: score the nearest pending wave, not simply the oldest.
	var index := -1
	var nearest := HIT_WINDOW + 0.000001
	for position in range(head, indices.size()):
		var candidate: int = indices[position]
		if status[candidate] != 0:
			continue
		var candidate_offset := judge_time - float(beats[candidate]["t"])
		if candidate_offset < -HIT_WINDOW - 0.000001:
			break
		var distance := absf(candidate_offset)
		if distance <= HIT_WINDOW + 0.000001 and (index == -1 or distance < nearest - 0.000001):
			index = candidate
			nearest = distance
	if index == -1:
		_penalize_stray()
		return {}
	var offset := judge_time - float(beats[index]["t"])
	status[index] = 1
	while head < indices.size() and status[indices[head]] != 0:
		head += 1
	heads[lane] = head
	var perfect := absf(offset) <= PERFECT_WINDOW + 0.000001
	perfect_streak = perfect_streak + 1 if perfect else 0
	var points := 2 if perfect else 1
	score += points
	lane_scores[hand] += points
	var close_hit := absf(offset) > FULL_CREDIT_WINDOW + 0.000001
	var quality := CLOSE_HIT_CREDIT if close_hit else 1.0
	accuracy_credit += quality
	hits += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	vibe = minf(1.0, vibe + HIT_GAIN)
	offsets.append(offset)
	return {"index": index, "offset": offset, "hand": hand, "lane": lane, "points": points, "perfect": perfect, "quality": quality, "close_hit": close_hit}

func _penalize_stray() -> void:
	last_attempt_penalized = true
	stray_flicks += 1
	perfect_streak = 0
	combo = 0
	vibe = maxf(0.0, vibe - STRAY_COST)
	if vibe < 0.000001 and not practice:
		lost = true

func accuracy() -> float:
	return accuracy_credit / maxf(1.0, hits + misses + stray_flicks)

func average_offset_ms() -> float:
	if offsets.is_empty():
		return 0.0
	var total := 0.0
	for value in offsets:
		total += value
	return total * 1000.0 / offsets.size()

func take_misses() -> Array[int]:
	# Both frame expiry and expiry inside flick() share this exactly-once queue.
	var result: Array[int] = pending_misses.duplicate()
	pending_misses.clear()
	return result
