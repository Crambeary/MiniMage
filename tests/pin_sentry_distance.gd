extends SceneTree

# Two idle sentries watch the same player from different distances.
# The near one must build alertness faster than the far one.

const PLAYER_POSITION := Vector2.ZERO
const NEAR_POSITION := Vector2(-40, 0)
const FAR_POSITION := Vector2(200, -60)
const OUT_OF_SIGHT_POSITION := Vector2(0, 400)
const SAMPLE_TIME := 0.5

var _near: Node2D
var _far: Node2D
var _blind: Node2D
var _elapsed := 0.0


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var level := Node2D.new()
	root.add_child(level)

	var paths := Node2D.new()
	paths.add_to_group("Sentry1")
	var waypoint := Marker2D.new()
	waypoint.set_script(load("res://assets/scripts/Waypoint2D.gd"))
	paths.add_child(waypoint)
	level.add_child(paths)

	var player := Node2D.new()
	player.add_to_group("player")
	player.position = PLAYER_POSITION
	level.add_child(player)

	_near = _add_watching_sentry(level, NEAR_POSITION)
	_far = _add_watching_sentry(level, FAR_POSITION)
	_blind = _add_watching_sentry(level, OUT_OF_SIGHT_POSITION)


func _add_watching_sentry(level: Node2D, at: Vector2) -> Node2D:
	var sentry: Node2D = (
		(load("res://assets/scenes/characters/sentry.tscn") as PackedScene).instantiate()
	)
	sentry.position = at
	sentry.idle_task = sentry.IdleTasks.WAIT
	level.add_child(sentry)
	# Keep the body capsule on the sentry so it cannot drift into a sight line.
	(sentry.get_node("RigidBody2D") as RigidBody2D).freeze = true
	sentry.set_vision_direction(PLAYER_POSITION - at)
	return sentry


func _physics_process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < SAMPLE_TIME:
		return false
	var failures := PackedStringArray()
	var near_multiplier: float = _near.get_distance_detection_multiplier()
	var far_multiplier: float = _far.get_distance_detection_multiplier()
	if near_multiplier <= far_multiplier:
		failures.append(
			"near multiplier %s not above far multiplier %s" % [near_multiplier, far_multiplier]
		)
	if _near.alertness_value <= _far.alertness_value:
		failures.append(
			(
				"near alertness %s not above far alertness %s"
				% [_near.alertness_value, _far.alertness_value]
			)
		)
	if _far.alertness_value <= 0.0:
		failures.append("far sentry never started detecting")
	if _blind.alertness_value != 0.0:
		failures.append("sentry beyond sight range gained alertness %s" % _blind.alertness_value)
	print(
		(
			"DISTANCE near=%.3f (x%.2f) far=%.3f (x%.2f) blind=%.3f"
			% [
				_near.alertness_value,
				near_multiplier,
				_far.alertness_value,
				far_multiplier,
				_blind.alertness_value
			]
		)
	)
	if failures.is_empty():
		quit(0)
	else:
		push_error(", ".join(failures))
		quit(1)
	return true
