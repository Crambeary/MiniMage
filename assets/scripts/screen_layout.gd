extends Node

## Fits the UI to the screen and reports the safe area.
##
## project.godot stretches canvas items with aspect `expand`. This autoload sets
## the root window's content scale size to a square whose side is the number of
## UI units on the screen's short side, so a unit keeps one physical size in
## portrait and landscape. A small screen gets fewer units, so UI drawn in units
## (fonts, buttons, joysticks) stays big enough to read and touch.

signal layout_changed

## UI units on the short side of a large screen. This was the old fixed viewport height.
const DESIGN_SHORT_SIDE: float = 648.0
## The fewest UI units the short side may have, so a tiny window still shows something usable.
const MIN_SHORT_SIDE: float = 360.0
## One UI unit is never drawn smaller than this many logical points (CSS px on the web).
const MIN_POINTS_PER_UNIT: float = 0.9
## A screen whose short side is below this many logical points is a phone.
const HANDHELD_MAX_SHORT_POINTS: float = 500.0
## Safari settles its safe-area insets a moment after a rotation resize.
const SAFE_AREA_RECHECK_SECONDS: float = 0.3
const WEB_SAFE_AREA_QUERY: String = """(function () {
	var probe = document.getElementById('mm-safe-area');
	if (!probe) {
		probe = document.createElement('div');
		probe.id = 'mm-safe-area';
		probe.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;pointer-events:none;'
			+ 'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left);';
		document.body.appendChild(probe);
	}
	var s = getComputedStyle(probe);
	return [s.paddingLeft, s.paddingTop, s.paddingRight, s.paddingBottom].map(parseFloat).join(',');
})()"""

var _safe_insets: Vector4 = Vector4.ZERO  # left, top, right, bottom in UI units
var _logical_short_side: float = DESIGN_SHORT_SIDE


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_root_size_changed)
	_relayout()


## The part of the viewport that no notch, island or home indicator covers, in UI units.
func get_safe_rect() -> Rect2:
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	var top_left := Vector2(_safe_insets.x, _safe_insets.y)
	var bottom_right := Vector2(_safe_insets.z, _safe_insets.w)
	return Rect2(top_left, viewport_size - top_left - bottom_right)


## A part of the safe rect given as fractions of it (0..1 on each axis), in UI units.
## Touch schemes use this so an activation area never reaches under a notch or home indicator.
func get_safe_fraction_rect(fraction: Rect2) -> Rect2:
	var safe: Rect2 = get_safe_rect()
	return Rect2(safe.position + fraction.position * safe.size, fraction.size * safe.size)


## True on a phone: a mobile build, or a Web export whose short side is under
## HANDHELD_MAX_SHORT_POINTS. A desktop window never counts, however small or HiDPI.
func is_handheld() -> bool:
	if OS.has_feature("mobile"):
		return true
	return OS.has_feature("web") and _logical_short_side < HANDHELD_MAX_SHORT_POINTS


func _on_root_size_changed() -> void:
	_relayout()
	if OS.has_feature("web"):
		get_tree().create_timer(SAFE_AREA_RECHECK_SECONDS).timeout.connect(_relayout)


func _relayout() -> void:
	var window: Window = get_tree().root
	var window_size: Vector2 = Vector2(window.size)
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	var screen_scale: float = maxf(DisplayServer.screen_get_scale(), 1.0)
	_logical_short_side = minf(window_size.x, window_size.y) / screen_scale
	var units: int = roundi(clampf(_logical_short_side / MIN_POINTS_PER_UNIT, MIN_SHORT_SIDE, DESIGN_SHORT_SIDE))
	var content_size := Vector2i(units, units)
	if window.content_scale_size != content_size:
		window.content_scale_size = content_size
	var window_pixels_per_unit: float = minf(window_size.x, window_size.y) / float(units)
	_safe_insets = _read_safe_insets_in_window_pixels(window, screen_scale) / window_pixels_per_unit
	layout_changed.emit()


# Left, top, right, bottom in window pixels.
func _read_safe_insets_in_window_pixels(window: Window, screen_scale: float) -> Vector4:
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval(WEB_SAFE_AREA_QUERY)
		if not raw is String:
			return Vector4.ZERO
		var parts: PackedFloat64Array = (raw as String).split_floats(",")
		if parts.size() != 4:
			return Vector4.ZERO
		# CSS px times devicePixelRatio is canvas px, which is window px.
		return Vector4(parts[0], parts[1], parts[2], parts[3]) * screen_scale
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window_rect := Rect2i(window.position, window.size)
		if safe.size.x <= 0 or safe.size.y <= 0:
			return Vector4.ZERO
		return Vector4(
			maxi(safe.position.x - window_rect.position.x, 0),
			maxi(safe.position.y - window_rect.position.y, 0),
			maxi(window_rect.end.x - safe.end.x, 0),
			maxi(window_rect.end.y - safe.end.y, 0))
	return Vector4.ZERO
