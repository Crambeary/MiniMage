class_name CameraFit
extends Camera2D

## Zooms so every screen shows the same area of world (ViewSettings.get_visible_world_area()).
##
## Portrait and landscape keep one area, so a tall phone trades width for height
## instead of losing most of the world. The UI scale changes how many viewport
## units a screen has (see ScreenLayout), so the zoom is worked out from the
## viewport rect on every layout or settings change.


func _ready() -> void:
	ScreenLayout.layout_changed.connect(_fit_zoom)
	ViewSettings.changed.connect(_fit_zoom)
	_fit_zoom()


## World pixels on screen at the current zoom.
func get_visible_world_size() -> Vector2:
	return get_viewport_rect().size / zoom


func _fit_zoom() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_area: float = viewport_size.x * viewport_size.y
	if viewport_area <= 0.0:
		return
	zoom = Vector2.ONE * sqrt(viewport_area / ViewSettings.get_visible_world_area())
