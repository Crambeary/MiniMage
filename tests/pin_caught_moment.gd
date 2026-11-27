extends SceneTree

# The caught moment plays before the game-over screen and always restores time.
#   natural - runs to its end on its own, within the promised 1.5-2.5s
#   skip    - skip() ends it at once and still opens the game-over screen

const MIN_SECONDS := 1.5
const MAX_SECONDS := 2.5

var _manager: Node
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_manager = root.get_node_or_null("GameOverManager")
	if _manager == null:
		push_error("GameOverManager autoload missing")
		quit(1)
		return
	await _natural()
	await _skip()
	if _failures.is_empty():
		print("CAUGHT_MOMENT all scenarios passed")
		quit(0)
	else:
		push_error(", ".join(_failures))
		quit(1)


func _natural() -> void:
	_manager.show_caught_moment()
	var started := Time.get_ticks_msec()
	await create_timer(0.4, true, false, true).timeout
	if Engine.time_scale >= 1.0:
		_failures.append("natural: no slow motion during the moment")
	if _manager._screen != null:
		_failures.append("natural: game-over screen shown before the moment ended")
	while _manager._screen == null and Time.get_ticks_msec() - started < 4000:
		await process_frame
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("CAUGHT_MOMENT natural seconds=%s" % seconds)
	if seconds < MIN_SECONDS or seconds > MAX_SECONDS:
		_failures.append("natural: moment lasted %ss" % seconds)
	_check_game_over_open("natural")
	_manager._close_screen()
	_check_clean("natural close")


func _skip() -> void:
	_manager.show_caught_moment()
	await process_frame
	await process_frame
	var moment: Node = _manager._moment
	if not is_instance_valid(moment):
		_failures.append("skip: moment did not start")
		return
	moment.skip()
	await process_frame
	await process_frame
	_check_game_over_open("skip")
	_manager._close_screen()
	_check_clean("skip close")


func _check_game_over_open(label: String) -> void:
	if _manager._screen == null:
		_failures.append("%s: game-over screen never opened" % label)
	if Engine.time_scale != 1.0:
		_failures.append("%s: time scale left at %s" % [label, Engine.time_scale])
	if not paused:
		_failures.append("%s: tree not paused behind the game-over screen" % label)


func _check_clean(label: String) -> void:
	if paused or Engine.time_scale != 1.0:
		_failures.append("%s: state not reset" % label)
