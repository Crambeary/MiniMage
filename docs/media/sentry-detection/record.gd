extends SceneTree

## Replays player input through the real level and saves rendered frames plus
## telemetry for the sentry detection recording. No gameplay nodes are moved.

const MAIN_MENU := "res://assets/scenes/ui/MainMenu.tscn"
const LEVEL := "res://assets/scenes/levels/main.tscn"
const OUTPUT_DIR := "res://docs/media/sentry-detection/frames"
const CAPTURE_EVERY_PHYSICS_FRAMES := 6

var _frame_index := 0
var _label: Label
var _telemetry: FileAccess
var _output_dir := OUTPUT_DIR


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var override_dir := OS.get_environment("SENTRY_RECORD_OUTPUT_DIR")
	if not override_dir.is_empty():
		_output_dir = override_dir
	var absolute_output := (
		ProjectSettings.globalize_path(_output_dir)
		if _output_dir.begins_with("res://")
		else _output_dir
	)
	DirAccess.make_dir_recursive_absolute(absolute_output)
	_telemetry = FileAccess.open(absolute_output.path_join("telemetry.csv"), FileAccess.WRITE)
	if _telemetry == null:
		push_error("RECORD_FAIL could not open telemetry.csv")
		quit(1)
		return
	_telemetry.store_line(
		(
			"frame,phase,detector,player_x,player_y,sentry_x,sentry_y,visible,angle_deg,"
			+ "alertness,multiplier,turning"
		)
	)

	var error := change_scene_to_file(MAIN_MENU)
	if error != OK:
		push_error("RECORD_FAIL could not open main menu: %s" % error)
		quit(1)
		return
	var button := await _wait_for_button("Start Game")
	if button == null:
		push_error("RECORD_FAIL Start Game button did not appear")
		quit(1)
		return
	await _click(button)
	if not await _wait_for_level():
		push_error("RECORD_FAIL level did not open")
		quit(1)
		return
	_add_telemetry_overlay()

	# Move down into the gap, then right past the wall. These are physical player
	# inputs using the same actions as the normal game controls.
	await _hold_key(KEY_S, 72, true)
	await _hold_key(KEY_D, 100, true)

	# The second patrol sees the mage near the cone edge in this approach. Move
	# along the screen using player inputs so the view angle changes naturally.
	await _hold_keys([KEY_D, KEY_W], 20, true)
	await _hold_key(KEY_D, 44, true)

	# Let the patrol turn and detection continue; stop when the tree pauses at a
	# full alert or after the evidence window is complete.
	for frame in 180:
		await physics_frame
		if frame % CAPTURE_EVERY_PHYSICS_FRAMES == 0:
			await _capture_frame()
		if paused:
			break

	_telemetry.close()
	print("RECORD_PASS frames=%d output=%s" % [_frame_index, _output_dir])
	quit(0)


func _add_telemetry_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RecordingTelemetry"
	root.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)
	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.065, 0.88)
	style.border_color = Color(0.54, 0.67, 0.82, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _capture_frame() -> void:
	var player := get_nodes_in_group("player")[0] as Node2D
	var best_sentry: Node2D
	var best_visible_sentry: Node2D
	var best_visible_value := -1.0
	var best_value := -1.0
	for node in get_nodes_in_group("sentry"):
		var sentry := node as Node2D
		var sentry_visible: bool = sentry.vision_manager.can_see_point(player.global_position)
		if sentry_visible and sentry.alertness_value > best_visible_value:
			best_visible_sentry = sentry
			best_visible_value = sentry.alertness_value
		if sentry.alertness_value > best_value:
			best_value = sentry.alertness_value
			best_sentry = sentry
	if is_instance_valid(best_visible_sentry):
		best_sentry = best_visible_sentry
	if not is_instance_valid(best_sentry):
		return

	var to_player: Vector2 = player.global_position - best_sentry.vision_manager.global_position
	var visible: bool = best_sentry.vision_manager.can_see_point(player.global_position)
	var angle_deg := (
		absf(best_sentry.vision_manager.get_forward_vector().angle_to(to_player.normalized()))
		* 180.0
		/ PI
	)
	var multiplier: float = best_sentry._get_detection_speed_multiplier()
	var turning: bool = best_sentry._has_started_turning
	var half_arc_deg: float = best_sentry.vision_manager.sight_arc / 2.0
	var phase := "NOT IN VIEW"
	if turning:
		phase = "TURNING · x%.1f detection" % multiplier
	elif visible and angle_deg < 12.0:
		phase = "CENTER VIEW · x%.1f detection" % multiplier
	elif visible and angle_deg <= half_arc_deg:
		phase = "PERIPHERAL VIEW · x%.1f detection" % multiplier
	elif visible:
		phase = "CLOSE RANGE · x%.1f detection" % multiplier
	var multiplier_text := "x%.1f" % multiplier if visible else "—"
	_label.text = (
		"SENTRY DETECTION DEMO · %s\n%s\nAlertness: %0.3f · View angle: %0.1f° · %s"
		% [best_sentry.name, phase, best_sentry.alertness_value, angle_deg, multiplier_text]
	)

	var root_texture := root.get_texture()
	if root_texture == null:
		return
	await RenderingServer.frame_post_draw
	var image := root_texture.get_image()
	var absolute_output := (
		ProjectSettings.globalize_path(_output_dir)
		if _output_dir.begins_with("res://")
		else _output_dir
	)
	var filename := "frame-%04d.png" % _frame_index
	var error := image.save_png(absolute_output.path_join(filename))
	if error != OK:
		push_error("RECORD_FAIL could not save %s: %s" % [filename, error])
		return
	(
		_telemetry
		. store_line(
			(
				"%d,%s,%s,%0.3f,%0.3f,%0.3f,%0.3f,%s,%0.2f,%0.3f,%0.2f,%s"
				% [
					_frame_index,
					phase,
					best_sentry.name,
					player.global_position.x,
					player.global_position.y,
					best_sentry.global_position.x,
					best_sentry.global_position.y,
					str(visible),
					angle_deg,
					best_sentry.alertness_value,
					multiplier,
					str(turning),
				]
			)
		)
	)
	_frame_index += 1


func _hold_key(code: Key, frames: int, capture: bool) -> void:
	for i in frames:
		_push_key(code, true, i > 0)
		await physics_frame
		if capture and i % CAPTURE_EVERY_PHYSICS_FRAMES == 0:
			await _capture_frame()
	_push_key(code, false, false)
	await physics_frame


func _hold_keys(codes: Array[Key], frames: int, capture: bool) -> void:
	for i in frames:
		for code in codes:
			_push_key(code, true, i > 0)
		await physics_frame
		if capture and i % CAPTURE_EVERY_PHYSICS_FRAMES == 0:
			await _capture_frame()
	for code in codes:
		_push_key(code, false, false)
	await physics_frame


func _push_key(code: Key, pressed: bool, echo: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _wait_for_button(text: String) -> Button:
	for _i in 120:
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


func _click(control: Control) -> void:
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
	root.push_input(release)
	await process_frame


func _wait_for_level() -> bool:
	for _i in 180:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == LEVEL:
			if get_nodes_in_group("player").size() > 0:
				return true
	return false
