class_name PlayerDetectionHandler
extends Node

const DETECTION_ARROW_SCENE: PackedScene = preload("res://assets/scenes/ui/detection_arrow.tscn")

@export var debug_mode: bool = false

var detecting_entities: Dictionary = {}
var active_arrows: Dictionary = {}


func _ready() -> void:
	_connect_to_sentries()

	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	for entity in detecting_entities.keys():
		if is_instance_valid(entity) and active_arrows.has(entity):
			var detection_level = detecting_entities[entity]
			var arrow = active_arrows[entity]
			arrow.update_detection_level(detection_level)


func _on_sentry_detected(detector, detection_level: float) -> void:
	if not is_instance_valid(detector):
		return

	detecting_entities[detector] = detection_level

	if debug_mode:
		print("Sentry detected player - Level: ", detection_level)

	if active_arrows.has(detector):
		var old_arrow = active_arrows[detector]
		if is_instance_valid(old_arrow):
			old_arrow.queue_free()
		active_arrows.erase(detector)

	var new_arrow = DETECTION_ARROW_SCENE.instantiate()
	add_child(new_arrow)
	active_arrows[detector] = new_arrow

	new_arrow.start_detection(detector, detection_level)


func _on_sentry_detection_lost(detector) -> void:
	if not is_instance_valid(detector):
		return

	if debug_mode:
		print("Sentry lost detection of player")

	detecting_entities.erase(detector)

	if active_arrows.has(detector):
		var arrow = active_arrows[detector]
		if is_instance_valid(arrow):
			arrow.queue_free()
		active_arrows.erase(detector)

		if debug_mode:
			print("Arrow removed for detector")


func _connect_to_sentries() -> void:
	var sentries = get_tree().get_nodes_in_group("sentry")
	for sentry in sentries:
		_connect_sentry_signals(sentry)


func _connect_sentry_signals(sentry: Node) -> void:
	if (
		sentry.has_signal("player_detected")
		and not sentry.player_detected.is_connected(_on_sentry_detected)
	):
		sentry.player_detected.connect(_on_sentry_detected)

	if (
		sentry.has_signal("player_detection_lost")
		and not sentry.player_detection_lost.is_connected(_on_sentry_detection_lost)
	):
		sentry.player_detection_lost.connect(_on_sentry_detection_lost)


func _on_node_added(node: Node) -> void:
	if node.is_in_group("sentry"):
		await get_tree().process_frame
		_connect_sentry_signals(node)
