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
	# Clean up dead units when they are destroyed
	SignalBus.unit_destroyed.connect(_on_unit_destroyed)

## Spawn a unit at a hex position.
func spawn_unit(unit_id: String, hex_pos: Vector2i, faction_id: int) -> var:
	var data = UnitData.get_unit(unit_id)
	if data.is_empty():
		push_error("Unknown unit: " + unit_id)
		return null

	var unit = unit_scene.instantiate()
	add_child(unit)
	unit.setup(data, hex_pos, faction_id, hex_grid.hex_size)
	unit.map_data = hex_grid.map_data
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

	# Apply special abilities
	var attacker_special = attacker.unit_data.get("special", "")
	var defender_special = defender.unit_data.get("special", "")

	# bonus_vs_infantry: +50% damage vs non-cavalry, non-ranged units
	if attacker_special == "bonus_vs_infantry":
		var def_type = defender.unit_data.get("special", "")
		if def_type != "ranged_cavalry" and def_type != "naval":
			attacker_attack = int(attacker_attack * 1.5)

	# bonus_vs_cavalry: +50% damage vs cavalry units
	if attacker_special == "bonus_vs_cavalry":
		var def_type = defender.unit_data.get("special", "")
		if def_type == "ranged_cavalry" or def_type == "first_strike":
			attacker_attack = int(attacker_attack * 1.5)

	# first_strike: attacker attacks before defender can counter
	var skip_counter = (attacker_special == "first_strike")

	# Simple combat formula
	var damage = max(1, attacker_attack - defender_defense / 2)
	damage = int(damage * (0.8 + randf() * 0.4))  # Add randomness

	SignalBus.unit_attacked.emit(attacker, defender, damage)
	defender.take_damage(damage)
	attacker.has_acted = true

	# Counter-attack if defender survives and is in range
	var counter_damage = 0
	if defender.hp > 0 and not skip_counter:
		var dist = HexUtils.hex_distance(attacker.hex_position, defender.hex_position)
		if dist <= defender.unit_data.get("range", 1):
			# siege_terror: defender loses attack when facing siege units
			if defender_special == "siege_terror":
				pass  # No counter from terrified units
			else:
				var counter_attack = defender.get_attack()
				# capital_bonus: +4 defense when near own capital (simplified: always active)
				if defender_special == "capital_bonus":
					counter_attack = int(counter_attack * 1.25)
				counter_damage = max(1, counter_attack / 2 - attacker.get_defense() / 3)
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

## Handle unit destroyed signal - clean up from array.
func _on_unit_destroyed(unit) -> void:
	if unit in units:
		units.erase(unit)
	if selected_unit == unit:
		deselect_unit()
