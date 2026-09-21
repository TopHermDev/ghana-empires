## Hex grid map renderer and controller.
extends Node2D

## Size of each hex in pixels.
@export var hex_size: float = 32.0

## Map dimensions in hexes.
@export var map_width: int = 60
@export var map_height: int = 45

## Map data - stores terrain type for each hex.
var map_data: Dictionary = {}

## Currently highlighted hex.
var highlighted_hex: Vector2i = Vector2i(-1, -1)

## Selected hex.
var selected_hex: Vector2i = Vector2i(-1, -1)

## Terrain colors for placeholder rendering.
var terrain_colors = {
	"grassland": Color(0.4, 0.7, 0.3),
	"savanna": Color(0.8, 0.75, 0.4),
	"forest": Color(0.2, 0.5, 0.2),
	"dense_forest": Color(0.1, 0.35, 0.1),
	"hills": Color(0.6, 0.5, 0.3),
	"mountains": Color(0.5, 0.45, 0.4),
	"desert": Color(0.9, 0.85, 0.6),
	"river": Color(0.3, 0.5, 0.8),
	"coast": Color(0.4, 0.6, 0.7),
	"ocean": Color(0.2, 0.35, 0.7),
}

func _ready() -> void:
	_generate_map()
	queue_redraw()

func _draw() -> void:
	# Draw all hexes
	for y in range(map_height):
		for x in range(map_width):
			var hex = Vector2i(x, y)
			var pos = HexUtils.hex_to_pixel(hex, hex_size)
			var color = _get_hex_color(hex)

			# Highlight selected hex
			if hex == selected_hex:
				color = color.lightened(0.3)
			elif hex == highlighted_hex:
				color = color.lightened(0.15)

			_draw_hex(pos, hex_size, color)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hex = _get_hex_at_mouse(event.position)
		if hex != highlighted_hex:
			highlighted_hex = hex
			queue_redraw()
			SignalBus.hex_hovered.emit(hex)

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hex = _get_hex_at_mouse(event.position)
			if HexUtils.hex_in_bounds(hex, Vector2i(map_width, map_height)):
				selected_hex = hex
				queue_redraw()
				SignalBus.hex_clicked.emit(hex)

## Generate the map with random terrain.
func _generate_map() -> void:
	map_data.clear()
	for y in range(map_height):
		for x in range(map_width):
			var hex = Vector2i(x, y)
			var terrain = _generate_terrain(hex)
			map_data[hex] = terrain

## Generate terrain for a hex based on position.
func _generate_terrain(hex: Vector2i) -> String:
	var y_ratio = float(hex.y) / float(map_height)

	# South is ocean/coast, north is desert/savanna
	if y_ratio > 0.9:
		return "ocean"
	elif y_ratio > 0.8:
		if randf() > 0.3:
			return "coast"
		return "ocean"
	elif y_ratio > 0.7:
		if randf() > 0.5:
			return "grassland"
		return "coast"
	elif y_ratio > 0.4:
		var r = randf()
		if r > 0.7:
			return "forest"
		elif r > 0.5:
			return "hills"
		elif r > 0.3:
			return "grassland"
		return "savanna"
	elif y_ratio > 0.2:
		var r = randf()
		if r > 0.6:
			return "hills"
		elif r > 0.3:
			return "savanna"
		return "desert"
	else:
		if randf() > 0.4:
			return "desert"
		return "savanna"

## Get the color for a hex.
func _get_hex_color(hex: Vector2i) -> Color:
	var terrain = map_data.get(hex, "grassland")
	return terrain_colors.get(terrain, Color.WHITE)

## Draw a hex at a position.
func _draw_hex(center: Vector2, size: float, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(6):
		var angle = PI / 180 * (60 * i - 30)
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), color.darkened(0.2), 1.0)

## Get hex at mouse position.
func _get_hex_at_mouse(mouse_pos: Vector2) -> Vector2i:
	# Adjust for camera position (if we add camera later)
	return HexUtils.pixel_to_hex(mouse_pos, hex_size)

## Get terrain at a hex.
func get_terrain(hex: Vector2i) -> String:
	return map_data.get(hex, "grassland")

## Set terrain at a hex.
func set_terrain(hex: Vector2i, terrain: String) -> void:
	map_data[hex] = terrain
	queue_redraw()
