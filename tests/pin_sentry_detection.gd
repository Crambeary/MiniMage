extends SceneTree

const WAYPOINT := Vector2(200, 0)
const PLAYER_IN_SIGHT := Vector2(180, 0)
const PLAYER_HIDDEN := Vector2(-400, 400)

var _sentry: Node2D
var _player: Node2D
var _handler: Node
var _elapsed := 0.0
var _hid_player := false
var _closest := INF
var _max_patrol_deviation := 0.0
var _saw_alert := false
var _saw_surprise := false
var _saw_aimed_arrow := false
var _saw_question := false
var _arrow_cleared := false
var _exclamation_hidden_while_suspicious := false
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var level := Node2D.new()
	root.add_child(level)

	var paths: Node2D = (load("res://assets/scripts/patrol_path_2d.gd") as GDScript).new()
	var waypoint_script: Script = load("res://assets/scripts/Waypoint2D.gd")
	var first := Marker2D.new()
	first.set_script(waypoint_script)
	first.position = WAYPOINT
	paths.add_child(first)
	var second := Marker2D.new()
	second.set_script(waypoint_script)
	second.position = Vector2(200, 80)
	paths.add_child(second)
	level.add_child(paths)

	_player = Node2D.new()
	_player.add_to_group("player")
	_player.position = PLAYER_IN_SIGHT
	level.add_child(_player)

	_sentry = (load("res://assets/scenes/characters/sentry.tscn") as PackedScene).instantiate()
	_sentry.position = Vector2.ZERO
	_sentry.patrol_path = paths
	level.add_child(_sentry)

	_handler = (
		(load("res://assets/scenes/characters/player_detection_handler.gd") as GDScript).new()
	)
	level.add_child(_handler)


func _process(delta: float) -> bool:
	_elapsed += delta
	_closest = minf(_closest, _sentry.global_position.distance_to(WAYPOINT))
	_max_patrol_deviation = maxf(_max_patrol_deviation, absf(_sentry.global_position.y))
	_saw_alert = _saw_alert or _sentry.alertness_value >= _sentry.alertness_threshold
	_saw_surprise = _saw_surprise or _sentry.is_surprised()
	_note_what_the_player_sees()
	if _saw_question and _saw_aimed_arrow and not _hid_player:
		_hid_player = true
		_player.global_position = PLAYER_HIDDEN
	if _hid_player and _visible_arrow_count() == 0:
		_finish()
		return true
	if _elapsed > 4.0:
		_finish()
		return true
	return false


func _note_what_the_player_sees() -> void:
	var question: CanvasItem = _sentry.get_node("Emotes/QuestionMark")
	var exclamation: CanvasItem = _sentry.get_node("Emotes/Exclamation")
	if question.visible:
		_saw_question = true
		if not exclamation.visible:
			_exclamation_hidden_while_suspicious = true
	for child in _handler.get_children():
		if not child is Node2D or not (child as Node2D).visible:
			continue
		var arrow := child as Node2D
		var aim := arrow.global_position.angle_to_point(_sentry.global_position)
		if absf(wrapf(arrow.global_rotation - aim, -PI, PI)) < 0.35:
			_saw_aimed_arrow = true


func _visible_arrow_count() -> int:
	var count := 0
	for child in _handler.get_children():
		if child is Node2D and (child as Node2D).visible:
			count += 1
	return count


func _finish() -> void:
	var start_distance := Vector2.ZERO.distance_to(WAYPOINT)
	if _closest > start_distance - 5.0:
		_failures.append("sentry did not close on the waypoint, closest=%s" % _closest)
	if _max_patrol_deviation > 1.0:
		_failures.append("sentry left the patrol line, deviation=%s" % _max_patrol_deviation)
	if _saw_alert:
		_failures.append("sentry became alerted during the suspicion check")
	if _saw_surprise:
		_failures.append("sentry entered the surprise window during the suspicion check")
	if not _saw_aimed_arrow:
		_failures.append("no visible arrow pointed at the sentry")
	if not _saw_question:
		_failures.append("question mark stayed hidden while the player stood in front")
	if not _exclamation_hidden_while_suspicious:
		_failures.append("exclamation showed while the question mark was up")
	if _visible_arrow_count() != 0:
		_failures.append("arrow still visible after the player left sight")
	else:
		_arrow_cleared = true
	print(
		(
			"BEHAVIOR pos=%s closest=%s aimed=%s question=%s exclamation_hidden=%s cleared=%s"
			% [
				_sentry.global_position,
				_closest,
				_saw_aimed_arrow,
				_saw_question,
				_exclamation_hidden_while_suspicious,
				_arrow_cleared
			]
		)
	)
	if _failures.is_empty():
		quit(0)
	else:
		push_error(", ".join(_failures))
		quit(1)
