extends SceneTree

# Touching a sentry opens a surprise window instead of failing the run.
# Scenarios run one after another, each in a fresh level:
#   escape   - the player touches, runs during the window, is never caught
#   linger   - the player stays in reach, the sentry alerts when the window ends
#   caught   - an alerted sentry in catch range fails the player at once

const SENTRY_POSITION := Vector2.ZERO
# Beside the body capsule centre (0, -8), well inside touch_distance.
const TOUCH_POSITION := Vector2(6, -8)
const ESCAPE_POSITION := Vector2(120, -8)
const CATCH_POSITION := Vector2(4, 0)
const ESCAPE_AT := 0.3
const SCENARIOS: Array[String] = ["escape", "linger", "caught"]

var _scenario_index := -1
var _level: Node2D
var _sentry: Node2D
var _player: Node2D
var _elapsed := 0.0
var _frames := 0
var _surprised_at := -1.0
var _alerted_at := -1.0
var _caught_frame := -1
var _escaped := false
var _exclamation_during_surprise := false
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_next_scenario")


func _next_scenario() -> void:
	if is_instance_valid(_level):
		root.remove_child(_level)
		_level.queue_free()
	_scenario_index += 1
	if _scenario_index >= SCENARIOS.size():
		_finish()
		return
	_elapsed = 0.0
	_frames = 0
	_surprised_at = -1.0
	_alerted_at = -1.0
	_caught_frame = -1
	_escaped = false
	_exclamation_during_surprise = false

	_level = Node2D.new()
	root.add_child(_level)

	var paths := Node2D.new()
	paths.add_to_group("Sentry1")
	var waypoint := Marker2D.new()
	waypoint.set_script(load("res://assets/scripts/Waypoint2D.gd"))
	paths.add_child(waypoint)
	_level.add_child(paths)

	_player = Node2D.new()
	_player.add_to_group("player")
	_player.position = CATCH_POSITION if _scenario() == "caught" else TOUCH_POSITION
	_level.add_child(_player)

	_sentry = (load("res://assets/scenes/characters/sentry.tscn") as PackedScene).instantiate()
	_sentry.position = SENTRY_POSITION
	_sentry.idle_task = _sentry.IdleTasks.WAIT
	if _scenario() == "caught":
		_sentry.alertness_value = 1.0
	_level.add_child(_sentry)
	(_sentry.get_node("RigidBody2D") as RigidBody2D).freeze = true
	# Face away so only the touch, not sight, drives the sentry.
	_sentry.set_vision_direction(Vector2.LEFT)
	_sentry.player_surprised.connect(func(_s: Node) -> void: _surprised_at = _elapsed)
	_sentry.player_caught.connect(func(_c: Node) -> void: _caught_frame = _frames)


func _scenario() -> String:
	return SCENARIOS[_scenario_index]


func _physics_process(delta: float) -> bool:
	if _scenario_index < 0 or _scenario_index >= SCENARIOS.size() or not is_instance_valid(_sentry):
		return false
	_elapsed += delta
	_frames += 1
	var alerted: bool = _sentry.alertness_state == _sentry.AlertnessState.ALERTED
	if alerted and _alerted_at < 0.0:
		_alerted_at = _elapsed
	if _sentry.is_surprised() and (_sentry.get_node("Emotes/Exclamation") as CanvasItem).visible:
		_exclamation_during_surprise = true
	match _scenario():
		"escape":
			_run_escape()
		"linger":
			_run_linger()
		"caught":
			_run_caught()
	return false


func _run_escape() -> void:
	if not _escaped and _elapsed >= ESCAPE_AT:
		_escaped = true
		if not _sentry.is_surprised():
			_failures.append("escape: no surprise window open %ss after the touch" % ESCAPE_AT)
		if _alerted_at >= 0.0:
			_failures.append("escape: alerted before the window ended")
		_player.global_position = ESCAPE_POSITION
	if _elapsed < 1.5:
		return
	if _surprised_at < 0.0:
		_failures.append("escape: touch did not start a surprise")
	if not _exclamation_during_surprise:
		_failures.append("escape: no surprise cue shown")
	if _alerted_at >= 0.0:
		_failures.append("escape: sentry alerted although the player ran")
	if _caught_frame >= 0:
		_failures.append("escape: player was caught")
	if _sentry.is_surprised():
		_failures.append("escape: surprise window never closed")
	if _sentry.alertness_state != _sentry.AlertnessState.SUSPICIOUS:
		_failures.append(
			(
				"escape: expected SUSPICIOUS after escape, got %s"
				% _sentry.AlertnessState.find_key(_sentry.alertness_state)
			)
		)
	print("SURPRISE escape surprised_at=%s alerted_at=%s" % [_surprised_at, _alerted_at])
	call_deferred("_next_scenario")
	_sentry = null


func _run_linger() -> void:
	var window: float = _sentry.surprise_duration
	if _alerted_at >= 0.0:
		var after_touch := _alerted_at - _surprised_at
		if after_touch < window - 0.05 or after_touch > window + 0.1:
			_failures.append(
				"linger: alerted %ss after the touch, expected about %ss" % [after_touch, window]
			)
		if _surprised_at < 0.0:
			_failures.append("linger: alerted without a surprise window")
		print("SURPRISE linger surprised_at=%s alerted_at=%s" % [_surprised_at, _alerted_at])
		# Leave before the chase reaches catch range; the catch is pinned separately.
		_player.global_position = ESCAPE_POSITION * 10.0
		call_deferred("_next_scenario")
		_sentry = null
		return
	if _elapsed > window + 0.5:
		_failures.append("linger: window ended with the player in reach but no alert")
		call_deferred("_next_scenario")
		_sentry = null


func _run_caught() -> void:
	if _caught_frame >= 0 or _frames > 10:
		if _caught_frame < 0:
			_failures.append("caught: alerted sentry in catch range never caught the player")
		elif _caught_frame > 2:
			_failures.append("caught: catch took %s physics frames" % _caught_frame)
		if _surprised_at >= 0.0:
			_failures.append("caught: an alerted sentry opened a surprise window")
		print("SURPRISE caught frame=%s" % _caught_frame)
		call_deferred("_next_scenario")
		_sentry = null


func _finish() -> void:
	if _failures.is_empty():
		print("SURPRISE all scenarios passed")
		quit(0)
	else:
		push_error(", ".join(_failures))
		quit(1)
