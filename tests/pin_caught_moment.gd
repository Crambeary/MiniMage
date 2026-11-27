extends SceneTree

# The caught moment follows a real player_caught, freezes the world at once and
# always leaves the game in a clean state. Scenarios run in order:
#   natural   - runs out on its own within 1.5-2.5s, then opens game over once
#   skip      - skip() ends it at once and still opens the game-over screen
#   gesture   - emulated mouse is ignored; a skip ends on the touch release
#   interrupt - freeing the moment mid-run unfreezes and opens no screen
#   teardown  - replacing the scene mid-run cleans up and opens no screen
#   mismatch  - a release of another touch does not end a skip
#   held      - a skip still held at the cap keeps swallowing until its release
#   same_frame- replacing the scene in the catch frame abandons the run
#   fit       - the title shrinks to fit the narrowest portrait viewport
#   shutdown  - leaving the tree restores time scale and pause

const MIN_SECONDS := 1.5
const MAX_SECONDS := 2.5
const COUNTER_SOURCE := """extends Node
signal player_caught(catcher)
var ticks := 0
func _physics_process(_delta: float) -> void:
	ticks += 1
"""

var _manager: Node
var _level: Node
var _sentry: Node
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
	await _gesture()
	await _interrupt()
	await _teardown()
	await _mismatch()
	await _held()
	await _same_frame()
	await _fit()
	await _shutdown()
	if _failures.is_empty():
		print("CAUGHT_MOMENT all scenarios passed")
		quit(0)
	else:
		push_error(", ".join(_failures))
		quit(1)


func _new_level() -> void:
	_level = Node2D.new()
	root.add_child(_level)
	current_scene = _level
	var script := GDScript.new()
	script.source_code = COUNTER_SOURCE
	script.reload()
	_sentry = Node.new()
	_sentry.set_script(script)
	_sentry.add_to_group("sentry")
	_level.add_child(_sentry)


func _drop_level() -> void:
	if is_instance_valid(_level):
		root.remove_child(_level)
		_level.queue_free()
	_level = null
	_sentry = null


func _catch(label: String) -> void:
	_sentry.player_caught.emit(null)
	# The catch must be final in the same frame, before any overlay exists.
	if not paused:
		_failures.append("%s: tree not frozen the instant the player was caught" % label)
	_sentry.player_caught.emit(null)
	await process_frame
	await process_frame
	if not is_instance_valid(_manager._moment):
		_failures.append("%s: no moment after player_caught" % label)


func _moments() -> int:
	var count := 0
	for child in root.get_children():
		if child is CaughtMoment:
			count += 1
	return count


func _check_reset(label: String) -> void:
	if paused or Engine.time_scale != 1.0 or _manager._caught:
		_failures.append("%s: state not reset" % label)


func _close_open_screen(label: String) -> void:
	if _manager._screen == null:
		_failures.append("%s: game-over screen missing" % label)
		return
	_manager._close_screen()
	_check_reset(label + " close")


func _check_game_over_open(label: String) -> void:
	if _manager._screen == null:
		_failures.append("%s: game-over screen never opened" % label)
	if Engine.time_scale != 1.0:
		_failures.append("%s: time scale left at %s" % [label, Engine.time_scale])
	if not paused:
		_failures.append("%s: tree not paused behind the game-over screen" % label)


func _natural() -> void:
	_new_level()
	var started := Time.get_ticks_msec()
	await _catch("natural")
	if _moments() != 1:
		_failures.append("natural: %s moments after two catches" % _moments())
	var ticks_before: int = _sentry.ticks
	await create_timer(0.4, true, false, true).timeout
	if _sentry.ticks != ticks_before:
		_failures.append("natural: gameplay kept running during the moment")
	if _manager._screen != null:
		_failures.append("natural: game-over screen shown before the moment ended")
	while _manager._screen == null and Time.get_ticks_msec() - started < 4000:
		await process_frame
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("CAUGHT_MOMENT natural seconds=%s" % seconds)
	if seconds < MIN_SECONDS or seconds > MAX_SECONDS:
		_failures.append("natural: moment lasted %ss" % seconds)
	_check_game_over_open("natural")
	_close_open_screen("natural")
	_drop_level()


func _skip() -> void:
	_new_level()
	await _catch("skip")
	var moment: Node = _manager._moment
	if is_instance_valid(moment):
		moment.skip()
	await process_frame
	await process_frame
	_check_game_over_open("skip")
	_close_open_screen("skip")
	_drop_level()


func _gesture() -> void:
	_new_level()
	await _catch("gesture")
	var moment: Node = _manager._moment
	if not is_instance_valid(moment):
		_drop_level()
		return
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.pressed = true
	moment._input(emulated)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	moment._input(touch)
	await process_frame
	if _manager._screen != null or not is_instance_valid(moment):
		_failures.append("gesture: press alone ended the moment")
	touch = InputEventScreenTouch.new()
	touch.pressed = false
	moment._input(touch)
	await process_frame
	await process_frame
	_check_game_over_open("gesture")
	_close_open_screen("gesture")
	_drop_level()


func _interrupt() -> void:
	_new_level()
	await _catch("interrupt")
	var moment: Node = _manager._moment
	if is_instance_valid(moment):
		moment.free()
	await create_timer(0.3, true, false, true).timeout
	if _manager._screen != null:
		_failures.append("interrupt: game-over screen opened after the moment was freed")
	_check_reset("interrupt")
	_drop_level()


func _teardown() -> void:
	_new_level()
	await _catch("teardown")
	var old_level := _level
	root.remove_child(old_level)
	old_level.queue_free()
	_level = null
	await process_frame
	await process_frame
	var other := Node2D.new()
	root.add_child(other)
	current_scene = other
	await create_timer(0.3, true, false, true).timeout
	if _manager._screen != null:
		_failures.append("teardown: game-over screen opened over a different scene")
	if _moments() != 0:
		_failures.append("teardown: moment outlived its scene")
	_check_reset("teardown")
	root.remove_child(other)
	other.queue_free()


func _touch(index: int, pressed: bool) -> InputEventScreenTouch:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.pressed = pressed
	return touch


func _mismatch() -> void:
	_new_level()
	await _catch("mismatch")
	var moment: Node = _manager._moment
	if not is_instance_valid(moment):
		_drop_level()
		return
	moment._input(_touch(0, true))
	moment._input(_touch(1, true))
	moment._input(_touch(1, false))
	await process_frame
	if _manager._screen != null or not is_instance_valid(moment):
		_failures.append("mismatch: another touch's release ended the skip")
	moment._input(_touch(0, false))
	await process_frame
	await process_frame
	_check_game_over_open("mismatch")
	_close_open_screen("mismatch")
	_drop_level()


func _held() -> void:
	_new_level()
	await _catch("held")
	var moment: Node = _manager._moment
	if not is_instance_valid(moment):
		_drop_level()
		return
	moment._input(_touch(0, true))
	var started := Time.get_ticks_msec()
	while _manager._screen == null and Time.get_ticks_msec() - started < 2000:
		await process_frame
	await process_frame
	if _manager._screen == null:
		_failures.append("held: cap never opened the game-over screen")
	elif not is_instance_valid(moment):
		_failures.append("held: moment left before its gesture was released")
	moment._input(_touch(1, true))
	moment._input(_touch(0, false))
	await process_frame
	await process_frame
	if is_instance_valid(moment) and not moment.is_queued_for_deletion():
		_failures.append("held: moment stayed after its gesture was released")
	_close_open_screen("held")
	_drop_level()


func _same_frame() -> void:
	_new_level()
	_sentry.player_caught.emit(null)
	var old_level := _level
	root.remove_child(old_level)
	old_level.queue_free()
	_level = null
	var other := Node2D.new()
	root.add_child(other)
	current_scene = other
	await process_frame
	await process_frame
	await create_timer(0.3, true, false, true).timeout
	if _manager._screen != null or _moments() != 0:
		_failures.append("same_frame: the new scene was treated as the caught one")
	_check_reset("same_frame")
	root.remove_child(other)
	other.queue_free()


func _shutdown() -> void:
	root.remove_child(_manager)
	Engine.time_scale = 0.5
	_manager._abandon_moment()
	if Engine.time_scale != 1.0:
		_failures.append("shutdown: abandon left time scale at %s" % Engine.time_scale)
	Engine.time_scale = 0.5
	root.add_child(_manager)
	root.remove_child(_manager)
	if Engine.time_scale != 1.0:
		_failures.append("shutdown: leaving the tree left time scale at %s" % Engine.time_scale)
	root.add_child(_manager)


func _fit() -> void:
	var window := root
	var before := window.content_scale_size
	var before_mode := window.content_scale_mode
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i(360, 360)
	var moment := CaughtMoment.new()
	root.add_child(moment)
	await process_frame
	var title := moment.find_children("*", "Label", true, false)[0] as Label
	var font := title.get_theme_font("font")
	var size := title.get_theme_font_size("font_size")
	var width := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if title.text != "DETENTION":
		_failures.append("fit: title reads %s" % title.text)
	if width > 360.0:
		_failures.append("fit: title is %spx wide in a 360 viewport" % width)
	moment.free()
	window.content_scale_size = before
	window.content_scale_mode = before_mode
