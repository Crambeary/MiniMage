extends Node2D

signal player_detected(detector, detection_level)
signal player_detection_lost(detector)
signal player_caught(catcher)

enum IdleTasks { PATROL, WAIT, INVESTIGATE_LKP, CHASE }
enum AlertnessState { IDLE, SUSPICIOUS, ALERTED }

const STATUS_BAR_SCENE: PackedScene = preload("res://assets/scenes/ui/status_bar.tscn")
const STATUS_BAR_Y_OFFSET_FROM_SPRITE_TOP: float = -10.0
const PADDING_BELOW_EMOTE: float = 2.0
const IDLE_COLOR := Color.WHITE
const SUSPICIOUS_COLOR := Color.YELLOW
const ALERTED_COLOR := Color.RED
const CATCH_DISTANCE: float = 8.0

@export var path_group_name: String = "Sentry1"
@export var idle_task = IdleTasks.PATROL
@export var alertness_state = AlertnessState.IDLE
@export_range(0.0, 1.0, 0.01) var alertness_value: float = 0.0:
	set(value):
		var new_value = clampf(value, 0.0, 1.0)
		if alertness_value == new_value:
			return
		alertness_value = new_value
		if is_instance_valid(status_bar_instance):
			status_bar_instance.update_status(alertness_value, 1.0)
@export_range(0.0, 1.0, 0.05) var suspicion_threshold: float = 0.3
@export_range(0.0, 1.0, 0.05) var alertness_threshold: float = 0.7
@export var initial_alertness_increase_rate: float = 0.2
@export var alertness_increase_rate: float = 0.5
@export_range(1.0, 5.0, 0.1) var center_speed_multiplier: float = 2.0
@export_range(0.0, 1.0, 0.05) var turn_delay: float = 0.7
@export_range(1.0, 5.0, 0.1) var facing_speed_multiplier: float = 2.5
@export_range(0.1, 10.0, 0.1) var turn_speed: float = 3.0
@export var idle_cooldown_delay: float = 2.0
@export var idle_cooldown_rate: float = 0.1
@export var suspicious_cooldown_delay: float = 5.0
@export var suspicious_cooldown_rate: float = 0.05
@export var obstacle_collision_mask: int = 1
@export var speed: float = 10.0

var player: Node2D
var status_bar_instance: StatusBar
var current_index: int = 0
var dir: Vector2
var cooldown_timer: float = 0.0
var is_in_cooldown: bool = false
var was_player_seen: bool = false
var player_last_known_position: Vector2 = Vector2.ZERO
var _player_was_visible_last_frame: bool = false
var _last_movement_dir: Vector2 = Vector2.DOWN
var _has_caught_player: bool = false
var _detection_time: float = 0.0
var _has_started_turning: bool = false

@onready var vision_manager: VisionManager = $VisionManager
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var question_mark: Node2D = $Emotes/QuestionMark
@onready var exclamation: Node2D = $Emotes/Exclamation
@onready var emote_node: Node2D = $Emotes
@onready var waypoints: Array = get_tree().get_first_node_in_group(path_group_name).get_children()


func get_current_waypoint():
	return waypoints[current_index] as Marker2D


func handle_waypoint_action(wp):
	match wp.action:
		"wait":
			idle_task = IdleTasks.WAIT
			await get_tree().create_timer(wp.wait_time, false).timeout
			if idle_task == IdleTasks.WAIT:
				idle_task = IdleTasks.PATROL
		_:
			pass


func set_vision_direction(direction: Vector2) -> void:
	direction = direction * -1
	vision_manager.rotation = direction.angle()


func update_alertness():
	if (
		alertness_value < suspicion_threshold
		and alertness_state != AlertnessState.IDLE
		and idle_task != IdleTasks.INVESTIGATE_LKP
	):
		update_alert_state(AlertnessState.IDLE)
		idle_task = IdleTasks.PATROL
		question_mark.visible = false
		exclamation.visible = false
	elif (
		alertness_value >= suspicion_threshold
		and alertness_value < alertness_threshold
		and alertness_state != AlertnessState.SUSPICIOUS
	):
		update_alert_state(AlertnessState.SUSPICIOUS)

		if is_instance_valid(player):
			var space_state = get_world_2d().direct_space_state
			if space_state:
				var query_params = PhysicsRayQueryParameters2D.create(
					global_position, player.global_position, obstacle_collision_mask
				)
				query_params.collide_with_areas = true
				query_params.collide_with_bodies = true

				var result = space_state.intersect_ray(query_params)

				if not result:
					player_last_known_position = player.global_position

			else:
				player_last_known_position = player.global_position
		else:
			player_last_known_position = global_position

		idle_task = IdleTasks.WAIT
		question_mark.visible = true
		exclamation.visible = false
		call_deferred("_start_investigation_after_surprise")
	elif alertness_value >= alertness_threshold and alertness_state != AlertnessState.ALERTED:
		update_alert_state(AlertnessState.ALERTED)
		question_mark.visible = false
		exclamation.visible = true


func _update_status_bar_color() -> void:
	if not is_instance_valid(status_bar_instance):
		return

	match alertness_state:
		AlertnessState.IDLE:
			status_bar_instance.set_fill_color(IDLE_COLOR)
		AlertnessState.SUSPICIOUS:
			status_bar_instance.set_fill_color(SUSPICIOUS_COLOR)
		AlertnessState.ALERTED:
			status_bar_instance.set_fill_color(ALERTED_COLOR)
		_:
			status_bar_instance.set_fill_color(Color.WHITE)


func _start_investigation_after_surprise() -> void:
	if alertness_state != AlertnessState.SUSPICIOUS:
		return
	await get_tree().create_timer(1.0).timeout

	if alertness_state == AlertnessState.SUSPICIOUS:
		idle_task = IdleTasks.INVESTIGATE_LKP
	else:
		return


func update_alert_state(new_state: AlertnessState) -> void:
	if alertness_state == new_state:
		return

	alertness_state = new_state

	print("Sentry alertness_state changed to: ", AlertnessState.find_key(alertness_state))

	_update_status_bar_color()

	match alertness_state:
		AlertnessState.IDLE:
			question_mark.visible = false
			exclamation.visible = false
		AlertnessState.SUSPICIOUS:
			question_mark.visible = true
			exclamation.visible = false
		AlertnessState.ALERTED:
			question_mark.visible = false
			exclamation.visible = true
			idle_task = IdleTasks.CHASE


func _ready() -> void:
	print("Sentry _ready: Attempting to initialize status bar.")
	if STATUS_BAR_SCENE == null:
		push_error("Sentry _ready: STATUS_BAR_SCENE is null! Preload failed.")
		return
	print("Sentry _ready: STATUS_BAR_SCENE loaded successfully.")

	player = get_tree().get_first_node_in_group("player")

	if STATUS_BAR_SCENE:
		status_bar_instance = STATUS_BAR_SCENE.instantiate() as StatusBar
		if status_bar_instance == null:
			push_error(
				"Sentry _ready: Failed to instantiate STATUS_BAR_SCENE! status_bar_instance is null."
			)

		else:
			print("Sentry _ready: status_bar_instance created successfully: ", status_bar_instance)

		add_child(status_bar_instance)

		status_bar_instance.update_status(alertness_value, 1.0)

		_update_status_bar_color()
	else:
		push_error("Sentry _ready: STATUS_BAR_SCENE was unexpectedly null after initial check.")

	player_last_known_position = global_position


func _physics_process(delta: float) -> void:
	if idle_task == IdleTasks.WAIT:
		if abs(_last_movement_dir.x) > abs(_last_movement_dir.y):
			animated_sprite_2d.play("idle_side")
			animated_sprite_2d.flip_h = _last_movement_dir.x < 0
		else:
			if _last_movement_dir.y > 0:
				animated_sprite_2d.play("idle_down")
			else:
				animated_sprite_2d.play("idle_up")

	elif idle_task == IdleTasks.PATROL:
		if waypoints.size() == 0:
			return
		var target = get_current_waypoint().global_position
		dir = (target - global_position).normalized()

		if global_position.distance_to(target) > 0.5:
			global_position += dir * speed * delta
			if not _has_started_turning:
				set_vision_direction(dir)
			_last_movement_dir = dir

			if dir.x <= -0.5:
				animated_sprite_2d.flip_h = true
				animated_sprite_2d.play("walk_side")
			elif dir.x >= 0.5:
				animated_sprite_2d.flip_h = false
				animated_sprite_2d.play("walk_side")
			if dir.y >= 0.5:
				animated_sprite_2d.play("walk_down")
			elif dir.y <= -0.5:
				animated_sprite_2d.play("walk_up")
		else:
			handle_waypoint_action(get_current_waypoint())
			current_index = (current_index + 1) % waypoints.size()

	elif idle_task == IdleTasks.INVESTIGATE_LKP:
		var target_position = player_last_known_position

		dir = (target_position - global_position).normalized()
		var distance_to_lkp = global_position.distance_to(target_position)

		if distance_to_lkp > 10.0:
			global_position += dir * speed * delta
			if not _has_started_turning:
				set_vision_direction(dir)
			_last_movement_dir = dir

			if dir.x <= -0.5:
				animated_sprite_2d.flip_h = true
				animated_sprite_2d.play("walk_side")
			elif dir.x >= 0.5:
				animated_sprite_2d.flip_h = false
				animated_sprite_2d.play("walk_side")
			if dir.y >= 0.5:
				animated_sprite_2d.play("walk_down")
			elif dir.y <= -0.5:
				animated_sprite_2d.play("walk_up")
		else:
			idle_task = IdleTasks.WAIT

	elif idle_task == IdleTasks.CHASE:
		_chase_player(delta)

	if is_instance_valid(vision_manager) and is_instance_valid(player):
		var player_is_currently_visible: bool = vision_manager.can_see_point(player.global_position)
		_on_vision_manager_player_visibility_updated(player_is_currently_visible, delta)

	_handle_alertness_cooldown(delta)
	update_alertness()


func _chase_player(delta: float) -> void:
	if _has_caught_player or not is_instance_valid(player):
		return
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() <= CATCH_DISTANCE:
		_has_caught_player = true
		idle_task = IdleTasks.WAIT
		player_caught.emit(self)
		return
	dir = to_player.normalized()
	global_position += dir * minf(maxf(speed * delta, 0.0), to_player.length() - CATCH_DISTANCE)
	set_vision_direction(dir)
	_last_movement_dir = dir
	if absf(dir.x) > absf(dir.y):
		animated_sprite_2d.flip_h = dir.x < 0.0
		animated_sprite_2d.play("walk_side")
	elif dir.y > 0.0:
		animated_sprite_2d.play("walk_down")
	else:
		animated_sprite_2d.play("walk_up")


func _on_vision_manager_player_visibility_updated(p_is_visible: bool, delta: float) -> void:
	if p_is_visible:
		is_in_cooldown = false
		cooldown_timer = 0.0
		was_player_seen = true
		_detection_time += delta
		if _detection_time >= turn_delay:
			_has_started_turning = true
			_turn_toward_player(delta)

		var detection_multiplier: float = _get_detection_speed_multiplier()

		if alertness_value < suspicion_threshold:
			alertness_value = min(
				alertness_value + (initial_alertness_increase_rate * detection_multiplier * delta),
				1.0
			)
		else:
			alertness_value = min(
				alertness_value + (alertness_increase_rate * detection_multiplier * delta), 1.0
			)

		if not _player_was_visible_last_frame:
			emit_signal("player_detected", self, alertness_value)

	else:
		_detection_time = 0.0
		_has_started_turning = false
		if _player_was_visible_last_frame:
			emit_signal("player_detection_lost", self)

		if was_player_seen and !is_in_cooldown:
			cooldown_timer += delta

			var active_cooldown_delay: float = idle_cooldown_delay
			if alertness_state == AlertnessState.SUSPICIOUS:
				active_cooldown_delay = suspicious_cooldown_delay

			if cooldown_timer >= active_cooldown_delay:
				is_in_cooldown = true
				cooldown_timer = 0.0

	_player_was_visible_last_frame = p_is_visible


func _get_detection_speed_multiplier() -> float:
	if _has_started_turning:
		return facing_speed_multiplier

	var direction_to_player: Vector2 = player.global_position - vision_manager.global_position
	if direction_to_player.is_zero_approx():
		return center_speed_multiplier

	var facing_angle: float = absf(
		vision_manager.get_forward_vector().angle_to(direction_to_player.normalized())
	)
	var half_arc: float = deg_to_rad(vision_manager.sight_arc / 2.0)
	if half_arc <= 0.0:
		return 1.0
	var center_weight: float = 1.0 - clampf(facing_angle / half_arc, 0.0, 1.0)
	return lerpf(1.0, center_speed_multiplier, center_weight)


func _turn_toward_player(delta: float) -> void:
	var direction_to_player: Vector2 = player.global_position - vision_manager.global_position
	if direction_to_player.is_zero_approx():
		return
	var target_rotation: float = (
		direction_to_player.angle() - vision_manager.get_local_forward_vector().angle()
	)
	vision_manager.global_rotation = rotate_toward(
		vision_manager.global_rotation, target_rotation, turn_speed * delta
	)


func _handle_alertness_cooldown(delta: float) -> void:
	if is_in_cooldown:
		var active_cooldown_rate: float = idle_cooldown_rate
		if alertness_value >= suspicion_threshold:
			active_cooldown_rate = suspicious_cooldown_rate
		alertness_value = max(alertness_value - (active_cooldown_rate * delta), 0.0)

		if alertness_value <= 0.0:
			alertness_value = 0.0
			was_player_seen = false
			is_in_cooldown = false

			emit_signal("player_detection_lost", self)


func _process(_delta: float) -> void:
	if is_instance_valid(status_bar_instance):
		var status_bar_pos: Vector2 = Vector2.ZERO

		status_bar_pos.x = -status_bar_instance.size.x / 2.0

		if is_instance_valid(emote_node) and emote_node.visible:
			var emote_height: float = 0.0
			if emote_node.has_method("get_rect"):
				emote_height = emote_node.get_rect().size.y * emote_node.scale.y
			elif emote_node is Sprite2D and emote_node.texture:
				emote_height = emote_node.texture.get_height() * emote_node.scale.y

			var emote_bottom_y: float = emote_node.position.y + emote_height
			status_bar_pos.y = emote_bottom_y + PADDING_BELOW_EMOTE
		elif is_instance_valid(animated_sprite_2d):
			var sprite_top_y: float = 0.0
			if animated_sprite_2d.sprite_frames and animated_sprite_2d.animation:
				var current_anim_name: StringName = animated_sprite_2d.animation
				if animated_sprite_2d.sprite_frames.has_animation(current_anim_name):
					var frame_texture: Texture2D = (
						animated_sprite_2d
						. sprite_frames
						. get_frame_texture(current_anim_name, animated_sprite_2d.frame)
					)
					if frame_texture:
						sprite_top_y = (
							-frame_texture.get_height() / 2.0 * animated_sprite_2d.scale.y
						)
			status_bar_pos.y = sprite_top_y + STATUS_BAR_Y_OFFSET_FROM_SPRITE_TOP

		status_bar_instance.position = status_bar_pos
