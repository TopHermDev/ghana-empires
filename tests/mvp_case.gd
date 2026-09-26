extends Node
##
## MVP acceptance test for GhanaEmpires (roadmap Phases 0-5).
##
## Run:  godot --headless --path . --script res://tests/mvp_test.gd
##
## This file is only a thin entry point: it is compiled before the engine
## registers autoloads, so anything referencing GameManager / class_name
## scripts must be loaded at runtime instead. The real test lives in
## mvp_case.gd and is loaded from _initialize().
##
## Loads the real game scene, checks every feature that was pending on the
## roadmap, then simulates a dozen full turns (player -> diplomacy -> AI)
## and validates the invariants that must hold afterwards.
##

var failures: Array = []
## Set when the test reaches its verdict (used by the entry watchdog).
var finished: bool = false
## Autoloads are not visible to the entry script at compile time
## (it is compiled before autoloads register), so we fetch them at runtime.
var gm = null
var sb = null
var game = null
var hex_grid = null
var unit_manager = null
var city_manager = null

# Signal evidence gathered during the run.
var events = {
	"production_complete": 0,
	"units_destroyed": 0,
	"attacks": 0,
	"war_declared": 0,
	"peace_signed": 0,
	"trade_established": 0,
	"diplomacy_proposal": 0,
	"city_captured": 0,
	"revolted": 0,
	"moves": 0,
}

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   - ", label)
	else:
		failures.append(label)
		print("  FAIL - ", label)

func fail(message: String) -> void:
	failures.append(message)
	print("  FAIL - ", message)

func _ready() -> void:
	# The tree is still setting up children while _ready runs, so starting
	# the test synchronously would make add_child() fail. Defer one frame.
	call_deferred("_start")

func _start() -> void:
	seed(20260926)
	Engine.time_scale = 4.0
	_run()

func _run() -> void:
	print("== GhanaEmpires MVP test ==")
	gm = get_tree().root.get_node("GameManager")
	sb = get_tree().root.get_node("SignalBus")
	check(gm != null and sb != null, "autoloads reachable")

	# --- boot ----------------------------------------------------------
	gm.new_game(0, Vector2i(60, 45))
	gm.ai_difficulty = "normal"

	var scene = load("res://scenes/game/game.tscn")
	check(scene != null, "game scene loads")
	game = scene.instantiate()
	get_tree().root.add_child(game)

	hex_grid = game.get_node("HexGrid")
	unit_manager = game.get_node("UnitManager")
	city_manager = game.get_node("CityManager")
	check(hex_grid != null and unit_manager != null and city_manager != null,
			"managers are wired into the scene")

	_wire_signals()

	# Let _ready finish (spawning, AI init, first fog update).
	for i in range(5):
		await get_tree().process_frame

	# --- Phase 2: terrain data, map file, resources ---------------------
	print("-- terrain and map data --")
	check(TerrainData.ids().size() >= 10, "terrain types loaded from data/terrain.json")
	check(TerrainData.get_move_cost("hills") == 2, "hills cost 2 movement")
	check(TerrainData.get_move_cost("dense_forest") == 3, "dense forest costs 3 movement")
	check(TerrainData.is_water("ocean") and not TerrainData.is_water("grassland"),
			"water flags come from JSON")
	check(TerrainData.code_to_id("m") == "mountains", "map codes resolve to terrain ids")
	check(UnitData.get_terrain_cost("river") == 2,
			"movement costs now come from terrain JSON (UnitData delegates)")

	check(hex_grid.loaded_map_path.ends_with("medium.json"), "map loaded from JSON file")
	check(hex_grid.map_width == 60 and hex_grid.map_height == 45, "map dimensions from file")
	check(hex_grid.resources.size() > 0, "resources placed on the map")
	check(ResourceData.ids().size() >= 6, "resource types loaded from JSON")
	var bad_terrain = 0
	for hex in hex_grid.map_data:
		if not TerrainData.terrain.has(hex_grid.map_data[hex]):
			bad_terrain += 1
	check(bad_terrain == 0, "every hex maps to a known terrain id")

	# --- Phase 1: hex info panel ---------------------------------------
	print("-- hex info panel --")
	var info_panel = game.get_node("HexInfoPanel")
	check(info_panel != null, "hex info panel exists")
	var city_hex = city_manager.cities[0].hex_position
	var info = hex_grid.get_hex_info(city_hex)
	check(info["explored"], "city hex is explored (own vision)")
	check(str(info["name"]) != "Unexplored" and str(info["name"]) != "",
			"explored hex reports terrain name")
	check(info["move_cost"] >= 1, "hex info reports movement cost")
	var unexplored_hex = _find_unexplored()
	check(unexplored_hex != null, "some hexes are still unexplored (fog exists)")
	if unexplored_hex:
		var hidden = hex_grid.get_hex_info(unexplored_hex)
		check(str(hidden["name"]) == "Unexplored", "unexplored hex reveals nothing")
	info_panel.show_hex(city_hex)
	check(info_panel.visible, "hex info panel shows on hover")

	# --- Phase 3: zone of control --------------------------------------
	print("-- zone of control --")
	var zoc = unit_manager.get_zoc_hexes(0)
	check(zoc.size() > 0, "enemy units exert zones of control")

	var probe = _find_player_unit()
	check(probe != null, "player has a unit to probe with")
	if probe:
		probe.movement_left = probe.max_movement
		var clean = probe.get_movement_range(hex_grid.map_data, {}, {})
		check(clean.size() > 0, "unit has a movement range without ZOC")

		# Put a synthetic ZOC on a reachable hex and re-measure.
		if clean.size() > 0:
			var zoc_target = clean[clean.size() - 1]["hex"]
			probe.movement_left = probe.max_movement
			var under_zoc = probe.get_movement_range(hex_grid.map_data, {zoc_target: true}, {})
			var found = false
			for entry in under_zoc:
				if entry["hex"] == zoc_target:
					found = true
					check(entry["cost"] == probe.movement_left,
							"entering a ZOC hex burns all remaining movement")
					if entry["cost"] != probe.movement_left:
						print("       got ", entry["cost"], " expected ", probe.movement_left)
			check(found, "ZOC hex is still reachable (just expensive)")

		# Pathfinding must stop at a ZOC hex instead of running past it.
		var path = HexPathfinder.find_path(probe.hex_position,
				probe.hex_position + Vector2i(3, 0), hex_grid.map_data, 6)
		if path.size() >= 3:
			var mid = path[1]
			var blocked_path = HexPathfinder.find_path(probe.hex_position,
					path[path.size() - 1], hex_grid.map_data, 6, {mid: true}, {})
			var zoc_index = blocked_path.find(mid)
			check(zoc_index == -1 or zoc_index == blocked_path.size() - 1,
					"path never continues past a zone of control hex")
			var to_zoc = HexPathfinder.find_path(probe.hex_position, mid,
					hex_grid.map_data, 6, {mid: true}, {})
			check(to_zoc.size() > 0, "path can still end on the ZOC hex itself")

	# --- Phase 3: stacking ---------------------------------------------
	print("-- stacking --")
	var open_hex = _find_free_land_hex(Vector2i(20, 22))
	check(open_hex != null, "found a free land hex for the stacking test")
	if open_hex:
		var a = unit_manager.spawn_unit("warrior", open_hex, 0)
		var b = unit_manager.spawn_unit("scout", open_hex, 0)
		check(a != null and b != null, "two friendly units can share a hex")
		check(unit_manager.get_stack_size(open_hex, 0) == 2, "stack size reports 2")
		check(not unit_manager.can_spawn_at(open_hex, 0),
				"third unit rejected at the stack limit")
		var enemy_here = unit_manager.get_units_at(open_hex)
		check(enemy_here.size() == 2, "both units found on the hex")
		var enemy_spawn = unit_manager.spawn_unit("warrior", open_hex, 1)
		if enemy_spawn:
			check(not unit_manager.can_spawn_at(open_hex, 1),
					"enemies may not stack onto a hostile hex")
			unit_manager.remove_unit(enemy_spawn)
		unit_manager.remove_unit(a)
		unit_manager.remove_unit(b)
		check(unit_manager.get_stack_size(open_hex, 0) == 0, "test units cleaned up")

	# --- Phase 4: buildings --------------------------------------------
	print("-- buildings --")
	check(BuildingData.ids().size() >= 7, "buildings loaded from data/buildings.json")
	var player_city = city_manager.get_faction_cities(0)[0]
	var income_before = player_city.get_income()
	check(player_city.can_build("market"), "city can start a building")
	player_city.start_construction("market")
	check(player_city.constructing == "market", "construction started")

	var turns_needed = 0
	while player_city.constructing != "" and turns_needed < 60:
		player_city.advance_production()
		turns_needed += 1
	check(player_city.has_building("market"), "building completed and stored")
	check(turns_needed < 60, "construction finished within a sane number of turns")
	check(player_city.get_income() == income_before + 5,
			"building effect applied to income (+5 gold/turn)")
	check(player_city.get_defense_bonus() >= 1, "city defense bonus computed")

	# Building effects and happiness feed the UI strings.
	check(player_city.get_production_speed() >= 1, "production speed computed")
	check(player_city.get_happiness_label() != "", "happiness label exists")

	# --- Phase 4: happiness --------------------------------------------
	print("-- happiness --")
	var happy_city = city_manager.get_faction_cities(0)[0]
	happy_city.update_happiness(false)
	var happy_before = happy_city.happiness
	check(happy_before >= 0 and happy_before <= 100, "happiness stays in 0-100")
	happy_city.population = 12
	happy_city.update_happiness(false)
	check(happy_city.happiness < happy_before,
			"population pressure lowers happiness")
	check(happy_city.get_production_speed() >= 1, "production speed survives low happiness")

	# --- Phase 5: diplomacy primitives ---------------------------------
	print("-- diplomacy --")
	var relation_before = Diplomacy.get_relation(1, 3)
	Diplomacy.declare_war(1, 3)
	check(Diplomacy.is_at_war(1, 3), "war can be declared")
	var relation_at_war = Diplomacy.get_relation(1, 3)
	check(relation_at_war < relation_before, "war lowers relations")
	Diplomacy.make_peace(1, 3)
	check(not Diplomacy.is_at_war(1, 3), "peace ends the war")
	check(Diplomacy.get_relation(1, 3) > relation_at_war,
			"peace improves relations")

	var gold_before_a = gm.get_gold(1)
	Diplomacy.establish_trade(1, 2)
	check(Diplomacy.is_trading(1, 2), "trade agreement can be established")
	Diplomacy.process_turn()
	check(gm.get_gold(1) > gold_before_a, "trade pays income each turn")
	Diplomacy.end_trade(1, 2)

	check(Diplomacy.estimate_strength(0) > 0, "strength estimate works")
	check(Diplomacy.attitude_label(0, 0) == "Neutral", "attitude label resolves")

	# --- combat / capture rules ----------------------------------------
	print("-- combat rules --")
	# Range is enforced for the player, and attacking starts a war.
	var spot = _find_free_land_hex(Vector2i(20, 25))
	var adjacent = null
	if spot:
		for neighbor in HexUtils.hex_neighbors(spot):
			if _is_free_land(neighbor):
				adjacent = neighbor
				break
	if spot and adjacent:
		var attacker = unit_manager.spawn_unit("warrior", spot, 0)
		var defender = unit_manager.spawn_unit("warrior", adjacent, 1)
		# Out of range: nothing happens.
		var far = _find_free_land_hex(spot + Vector2i(4, 0))
		var far_unit = null
		if far:
			far_unit = unit_manager.spawn_unit("warrior", far, 1)
		var attacks_before = events["attacks"]
		if far_unit:
			game._try_attack(attacker, far_unit)
			check(events["attacks"] == attacks_before, "attack refused when out of range")
			check(not attacker.has_acted, "unit does not act on a refused attack")

		# In range: combat happens and a war starts if there was peace.
		var was_at_war = Diplomacy.is_at_war(0, 1)
		game._try_attack(attacker, defender)
		check(events["attacks"] == attacks_before + 1, "in-range attack resolves")
		check(was_at_war or Diplomacy.is_at_war(0, 1),
				"attacking a faction at peace declares war")

		if far_unit:
			unit_manager.remove_unit(far_unit)
		unit_manager.remove_unit(attacker)
		unit_manager.remove_unit(defender)
		if Diplomacy.is_at_war(0, 1):
			Diplomacy.make_peace(0, 1)
	else:
		fail("could not find two adjacent free land hexes for the combat test")

	# Capture changes owner and sour relations.
	var faction_one_cities = city_manager.get_faction_cities(1)
	if faction_one_cities.size() > 0:
		var victim = faction_one_cities[0]
		var old_owner = victim.faction_id
		city_manager.capture_city(victim, 0)
		check(victim.faction_id == 0, "city capture changes the owner")
		check(events["city_captured"] > 0, "city_captured signal fired")
		city_manager.capture_city(victim, old_owner)
	else:
		fail("faction 1 had no city to capture in the test")

	# --- Phase 5: run full turns ---------------------------------------
	# --- pathfinder internals (diagnostic) ---
	var heap = []
	for v in [5, 3, 9, 1, 7, 2, 8, 4, 6, 0, 12, 11]:
		HexPathfinder._heap_push(heap, {"f": v, "g": v, "hex": Vector2i(v, 0)})
	var popped = []
	while heap.size() > 0:
		popped.append(HexPathfinder._heap_pop(heap)["f"])
	print("HEAP order: ", popped)
	check(popped == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12], "heap pops in ascending f order")

	var ta = Time.get_ticks_msec()
	var pa = HexPathfinder.find_path(Vector2i(10, 10), Vector2i(20, 10), hex_grid.map_data, 999, {}, {})
	print("small A* (10,10)->(20,10): len=", pa.size(), " in ", Time.get_ticks_msec() - ta, "ms")
	check(pa.size() == 11, "short A* finds the 10-step route")
	check(Time.get_ticks_msec() - ta < 50, "short A* resolves in under 50ms")

	print("-- simulation (12 turns) --")
	var units_at_start = unit_manager.units.size()
	var positions_at_start = {}
	for unit in unit_manager.units:
		positions_at_start[unit.get_instance_id()] = unit.hex_position

	for i in range(12):
		var moves_before = events["moves"]
		gm.next_turn()
		var waited = 0
		while gm.turn_processing and waited < 4000:
			await get_tree().process_frame
			waited += 1
		if gm.turn_processing:
			fail("turn %d never finished (turn lock stuck)" % (i + 1))
			break
		# Let movement animations settle between turns.
		for j in range(15):
			await get_tree().process_frame
		var spent = 0
		var ai_idle = 0
		for u in unit_manager.units:
			if u.movement_left < u.max_movement:
				spent += 1
			if u.faction_id != 0 and u.movement_left == u.max_movement and not u.is_moving:
				ai_idle += 1
		print("       turn %d: %d move steps, %d units, %d spent movement, %d AI idle, lock=%s" % [
			gm.current_turn, events["moves"] - moves_before,
			unit_manager.units.size(), spent, ai_idle, str(gm.turn_processing)])

	check(not gm.turn_processing, "turn lock is released after each turn")
	check(gm.current_turn == 12, "all 12 turns advanced")

	print("-- simulation results --")
	print("       attacks=", events["attacks"],
			" destroyed=", events["units_destroyed"],
			" production=", events["production_complete"],
			" proposals=", events["diplomacy_proposal"],
			" trades=", events["trade_established"],
			" wars=", events["war_declared"],
			" captures=", events["city_captured"])
	check(events["attacks"] > 0 or events["units_destroyed"] > 0,
			"combat happened during the simulation")
	check(events["production_complete"] > 0,
			"cities produced units during the simulation")
	check(events["diplomacy_proposal"] > 0 or events["trade_established"] > 0
			or events["war_declared"] > 0,
			"AI diplomacy acted during the simulation")

	var moved = 0
	for unit in unit_manager.units:
		var id = unit.get_instance_id()
		if positions_at_start.has(id) and positions_at_start[id] != unit.hex_position:
			moved += 1
	check(events["moves"] >= 20,
			"units moved during the simulation (%d move steps)" % events["moves"])
	print("       (", events["moves"], " movement steps; ", moved, "of",
			units_at_start, "start units ended elsewhere)")

	# --- invariants -----------------------------------------------------
	print("-- invariants --")
	var stack_violations = 0
	var water_violations = 0
	var fog_ok = hex_grid.explored.size() > 0
	for unit in unit_manager.units:
		if unit_manager.get_stack_size(unit.hex_position, unit.faction_id) > \
				unit_manager.STACK_LIMIT:
			stack_violations += 1
		if TerrainData.is_water(hex_grid.get_terrain(unit.hex_position)):
			water_violations += 1
	check(stack_violations == 0, "no faction exceeds the stack limit")
	check(water_violations == 0, "no land unit ended up on water")
	check(fog_ok, "fog of war still tracks explored hexes")

	var bad_happiness = 0
	for city in city_manager.cities:
		if city.happiness < 0 or city.happiness > 100:
			bad_happiness += 1
	check(bad_happiness == 0, "city happiness stays in range")

	var ai_ok = true
	for faction_id in game.ai_controllers:
		var ai = game.ai_controllers[faction_id]
		if ai == null or not is_instance_valid(ai):
			ai_ok = false
		elif ai.personality.is_empty():
			ai_ok = false
	check(ai_ok, "every AI controller survived the simulation")
	check(game.ai_controllers.size() == 3, "three AI factions are running")

	# --- Phase 4: revolt ------------------------------------------------
	print("-- revolt --")
	var unhappy = city_manager.get_faction_cities(0)[0]
	unhappy.happiness = 5
	city_manager.revolt_city(unhappy)
	check(unhappy.faction_id == city_manager.REBEL_FACTION,
			"miserable city revolts to the rebels")
	check(events["revolted"] > 0, "city_revolted signal fired")

	# --- result ---------------------------------------------------------
	print("")
	if failures.is_empty():
		print("TEST PASS")
		finished = true
		get_tree().quit(0)
	else:
		print("TEST FAIL (", failures.size(), " problems):")
		for f in failures:
			print("  - ", f)
		finished = true
		get_tree().quit(1)

## --- helpers ----------------------------------------------------------

func _wire_signals() -> void:
	sb.city_production_complete.connect(func(_c, _i): events["production_complete"] += 1)
	sb.unit_destroyed.connect(func(_u): events["units_destroyed"] += 1)
	sb.unit_attacked.connect(func(_a, _b, _d): events["attacks"] += 1)
	sb.war_declared.connect(func(_a, _b): events["war_declared"] += 1)
	sb.peace_signed.connect(func(_a, _b): events["peace_signed"] += 1)
	sb.trade_established.connect(func(_a, _b): events["trade_established"] += 1)
	sb.diplomacy_proposal.connect(func(_a, _b, _c): events["diplomacy_proposal"] += 1)
	sb.city_captured.connect(func(_c, _o): events["city_captured"] += 1)
	sb.city_revolted.connect(func(_c, _o): events["revolted"] += 1)
	sb.unit_moved.connect(func(_u, _f, _t): events["moves"] += 1)

func _find_player_unit():
	for unit in unit_manager.units:
		if unit.faction_id == 0:
			return unit
	return null

## True when a hex is in bounds, land, and holds no city or unit.
func _is_free_land(hex: Vector2i) -> bool:
	if not HexUtils.hex_in_bounds(hex, Vector2i(hex_grid.map_width, hex_grid.map_height)):
		return false
	if TerrainData.is_water(hex_grid.get_terrain(hex)):
		return false
	if city_manager.get_city_at(hex) != null:
		return false
	return unit_manager.get_units_at(hex).size() == 0

func _find_unexplored():
	for y in range(hex_grid.map_height):
		for x in range(hex_grid.map_width):
			var hex = Vector2i(x, y)
			if not hex_grid.explored.has(hex) and not TerrainData.is_water(hex_grid.get_terrain(hex)):
				return hex
	return null

func _find_free_land_hex(near: Vector2i):
	for radius in range(0, 20):
		for offset in HexUtils.hex_range(Vector2i.ZERO, radius):
			var hex = near + offset
			if not HexUtils.hex_in_bounds(hex, Vector2i(hex_grid.map_width, hex_grid.map_height)):
				continue
			if TerrainData.is_water(hex_grid.get_terrain(hex)):
				continue
			if city_manager.get_city_at(hex) != null:
				continue
			if unit_manager.get_units_at(hex).size() > 0:
				continue
			return hex
	return null
