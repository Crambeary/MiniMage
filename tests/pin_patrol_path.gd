extends SceneTree

## Pins PatrolPath2D ordering and the level migration.
## Run: godot --headless --path . -s tests/pin_patrol_path.gd   (exit 0 = pass)

const PATROL_PATH := preload("res://assets/scripts/patrol_path_2d.gd")
const WAYPOINT := preload("res://assets/scripts/Waypoint2D.gd")

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_order(PATROL_PATH.Mode.LOOP, 4, [1, 2, 3, 0, 1, 2, 3, 0])
	_check_order(PATROL_PATH.Mode.PING_PONG, 4, [1, 2, 3, 2, 1, 0, 1, 2])
	_check_order(PATROL_PATH.Mode.PING_PONG, 2, [1, 0, 1, 0])
	_check_order(PATROL_PATH.Mode.LOOP, 1, [0, 0])
	_check_order(PATROL_PATH.Mode.PING_PONG, 1, [0, 0])
	_check_snap()

	# Each sentry in each level must resolve to the same global waypoint
	# positions its old group lookup found (copied from the pre-migration scenes).
	_check_level(
		"res://assets/scenes/levels/main.tscn",
		{
			"Sentry": [Vector2(-192, 0), Vector2(-192, -64), Vector2(-112, -64), Vector2(-112, 0)],
			"Sentry2":
			[
				Vector2(-336, -64),
				Vector2(-336, 8),
				Vector2(-296, 8),
				Vector2(-296, -8),
				Vector2(-256, -8),
				Vector2(-256, -64)
			],
		}
	)
	_check_level(
		"res://assets/scenes/levels/level_3.tscn",
		{
			"Sentry": [Vector2(40, 82)],
		}
	)
	_check_level_counts("res://assets/scenes/levels/level_2.tscn", {"Sentry": 12, "Sentry2": 10})

	if _failures.is_empty():
		print("PATROL_PATH ok")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _check_order(mode: int, count: int, expected: Array) -> void:
	var path: Node2D = PATROL_PATH.new()
	path.mode = mode
	for i in count:
		var wp: Marker2D = WAYPOINT.new()
		path.add_child(wp)
	var index := 0
	var step := 1
	var got: Array = []
	for i in expected.size():
		var n: Vector2i = path.next(index, step)
		index = n.x
		step = n.y
		got.append(index)
	if got != expected:
		_failures.append("mode %d count %d: expected %s got %s" % [mode, count, expected, got])
	path.free()


func _check_snap() -> void:
	var path: Node2D = PATROL_PATH.new()
	if path.snap_global(Vector2(13, -3)) != Vector2(16, 0):
		_failures.append("snap 8: got %s" % path.snap_global(Vector2(13, -3)))
	path.snap_step = Vector2.ZERO
	if path.snap_global(Vector2(13, -3)) != Vector2(13, -3):
		_failures.append("snap off moved the point")
	path.free()


func _instance_level(scene_path: String) -> Node:
	var level: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(level)
	return level


func _check_level(scene_path: String, expected: Dictionary) -> void:
	var level := _instance_level(scene_path)
	for sentry_name in expected:
		var sentry := level.get_node(NodePath(sentry_name))
		if sentry.patrol_path == null:
			_failures.append("%s/%s has no patrol_path" % [scene_path, sentry_name])
			continue
		if sentry.patrol_path.mode != PATROL_PATH.Mode.LOOP:
			_failures.append("%s/%s path is not LOOP" % [scene_path, sentry_name])
		var got: Array = []
		for wp in sentry.waypoints:
			got.append(wp.global_position)
		if got != expected[sentry_name]:
			_failures.append(
				"%s/%s: expected %s got %s" % [scene_path, sentry_name, expected[sentry_name], got]
			)
	level.free()


func _check_level_counts(scene_path: String, expected: Dictionary) -> void:
	var level := _instance_level(scene_path)
	for sentry_name in expected:
		var sentry := level.get_node(NodePath(sentry_name))
		if sentry.patrol_path == null or sentry.waypoints.size() != expected[sentry_name]:
			_failures.append(
				"%s/%s: expected %d waypoints" % [scene_path, sentry_name, expected[sentry_name]]
			)
	level.free()
