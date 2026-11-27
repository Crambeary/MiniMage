extends SceneTree

## Drives Mini Mage through the live input path.
## Invoked by helpers/mm-verify. Reads user args after `--`.

const LEVEL_SCENE := "res://assets/scenes/levels/main.tscn"
const HOLD_FRAMES := 45
const MIN_RIGHT_PX := 20.0
## Each touch scheme, the way the finger pushes, and where the finger lands.
const TOUCH_SCHEMES := [
	{"scheme": "locked", "label": "Locked", "direction": 1.0},
	{"scheme": "floating", "label": "Floating", "direction": -1.0},
	{"scheme": "drag", "label": "Drag", "direction": 1.0},
]
const TOUCH_PUSH_UNITS := 60.0
const MIN_TOUCH_PX := 8.0
const SETTINGS_SCENE := "res://assets/scenes/ui/SettingsMenu.tscn"
const MENU_SCENE := "res://assets/scenes/ui/MainMenu.tscn"
## Where on a slider's track the finger lands for each step, as a fraction of its width.
const FOV_STEPS := [
	{"name": "min", "at": 0.0, "fov": 0.85},
	{"name": "default", "at": 0.5, "fov": 1.0},
	{"name": "max", "at": 1.0, "fov": 1.15},
]
const HUD_STEPS := [
	{"name": "min", "at": 0.0, "hud": 0.75},
	{"name": "max", "at": 1.0, "hud": 2.5},
]
const AREA_TOLERANCE := 0.01

var _feature := ""
var _evidence := ""


func _initialize() -> void:
	_parse_args()
	if _feature not in ["walk", "start-game", "touch-scheme", "view-settings"]:
		push_error("VERIFY_FAIL no automated drive for '%s'" % _feature)
		quit(3)
		return
	var button := await _open_menu()
	if button == null:
		return
	var title := _label_text("Mini Mage")
	print("VERIFY_READY menu title=%s button=%s" % [title, button.text])
	await _shot("menu.png")
	if _feature == "view-settings":
		await _drive_view_settings(title)
		return
	if _feature == "touch-scheme":
		await _drive_touch_schemes(title)
		return
	await _drive_level(title, button)


## Opens the main menu and waits for Start Game; null (after failing the run) if it never shows.
func _open_menu() -> Button:
	var menu_path := _main_scene_path()
	var err := change_scene_to_file(menu_path)
	if err != OK:
		_fail("could not open main scene %s (error %s)" % [menu_path, err])
		return null
	var button := await _wait_for_button("Start Game")
	if button == null:
		await _shot("menu.png")
		_fail("Start Game button did not appear")
	return button


## Presses Start Game and runs the walk or start-game drive in the level.
func _drive_level(title: String, button: Button) -> void:
	var click_at := await _click(button)
	var reached := await _wait_for_level()
	if not reached:
		await _shot("level-before.png")
		_fail("Start Game did not open %s" % LEVEL_SCENE)
		return
	var player := get_nodes_in_group("player")[0] as CharacterBody2D
	var before: Vector2 = player.global_position
	await _shot("level-before.png")
	print(
		(
			"VERIFY_LEVEL scene=%s player=%s window=%s viewport=%s zoom=%s"
			% [
				current_scene.scene_file_path,
				before,
				root.size,
				root.get_visible_rect().size,
				get_first_node_in_group("player").get_node("Camera2D").zoom
			]
		)
	)
	if _feature == "start-game":
		_write_result(
			true,
			title,
			click_at,
			before,
			before,
			"start-game checks the menu and the spawned player"
		)
		print("VERIFY_PASS start-game")
		quit(0)
		return
	await _hold_key(KEY_D, HOLD_FRAMES)
	var after: Vector2 = player.global_position
	await _shot("level-after.png")
	var moved := after.x - before.x
	print("VERIFY_MOVED before=%s after=%s dx=%s" % [before, after, moved])
	if moved < MIN_RIGHT_PX:
		var detail := "D moved the player %.2f px; need >= %.0f" % [moved, MIN_RIGHT_PX]
		_write_result(false, title, click_at, before, after, detail)
		_fail("walk did not move right far enough (dx=%s)" % moved)
		return
	_write_result(
		true, title, click_at, before, after, "held physical D through the move_right action"
	)
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


# Viewport (UI unit) point to window pixel. push_input undoes the stretch transform,
# so events must start in window pixels or they land in the wrong place.
func _to_window(viewport_point: Vector2) -> Vector2:
	return root.get_final_transform() * viewport_point


func _click(control: Control) -> Vector2:
	var center := _to_window(control.get_global_rect().get_center())
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


# Picks each scheme in Settings, starts the level and swipes it. Between runs the drive
# reopens the menu by scene change, since the level has no way back to it.
func _drive_touch_schemes(title: String) -> void:
	var touch_controls := root.get_node_or_null("TouchControls")
	if touch_controls == null:
		_fail("TouchControls autoload is missing")
		return
	var checks: Dictionary = {
		"default_floating": touch_controls.call("get_scheme_name") == "floating",
	}
	var runs: Array = []
	var all_passed := true
	var click_at := Vector2.ZERO
	var start := Vector2.ZERO
	for entry: Dictionary in TOUCH_SCHEMES:
		var run := await _pick_scheme_in_settings(entry, touch_controls)
		if run.is_empty():
			return
		var start_button := await _wait_for_button("Start Game")
		click_at = await _click(start_button)
		if not await _wait_for_level():
			_fail("Start Game did not open %s" % LEVEL_SCENE)
			return
		for _i in 10:
			await physics_frame
		var player := get_nodes_in_group("player")[0] as CharacterBody2D
		if runs.is_empty():
			start = player.global_position
		var finger := _touch_start(entry.scheme, touch_controls)
		var before: Vector2 = player.global_position
		await _swipe(finger, finger + Vector2(entry.direction * TOUCH_PUSH_UNITS, 0.0), HOLD_FRAMES)
		var after: Vector2 = player.global_position
		await _shot("touch-%s.png" % entry.scheme)
		var moved: float = (after.x - before.x) * entry.direction
		run["level_scheme"] = touch_controls.call("get_scheme_name")
		run["hud_buttons"] = touch_controls.find_children("*", "Button", true, false).size()
		run["finger_viewport"] = {"x": finger.x, "y": finger.y}
		run["direction"] = entry.direction
		run["moved_px"] = moved
		run["player_before"] = {"x": before.x, "y": before.y}
		run["player_after"] = {"x": after.x, "y": after.y}
		run["pass"] = (
			run.active_after_click == entry.scheme
			and run.button_pressed
			and run.level_scheme == entry.scheme
			and run.hud_buttons == 0
			and moved >= MIN_TOUCH_PX
		)
		all_passed = all_passed and run.pass
		print("VERIFY_TOUCH %s" % JSON.stringify(run))
		runs.append(run)
	var saved := ConfigFile.new()
	var load_error := saved.load("user://settings.cfg")
	var saved_scheme: String = str(saved.get_value("touch", "scheme", ""))
	checks["saved_last_scheme"] = load_error == OK and saved_scheme == TOUCH_SCHEMES[-1].scheme
	for key: String in checks:
		all_passed = all_passed and bool(checks[key])
	var player_now := get_first_node_in_group("player") as Node2D
	var detail := "picked each scheme in Settings, started the level, swiped with ScreenTouch/Drag"
	_write_result(
		all_passed,
		title,
		click_at,
		start,
		player_now.global_position,
		detail,
		{"checks": checks, "saved_scheme": saved_scheme, "touch_runs": runs}
	)
	if not all_passed:
		_fail("touch-scheme check failed (see result.json): %s" % JSON.stringify(checks))
		return
	print("VERIFY_PASS touch-scheme")
	quit(0)


# Opens Settings from the menu, presses the scheme's button and goes Back to the menu.
# Returns the run record so far, or {} after failing the drive.
func _pick_scheme_in_settings(entry: Dictionary, touch_controls: Node) -> Dictionary:
	if current_scene == null or current_scene.scene_file_path != MENU_SCENE:
		change_scene_to_file(MENU_SCENE)
		if not await _wait_for_scene(MENU_SCENE):
			_fail("could not reopen %s" % MENU_SCENE)
			return {}
	var settings_button := await _wait_for_button("Settings")
	if settings_button == null:
		_fail("no Settings button on the menu")
		return {}
	await _click(settings_button)
	if not await _wait_for_scene(SETTINGS_SCENE):
		_fail("Settings did not open %s" % SETTINGS_SCENE)
		return {}
	var button := await _wait_for_button(entry.label)
	if button == null:
		_fail("no %s button in Settings" % entry.label)
		return {}
	await _click(button)
	await process_frame
	var run := {
		"scheme": entry.scheme,
		"active_after_click": touch_controls.call("get_scheme_name"),
		"button_pressed": button.button_pressed,
		"button_rect": _rect_dict(button.get_global_rect()),
	}
	await _shot("settings-%s.png" % entry.scheme)
	await _click(_find_button("Back"))
	if not await _wait_for_scene(MENU_SCENE):
		_fail("Back did not return to %s" % MENU_SCENE)
		return {}
	return run


# Where a thumb goes down for each scheme, in viewport units.
func _touch_start(scheme: String, touch_controls: Node) -> Vector2:
	var size := root.get_visible_rect().size
	match scheme:
		"locked":
			return touch_controls.call("get_scheme").call("get_base_center")
		"floating":
			return Vector2(size.x * 0.3, size.y * 0.65)
	return Vector2(size.x * 0.5, size.y * 0.65)


func _swipe(from: Vector2, to: Vector2, hold_frames: int) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = _to_window(from)
	root.push_input(press)
	await physics_frame
	var steps := 6
	for i in range(1, steps + 1):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		var previous := _to_window(from.lerp(to, float(i - 1) / steps))
		drag.position = _to_window(from.lerp(to, float(i) / steps))
		drag.relative = drag.position - previous
		root.push_input(drag)
		await physics_frame
	for _i in hold_frames:
		await physics_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = _to_window(to)
	root.push_input(release)
	for _i in 4:
		await physics_frame


func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _drive_view_settings(title: String) -> void:
	var view_settings := root.get_node("ViewSettings")
	var touch_controls := root.get_node_or_null("TouchControls")
	var settings_button := _find_button("Settings")
	if settings_button == null:
		_fail("no Settings button on the menu")
		return
	await _click(settings_button)
	if not await _wait_for_scene(SETTINGS_SCENE):
		_fail("Settings did not open %s" % SETTINGS_SCENE)
		return
	for _i in 10:
		await process_frame
	var checks: Dictionary = {}
	checks["touch_controls_suspended"] = touch_controls == null or not touch_controls.visible
	checks["touch_row_shows_scheme"] = _settings_shows_scheme(touch_controls)
	await _click(current_scene.find_child("ReadoutToggle", true, false) as Control)
	checks["readout_on"] = bool(view_settings.get("debug_readout"))
	var fov_slider := current_scene.find_child("FovSlider", true, false) as HSlider
	var hud_slider := current_scene.find_child("HudSlider", true, false) as HSlider
	var fov_runs: Array = []
	var fov_ok := true
	for step: Dictionary in FOV_STEPS:
		await _tap_slider(fov_slider, step.at)
		var run := _view_snapshot(view_settings)
		run["step"] = step.name
		run["slider_value"] = fov_slider.value
		var expected_area: float = 384.0 * 216.0 * step.fov * step.fov
		run["expected_world_area"] = expected_area
		run["pass"] = (
			is_equal_approx(float(view_settings.get("fov_scale")), step.fov)
			and absf(run.world_area / expected_area - 1.0) < AREA_TOLERANCE
		)
		fov_ok = fov_ok and run.pass
		fov_runs.append(run)
		print("VERIFY_FOV %s" % JSON.stringify(run))
		await _shot("fov-%s.png" % step.name)
	checks["fov_steps"] = fov_ok
	var hud_runs: Array = []
	var hud_ok := true
	for step: Dictionary in HUD_STEPS:
		await _tap_slider(hud_slider, step.at)
		var run := _view_snapshot(view_settings)
		run["step"] = step.name
		run["slider_value"] = hud_slider.value
		run["pass"] = (
			is_equal_approx(float(view_settings.get("hud_scale")), step.hud)
			and is_equal_approx(run.status_bar_scale, step.hud)
			and is_equal_approx(run.detection_arrow_scale, step.hud)
		)
		hud_ok = hud_ok and run.pass
		hud_runs.append(run)
		print("VERIFY_HUD %s" % JSON.stringify(run))
		await _shot("hud-%s.png" % step.name)
	checks["hud_steps"] = hud_ok
	await _click(_find_button("Back"))
	if not await _wait_for_scene(MENU_SCENE):
		_fail("Back did not return to %s" % MENU_SCENE)
		return
	var saved := ConfigFile.new()
	var load_error := saved.load("user://settings.cfg")
	var saved_values := {
		"load_error": load_error,
		"fov_scale": saved.get_value("view", "fov_scale", -1.0),
		"hud_scale": saved.get_value("view", "hud_scale", -1.0),
		"debug_readout": saved.get_value("view", "debug_readout", false),
	}
	checks["saved"] = (
		load_error == OK
		and is_equal_approx(float(saved_values.fov_scale), 1.15)
		and is_equal_approx(float(saved_values.hud_scale), 2.5)
	)
	var start_button := await _wait_for_button("Start Game")
	var click_at := await _click(start_button)
	if not await _wait_for_level():
		_fail("Start Game did not open %s" % LEVEL_SCENE)
		return
	for _i in 10:
		await process_frame
	var level := _view_snapshot(view_settings)
	level["touch_controls_visible"] = touch_controls == null or touch_controls.visible
	checks["applied_in_level"] = (
		absf(level.world_area / (384.0 * 216.0 * 1.15 * 1.15) - 1.0) < AREA_TOLERANCE
		and is_equal_approx(level.status_bar_scale, 2.5)
		and level.touch_controls_visible
	)
	print("VERIFY_LEVEL_VIEW %s" % JSON.stringify(level))
	await _shot("level-applied.png")
	var passed := true
	for key: String in checks:
		passed = passed and bool(checks[key])
	var player := get_first_node_in_group("player") as Node2D
	_write_result(
		passed,
		title,
		click_at,
		player.global_position,
		player.global_position,
		"tapped FOV and HUD sliders at min/default/max, then started the game",
		{
			"checks": checks,
			"fov_runs": fov_runs,
			"hud_runs": hud_runs,
			"saved": saved_values,
			"level_view": level
		}
	)
	if not passed:
		_fail("view-settings check failed: %s" % JSON.stringify(checks))
		return
	print("VERIFY_PASS view-settings")
	quit(0)


# True when the Settings touch row has exactly the active scheme's button pressed.
func _settings_shows_scheme(touch_controls: Node) -> bool:
	if touch_controls == null:
		return false
	var active: String = touch_controls.call("get_scheme_name")
	var pressed: Array = []
	for entry: Dictionary in TOUCH_SCHEMES:
		var button := _find_button(entry.label)
		if button == null:
			return false
		if button.button_pressed:
			pressed.append(entry.scheme)
	return pressed == [active]


# Taps a slider's track with a screen touch (mouse comes from touch emulation, as on a phone).
func _tap_slider(slider: HSlider, fraction: float) -> void:
	var rect := slider.get_global_rect()
	var x := lerpf(rect.position.x + 1.0, rect.end.x - 1.0, fraction)
	var point := _to_window(Vector2(x, rect.get_center().y))
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = point
		Input.parse_input_event(touch)
		await process_frame
	for _i in 3:
		await process_frame


func _view_snapshot(view_settings: Node) -> Dictionary:
	var viewport_size := root.get_visible_rect().size
	var camera := root.get_camera_2d()
	var world := viewport_size / camera.zoom if camera != null else Vector2.ZERO
	var status_bar := _first_of_class(current_scene, "StatusBar") as Control
	var arrow := _first_of_class(current_scene, "DetectionArrow") as Node2D
	return {
		"fov_scale": view_settings.get("fov_scale"),
		"hud_scale": view_settings.get("hud_scale"),
		"viewport_units": {"x": viewport_size.x, "y": viewport_size.y},
		"orientation": "portrait" if viewport_size.y > viewport_size.x else "landscape",
		"zoom": camera.zoom.x if camera != null else 0.0,
		"world_px": {"x": world.x, "y": world.y},
		"world_area": world.x * world.y,
		"tiles": {"x": world.x / 16.0, "y": world.y / 16.0},
		"status_bar_scale": status_bar.scale.x if status_bar != null else 0.0,
		"detection_arrow_scale": arrow.scale.x if arrow != null else 0.0,
	}


func _first_of_class(parent: Node, script_class: String) -> Node:
	for node in parent.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and script.get_global_name() == script_class:
			return node
	return null


func _wait_for_scene(path: String) -> bool:
	for _i in 120:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			return true
	return false


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


func _write_result(
	passed: bool,
	title: String,
	click_at: Vector2,
	before: Vector2,
	after: Vector2,
	detail: String,
	extra: Dictionary = {}
) -> void:
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
		"window_px": {"x": root.size.x, "y": root.size.y},
		"viewport_units":
		{"x": root.get_visible_rect().size.x, "y": root.get_visible_rect().size.y},
	}
	body.merge(extra)
	var file := FileAccess.open(_evidence.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		push_error("VERIFY_FAIL could not write result.json")
		return
	file.store_string(JSON.stringify(body, "  "))
	file.close()


func _fail(reason: String) -> void:
	push_error("VERIFY_FAIL %s" % reason)
	quit(2)
