extends SceneTree

var _phase := 0
var _sentry: Node2D
var _handler: Node
var _fake: Node2D
var _start_x := 0.0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var level := Node2D.new()
	level.name = "PinLevel"
	root.add_child(level)

	var paths := Node2D.new()
	paths.name = "Paths_1"
	paths.add_to_group("Sentry1")
	var waypoint_script := load("res://assets/scripts/Waypoint2D.gd")
	var first := Marker2D.new()
	first.set_script(waypoint_script)
	first.position = Vector2(200, 0)
	first.action = "walk"
	paths.add_child(first)
	var second := Marker2D.new()
	second.set_script(waypoint_script)
	second.position = Vector2(200, 80)
	second.action = "walk"
	paths.add_child(second)
	level.add_child(paths)

	_sentry = (load("res://assets/scenes/characters/sentry.tscn") as PackedScene).instantiate()
	_sentry.position = Vector2(0, 0)
	level.add_child(_sentry)
	_start_x = _sentry.global_position.x

	_handler = (load("res://assets/scenes/characters/player_detection_handler.gd") as GDScript).new()
	level.add_child(_handler)

	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node2D\nsignal player_detected(detector, detection_level)\nsignal player_detection_lost(detector)\n"
	if fake_script.reload() != OK:
		_fail("fake sentry script failed to reload")
		quit(1)
		return
	_fake = Node2D.new()
	_fake.set_script(fake_script)
	_fake.add_to_group("sentry")
	level.add_child(_fake)


func _process(_delta: float) -> bool:
	_phase += 1
	if _phase == 20:
		_check_patrol()
	elif _phase == 22:
		_fake.player_detected.emit(_fake, 0.4)
	elif _phase == 23:
		_check_detect()
		_fake.player_detection_lost.emit(_fake)
	elif _phase == 24:
		_check_lost()
		_check_alertness()
		_finish()
	return false


func _check_patrol() -> void:
	if _sentry.global_position.x <= _start_x + 1.0:
		_fail("patrol did not move +x, x=%s start=%s" % [_sentry.global_position.x, _start_x])
	if absf(_sentry.global_position.y) > 0.01:
		_fail("patrol drifted on y, y=%s" % _sentry.global_position.y)
	if _sentry.idle_task != _sentry.IdleTasks.PATROL:
		_fail("patrol idle_task is %s" % _sentry.IdleTasks.keys()[_sentry.idle_task])
	if not is_equal_approx(_sentry.suspicion_threshold, 0.3):
		_fail("suspicion_threshold is %s" % _sentry.suspicion_threshold)


func _check_detect() -> void:
	if _handler.get_child_count() != 1:
		_fail("detect child count %s" % _handler.get_child_count())
		return
	var arrow := _handler.get_child(0)
	if not is_equal_approx(arrow.detection_level, 0.4):
		_fail("arrow level %s" % arrow.detection_level)


func _check_lost() -> void:
	if _handler.get_child_count() != 0:
		_fail("lost child count %s" % _handler.get_child_count())


func _check_alertness() -> void:
	_sentry.alertness_value = 0.5
	_sentry.update_alertness()
	if _sentry.alertness_state != _sentry.AlertnessState.SUSPICIOUS:
		_fail("alertness_state %s" % _sentry.AlertnessState.keys()[_sentry.alertness_state])
	if not _sentry.question_mark.visible:
		_fail("question mark hidden at suspicion")
	if _sentry.idle_task != _sentry.IdleTasks.WAIT:
		_fail("surprise idle_task %s" % _sentry.IdleTasks.keys()[_sentry.idle_task])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIN ok patrol_x=%s suspicion=%s" % [_sentry.global_position.x, _sentry.suspicion_threshold])
		quit(0)
	else:
		print("PIN failed %s" % ", ".join(_failures))
		quit(1)
