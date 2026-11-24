extends SceneTree

## Deterministic staged recording of sentry detection speed, run in the real level.
##
## Run with --fixed-fps 60 and --write-movie <png path> so every rendered frame is
## exactly one physics step. Telemetry rows carry the same frame number as the
## PNG they describe. The recorder pins the sentry's facing and freezes its patrol,
## and teleports the player to fixed coordinates per segment, so the only value
## that changes during a segment is the detection meter.

const MAIN_MENU := "res://assets/scenes/ui/MainMenu.tscn"
const LEVEL := "res://assets/scenes/levels/main.tscn"
const SentryScript := preload("res://assets/scenes/characters/sentry.gd")
const DEFAULT_TELEMETRY_PATH := "res://docs/media/sentry-detection/telemetry.csv"
const SENTRY_NODE := "Sentry"
const BYSTANDER_SENTRY_NODE := "Sentry2"
const SENTRY_FACING := Vector2.LEFT
const LEAD_IN_FRAMES := 60
const TITLE_HOLD_FRAMES := 60
const LOST_HOLD_FRAMES := 30
const MAX_SEGMENT_FRAMES := 480
# Stop each segment before the sentry reaches ALERTED (alertness_threshold 0.7),
# so no chase starts and no segment ends in a catch.
const STAGE_STOP_ALERTNESS := 0.6
const HIDDEN_POSITION := Vector2(-900, 900)

const SEGMENTS := [
	{
		"id": "A",
		"title": "A · PERIPHERAL — baseline fill",
		"note": "Player 30° off axis, inside the 35° half-arc. Turn held: fill is baseline only.",
		"angle_deg": -30.0,
		"distance": 50.0,
		"turns": false,
	},
	{
		"id": "B",
		"title": "B · CENTER — fills at x2.0",
		"note": "Player dead center on the sentry's facing axis (0°), 200px away. Turn held.",
		"angle_deg": 0.0,
		"distance": 200.0,
		"turns": false,
	},
	{
		"id": "C",
		"title": "C · TURN — fills at x2.5 after the turn",
		"note": "Player starts 20° off axis. After 0.7s in view the sentry turns to face them.",
		"angle_deg": -20.0,
		"distance": 70.0,
		"turns": true,
	},
]

var _sentry: Node2D
var _player: Node2D
# Set per segment. While false, the detection timer is held at zero so the sentry's
# 0.7s turn never starts and the fill stays at its baseline or center multiplier.
var _turn_allowed := true
var _telemetry: FileAccess
var _title: Label
var _note: Label
var _readout: Label
var _meter: AlertMeter
var _cone: SentryCone


class AlertMeter:
	extends Control
	var alertness := 0.0
	var multiplier_text := "—"

	func _init() -> void:
		custom_minimum_size = Vector2(420, 78)

	func _draw() -> void:
		var font := get_theme_default_font()
		var bar := Rect2(Vector2(0, 30), Vector2(size.x, 22))
		draw_rect(bar, Color(0.1, 0.12, 0.16, 0.95))
		var fill := Color.WHITE
		if alertness >= 0.7:
			fill = Color(1, 0.25, 0.2)
		elif alertness >= 0.3:
			fill = Color(1, 0.85, 0.2)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * alertness, bar.size.y)), fill)
		for mark in [0.3, 0.7]:
			var x: float = bar.position.x + bar.size.x * mark
			draw_line(Vector2(x, bar.position.y - 4), Vector2(x, bar.end.y + 4), Color.WHITE, 2.0)
		draw_string(
			font,
			Vector2(0, 20),
			"DETECTION METER  %0.3f   fill %s" % [alertness, multiplier_text],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			17,
			Color.WHITE
		)
		draw_string(
			font,
			Vector2(bar.position.x + bar.size.x * 0.3 - 40, 72),
			"suspicious 0.3",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(1, 0.85, 0.2)
		)
		draw_string(
			font,
			Vector2(bar.position.x + bar.size.x * 0.7 - 30, 72),
			"alerted 0.7",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(1, 0.4, 0.35)
		)


class SentryCone:
	extends Node2D
	var sentry: Node2D
	var player: Node2D
	var reach := 250.0
	var half_arc_deg := 35.0

	func _draw() -> void:
		if not is_instance_valid(sentry) or not is_instance_valid(player):
			return
		var vision: Node2D = sentry.vision_manager
		var eye := to_local(vision.global_position)
		var forward: Vector2 = vision.get_forward_vector()
		var half := deg_to_rad(half_arc_deg)
		var points := PackedVector2Array([eye])
		var steps := 32
		for i in steps + 1:
			points.append(eye + forward.rotated(lerpf(-half, half, float(i) / steps)) * reach)
		draw_colored_polygon(points, Color(1, 0.95, 0.5, 0.16))
		draw_line(eye, eye + forward.rotated(half) * reach, Color(1, 0.85, 0.2, 0.9), 2.0)
		draw_line(eye, eye + forward.rotated(-half) * reach, Color(1, 0.85, 0.2, 0.9), 2.0)
		draw_line(eye, eye + forward * reach, Color(1, 1, 1, 0.7), 1.5)
		var to_player := to_local(player.global_position)
		var off_axis := absf(rad_to_deg(forward.angle_to(to_player - eye)))
		var line_color := Color(0.4, 1, 0.5, 1) if off_axis < 2.0 else Color(1, 0.6, 0.3, 1)
		draw_line(eye, to_player, line_color, 2.0)
		draw_circle(to_player, 5.0, line_color)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var telemetry_path := OS.get_environment("SENTRY_RECORD_TELEMETRY")
	if telemetry_path.is_empty():
		telemetry_path = DEFAULT_TELEMETRY_PATH
	var absolute_telemetry := (
		ProjectSettings.globalize_path(telemetry_path)
		if telemetry_path.begins_with("res://")
		else telemetry_path
	)
	_telemetry = FileAccess.open(absolute_telemetry, FileAccess.WRITE)
	if _telemetry == null:
		push_error("RECORD_FAIL could not open telemetry at %s" % absolute_telemetry)
		quit(1)
		return
	_telemetry.store_line(
		(
			"frame,segment,phase,player_x,player_y,sentry_x,sentry_y,facing_deg,visible,"
			+ "angle_deg,alertness,multiplier,turning"
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

	_sentry = current_scene.get_node(SENTRY_NODE)
	# The second patrol is switched off so only the staged sentry can see the player.
	var bystander := current_scene.get_node(BYSTANDER_SENTRY_NODE) as Node2D
	bystander.process_mode = Node.PROCESS_MODE_DISABLED
	bystander.visible = false
	_player = get_nodes_in_group("player")[0] as Node2D
	_sentry.speed = 0.0
	# Render at the movie's native 1152x648 so overlay pixels match video pixels whatever
	# size the window manager gives the editor window.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1152, 648)
	_build_overlay()
	print("OVERLAY screen=%s" % root.get_visible_rect().size)

	_reset_sentry()
	_player.global_position = HIDDEN_POSITION
	_set_caption("Stage setup", "Sentry frozen and facing right. Player is out of view.")
	for i in LEAD_IN_FRAMES:
		await _step("SETUP", "SETUP · player hidden")

	for segment in SEGMENTS:
		if not await _run_segment(segment):
			_telemetry.close()
			quit(1)
			return

	_telemetry.close()
	print("RECORD_PASS telemetry=%s" % absolute_telemetry)
	quit(0)


func _run_segment(segment: Dictionary) -> bool:
	var segment_id: String = segment.id
	_turn_allowed = segment.turns
	_reset_sentry()
	_player.global_position = HIDDEN_POSITION
	_set_caption(segment.title, segment.note)
	for i in TITLE_HOLD_FRAMES:
		await _step(segment_id, "SETUP · player hidden")

	var target := _find_stage_point(segment.angle_deg, segment.distance)
	print(
		(
			"STAGE %s target=(%0.1f, %0.1f) angle=%0.1f distance=%0.1f"
			% [
				segment_id,
				target.x,
				target.y,
				segment.angle_deg,
				target.distance_to(_sentry.vision_manager.global_position)
			]
		)
	)
	_player.global_position = target
	var reached := false
	for i in MAX_SEGMENT_FRAMES:
		await _step(segment_id, "")
		if _sentry.alertness_value >= STAGE_STOP_ALERTNESS:
			reached = true
			break
	if not reached:
		push_error(
			(
				"RECORD_FAIL segment %s did not reach %0.2f alertness"
				% [segment_id, STAGE_STOP_ALERTNESS]
			)
		)
		return false

	_player.global_position = HIDDEN_POSITION
	_set_caption(segment.title, "Player leaves view. Resetting the sentry for the next segment.")
	for i in LOST_HOLD_FRAMES:
		await _step(segment_id, "LOST · player hidden")
	return true


## Picks a point near the requested off-axis angle and distance that has clear floor
## around it (no wall or prop within the player's body radius) and that the sentry can
## see. Candidates are tried in a fixed order, so the same level gives the same point.
func _find_stage_point(angle_deg: float, preferred_distance: float) -> Vector2:
	var vision: Node2D = _sentry.vision_manager
	var eye := vision.global_position
	var space := _player.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = _player.collision_mask
	for angle_offset in [0.0, -1.0, 1.0, -2.0, 2.0, -3.0, 3.0, -4.0, 4.0]:
		var direction := SENTRY_FACING.rotated(deg_to_rad(angle_deg + angle_offset))
		for distance_offset in [0.0, -20.0, 20.0, -40.0, 40.0, -60.0, 60.0, -80.0, 80.0]:
			var distance := clampf(preferred_distance + distance_offset, 40.0, 230.0)
			var point := eye + direction * distance
			if not _has_clear_floor(space, query, point):
				continue
			if vision.can_see_point(point):
				print("STAGE_POINT angle_offset=%0.1f distance=%0.1f" % [angle_offset, distance])
				return point
	push_error("RECORD_FAIL no clear visible point near %0.1f° from the sentry axis" % angle_deg)
	return eye + SENTRY_FACING.rotated(deg_to_rad(angle_deg)) * preferred_distance


## True when the point and its 8 neighbors at a 10px radius contain no collision body.
func _has_clear_floor(
	space: PhysicsDirectSpaceState2D, query: PhysicsPointQueryParameters2D, point: Vector2
) -> bool:
	for i in 9:
		var sample := point
		if i > 0:
			sample = point + Vector2.RIGHT.rotated(TAU * (i - 1) / 8.0) * 10.0
		query.position = sample
		if not space.intersect_point(query).is_empty():
			return false
	return true


func _step(segment_id: String, phase_override: String) -> void:
	_freeze_sentry()
	await physics_frame
	_refresh(segment_id, phase_override)


func _freeze_sentry() -> void:
	_sentry.idle_task = SentryScript.IdleTasks.WAIT
	if not _turn_allowed:
		_sentry._detection_time = 0.0
	# Pin the cone to the staged facing except while the sentry is turning toward the player.
	if not _sentry._has_started_turning:
		_sentry.set_vision_direction(SENTRY_FACING)


func _reset_sentry() -> void:
	_sentry.alertness_value = 0.0
	_sentry.update_alert_state(SentryScript.AlertnessState.IDLE)
	_sentry.idle_task = SentryScript.IdleTasks.WAIT
	_sentry.is_in_cooldown = false
	_sentry.was_player_seen = false
	_sentry.cooldown_timer = 0.0
	_sentry._detection_time = 0.0
	_sentry._has_started_turning = false
	_sentry._player_was_visible_last_frame = false
	_sentry.set_vision_direction(SENTRY_FACING)


func _refresh(segment_id: String, phase_override: String) -> void:
	var vision: Node2D = _sentry.vision_manager
	var eye: Vector2 = vision.global_position
	var forward: Vector2 = vision.get_forward_vector()
	var to_player: Vector2 = _player.global_position - eye
	var visible: bool = vision.can_see_point(_player.global_position)
	var angle_deg := rad_to_deg(absf(forward.angle_to(to_player)))
	var multiplier: float = _sentry._get_detection_speed_multiplier()
	var turning: bool = _sentry._has_started_turning
	var multiplier_text := "x%.2f" % multiplier if visible else "—"

	var phase := "NOT IN VIEW"
	if not phase_override.is_empty():
		phase = phase_override
	elif turning:
		phase = "TURNING · %s" % multiplier_text
	elif visible:
		phase = "IN VIEW · %s" % multiplier_text

	_meter.alertness = _sentry.alertness_value
	_meter.multiplier_text = multiplier_text
	_meter.queue_redraw()
	_cone.queue_redraw()
	_readout.text = (
		(
			"Segment %s   ·   %s\nAngle off sentry axis: %0.1f°   ·   Detection multiplier: %s\n"
			+ "Sentry turning: %s   ·   Alertness %0.3f (stop at %0.2f)"
		)
		% [
			segment_id,
			phase,
			angle_deg,
			multiplier_text,
			"yes" if turning else "no",
			_sentry.alertness_value,
			STAGE_STOP_ALERTNESS,
		]
	)

	(
		_telemetry
		. store_line(
			(
				"%d,%s,%s,%0.3f,%0.3f,%0.3f,%0.3f,%0.2f,%s,%0.2f,%0.4f,%0.3f,%s"
				% [
					Engine.get_frames_drawn(),
					segment_id,
					phase,
					_player.global_position.x,
					_player.global_position.y,
					eye.x,
					eye.y,
					rad_to_deg(forward.angle()),
					str(visible),
					angle_deg,
					_sentry.alertness_value,
					multiplier,
					str(turning),
				]
			)
		)
	)


func _set_caption(title: String, note: String) -> void:
	if _title == null:
		return
	_title.text = title
	_note.text = note


## Overlay layout uses fixed rectangles in screen pixels (the movie's native size), so
## panels never depend on container minimum sizes and nothing is clipped.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RecordingOverlay"
	layer.layer = 100
	root.add_child(layer)

	var screen := root.get_visible_rect().size

	# Stops short of the game's own touch-scheme selector at the top right.
	var caption := _make_panel(Vector2(960.0, 84.0))
	caption.position = Vector2(16.0, 12.0)
	_title = _make_label(26, Color(1, 0.9, 0.4))
	_title.position = Vector2(12.0, 6.0)
	_note = _make_label(18, Color.WHITE)
	_note.position = Vector2(12.0, 46.0)
	caption.add_child(_title)
	caption.add_child(_note)
	layer.add_child(caption)

	var meter_panel := _make_panel(Vector2(440.0, 92.0))
	meter_panel.position = Vector2(screen.x - 456.0, screen.y - 104.0)
	_meter = AlertMeter.new()
	_meter.position = Vector2(10.0, 6.0)
	_meter.size = Vector2(420.0, 78.0)
	meter_panel.add_child(_meter)
	layer.add_child(meter_panel)

	var readout_panel := _make_panel(Vector2(640.0, 92.0))
	readout_panel.position = Vector2(16.0, screen.y - 104.0)
	_readout = _make_label(17, Color.WHITE)
	_readout.position = Vector2(12.0, 10.0)
	readout_panel.add_child(_readout)
	layer.add_child(readout_panel)

	_cone = SentryCone.new()
	_cone.sentry = _sentry
	_cone.player = _player
	_cone.z_index = 50
	current_scene.add_child(_cone)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_panel(panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel


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
