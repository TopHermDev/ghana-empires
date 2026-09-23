## City controller - represents a single city on the map.
extends Node2D

## City data dictionary.
var city_data: Dictionary = {}

## Hex position on the map.
var hex_position: Vector2i = Vector2i(0, 0)

## Faction owner id.
var faction_id: int = 0

## City population.
var population: int = 1

## Gold income per turn.
var gold_per_turn: int = 5

## Production speed multiplier.
var production_speed: int = 1

## Current production (unit_id or "" for nothing).
var producing: String = ""

## Turns left on current production.
var production_turns_left: int = 0

## Accumulated production points.
var production_progress: int = 0

## Hex size for rendering.
var hex_size: float = 32.0

## Initialize city with data.
func setup(data: Dictionary, pos: Vector2i, faction: int, size: float) -> void:
	city_data = data
	hex_position = pos
	faction_id = faction
	hex_size = size

	population = data.get("population", 1)
	gold_per_turn = data.get("gold_per_turn", 5)
	production_speed = data.get("production_speed", 1)

	# Set position from hex
	position = HexUtils.hex_to_pixel(pos, size)

## Start producing a unit.
func start_production(unit_id: String) -> bool:
	var unit_info = UnitData.get_unit(unit_id)
	if unit_info.is_empty():
		return false

	producing = unit_id
	production_turns_left = _calculate_turns(unit_info.get("cost", 40))
	production_progress = 0
	return true

## Calculate turns to produce based on cost and city production speed.
func _calculate_turns(cost: int) -> int:
	var base_turns = ceili(float(cost) / float(production_speed * 5))
	return max(1, base_turns)

## Advance production by one turn. Returns completed unit_id or "".
func advance_production() -> String:
	if producing.is_empty():
		return ""

	production_progress += production_speed * 5
	var unit_info = UnitData.get_unit(producing)
	var cost = unit_info.get("cost", 40)

	if production_progress >= cost:
		var completed = producing
		producing = ""
		production_progress = 0
		production_turns_left = 0
		return completed

	# Update turns left
	var remaining = cost - production_progress
	production_turns_left = ceili(float(remaining) / float(production_speed * 5))
	return ""

## Collect gold income for this turn.
func collect_income() -> int:
	return gold_per_turn

## Grow population (called periodically).
func grow_population() -> void:
	if population < 10 and randf() < 0.15:
		population += 1
		gold_per_turn += 2

## Get production progress as ratio (0.0 to 1.0).
func get_production_ratio() -> float:
	if producing.is_empty():
		return 0.0
	var unit_info = UnitData.get_unit(producing)
	var cost = unit_info.get("cost", 40)
	return clampf(float(production_progress) / float(cost), 0.0, 1.0)

## Draw the city.
func _draw() -> void:
	var color = _get_faction_color()

	# Draw city square (darker outline)
	var city_size = hex_size * 0.5
	var rect = Rect2(Vector2(-city_size / 2, -city_size / 2), Vector2(city_size, city_size))
	draw_rect(rect, color.darkened(0.2))
	draw_rect(rect, color, false, 2.0)

	# Draw population indicator (small dots inside)
	var dot_radius = 2.0
	var dots_per_row = mini(population, 4)
	for i in range(dots_per_row):
		var dot_x = -city_size / 2 + 6.0 + i * 6.0
		var dot_y = 0.0
		draw_circle(Vector2(dot_x, dot_y), dot_radius, Color.WHITE)

	# Draw production indicator if producing
	if not producing.is_empty():
		var bar_width = city_size * 0.8
		var bar_height = 3.0
		var bar_y = city_size / 2 + 4.0
		var ratio = get_production_ratio()

		# Background
		draw_rect(
			Rect2(Vector2(-bar_width / 2, bar_y), Vector2(bar_width, bar_height)),
			Color(0.2, 0.2, 0.2)
		)
		# Progress
		draw_rect(
			Rect2(Vector2(-bar_width / 2, bar_y), Vector2(bar_width * ratio, bar_height)),
			Color(0.8, 0.6, 0.1)
		)

## Get color based on faction.
func _get_faction_color() -> Color:
	match faction_id:
		0: return Color(0.8, 0.65, 0.2)   # Ashanti - Gold
		1: return Color(0.6, 0.4, 0.2)    # Dagbon - Brown
		2: return Color(0.2, 0.5, 0.7)    # Fante - Blue
		3: return Color(0.5, 0.3, 0.6)    # Mamprusi - Purple
		_: return Color(0.5, 0.5, 0.5)    # Neutral - Gray
