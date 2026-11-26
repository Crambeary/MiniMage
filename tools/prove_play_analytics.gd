extends SceneTree

const LEVEL_1 := "res://assets/scenes/levels/main.tscn"
const LEVEL_2 := "res://assets/scenes/levels/level_2.tscn"
const END_SCREEN := "res://assets/scenes/ui/EndScreen.tscn"


func _initialize() -> void:
	var menu_path := _main_scene_path()
	var err := change_scene_to_file(menu_path)
	if err != OK:
		_fail("could not open main scene %s (error %s)" % [menu_path, err])
		return
	var button := await _wait_for_button("Start Game")
	if button == null:
		_fail("Start Game button did not appear")
		return
	await _click(button)
	if not await _wait_for_scene(LEVEL_1, true):
		_fail("Start Game did not open %s" % LEVEL_1)
		return
	if not await _cross_exit(LEVEL_2):
		_fail("level 1 exit did not open %s" % LEVEL_2)
		return
	if not await _cross_exit(END_SCREEN):
		_fail("level 2 exit did not open %s" % END_SCREEN)
		return
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() <= deadline:
		if _analytics_settled():
			print("ANALYTICS_PROOF pass")
			quit(0)
			return
		await process_frame
	_fail("analytics queue did not settle")


func _analytics_settled() -> bool:
	var analytics: Node = root.get_node_or_null("PlayAnalytics")
	if analytics == null:
		return false
	return analytics.call("settled") == true


func _main_scene_path() -> String:
	var raw := str(ProjectSettings.get_setting("application/run/main_scene"))
	if raw.begins_with("uid://"):
		var id := ResourceUID.text_to_id(raw)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return raw


func _fit_window() -> void:
	root.size = Vector2i(960, 540)


func _wait_for_button(text: String) -> Button:
	for _i in 90:
		_fit_window()
		await process_frame
		var button := _find_button(text)
		if button == null:
			continue
		var rect := button.get_global_rect()
		var center := rect.get_center()
		var viewport := root.size
		var inside := center.x >= 0.0 and center.y >= 0.0 and center.x <= viewport.x and center.y <= viewport.y
		if rect.size.x > 1.0 and inside:
			return button
	return null


func _find_button(text: String) -> Button:
	if current_scene == null:
		return null
	for node in current_scene.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text:
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
	release.button_mask = 0
	root.push_input(release)
	await process_frame


func _wait_for_scene(path: String, need_player: bool) -> bool:
	for _i in 180:
		await process_frame
		if current_scene == null or current_scene.scene_file_path != path:
			continue
		if not need_player or get_nodes_in_group("player").size() > 0:
			return true
	return false


func _cross_exit(next_scene: String) -> bool:
	_disable_sentries()
	var shape := _exit_shape()
	if shape == null:
		print("ANALYTICS_PROOF detail missing level change shape")
		return false
	var player := _player()
	if player == null:
		print("ANALYTICS_PROOF detail missing player")
		return false
	player.velocity = Vector2.ZERO
	player.global_position = shape.global_position
	if await _wait_for_scene(next_scene, false):
		return true
	return await _nudge_into(shape, next_scene)


func _nudge_into(shape: CollisionShape2D, next_scene: String) -> bool:
	var player := _player()
	if player == null or not is_instance_valid(shape):
		return false
	var center := shape.global_position
	var half := Vector2(10, 10)
	var rect := shape.shape as RectangleShape2D
	if rect != null:
		half = rect.size * 0.5
	var outside := center - Vector2(half.x + 16.0, 0.0)
	player.velocity = Vector2.ZERO
	player.global_position = outside
	await physics_frame
	for step in 24:
		player = _player()
		if player == null:
			break
		var t := float(step + 1) / 24.0
		player.velocity = Vector2.ZERO
		player.global_position = outside.lerp(center, t)
		await physics_frame
		if current_scene != null and current_scene.scene_file_path == next_scene:
			return true
	return await _wait_for_scene(next_scene, false)


func _disable_sentries() -> void:
	for node in get_nodes_in_group("sentry"):
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _exit_shape() -> CollisionShape2D:
	if current_scene == null:
		return null
	for node in current_scene.find_children("*", "CollisionShape2D", true, false):
		var shape := node as CollisionShape2D
		if shape == null:
			continue
		var parent := shape.get_parent()
		if parent == null:
			continue
		var attached := parent.get_script() as Script
		if attached != null and attached.resource_path == "res://assets/scripts/level_change.gd":
			return shape
	return null


func _player() -> CharacterBody2D:
	var nodes := get_nodes_in_group("player")
	if nodes.is_empty():
		return null
	return nodes[0] as CharacterBody2D


func _fail(reason: String) -> void:
	print("ANALYTICS_PROOF fail %s" % reason)
	quit(1)
