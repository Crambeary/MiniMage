extends SceneTree

## Drives Mini Mage through the live input path.
## Invoked by helpers/mm-verify. Reads user args after `--`.

const LEVEL_SCENE := "res://assets/scenes/levels/main.tscn"
const HOLD_FRAMES := 45
const MIN_RIGHT_PX := 20.0

var _feature := ""
var _evidence := ""

func _initialize() -> void:
	_parse_args()
	if _feature not in ["walk", "start-game"]:
		push_error("VERIFY_FAIL no automated drive for '%s'" % _feature)
		quit(3)
		return
	var menu_path := _main_scene_path()
	var err := change_scene_to_file(menu_path)
	if err != OK:
		_fail("could not open main scene %s (error %s)" % [menu_path, err])
		return
	var button := await _wait_for_button("Start Game")
	if button == null:
		await _shot("menu.png")
		_fail("Start Game button did not appear")
		return
	var title := _label_text("Mini Mage")
	print("VERIFY_READY menu title=%s button=%s" % [title, button.text])
	await _shot("menu.png")
	var click_at := await _click(button)
	var reached := await _wait_for_level()
	if not reached:
		await _shot("level-before.png")
		_fail("Start Game did not open %s" % LEVEL_SCENE)
		return
	var player := get_nodes_in_group("player")[0] as CharacterBody2D
	var before: Vector2 = player.global_position
	await _shot("level-before.png")
	print("VERIFY_LEVEL scene=%s player=%s" % [current_scene.scene_file_path, before])
	if _feature == "start-game":
		_write_result(true, title, click_at, before, before, "start-game checks the menu and the spawned player")
		print("VERIFY_PASS start-game")
		quit(0)
		return
	await _hold_key(KEY_D, HOLD_FRAMES)
	var after: Vector2 = player.global_position
	await _shot("level-after.png")
	var moved := after.x - before.x
	print("VERIFY_MOVED before=%s after=%s dx=%s" % [before, after, moved])
	if moved < MIN_RIGHT_PX:
		_write_result(false, title, click_at, before, after, "D moved the player %.2f px; need >= %.0f" % [moved, MIN_RIGHT_PX])
		_fail("walk did not move right far enough (dx=%s)" % moved)
		return
	_write_result(true, title, click_at, before, after, "held physical D through the move_right action")
	print("VERIFY_PASS walk")
	quit(0)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--feature" and i + 1 < args.size():
			_feature = args[i + 1]
			i += 2
		elif arg == "--evidence" and i + 1 < args.size():
			_evidence = args[i + 1]
			i += 2
		else:
			i += 1
	if _evidence.is_empty():
		_evidence = "user://verify-mini-mage"

func _main_scene_path() -> String:
	var raw := str(ProjectSettings.get_setting("application/run/main_scene"))
	if raw.begins_with("uid://"):
		var id := ResourceUID.text_to_id(raw)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return raw

func _wait_for_button(text: String) -> Button:
	for _i in 60:
		await process_frame
		var button := _find_button(text)
		if button != null and button.get_global_rect().size.x > 1.0:
			return button
	return null

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

func _click(control: Control) -> Vector2:
	var center := control.get_global_rect().get_center()
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
	return center

func _wait_for_level() -> bool:
	for _i in 120:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == LEVEL_SCENE:
			if get_nodes_in_group("player").size() > 0:
				return true
	return false

func _hold_key(code: Key, frames: int) -> void:
	for i in frames:
		var down := InputEventKey.new()
		down.physical_keycode = code
		down.keycode = code
		down.pressed = true
		down.echo = i > 0
		Input.parse_input_event(down)
		await physics_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await physics_frame

func _shot(name: String) -> void:
	var image := root.get_texture().get_image() if root.get_texture() else null
	if image == null:
		push_error("VERIFY_FAIL viewport has no image for %s" % name)
		return
	var path := _evidence.path_join(name)
	var err := image.save_png(path)
	if err != OK:
		push_error("VERIFY_FAIL save %s error %s" % [path, err])
	else:
		print("VERIFY_SHOT %s %s" % [path, image.get_size()])

func _write_result(passed: bool, title: String, click_at: Vector2, before: Vector2, after: Vector2, detail: String) -> void:
	var version := Engine.get_version_info()
	var body := {
		"feature": _feature,
		"pass": passed,
		"detail": detail,
		"godot": "%s.%s" % [version.major, version.minor],
		"godot_string": version.string,
		"menu_title": title,
		"button": "Start Game",
		"click": {"x": click_at.x, "y": click_at.y},
		"scene_after_click": current_scene.scene_file_path if current_scene else "",
		"player_before": {"x": before.x, "y": before.y},
		"player_after": {"x": after.x, "y": after.y},
		"delta_x": after.x - before.x,
		"hold_frames": HOLD_FRAMES if _feature == "walk" else 0,
		"key": "D" if _feature == "walk" else "",
	}
	var file := FileAccess.open(_evidence.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		push_error("VERIFY_FAIL could not write result.json")
		return
	file.store_string(JSON.stringify(body, "  "))
	file.close()

func _fail(reason: String) -> void:
	push_error("VERIFY_FAIL %s" % reason)
	quit(2)
