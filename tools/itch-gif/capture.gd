extends SceneTree

const LEVEL_SCENE := "res://assets/scenes/levels/main.tscn"
const SAMPLE_EVERY := 6

const BEATS: Array[Dictionary] = [
	{"op": "click", "button": "Start Game"},
	{"op": "wait_level"},
	{"op": "wait", "frames": 12},
	{"op": "hold", "key": KEY_S, "frames": 40},
	{"op": "hold", "key": KEY_D, "frames": 48},
	{"op": "hold", "key": KEY_W, "frames": 55},
	{"op": "hold", "key": KEY_D, "frames": 70},
	{"op": "hold", "key": KEY_A, "frames": 100},
	{"op": "wait", "frames": 18},
]

var _out := ""
var _shot := 0
var _since_shot := 0
var _failed := false
var _recording := false


func _initialize() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out)
	var menu_path := _main_scene_path()
	var err := change_scene_to_file(menu_path)
	if err != OK:
		_fail("could not open main scene %s (error %s)" % [menu_path, err])
		return
	for beat in BEATS:
		var op: String = beat["op"]
		match op:
			"click":
				await _open_level(str(beat["button"]))
			"wait_level":
				await _wait_level()
			"wait":
				await _frames(int(beat["frames"]))
			"hold":
				await _frames(int(beat["frames"]), int(beat["key"]))
			_:
				_fail("unknown beat %s" % op)
		if _failed:
			return
	_flush_shot()
	print("ITCH_GIF_FRAMES %s count=%s" % [_out, _shot])
	quit(0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--out" and i + 1 < args.size():
			_out = args[i + 1]
			i += 2
		else:
			i += 1
	if _out.is_empty():
		_out = "user://itch-gif-frames"


func _main_scene_path() -> String:
	var raw := str(ProjectSettings.get_setting("application/run/main_scene"))
	if raw.begins_with("uid://"):
		var id := ResourceUID.text_to_id(raw)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return raw


func _open_level(text: String) -> void:
	var button: Button = null
	for _i in 90:
		await process_frame
		button = _find_button(text)
		if button != null and button.get_global_rect().size.x > 1.0:
			break
	if button == null:
		_fail("Start Game button did not appear")
		return
	print("ITCH_GIF_MENU title=%s skipped=true" % _label_text("Mini Mage"))
	await _click_button(text)


func _click_button(text: String) -> void:
	var button := _find_button(text)
	if button == null:
		_fail("missing button %s" % text)
		return
	var center := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	release.button_mask = 0
	root.push_input(release)
	await process_frame
	print("ITCH_GIF_CLICK %s at %s" % [text, center])


func _wait_level() -> void:
	for _i in 180:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == LEVEL_SCENE:
			if get_nodes_in_group("player").size() > 0:
				var player := get_nodes_in_group("player")[0] as Node2D
				_recording = true
				print("ITCH_GIF_LEVEL player=%s" % player.global_position)
				return
	_fail("Start Game did not open %s" % LEVEL_SCENE)


func _frames(count: int, key: int = 0) -> void:
	for i in count:
		if key != 0:
			var down := InputEventKey.new()
			down.physical_keycode = key as Key
			down.keycode = key as Key
			down.pressed = true
			down.echo = i > 0
			Input.parse_input_event(down)
		await physics_frame
		_sample()
	if key != 0:
		var up := InputEventKey.new()
		up.physical_keycode = key as Key
		up.keycode = key as Key
		up.pressed = false
		Input.parse_input_event(up)
		await physics_frame
		_sample()
	_log_player()


func _question_visible() -> bool:
	for node in get_nodes_in_group("sentry"):
		var mark = node.get("question_mark")
		if mark != null and mark.visible:
			return true
	return false


func _max_alert() -> float:
	var best := 0.0
	for node in get_nodes_in_group("sentry"):
		var value = node.get("alertness_value")
		if value != null:
			best = maxf(best, float(value))
	return best


func _sample() -> void:
	if not _recording:
		return
	_since_shot += 1
	if _since_shot < SAMPLE_EVERY:
		return
	_since_shot = 0
	_flush_shot()


func _flush_shot() -> void:
	var image := root.get_texture().get_image() if root.get_texture() else null
	if image == null:
		_fail("viewport has no image")
		return
	_shot += 1
	var path := _out.path_join("frame_%04d.png" % _shot)
	var err := image.save_png(path)
	if err != OK:
		_fail("save %s error %s" % [path, err])
		return
	var alert := _max_alert()
	if alert >= 0.7:
		_fail("sentry alertness reached %s" % alert)
		return
	print(
		"ITCH_GIF_SHOT %s %s player=%s alert=%s question=%s"
		% [path, image.get_size(), _player_pos(), alert, _question_visible()]
	)


func _log_player() -> void:
	print("ITCH_GIF_POS %s" % _player_pos())


func _player_pos() -> String:
	var nodes := get_nodes_in_group("player")
	if nodes.is_empty():
		return "none"
	var player := nodes[0] as Node2D
	if player == null:
		return "none"
	return str(player.global_position)


func _find_button(text: String) -> Button:
	if current_scene == null:
		return null
	for node in current_scene.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == text:
			return button
	return null


func _label_text(expected: String) -> String:
	if current_scene == null:
		return ""
	for node in current_scene.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == expected:
			return label.text
	return ""


func _fail(detail: String) -> void:
	_failed = true
	push_error("ITCH_GIF_FAIL %s" % detail)
	quit(1)
