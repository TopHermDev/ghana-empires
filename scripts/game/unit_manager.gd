## Manages all units on the map.
extends Node

## Unit scene for instancing.
var unit_scene = preload("res://scenes/units/unit.tscn")

## All active units.
var units: Array = []

## Currently selected unit.
var selected_unit = null

## Hex grid reference.
var hex_grid = null

## Initialize with hex grid reference.
func setup(grid) -> void:
	hex_grid = grid

## Spawn a unit at a hex position.
func spawn_unit(unit_id: String, hex_pos: Vector2i, faction_id: int) -> var:
	var data = UnitData.get_unit(unit_id)
	if data.is_empty():
		push_error("Unknown unit: " + unit_id)
		return null

	var unit = unit_scene.instantiate()
	add_child(unit)
	unit.setup(data, hex_pos, faction_id, hex_grid.hex_size)
	units.append(unit)
	return unit

## Get unit at a hex position.
func get_unit_at(hex: Vector2i) -> var:
	for unit in units:
		if unit.hex_position == hex:
			return unit
	return null

## Select a unit.
func select_unit(unit) -> void:
	if selected_unit == unit:
		return
	if selected_unit:
		deselect_unit()
	selected_unit = unit
	SignalBus.unit_selected.emit(unit)

## Deselect current unit.
func deselect_unit() -> void:
	if selected_unit:
		selected_unit = null
		SignalBus.unit_deselected.emit()

## Get all units for a faction.
func get_faction_units(faction_id: int) -> Array:
	return units.filter(func(u): return u.faction_id == faction_id)

## Move unit to a hex position.
func move_unit(unit, target_hex: Vector2i) -> bool:
	if not unit:
		return false

	# Check if target is occupied
	var occupant = get_unit_at(target_hex)
	if occupant and occupant != unit:
		return false

	# Check if unit can move there
	if not unit.can_move_to(target_hex, hex_grid.map_data):
		return false

	# Find path
	var path = HexPathfinder.find_path(
		unit.hex_position,
		target_hex,
		hex_grid.map_data,
		unit.movement_left
	)

	if path.size() == 0:
		return false

	# Move along path (skip first hex, it's current position)
	unit.move_along_path(path.slice(1))
	return true

## Process combat between two units.
func process_combat(attacker, defender) -> Dictionary:
	if not attacker or not defender:
		return {}

	var attacker_attack = attacker.get_attack()
	var defender_defense = defender.get_defense()

	# Simple combat formula
	var damage = max(1, attacker_attack - defender_defense / 2)
	damage = int(damage * (0.8 + randf() * 0.4))  # Add randomness

	defender.take_damage(damage)
	attacker.has_acted = true

	# Counter-attack if defender survives and is adjacent
	var counter_damage = 0
	if defender.hp > 0:
		var dist = HexUtils.hex_distance(attacker.hex_position, defender.hex_position)
		if dist <= defender.unit_data.get("range", 1):
			counter_damage = max(1, defender.get_defense() / 2 - attacker.get_defense() / 3)
			counter_damage = int(counter_damage * (0.8 + randf() * 0.4))
			attacker.take_damage(counter_damage)

	return {
		"damage_dealt": damage,
		"counter_damage": counter_damage,
		"attacker_hp": attacker.hp,
		"defender_hp": defender.hp
	}

## End turn for all units of a faction.
func end_turn(faction_id: int) -> void:
	for unit in units:
		if unit.faction_id == faction_id:
			unit.reset_turn()

## Remove a unit from the game.
func remove_unit(unit) -> void:
	if unit in units:
		units.erase(unit)
	if selected_unit == unit:
		deselect_unit()
	unit.queue_free()

## Get vision hexes for a faction.
func get_faction_vision(faction_id: int) -> Dictionary:
	var vision = {}
	for unit in units:
		if unit.faction_id == faction_id:
			var range = unit.get_vision_range()
			var hexes = HexUtils.hex_range(unit.hex_position, range)
			for hex in hexes:
				vision[hex] = true
	return vision
