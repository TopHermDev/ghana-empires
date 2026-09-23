## Manages all cities on the map.
extends Node

## City scene for instancing.
var city_scene = preload("res://scenes/cities/city.tscn")

## All active cities.
var cities: Array = []

## Currently selected city.
var selected_city = null

## Hex grid reference.
var hex_grid = null

## Initialize with hex grid reference.
func setup(grid) -> void:
	hex_grid = grid

## Spawn a city at a hex position.
func spawn_city(city_id: String, hex_pos: Vector2i, faction_id: int) -> var:
	var data = CityData.get_city(city_id)
	if data.is_empty():
		push_error("Unknown city: " + city_id)
		return null

	var city = city_scene.instantiate()
	add_child(city)
	city.setup(data, hex_pos, faction_id, hex_grid.hex_size)
	cities.append(city)
	return city

## Get city at a hex position.
func get_city_at(hex: Vector2i) -> var:
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

## Process one turn for all cities of a faction.
## Returns array of {city, unit_id} for completed productions.
func process_turn(faction_id: int) -> Array:
	var completed = []
	var total_income = 0

	for city in cities:
		if city.faction_id == faction_id:
			# Collect income
			total_income += city.collect_income()

			# Advance production
			var unit_id = city.advance_production()
			if not unit_id.is_empty():
				completed.append({"city": city, "unit_id": unit_id})

			# Population growth
			city.grow_population()

			# Update city visual
			city.queue_redraw()

	# Add gold to faction (with season modifier)
	if GameManager.factions.size() > faction_id:
		var season_mod = GameManager.get_season_trade_modifier()
		var modified_income = int(total_income * season_mod)
		GameManager.factions[faction_id]["gold"] += modified_income

	return completed

## Set city production.
func set_production(city, unit_id: String) -> bool:
	if not city:
		return false
	return city.start_production(unit_id)

## Capture a city for a new faction.
func capture_city(city, new_faction: int) -> void:
	if not city:
		return
	var old_faction = city.faction_id
	city.faction_id = new_faction
	city.producing = ""
	city.production_progress = 0
	city.queue_redraw()
	SignalBus.city_captured.emit(city, new_faction)

## Remove a city.
func remove_city(city) -> void:
	if city in cities:
		cities.erase(city)
	if selected_city == city:
		deselect_city()
	city.queue_free()
