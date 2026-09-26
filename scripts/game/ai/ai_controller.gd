## AI controller - makes decisions for a single faction.
##
## A turn runs: diplomacy -> cities (production and construction) -> units.
## `execute_turn_async()` yields to the frame between chunks so the game
## stays responsive and a per-faction time budget can be enforced.
extends Node

## Milliseconds of unbroken work allowed for this faction's turn.
const TIME_BUDGET_MS: int = 5000

## Minimum turns between diplomacy offers to the same faction.
const PROPOSAL_COOLDOWN: int = 5

## Minimum turns between war declarations against the same faction.
const WAR_COOLDOWN: int = 8

## Which faction this AI controls.
var faction_id: int = 0

## Personality weights for decision-making.
## Keys: expand, build, attack, trade, defend
var personality: Dictionary = {}

## References to game systems (set via setup()).
var unit_manager = null
var city_manager = null
var hex_grid = null

## Difficulty multiplier: 0.7 = easy, 1.0 = normal, 1.4 = hard.
var difficulty: float = 1.0

## Cooldown bookkeeping: "other|action" -> turn it was last used.
var diplomacy_cooldowns: Dictionary = {}

## Initialize the AI for a faction with a given personality.
func setup(faction: int, units, cities, grid, diff: float = -1.0) -> void:
	faction_id = faction
	unit_manager = units
	city_manager = cities
	hex_grid = grid
	difficulty = GameManager.get_difficulty_value() if diff < 0 else diff
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

## Execute one full AI turn synchronously (used by tests and fallbacks).
func execute_turn() -> void:
	_process_diplomacy()
	_process_cities()
	_process_units()

## Execute one AI turn spread across frames, respecting a time budget.
func execute_turn_async() -> void:
	_process_diplomacy()
	_process_cities()
	await _yield_frame()

	var start_ms = Time.get_ticks_msec()
	var acted = 0
	var roster = unit_manager.get_faction_units(faction_id)
	for unit in roster:
		if not is_instance_valid(unit):
			continue
		_act_with_unit_or_explore(unit)
		acted += 1

		if acted % 3 == 0:
			if Time.get_ticks_msec() - start_ms > TIME_BUDGET_MS:
				push_warning("AI faction %d hit the %dms turn budget" % [faction_id, TIME_BUDGET_MS])
				return
			await _yield_frame()

## Await one frame when in the tree, otherwise continue synchronously.
func _yield_frame() -> void:
	if is_inside_tree() and get_tree():
		await get_tree().process_frame

## --- DIPLOMACY -------------------------------------------------------

func _process_diplomacy() -> void:
	for other in range(4):
		if other == faction_id:
			continue
		if other >= GameManager.factions.size():
			continue

		if Diplomacy.is_at_war(faction_id, other):
			_maybe_offer_peace(other)
		else:
			_maybe_offer_trade(other)
			_maybe_declare_war(other)

## Offer peace when the war drags on or is going badly.
func _maybe_offer_peace(other: int) -> void:
	if not _cooldown_ready(other, "peace", PROPOSAL_COOLDOWN):
		return

	var war_dragging = Diplomacy.war_turns(faction_id, other) >= 5
	var losing = Diplomacy.estimate_strength(faction_id) < \
			Diplomacy.estimate_strength(other) * 0.75
	var war_weariness = personality["defend"] > 0.25 and \
			Diplomacy.war_turns(faction_id, other) >= 3

	if war_dragging or losing or war_weariness:
		diplomacy_cooldowns["%d|peace" % other] = GameManager.current_turn
		Diplomacy.propose(faction_id, other, "peace")

## Offer a trade agreement to a faction we are on decent terms with.
func _maybe_offer_trade(other: int) -> void:
	if Diplomacy.is_trading(faction_id, other):
		return
	if not _cooldown_ready(other, "trade", PROPOSAL_COOLDOWN):
		return
	if Diplomacy.get_relation(faction_id, other) < -10:
		return
	if Diplomacy.get_relation(other, faction_id) < -10:
		return

	var willingness = personality["trade"] + (0.1 if difficulty > 1.0 else 0.0)
	if randf() < willingness:
		diplomacy_cooldowns["%d|trade" % other] = GameManager.current_turn
		Diplomacy.propose(faction_id, other, "trade")

## Declare war on a neighbour we dislike and think we can beat.
func _maybe_declare_war(other: int) -> void:
	if not _cooldown_ready(other, "war", WAR_COOLDOWN):
		return

	var relation = Diplomacy.get_relation(faction_id, other)
	var hostility = personality["attack"]
	if relation > -15:
		return
	if randf() > hostility * 0.5:
		return

	var mine = Diplomacy.estimate_strength(faction_id)
	var theirs = Diplomacy.estimate_strength(other)
	# Hard AI picks fights more readily, easy AI rarely starts them.
	var needed = 1.1 - (difficulty - 1.0) * 0.4
	if mine >= theirs * max(0.6, needed):
		diplomacy_cooldowns["%d|war" % other] = GameManager.current_turn
		Diplomacy.declare_war(faction_id, other)

func _cooldown_ready(other: int, action: String, cooldown: int) -> bool:
	var key = "%d|%s" % [other, action]
	if not diplomacy_cooldowns.has(key):
		return true
	return GameManager.current_turn - int(diplomacy_cooldowns[key]) >= cooldown

## Rebel factions and anyone we are at war with count as enemies.
func _is_hostile(faction: int) -> bool:
	if faction == faction_id:
		return false
	if faction >= 4:
		return true
	return Diplomacy.is_at_war(faction_id, faction)

## --- CITY MANAGEMENT -------------------------------------------------

func _process_cities() -> void:
	var cities = city_manager.get_faction_cities(faction_id)
	var gold = _get_faction_gold()

	for city in cities:
		# Keep both queues busy: production first, then construction.
		if not city.producing.is_empty():
			continue
		var choice = _choose_production(city, gold)
		if choice != "":
			var cost = UnitData.get_unit(choice).get("cost", 40)
			if gold >= cost:
				city.start_production(choice)
				gold -= cost
				_set_faction_gold(gold)
			continue

		if not city.constructing.is_empty():
			continue
		var building = _choose_building(city, gold)
		if building != "":
			var cost = BuildingData.get_cost(building)
			if gold >= cost:
				city.start_construction(building)
				gold -= cost
				_set_faction_gold(gold)

## Decide which building (if any) this city should start.
func _choose_building(city, gold: int) -> String:
	if city.buildings.size() >= 4:
		return ""

	# Higher difficulty builds infrastructure more consistently.
	var chance = 0.15 + 0.2 * clampf(difficulty - 0.7, 0.0, 1.0)
	if randf() > chance:
		return ""

	# Pick the affordable building whose effects the city needs most.
	var best_id = ""
	var best_score = -1
	for key in BuildingData.ids():
		if city.has_building(key):
			continue
		var cost = BuildingData.get_cost(key)
		if cost > gold:
			continue

		var score = 10 - cost / 20
		var effects = BuildingData.get_effects(key)
		if city.happiness < 50 and effects.has("happiness"):
			score += int(effects["happiness"])
		if gold < 120 and effects.has("gold_per_turn"):
			score += 8
		if effects.has("defense") and personality["defend"] > 0.2:
			score += 6
		if effects.has("food") and city.population <= 4:
			score += 5

		if score > best_score:
			best_score = score
			best_id = key
	return best_id

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

		# Easy AI avoids expensive units, hard AI values quality.
		if cost > 100 and difficulty < 1.0:
			continue

		# Score based on preference
		var score = 0
		if preference == "military":
			score = unit.get("attack", 0) + unit.get("defense", 0)
			# Prefer cheaper units early
			score -= cost / 10
			score = int(score * difficulty) if difficulty > 1.0 else score
		elif preference == "scout":
			score = unit.get("movement", 2) * 3
			if unit.get("special", "") == "extra_vision":
				score += 10

		if score > best_score:
			best_score = score
			best_id = key

	return best_id if best_id != "" else "warrior"

## --- UNIT MANAGEMENT -------------------------------------------------

func _process_units() -> void:
	for unit in unit_manager.get_faction_units(faction_id):
		if not is_instance_valid(unit):
			continue
		_act_with_unit_or_explore(unit)

## Shared entry point for acting with one unit.
func _act_with_unit_or_explore(unit) -> void:
	if unit.has_acted or unit.movement_left <= 0:
		return

	# Skip non-combat units (attack = 0)
	var attack = unit.unit_data.get("attack", 0)
	if attack == 0:
		# Non-combat units (griots): move toward nearest friendly unit
		_move_toward_ally(unit)
		return

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
	if not _is_hostile(defender.faction_id):
		return false

	var atk_power = attacker.get_attack() + attacker.hp / 10
	var def_power = defender.get_defense() + defender.get_terrain_defense_bonus() + defender.hp / 10

	# Personality affects aggression, difficulty affects caution:
	# hard AI attacks at lower odds, easy AI only when clearly stronger.
	var aggression = personality["attack"]
	var threshold = 0.6 + (1.0 - aggression) * 0.4
	threshold *= 1.0 + (1.0 - difficulty) * 0.6

	# Attack if we're strong enough
	var ratio = float(atk_power) / max(1.0, float(def_power))
	return ratio >= threshold

func _attack_target(unit, target) -> void:
	var dist = HexUtils.hex_distance(unit.hex_position, target.hex_position)

	if dist <= unit.unit_data.get("range", 1):
		# In range: attack directly (war follows automatically)
		if not Diplomacy.is_at_war(faction_id, target.faction_id) and target.faction_id < 4:
			Diplomacy.on_attack(faction_id, target.faction_id)
		unit_manager.process_combat(unit, target)
	else:
		# Move toward target first, then attack next turn
		_move_toward(unit, target.hex_position)

func _move_toward(unit, target_hex: Vector2i) -> void:
	var zoc = unit_manager.get_zoc_hexes(faction_id)
	var blocked = unit_manager.get_blocked_hexes(unit)
	# Search for the whole route; the affordable prefix is taken below so
	# distant targets are approached instead of ignored.
	var path = HexPathfinder.find_path(
		unit.hex_position,
		target_hex,
		hex_grid.map_data,
		999,
		zoc,
		blocked
	)

	if path.size() <= 1:
		return

	var affordable = unit_manager.build_move_path(unit, path, zoc)
	if affordable.size() > 1:
		unit.move_along_path(affordable.slice(1))

func _explore(unit) -> void:
	# Find a random direction and move that way
	var neighbors = HexUtils.hex_neighbors(unit.hex_position)
	neighbors.shuffle()

	var zoc = unit_manager.get_zoc_hexes(faction_id)
	var blocked = unit_manager.get_blocked_hexes(unit)

	for neighbor in neighbors:
		if HexUtils.hex_in_bounds(neighbor, Vector2i(hex_grid.map_width, hex_grid.map_height)):
			if not blocked.has(neighbor) and unit.can_move_to(neighbor, hex_grid.map_data, zoc, blocked):
				unit.move_along_path([neighbor])
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

## --- HELPERS ---------------------------------------------------------

func _get_enemy_units() -> Array:
	var enemies = []
	for unit in unit_manager.units:
		if _is_hostile(unit.faction_id):
			enemies.append(unit)
	return enemies

func _get_enemy_cities() -> Array:
	var enemies = []
	for city in city_manager.cities:
		if _is_hostile(city.faction_id):
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
	# Hostile cities with no real garrison (simplified).
	var empty = []
	for city in city_manager.cities:
		if not _is_hostile(city.faction_id):
			continue
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
	return GameManager.get_gold(faction_id)

func _set_faction_gold(amount: int) -> void:
	if faction_id >= 0 and faction_id < GameManager.factions.size():
		GameManager.factions[faction_id]["gold"] = amount
