class_name CameraFit
extends Camera2D

## Zooms so the short side of the screen always shows the same stretch of world.
##
## The UI scale changes how many viewport units a screen has (see ScreenLayout),
## so a fixed zoom would frame a phone and a desktop differently. A phone shows
## a little less world so the 16 px tiles, vision cones and detection arrows stay
## big enough to read at arm's length.

## World pixels across the short side on a desktop or tablet. 216 is the old 648 px / zoom 3 framing.
@export_range(64.0, 1024.0, 1.0, "suffix:px") var visible_world_short_side: float = 216.0
## World pixels across the short side on a phone.
@export_range(64.0, 1024.0, 1.0, "suffix:px") var handheld_visible_world_short_side: float = 192.0


func _ready() -> void:
	ScreenLayout.layout_changed.connect(_fit_zoom)
	_fit_zoom()


func _fit_zoom() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var short_side: float = minf(viewport_size.x, viewport_size.y)
	if short_side <= 0.0:
		return
	var world_short_side: float = handheld_visible_world_short_side if ScreenLayout.is_handheld() else visible_world_short_side
	zoom = Vector2.ONE * (short_side / world_short_side)
