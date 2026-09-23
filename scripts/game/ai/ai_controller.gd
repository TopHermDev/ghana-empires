## AI controller - makes decisions for a single faction.
extends Node

## Which faction this AI controls.
var faction_id: int = 0

## Personality weights for decision-making.
## Keys: expand, build, attack, trade, defend
var personality: Dictionary = {}

## References to game systems (set via setup()).
var unit_manager = null
var city_manager = null
var hex_grid = null

## Difficulty multiplier: 1.0 = normal, 0.7 = easy, 1.3 = hard
var difficulty: float = 1.0

## Initialize the AI for a faction with a given personality.
func setup(faction: int, units, cities, grid, diff: float = 1.0) -> void:
	faction_id = faction
	unit_manager = units
	city_manager = cities
	hex_grid = grid
	difficulty = diff
	personality = _get_personality(faction)

## Get personality weights for a faction.
func _get_personality(faction: int) -> Dictionary:
	match faction:
		0:  # Ashanti - Expansionist
			return {"expand": 0.35, "build": 0.2, "attack": 0.3, "trade": 0.05, "defend": 0.1}
		1:  # Dagbon - Defensive
			return {"expand": 0.15, "build": 0.25, "attack": 0.1, "trade": 0.2, "defend": 0.3}
		2:  # Fante - Commercial
			return {"expand": 0.1, "build": 0.3, "attack": 0.1, "trade": 0.35, "defend": 0.15}
		3:  # Mamprusi - Diplomatic
			return {"expand": 0.2, "build": 0.25, "attack": 0.15, "trade": 0.25, "defend": 0.15}
		_:
			return {"expand": 0.2, "build": 0.2, "attack": 0.2, "trade": 0.2, "defend": 0.2}

## Execute one full AI turn: manage cities, then move units.
func execute_turn() -> void:
	_process_cities()
	_process_units()

## --- CITY MANAGEMENT ---

func _process_cities() -> void:
	var cities = city_manager.get_faction_cities(faction_id)
	var gold = _get_faction_gold()

	for city in cities:
		# If city is already producing something, skip
		if not city.producing.is_empty():
			continue

		# Decide what to build
		var choice = _choose_production(city, gold)
		if choice != "":
			var cost = UnitData.get_unit(choice).get("cost", 40)
			if gold >= cost:
				city.start_production(choice)
				gold -= cost
				_set_faction_gold(gold)

func _choose_production(city, gold: int) -> String:
	var units = unit_manager.get_faction_units(faction_id)
	var enemy_units = _get_enemy_units()
	var my_cities = city_manager.get_faction_cities(faction_id)

	# Count military vs total units
	var military_count = 0
	for u in units:
		if u.unit_data.get("attack", 0) > 0:
			military_count += 1

	# Decide based on personality
	var build_weight = personality["build"]
	var attack_weight = personality["attack"]
	var expand_weight = personality["expand"]

	# If we have few military units, prioritize military
	if military_count < my_cities.size() * 2:
		return _pick_best_unit(city, "military")

	# If enemies are nearby, build military
	if enemy_units.size() > 0 and _nearest_enemy_distance(city) < 15:
		if randf() < attack_weight:
			return _pick_best_unit(city, "military")

	# If personality favors building, build economic units
	if randf() < build_weight:
		return _pick_best_unit(city, "scout")

	# Default: build military
	return _pick_best_unit(city, "military")

func _pick_best_unit(city, preference: String) -> String:
	var faction_names = ["ashanti", "dagbon", "fante", "mamprusi"]
	var faction_name = faction_names[faction_id]

	var best_id = ""
	var best_score = -1

	for key in UnitData.units:
		var unit = UnitData.units[key]
		var unit_faction = unit.get("faction", "neutral")

		# Only build faction-appropriate or neutral units
		if unit_faction != faction_name and unit_faction != "neutral":
			continue

		# Skip units we can't afford
		var cost = unit.get("cost", 40)
		if cost > _get_faction_gold():
			continue

		# Score based on preference
		var score = 0
		if preference == "military":
			score = unit.get("attack", 0) + unit.get("defense", 0)
			# Prefer cheaper units early
			score -= cost / 10
		elif preference == "scout":
			score = unit.get("movement", 2) * 3
			if unit.get("special", "") == "extra_vision":
				score += 10

		if score > best_score:
			best_score = score
			best_id = key

	return best_id if best_id != "" else "warrior"

## --- UNIT MANAGEMENT ---

func _process_units() -> void:
	var units = unit_manager.get_faction_units(faction_id)

	for unit in units:
		if unit.has_acted or unit.movement_left <= 0:
			continue

		# Skip non-combat units (attack = 0)
		var attack = unit.unit_data.get("attack", 0)
		if attack == 0:
			# Non-combat units (griots): move toward nearest friendly unit
			_move_toward_ally(unit)
			continue

		# Combat unit: find best target and act
		_act_with_unit(unit)

func _act_with_unit(unit) -> void:
	var enemy_units = _get_enemy_units()
	var nearest_enemy = _find_nearest(unit, enemy_units)
	var nearest_enemy_city = _find_nearest_enemy_city(unit)

	# Find nearest empty city to capture
	var empty_city = _find_nearest_empty_city(unit)

	# Decide action based on situation
	if nearest_enemy and _should_attack(unit, nearest_enemy):
		# Attack the enemy
		_attack_target(unit, nearest_enemy)
	elif empty_city and (not nearest_enemy or HexUtils.hex_distance(unit.hex_position, empty_city.hex_position) < 10):
		# Move toward empty city to capture
		_move_toward(unit, empty_city.hex_position)
	elif nearest_enemy_city and personality["attack"] > 0.2:
		# Move toward enemy city
		_move_toward(unit, nearest_enemy_city.hex_position)
	elif nearest_enemy and HexUtils.hex_distance(unit.hex_position, nearest_enemy.hex_position) <= unit.movement_left + 2:
		# Enemy is reachable, move to engage
		_move_toward(unit, nearest_enemy.hex_position)
	else:
		# Explore: move toward nearest unexplored area or random direction
		_explore(unit)

func _should_attack(attacker, defender) -> bool:
	var atk_power = attacker.get_attack() + attacker.hp / 10
	var def_power = defender.get_defense() + defender.hp / 10

	# Personality affects aggression
	var aggression = personality["attack"]
	var threshold = 0.6 + (1.0 - aggression) * 0.4

	# Attack if we're strong enough
	var ratio = float(atk_power) / max(1.0, float(def_power))
	return ratio >= threshold

func _attack_target(unit, target) -> void:
	var dist = HexUtils.hex_distance(unit.hex_position, target.hex_position)

	if dist <= unit.unit_data.get("range", 1):
		# In range: attack directly
		var result = unit_manager.process_combat(unit, target)
		if result.size() > 0:
			pass  # Combat happened
	else:
		# Move toward target first, then attack next turn
		_move_toward(unit, target.hex_position)

func _move_toward(unit, target_hex: Vector2i) -> void:
	var path = HexPathfinder.find_path(
		unit.hex_position,
		target_hex,
		hex_grid.map_data,
		unit.movement_left
	)

	if path.size() > 1:
		# Skip first hex (current position)
		unit.move_along_path(path.slice(1))

func _explore(unit) -> void:
	# Find a random direction and move that way
	var neighbors = HexUtils.hex_neighbors(unit.hex_position)
	neighbors.shuffle()

	for neighbor in neighbors:
		if HexUtils.hex_in_bounds(neighbor, Vector2i(hex_grid.map_width, hex_grid.map_height)):
			if unit_manager.get_unit_at(neighbor) == null:
				if unit.can_move_to(neighbor, hex_grid.map_data):
					var path = [unit.hex_position, neighbor]
					unit.move_along_path(path.slice(1))
					return

func _move_toward_ally(unit) -> void:
	var allies = unit_manager.get_faction_units(faction_id)
	var nearest_ally = null
	var nearest_dist = 999

	for ally in allies:
		if ally == unit:
			continue
		var dist = HexUtils.hex_distance(unit.hex_position, ally.hex_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_ally = ally

	if nearest_ally and nearest_dist > 3:
		_move_toward(unit, nearest_ally.hex_position)

## --- HELPERS ---

func _get_enemy_units() -> Array:
	var enemies = []
	for unit in unit_manager.units:
		if unit.faction_id != faction_id:
			enemies.append(unit)
	return enemies

func _get_enemy_cities() -> Array:
	var enemies = []
	for city in city_manager.cities:
		if city.faction_id != faction_id:
			enemies.append(city)
	return enemies

func _find_nearest(unit, targets: Array):
	var nearest = null
	var nearest_dist = 999

	for target in targets:
		var dist = HexUtils.hex_distance(unit.hex_position, target.hex_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	return nearest

func _find_nearest_enemy_city(unit):
	var cities = _get_enemy_cities()
	return _find_nearest(unit, cities)

func _find_nearest_empty_city(unit):
	# Cities with no garrison (simplified: any city not owned by us)
	var empty = []
	for city in city_manager.cities:
		if city.faction_id != faction_id:
			# Check if city is weakly defended
			var enemy_at_city = unit_manager.get_unit_at(city.hex_position)
			if enemy_at_city == null or enemy_at_city.unit_data.get("attack", 0) == 0:
				empty.append(city)
	return _find_nearest(unit, empty)

func _nearest_enemy_distance(from) -> int:
	var enemies = _get_enemy_units()
	var min_dist = 999
	for enemy in enemies:
		var dist = HexUtils.hex_distance(from.hex_position, enemy.hex_position)
		min_dist = mini(min_dist, dist)
	return min_dist

func _get_faction_gold() -> int:
	if GameManager.factions.size() > faction_id:
		return GameManager.factions[faction_id].get("gold", 0)
	return 0

func _set_faction_gold(amount: int) -> void:
	if GameManager.factions.size() > faction_id:
		GameManager.factions[faction_id]["gold"] = amount
