extends Node2D

# Signals for player detection system
signal player_detected(detector, detection_level)
signal player_detection_lost(detector)

var player: Node2D
@onready var vision_manager: VisionManager = $VisionManager
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var question_mark: Node2D = $Emotes/QuestionMark
@onready var exclamation: Node2D = $Emotes/Exclamation
@onready var emote_node: Node2D = $Emotes
@onready var animated_sprite_2d_ref_for_status_bar: AnimatedSprite2D = $AnimatedSprite2D # Explicit reference for clarity

# Preload the status bar scene. Ensure this path is correct.
const STATUS_BAR_SCENE: PackedScene = preload("res://assets/scenes/ui/status_bar.tscn")

# CONFIGURATION for status bar positioning
const STATUS_BAR_Y_OFFSET_FROM_SPRITE_TOP: float = -10.0 # Negative to go upwards from origin
const PADDING_BELOW_EMOTE: float = 2.0 # Small space between emote and status bar

var status_bar_instance: StatusBar

# Color constants for alertness states
const IDLE_COLOR := Color.WHITE
const SUSPICIOUS_COLOR := Color.YELLOW
const ALERTED_COLOR := Color.RED

@export var path_group_name: String = "Sentry1"
@onready var waypoints: Array = get_tree().get_first_node_in_group(path_group_name).get_children()
var current_index: int = 0
var dir: Vector2
enum IdleTasks {PATROL, WAIT, INSPECT, RETURN, INVESTIGATE_LKP}
enum AlertnessState {IDLE, SUSPICIOUS, ALERTED}
@export var idle_task = IdleTasks.PATROL
@export var alertness_state = AlertnessState.IDLE
# Alertness ranges from 0.0 (completely calm) to 1.0 (fully alerted)
@export_range(0.0, 1.0, 0.01) var alertness_value: float = 0.0:
	set(value):
		var new_value = clampf(value, 0.0, 1.0)
		if alertness_value == new_value:
			return
		alertness_value = new_value
		# Update debug print for alertness
		# print_alertness_bar()
		# Potentially change state based on new alertness
		# check_alertness_thresholds()
		if is_instance_valid(status_bar_instance):
			status_bar_instance.update_status(alertness_value, 1.0) # Max is 1.0 for alertness

# Thresholds as percentages (0.0-1.0)
const SUSPICIOUS_THRESHOLD: float = 0.3 # Example: 30% alertness to become suspicious
@export_range(0.0, 1.0, 0.05) var suspicion_threshold: float = 0.3
@export_range(0.0, 1.0, 0.05) var alertness_threshold: float = 0.7

# Rate of change per second
@export var initial_alertness_increase_rate: float = 0.2  # Slow initial increase
@export var alertness_increase_rate: float = 0.5          # Faster increase once suspicious/alerted

# Cooldown for returning to IDLE (e.g., from ALERTED or brief sightings)
@export var idle_cooldown_delay: float = 2.0              # Seconds before idle cooldown starts
@export var idle_cooldown_rate: float = 0.1               # Rate of idle cooldown after delay

# Cooldown specific to SUSPICIOUS state
@export var suspicious_cooldown_delay: float = 5.0        # Seconds before suspicious cooldown starts
@export var suspicious_cooldown_rate: float = 0.05        # Rate of suspicious cooldown after delay (slower)

# Internal state
var cooldown_timer: float = 0.0
var is_in_cooldown: bool = false
var was_player_seen: bool = false
var was_previously_seen: bool = false  # For tracking when player first leaves sight
var _player_was_visible_last_frame: bool = false # More robust tracking for visibility change

# Player's last known position
var player_last_known_position: Vector2 = Vector2.ZERO
@export var obstacle_collision_mask: int = 1 # Layer mask for obstacles that block Line of Sight for LKP updates. Configure in editor.

@export var speed: float = 10.0
var _last_movement_dir: Vector2 = Vector2.DOWN # Store the last direction of movement

func get_enum_name(enum_dict: Dictionary, value: int) -> String:
	for enum_key in enum_dict.keys(): # Renamed 'name' to 'enum_key'
		if enum_dict[enum_key] == value:
			return enum_key
	return "Unknown"

func get_current_waypoint():
	return waypoints[current_index] as Marker2D
	
func handle_waypoint_action(wp):
	match wp.action:
		"wait":
			idle_task = IdleTasks.WAIT
			await get_tree().create_timer(wp.wait_time, false).timeout
			idle_task = IdleTasks.PATROL
		_:
			pass
	
func set_vision_direction(direction: Vector2) -> void:
	direction = direction * -1 # Invert Vector2 Values
	vision_manager.rotation = direction.angle()
	
func update_alertness():
	if alertness_value < suspicion_threshold \
	and alertness_state != AlertnessState.IDLE \
	and idle_task != IdleTasks.INVESTIGATE_LKP:
		update_alert_state(AlertnessState.IDLE)
		idle_task = IdleTasks.PATROL
		question_mark.visible = false
		exclamation.visible = false
	elif alertness_value >= suspicion_threshold \
	and alertness_value < alertness_threshold \
	and alertness_state != AlertnessState.SUSPICIOUS:
		update_alert_state(AlertnessState.SUSPICIOUS) # Change state first

		if is_instance_valid(player):
			var space_state = get_world_2d().direct_space_state
			if space_state:
				var query_params = PhysicsRayQueryParameters2D.create(global_position, player.global_position, obstacle_collision_mask)
				query_params.collide_with_areas = true # Ensure checks against Area2D obstacles
				query_params.collide_with_bodies = true # Ensure checks against PhysicsBody2D obstacles
				
				var result = space_state.intersect_ray(query_params)
				
				if not result: # No obstacle hit, LOS is clear to player's current position
					player_last_known_position = player.global_position
				# else: Obstacle hit, LKP not updated, player_last_known_position remains unchanged
			else: # space_state is null, fallback to updating LKP without this specific check
				player_last_known_position = player.global_position
		else: # player not valid, fallback
			player_last_known_position = global_position
		
		# These actions occur because the sentry is now suspicious.
		idle_task = IdleTasks.WAIT # Initial halt for surprise
		question_mark.visible = true
		exclamation.visible = false
		call_deferred("_start_investigation_after_surprise")
	elif alertness_value >= alertness_threshold \
	and alertness_state != AlertnessState.ALERTED:
		update_alert_state(AlertnessState.ALERTED)
		question_mark.visible = false
		exclamation.visible = true

# Helper function to update the status bar color based on current alertness_state
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
			# Fallback, though ideally this case shouldn't be reached if states are managed
			status_bar_instance.set_fill_color(Color.WHITE)

func _start_investigation_after_surprise() -> void:
	if alertness_state != AlertnessState.SUSPICIOUS: # Ensure we are still suspicious
		return
	await get_tree().create_timer(1.0).timeout # Adjust time as needed (e.g., 1.0 seconds)
	
	# Check state again after timer, as it might have changed (e.g., player re-spotted and became ALERTED)
	if alertness_state == AlertnessState.SUSPICIOUS:
		idle_task = IdleTasks.INVESTIGATE_LKP
	else:
		return

func update_alert_state(new_state: AlertnessState) -> void:
	if alertness_state == new_state:
		return
	
	alertness_state = new_state
	
	print("Sentry alertness_state changed to: ", AlertnessState.find_key(alertness_state)) # Debug print

	# Update status bar color
	_update_status_bar_color()

	# Update emote visibility (existing logic)
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
			# Trigger game over
			get_tree().change_scene_to_file("res://assets/scenes/ui/game_over_screen.tscn")
	
func _ready() -> void:
	print("Sentry _ready: Attempting to initialize status bar.") # Debug print
	if STATUS_BAR_SCENE == null:
		push_error("Sentry _ready: STATUS_BAR_SCENE is null! Preload failed.")
		return # Stop further execution if preload failed
	else:
		print("Sentry _ready: STATUS_BAR_SCENE loaded successfully.")
	
	player = get_tree().get_first_node_in_group("player")

	# Instantiate and add the status bar
	if STATUS_BAR_SCENE:
		status_bar_instance = STATUS_BAR_SCENE.instantiate() as StatusBar # Cast to StatusBar
		if status_bar_instance == null:
			push_error("Sentry _ready: Failed to instantiate STATUS_BAR_SCENE! status_bar_instance is null.")
			# return # Stop if instantiation failed - let's allow it to continue for now to see other errors if any
		else:
			print("Sentry _ready: status_bar_instance created successfully: ", status_bar_instance)
		
		add_child(status_bar_instance)
		# Initial update for alertness
		status_bar_instance.update_status(alertness_value, 1.0)
		# Set initial color
		_update_status_bar_color()
	else:
		# This case should ideally be caught by the null check above
		push_error("Sentry _ready: STATUS_BAR_SCENE was unexpectedly null after initial check.")

	player_last_known_position = global_position # Initialize LKP to self position

func _physics_process(delta: float) -> void:
	# Task-specific logic first
	if idle_task == IdleTasks.WAIT:
		# Animation logic for waiting, facing last movement direction
		if abs(_last_movement_dir.x) > abs(_last_movement_dir.y): # Was moving more horizontally
			animated_sprite_2d.play("idle_side")
			animated_sprite_2d.flip_h = _last_movement_dir.x < 0
		else: # Was moving more vertically
			if _last_movement_dir.y > 0:
				animated_sprite_2d.play("idle_down")
			else:
				animated_sprite_2d.play("idle_up")
		# Original line that made sentry always face down:
		# animated_sprite_2d.play("idle_down") 
		pass # No movement, just animation handled above

	elif idle_task == IdleTasks.PATROL:
		if waypoints.size() == 0:
			# print_debug("Sentry has no waypoints for patrol.")
			return # Cannot patrol without waypoints
		var target = get_current_waypoint().global_position
		dir = (target - global_position).normalized() # dir is updated here for patrol
		
		if global_position.distance_to(target) > 0.5:
			global_position += dir * speed * delta
			set_vision_direction(dir)
			_last_movement_dir = dir # Store this direction

			# Animation based on direction
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
			# print_debug("Waypoint reached: ", get_current_waypoint().name)

	elif idle_task == IdleTasks.INVESTIGATE_LKP:
		var target_position = player_last_known_position
		# dir is updated here for investigation
		dir = (target_position - global_position).normalized() 
		var distance_to_lkp = global_position.distance_to(target_position)
		
		if distance_to_lkp > 10.0: # Threshold to stop, adjust as needed
			global_position += dir * speed * delta
			set_vision_direction(dir)
			_last_movement_dir = dir # Store this direction
			# Animation based on direction (similar to PATROL)
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
			idle_task = IdleTasks.WAIT # Reached LKP, now wait/scan

	elif idle_task == IdleTasks.INSPECT:
		pass

	# General updates that should happen every physics frame, regardless of most idle_tasks
	if is_instance_valid(vision_manager) and is_instance_valid(player):
		var player_is_currently_visible: bool = vision_manager.can_see_point(player.global_position)
		_on_vision_manager_player_visibility_updated(player_is_currently_visible, delta)

	_handle_alertness_cooldown(delta)
	update_alertness() # Crucial for state changes based on new alertness_value
	# print_alertness_bar() # Optional: Moved to _process or keep here if physics-tick debug is fine

func _on_vision_manager_player_visibility_updated(p_is_visible: bool, delta: float) -> void: # Renamed is_visible, removed _detection_strength
	if p_is_visible:
		# Stop cooldown if player is seen
		is_in_cooldown = false
		cooldown_timer = 0.0
		was_player_seen = true # Player has been seen
		
		# Different increase rates based on current state
		if alertness_value < suspicion_threshold:
			alertness_value = min(alertness_value + (initial_alertness_increase_rate * delta), 1.0)
		else:
			alertness_value = min(alertness_value + (alertness_increase_rate * delta), 1.0)
		
		# Emit the player detected signal with the current alertness level
		if not _player_was_visible_last_frame: # Only emit if newly detected this frame
			emit_signal("player_detected", self, alertness_value)
		
	else: # Player not in sight
		# If player was just seen but now isn't, emit the lost detection signal
		if _player_was_visible_last_frame: # Player was visible last frame, but not this one
			emit_signal("player_detection_lost", self)
		
		# If we've seen the player before (in this alert cycle) and now don't see them, start cooldown timer
		if was_player_seen and !is_in_cooldown:
			cooldown_timer += delta
			
			# Determine which delay to use
			var active_cooldown_delay: float = idle_cooldown_delay
			if alertness_state == AlertnessState.SUSPICIOUS:
				active_cooldown_delay = suspicious_cooldown_delay
			
			if cooldown_timer >= active_cooldown_delay:
				is_in_cooldown = true
				cooldown_timer = 0.0 # Reset timer as we are now in cooldown
	
	_player_was_visible_last_frame = p_is_visible # Update for next frame's check
	# update_alertness() # This was moved to _physics_process to run after cooldown handling

func _handle_alertness_cooldown(delta: float) -> void:
	if is_in_cooldown:
		var _initial_alertness = alertness_value # Prefixed with underscore
		# Determine which rate to use
		var active_cooldown_rate: float = idle_cooldown_rate # Default to idle
		if alertness_value >= suspicion_threshold: # If still suspicious or cooling down from alerted
			active_cooldown_rate = suspicious_cooldown_rate
		alertness_value = max(alertness_value - (active_cooldown_rate * delta), 0.0)
			
		if alertness_value <= 0.0:
			alertness_value = 0.0
			was_player_seen = false
			is_in_cooldown = false
			# Explicitly signal player_detection_lost when alertness drops to zero
			emit_signal("player_detection_lost", self)

func _process(_delta: float) -> void: # Renamed delta to _delta to address unused parameter warning
	# Update status bar position
	if is_instance_valid(status_bar_instance):
		var status_bar_pos: Vector2 = Vector2.ZERO

		# Center the status bar horizontally above the sprite
		# Assumes status_bar_instance's origin is top-left
		status_bar_pos.x = -status_bar_instance.size.x / 2.0

		# Position below the emote
		# This part requires knowing how your emote_node is structured and positioned.
		# Assuming emote_node.position.y is relative to the sentry,
		# and emote_node has a known height (e.g., from its texture or a bounding box).
		if is_instance_valid(emote_node) and emote_node.visible:
			# Assuming emote_node's Y position is its top, and it has a 'size' property (like Control nodes)
			# or a way to get its height.
			var emote_height: float = 0.0
			if emote_node.has_method("get_rect"): # For Control nodes
				emote_height = emote_node.get_rect().size.y * emote_node.scale.y
			elif emote_node is Sprite2D and emote_node.texture:
				emote_height = emote_node.texture.get_height() * emote_node.scale.y
			# Add other checks if emote_node is a different type

			# emote_node.position.y is where the emote's origin is.
			# If emote is above sentry, emote_node.position.y is negative.
			# The bottom of the emote would be emote_node.position.y + emote_height (if origin is top-left)
			# OR emote_node.position.y if origin is bottom-left and position.y is the bottom line.
			# Let's assume emote_node.position.y is the TOP of the emote relative to sentry.
			var emote_bottom_y: float = emote_node.position.y + emote_height
			status_bar_pos.y = emote_bottom_y + PADDING_BELOW_EMOTE
		elif is_instance_valid(animated_sprite_2d_ref_for_status_bar): # Fallback if emote_node is not valid/visible
			# Fallback: Position above the sprite if emote is not available
			# Assuming sprite's origin is its center, and sprite.texture gives its height.
			var sprite_top_y: float = 0.0
			if animated_sprite_2d_ref_for_status_bar.sprite_frames and animated_sprite_2d_ref_for_status_bar.animation:
				var current_anim_name: StringName = animated_sprite_2d_ref_for_status_bar.animation
				if animated_sprite_2d_ref_for_status_bar.sprite_frames.has_animation(current_anim_name):
					var frame_texture: Texture2D = animated_sprite_2d_ref_for_status_bar.sprite_frames.get_frame_texture(current_anim_name, animated_sprite_2d_ref_for_status_bar.frame)
					if frame_texture:
						sprite_top_y = -frame_texture.get_height() / 2.0 * animated_sprite_2d_ref_for_status_bar.scale.y
			status_bar_pos.y = sprite_top_y + STATUS_BAR_Y_OFFSET_FROM_SPRITE_TOP

		status_bar_instance.position = status_bar_pos
