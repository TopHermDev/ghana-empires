## Manages all cities on the map: production, income, growth,
## happiness, revolt and capture.
extends Node

## Rebel/neutral faction used when a city revolts.
const REBEL_FACTION: int = 4

## Happiness at or below this value risks revolt each turn.
const REVOLT_THRESHOLD: int = 20

## City scene for instancing.
var city_scene = preload("res://scenes/cities/city.tscn")

## All active cities.
var cities: Array = []

## Currently selected city.
var selected_city = null

## Hex grid reference (for resource yields).
var hex_grid = null

## Unit manager reference (for siege detection).
var unit_manager = null

## Initialize with hex grid reference.
func setup(grid) -> void:
	hex_grid = grid

## Spawn a city at a hex position.
func spawn_city(city_id: String, hex_pos: Vector2i, faction_id: int):
	var data = CityData.get_city(city_id)
	if data.is_empty():
		push_error("Unknown city: " + city_id)
		return null

	var city = city_scene.instantiate()
	add_child(city)
	city.setup(data, hex_pos, faction_id, hex_grid.hex_size)
	cities.append(city)
	_update_resource_yields(city)
	return city

## Get city at a hex position.
func get_city_at(hex: Vector2i):
	for city in cities:
		if city.hex_position == hex:
			return city
	return null

## Select a city.
func select_city(city) -> void:
	if selected_city == city:
		return
	if selected_city:
		deselect_city()
	selected_city = city
	SignalBus.city_selected.emit(city)

## Deselect current city.
func deselect_city() -> void:
	if selected_city:
		selected_city = null

## Get all cities for a faction.
func get_faction_cities(faction_id: int) -> Array:
	return cities.filter(func(c): return c.faction_id == faction_id)

## Cities owned by nobody (rebels).
func get_neutral_cities() -> Array:
	return cities.filter(func(c): return c.faction_id == REBEL_FACTION)

## --- TURN PROCESSING -------------------------------------------------

## Process one turn for all cities of a faction.
## Returns array of {city, kind, id} for completed production/construction.
func process_turn(faction_id: int) -> Array:
	var completed = []
	var total_income = 0

	for city in cities:
		if city.faction_id != faction_id:
			continue

		# Resource yields from the catchment area
		_update_resource_yields(city)

		# Collect income
		total_income += city.collect_income()

		# Advance unit production or building construction
		var result = city.advance_production()
		if not result.is_empty():
			completed.append({
				"city": city,
				"kind": result.get("kind", "unit"),
				"id": result.get("id", ""),
			})

		# Happiness depends on population pressure and siege
		city.update_happiness(_is_sieged(city))

		# Population growth (food surplus + happiness gated)
		city.grow_population()

		# Revolt risk when misery sets in
		_check_revolt(city)

		# Update city visual
		city.queue_redraw()

	# Add gold to faction (with season modifier). AI factions also get the
	# difficulty income modifier (easy AI earns less, hard AI earns more).
	if GameManager.factions.size() > faction_id:
		var season_mod = GameManager.get_season_trade_modifier()
		var modified_income = int(total_income * season_mod)
		if faction_id != GameManager.selected_faction:
			modified_income = int(modified_income * GameManager.get_ai_income_multiplier())
		GameManager.factions[faction_id]["gold"] += modified_income

	return completed

## Sum resources within the city's catchment into city yields.
func _update_resource_yields(city) -> void:
	if hex_grid == null:
		return
	var gold = 0
	var food = 0
	for hex in HexUtils.hex_range(city.hex_position, city.CATCHMENT_RADIUS):
		var resource_id = hex_grid.get_resource_at(hex)
		if resource_id != "":
			gold += ResourceData.get_gold(resource_id)
			food += ResourceData.get_food(resource_id)
	city.resource_gold = gold
	city.resource_food = food

## A city is sieged while an enemy unit sits on or next to it.
func _is_sieged(city) -> bool:
	if unit_manager == null:
		return false
	for unit in unit_manager.units:
		if unit.faction_id == city.faction_id:
			continue
		if HexUtils.hex_distance(unit.hex_position, city.hex_position) <= 1:
			return true
	return false

## Chance-based revolt for miserable cities. Returns true when revolted.
func _check_revolt(city) -> bool:
	if city.happiness > REVOLT_THRESHOLD:
		return false
	if city.faction_id == REBEL_FACTION:
		return false

	var chance = 0.25
	if city.happiness <= 10:
		chance = 0.5

	if randf() >= chance:
		return false

	revolt_city(city)
	return true

## City turns rebel: loses owner, production and some population.
func revolt_city(city) -> void:
	var old_owner = city.faction_id
	city.faction_id = REBEL_FACTION
	city.producing = ""
	city.producing_kind = ""
	city.production_progress = 0
	city.constructing = ""
	city.construction_progress = 0
	city.population = maxi(1, city.population - 1)
	city.happiness = 40
	city.queue_redraw()

	SignalBus.city_revolted.emit(city, REBEL_FACTION)
	SignalBus.show_message.emit(
		str(city.city_data.get("name", "A city")) + " has revolted!", "warning")
	print("City revolted: ", city.city_data.get("name", "?"), " (was faction ", old_owner, ")")

## --- PRODUCTION ------------------------------------------------------

## Set city production.
func set_production(city, unit_id: String) -> bool:
	if not city:
		return false
	return city.start_production(unit_id)

## Start a building project in a city (gold is handled by the caller).
func start_construction(city, building_id: String) -> bool:
	if not city:
		return false
	return city.start_construction(building_id)

## --- OWNERSHIP -------------------------------------------------------

## Capture a city for a new faction.
func capture_city(city, new_faction: int) -> void:
	if not city:
		return
	if city.faction_id == new_faction:
		return

	var old_faction = city.faction_id
	city.faction_id = new_faction
	city.producing = ""
	city.producing_kind = ""
	city.production_progress = 0
	city.constructing = ""
	city.construction_progress = 0
	city.happiness = 40
	city.queue_redraw()

	if city == selected_city:
		SignalBus.city_deselected.emit()
		selected_city = null

	SignalBus.city_captured.emit(city, new_faction)

	# Taking a city sour relations with the previous owner.
	if old_faction < 4 and new_faction < 4:
		Diplomacy.adjust_relation(new_faction, old_faction, -30)
		Diplomacy.adjust_relation(old_faction, new_faction, -30)

	SignalBus.show_message.emit(
		str(city.city_data.get("name", "City")) + " captured by " +
		GameManager.get_faction_name(new_faction), "info")
	print("City captured: ", city.city_data.get("name", "?"),
			" ", old_faction, " -> ", new_faction)

## Remove a city.
func remove_city(city) -> void:
	if city in cities:
		cities.erase(city)
	if selected_city == city:
		deselect_city()
	city.queue_free()
