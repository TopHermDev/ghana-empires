## City controller - represents a single city on the map.
##
## Handles production (units and buildings), permanent building bonuses,
## food-driven growth, happiness and revolt risk.
extends Node2D

## City data dictionary.
var city_data: Dictionary = {}

## Hex position on the map.
var hex_position: Vector2i = Vector2i(0, 0)

## Faction owner id (4 = rebel/neutral after a revolt).
var faction_id: int = 0

## City population.
var population: int = 1

## Base gold income per turn (before buildings and resources).
var gold_per_turn: int = 5

## Base production speed multiplier.
var production_speed: int = 1

## Current production ("unit" or "building" kind, id in `producing`).
var producing: String = ""
var producing_kind: String = ""

## Turns left on current production.
var production_turns_left: int = 0

## Accumulated production points.
var production_progress: int = 0

## Completed building ids (permanent bonuses).
var buildings: Array = []

## Building currently under construction ("" when idle).
var constructing: String = ""

## Progress points towards the building under construction.
var construction_progress: int = 0

## Happiness 0-100. Low happiness risks revolt, high happiness speeds work.
var happiness: int = 60

## Yields from resources in the city's catchment (set by CityManager).
var resource_gold: int = 0
var resource_food: int = 0

## Hex size for rendering.
var hex_size: float = 32.0

## Catchment radius (in hexes) for resource yields.
const CATCHMENT_RADIUS: int = 3

## Maximum population before starvation pressure is irrelevant.
const MAX_POPULATION: int = 12

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

	# New cities start content but not ecstatic.
	happiness = 60

## --- PRODUCTION (UNITS) ----------------------------------------------

## Start producing a unit.
func start_production(unit_id: String) -> bool:
	var unit_info = UnitData.get_unit(unit_id)
	if unit_info.is_empty():
		return false

	producing = unit_id
	producing_kind = "unit"
	production_turns_left = _calculate_turns(unit_info.get("cost", 40))
	production_progress = 0
	return true

## --- CONSTRUCTION (BUILDINGS) ---------------------------------------

## Start constructing a building. Returns false if already busy or unknown.
func start_construction(building_id: String) -> bool:
	if not BuildingData.is_valid(building_id):
		return false
	if not constructing.is_empty():
		return false

	constructing = building_id
	construction_progress = 0
	return true

## Cancel the building under construction (refund handled by the caller).
func cancel_construction() -> String:
	var cancelled = constructing
	constructing = ""
	construction_progress = 0
	return cancelled

## True when this city already has a building.
func has_building(building_id: String) -> bool:
	return building_id in buildings

## True when a building can be started (known, not already built, idle).
func can_build(building_id: String) -> bool:
	return BuildingData.is_valid(building_id) \
			and not has_building(building_id) \
			and constructing.is_empty()

## Effective production speed including building bonuses.
func get_production_speed() -> int:
	return production_speed + BuildingData.total_effect(buildings, "production_speed")

## Total gold income per turn (base + buildings + resources).
func get_income() -> int:
	return gold_per_turn \
			+ BuildingData.total_effect(buildings, "gold_per_turn") \
			+ resource_gold

## Total food per turn (base + buildings + resources).
func get_food() -> int:
	return 6 + BuildingData.total_effect(buildings, "food") + resource_food

## Defensive bonus granted to units defending inside this city.
func get_defense_bonus() -> int:
	return BuildingData.total_effect(buildings, "defense") + int(population / 4)

## Build turns for a given cost at the current production speed.
func _calculate_turns(cost: int) -> int:
	var base_turns = ceili(float(cost) / float(get_production_speed() * 5))
	return max(1, base_turns)

## Advance production by one turn.
## Returns {} when nothing completed, otherwise {"kind": unit|building, "id": String}.
func advance_production() -> Dictionary:
	if not producing.is_empty():
		return _advance_unit_production()
	if not constructing.is_empty():
		return _advance_building_production()
	return {}

func _advance_unit_production() -> Dictionary:
	var unit_info = UnitData.get_unit(producing)
	var cost = unit_info.get("cost", 40)

	production_progress += int(get_production_speed() * 5 * _happiness_production_modifier())

	if production_progress >= cost:
		var completed = {"kind": "unit", "id": producing}
		producing = ""
		producing_kind = ""
		production_progress = 0
		production_turns_left = 0
		return completed

	# Update turns left
	var remaining = cost - production_progress
	production_turns_left = ceili(float(remaining) / float(get_production_speed() * 5))
	return {}

func _advance_building_production() -> Dictionary:
	var cost = BuildingData.get_cost(constructing)

	construction_progress += int(get_production_speed() * 5 * _happiness_production_modifier())

	if construction_progress >= cost:
		var completed = {"kind": "building", "id": constructing}
		buildings.append(constructing)
		constructing = ""
		construction_progress = 0
		return completed
	return {}

## Happiness gates work speed: content cities work faster, miserable ones crawl.
func _happiness_production_modifier() -> float:
	if happiness >= 75:
		return 1.25
	if happiness < 35:
		return 0.5
	return 1.0

## Collect gold income for this turn.
func collect_income() -> int:
	return get_income()

## Grow population based on food surplus and happiness.
func grow_population() -> void:
	if population >= MAX_POPULATION:
		return

	var surplus = get_food() - population
	if surplus <= 0:
		return

	if happiness < 30:
		return

	var chance = clampf(0.05 + 0.05 * float(surplus), 0.0, 0.6)
	if randf() < chance:
		var old_pop = population
		population += 1
		SignalBus.city_population_changed.emit(self, old_pop, population)

## Recompute happiness from population pressure, buildings and siege.
func update_happiness(sieged: bool = false) -> void:
	var value = 50.0
	value += BuildingData.total_effect(buildings, "happiness")
	if population <= 3:
		value += 5
	# Crowding: large cities need buildings to stay happy.
	value -= max(0, population - 4) * 4.0
	if sieged:
		value -= 15
	if GameManager.is_harmattan() and get_food() < population:
		value -= 5

	happiness = int(clampf(value, 0, 100))

## Happiness label for the UI.
func get_happiness_label() -> String:
	if happiness >= 75:
		return "Content"
	if happiness >= 50:
		return "Happy"
	if happiness >= 35:
		return "Uneasy"
	if happiness >= 20:
		return "Angry"
	return "Rebellious"

## Get production progress as ratio (0.0 to 1.0).
func get_production_ratio() -> float:
	if not producing.is_empty():
		var unit_info = UnitData.get_unit(producing)
		var cost = unit_info.get("cost", 40)
		return clampf(float(production_progress) / float(cost), 0.0, 1.0)
	if not constructing.is_empty():
		var cost = BuildingData.get_cost(constructing)
		return clampf(float(construction_progress) / float(cost), 0.0, 1.0)
	return 0.0

## What the city is working on, for the UI.
func get_work_description() -> String:
	if not producing.is_empty():
		var unit_info = UnitData.get_unit(producing)
		return str(unit_info.get("name", producing)) + " (" + str(production_turns_left) + " turns)"
	if not constructing.is_empty():
		var cost = BuildingData.get_cost(constructing)
		var remaining = maxi(1, ceili(float(cost - construction_progress) / float(get_production_speed() * 5)))
		return BuildingData.get_building_name(constructing) + " (" + str(remaining) + " turns)"
	return "Nothing"

## --- RENDERING -------------------------------------------------------

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
	if not producing.is_empty() or not constructing.is_empty():
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

	# Happiness pip (colour reflects mood)
	var happy_color: Color
	if happiness >= 50:
		happy_color = Color(0.2, 0.8, 0.3)
	elif happiness >= 30:
		happy_color = Color(0.9, 0.8, 0.2)
	else:
		happy_color = Color(0.9, 0.2, 0.2)
	draw_circle(Vector2(-city_size / 2 - 5.0, -city_size / 2 - 3.0), 4.0, happy_color)

	# Completed buildings: small notches along the top edge
	for i in range(mini(buildings.size(), 6)):
		var notch = Rect2(
			Vector2(-city_size / 2 + i * 5.0, -city_size / 2 - 9.0),
			Vector2(4.0, 4.0)
		)
		draw_rect(notch, Color(0.75, 0.7, 0.55))

## Get color based on faction.
func _get_faction_color() -> Color:
	match faction_id:
		0: return Color(0.8, 0.65, 0.2)   # Ashanti - Gold
		1: return Color(0.6, 0.4, 0.2)    # Dagbon - Brown
		2: return Color(0.2, 0.5, 0.7)    # Fante - Blue
		3: return Color(0.5, 0.3, 0.6)    # Mamprusi - Purple
		_: return Color(0.5, 0.5, 0.5)    # Rebels - Gray
