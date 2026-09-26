## Manages all units on the map: spawning, movement, combat, stacking
## and zone-of-control rules.
extends Node

## How many friendly units may share one hex.
const STACK_LIMIT: int = 2

## Unit scene for instancing.
var unit_scene = preload("res://scenes/units/unit.tscn")

## All active units.
var units: Array = []

## Currently selected unit.
var selected_unit = null

## Hex grid reference.
var hex_grid = null

## City manager reference (optional: city capture and garrison defence).
var city_manager = null

## Initialize with hex grid reference.
func setup(grid) -> void:
	hex_grid = grid
	add_to_group("unit_manager")
	# Clean up dead units when they are destroyed
	SignalBus.unit_destroyed.connect(_on_unit_destroyed)
	SignalBus.unit_arrived.connect(_on_unit_arrived)
	SignalBus.unit_moved.connect(_on_unit_moved_refresh)

## Spawn a unit at a hex position.
func spawn_unit(unit_id: String, hex_pos: Vector2i, faction_id: int):
	var data = UnitData.get_unit(unit_id)
	if data.is_empty():
		push_error("Unknown unit: " + unit_id)
		return null

	var unit = unit_scene.instantiate()
	add_child(unit)
	unit.setup(data, hex_pos, faction_id, hex_grid.hex_size)
	unit.map_data = hex_grid.map_data
	units.append(unit)
	_refresh_stacks()
	return unit

## Get unit at a hex position (first unit found).
func get_unit_at(hex: Vector2i):
	for unit in units:
		if unit.hex_position == hex:
			return unit
	return null

## Get every unit at a hex position (stacking).
func get_units_at(hex: Vector2i) -> Array:
	return units.filter(func(u): return u.hex_position == hex)

## Number of units of a faction on a hex.
func get_stack_size(hex: Vector2i, faction_id: int) -> int:
	var count = 0
	for unit in units:
		if unit.hex_position == hex and unit.faction_id == faction_id:
			count += 1
	return count

## True when a faction may put another unit on this hex.
func can_stack_at(hex: Vector2i, faction_id: int) -> bool:
	return get_stack_size(hex, faction_id) < STACK_LIMIT

## True when a unit could be spawned on this hex (land, empty or friendly,
## below the stack limit).
func can_spawn_at(hex: Vector2i, faction_id: int) -> bool:
	if hex_grid == null:
		return false
	if not HexUtils.hex_in_bounds(hex, Vector2i(hex_grid.map_width, hex_grid.map_height)):
		return false
	if TerrainData.is_water(hex_grid.get_terrain(hex)):
		return false
	if city_manager and city_manager.get_city_at(hex) != null:
		return false
	for unit in get_units_at(hex):
		if unit.faction_id != faction_id:
			return false
	return can_stack_at(hex, faction_id)

## Hexes blocked for a unit: enemy units (attack instead) and friendly
## hexes already at the stack limit.
func get_blocked_hexes(unit) -> Dictionary:
	var blocked: Dictionary = {}
	if not unit:
		return blocked
	for other in units:
		if other == unit or other.hex_position == unit.hex_position:
			continue
		if other.faction_id != unit.faction_id:
			blocked[other.hex_position] = true
		elif get_stack_size(other.hex_position, unit.faction_id) >= STACK_LIMIT:
			blocked[other.hex_position] = true
	return blocked

## Zone of control for a faction: every hex adjacent to an enemy unit.
## Entering one of these hexes costs all remaining movement.
func get_zoc_hexes(faction_id: int) -> Dictionary:
	var zoc: Dictionary = {}
	for unit in units:
		if unit.faction_id == faction_id:
			continue
		for neighbor in HexUtils.hex_neighbors(unit.hex_position):
			zoc[neighbor] = true
	return zoc

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

## Move unit to a hex position. If the target is further than one turn of
## movement, the unit moves as far as it can along the route instead of
## refusing the order.
func move_unit(unit, target_hex: Vector2i) -> bool:
	if not unit:
		return false

	var zoc = get_zoc_hexes(unit.faction_id)
	var blocked = get_blocked_hexes(unit)

	# Enemy on target means attack, not move.
	if blocked.has(target_hex):
		return false

	# Check if unit can move there
	if not unit.can_move_to(target_hex, hex_grid.map_data, zoc, blocked) \
			and not _can_step_toward(unit, target_hex):
		return false

	# Find the full route (no movement cap: we truncate below).
	var path = HexPathfinder.find_path(
		unit.hex_position,
		target_hex,
		hex_grid.map_data,
		999,
		zoc,
		blocked
	)

	if path.size() <= 1:
		return false

	# Move along as much of it as this turn allows (skip first hex: it is
	# the unit's current position).
	var affordable = build_move_path(unit, path, zoc)
	if affordable.size() <= 1:
		return false

	unit.move_along_path(affordable.slice(1))
	return true

## True when the target terrain could be entered at all (used to reject
## water / impassable destinations even if they are far away).
func _can_step_toward(unit, target_hex: Vector2i) -> bool:
	var terrain = hex_grid.map_data.get(target_hex, "grassland")
	return unit.can_traverse_terrain(terrain) and unit.movement_left > 0

## Truncate a full route to what the unit can afford this turn.
## Entering a zone of control hex always ends the move there.
func build_move_path(unit, path: Array, zoc: Dictionary) -> Array:
	var prefix = [path[0]]
	var spent = 0
	for i in range(1, path.size()):
		var step = path[i]
		var terrain = hex_grid.map_data.get(step, "grassland")
		var cost = UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()

		if zoc.has(step):
			# Zone of control: stepping in burns all remaining movement.
			if spent + cost <= unit.movement_left:
				prefix.append(step)
			break

		if spent + cost > unit.movement_left:
			break

		spent += cost
		prefix.append(step)
	return prefix

## Process combat between two units.
func process_combat(attacker, defender) -> Dictionary:
	if not attacker or not defender:
		return {}

	var attacker_attack = attacker.get_attack()
	var defender_defense = defender.get_defense() + defender.get_terrain_defense_bonus()

	# City garrison bonus when defending inside an owned city.
	if city_manager:
		var garrison_city = city_manager.get_city_at(defender.hex_position)
		if garrison_city and garrison_city.faction_id == defender.faction_id:
			defender_defense += garrison_city.get_defense_bonus()

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

	# Simple combat formula; terrain and city defence feed into defense.
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

	_refresh_stacks()

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
	_refresh_stacks()
	unit.queue_free()

## Get vision hexes for a faction (units only; cities add their own).
func get_faction_vision(faction_id: int) -> Dictionary:
	var vision = {}
	for unit in units:
		if unit.faction_id == faction_id:
			var range = unit.get_vision_range()
			var hexes = HexUtils.hex_range(unit.hex_position, range)
			for hex in hexes:
				if HexUtils.hex_in_bounds(hex, Vector2i(hex_grid.map_width, hex_grid.map_height)):
					vision[hex] = true
	return vision

## Handle unit destroyed signal - clean up from array.
func _on_unit_destroyed(unit) -> void:
	if unit in units:
		units.erase(unit)
	if selected_unit == unit:
		deselect_unit()
	_refresh_stacks()

## A unit finished moving: take an undefended enemy city it walked into.
func _on_unit_arrived(unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if city_manager == null:
		return
	var city = city_manager.get_city_at(unit.hex_position)
	if city and city.faction_id != unit.faction_id and get_unit_at(city.hex_position) == unit:
		city_manager.capture_city(city, unit.faction_id)
	_refresh_stacks()

## Movement changes stacks as a unit steps; keep badges in sync.
func _on_unit_moved_refresh(_unit, _from_hex: Vector2i, _to_hex: Vector2i) -> void:
	# hex_position is updated immediately after this signal, so recompute next frame.
	call_deferred("_refresh_stacks")

## Recompute stack sizes and badge ownership for every hex.
func _refresh_stacks() -> void:
	var counts: Dictionary = {}
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var key = Vector3i(unit.hex_position.x, unit.hex_position.y, unit.faction_id)
		counts[key] = counts.get(key, 0) + 1

	var seen: Dictionary = {}
	for unit in units:
		if not is_instance_valid(unit):
			continue
		var key = Vector3i(unit.hex_position.x, unit.hex_position.y, unit.faction_id)
		unit.stack_size = counts.get(key, 1)
		unit.is_stack_leader = not seen.has(key)
		seen[key] = true
		unit.queue_redraw()
