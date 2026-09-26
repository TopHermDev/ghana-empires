## Main game scene controller.
##
## Owns the managers, drives the turn pipeline (player -> diplomacy ->
## AI factions), fog of war, unit/city selection and the UI wiring.
extends Node2D

## Starting positions in the 60x45 design space (scaled to the actual map).
const BASE_MAP_SIZE = Vector2i(60, 45)

const START_CITIES = [
	["kumasi", Vector2i(28, 30), 0],
	["ejisu", Vector2i(30, 32), 0],
	["bonwire", Vector2i(26, 29), 0],
	["yendi", Vector2i(15, 8), 1],
	["nalerigu", Vector2i(13, 10), 1],
	["elmina", Vector2i(42, 36), 2],
	["cape_coast", Vector2i(40, 38), 2],
	["mampong", Vector2i(45, 10), 3],
	["larabanga", Vector2i(47, 12), 3],
]

const START_UNITS = [
	["ashanti_warrior", Vector2i(27, 30), 0],
	["scout", Vector2i(29, 31), 0],
	["dagbon_raider", Vector2i(14, 8), 1],
	["dagbon_griot", Vector2i(16, 9), 1],
	["fante_canoe_warrior", Vector2i(41, 36), 2],
	["scout", Vector2i(43, 37), 2],
	["mamprusi_spearman", Vector2i(44, 10), 3],
	["scout", Vector2i(46, 11), 3],
]

@onready var hex_grid = $HexGrid
@onready var camera = $Camera2D

## Unit manager for handling all units.
var unit_manager = null

## City manager for handling all cities.
var city_manager = null

## HUD overlay.
var hud = null

## Unit info panel.
var unit_info_panel = null

## City screen.
var city_screen = null

## Hex info panel (terrain / resources on hover).
var hex_info_panel = null

## Diplomacy proposal dialog.
var proposal_dialog = null

## AI controllers for non-player factions.
var ai_controllers: Dictionary = {}

## Current game state.
## States: playing, unit_selected, unit_moving, city_selected
var game_state = "playing"

## Cycle index used when a hex holds several of the player's units.
var stack_cycle_index: int = 0

func _ready() -> void:
	# Create unit manager
	unit_manager = preload("res://scripts/game/unit_manager.gd").new()
	unit_manager.name = "UnitManager"
	add_child(unit_manager)
	unit_manager.setup(hex_grid)

	# Create city manager
	city_manager = preload("res://scripts/game/city_manager.gd").new()
	city_manager.name = "CityManager"
	add_child(city_manager)
	city_manager.setup(hex_grid)

	# Managers reference each other for sieges, capture and defence bonuses.
	unit_manager.city_manager = city_manager
	city_manager.unit_manager = unit_manager

	# Diplomacy state and the strength estimates it needs.
	Diplomacy.reset()
	Diplomacy.unit_manager = unit_manager
	Diplomacy.city_manager = city_manager

	# Instance UI scenes
	var hud_scene = preload("res://scenes/ui/hud.tscn")
	hud = hud_scene.instantiate()
	add_child(hud)

	var unit_info_scene = preload("res://scenes/ui/unit_info_panel.tscn")
	unit_info_panel = unit_info_scene.instantiate()
	add_child(unit_info_panel)

	var city_screen_scene = preload("res://scenes/ui/city_screen.tscn")
	city_screen = city_screen_scene.instantiate()
	add_child(city_screen)
	city_screen.player_faction = GameManager.selected_faction

	var hex_info_scene = preload("res://scenes/ui/hex_info_panel.tscn")
	hex_info_panel = hex_info_scene.instantiate()
	add_child(hex_info_panel)
	hex_info_panel.setup(hex_grid, unit_manager, city_manager)

	var proposal_scene = preload("res://scenes/ui/proposal_dialog.tscn")
	proposal_dialog = proposal_scene.instantiate()
	add_child(proposal_dialog)

	# Connect to signal bus
	SignalBus.hex_clicked.connect(_on_hex_clicked)
	SignalBus.hex_hovered.connect(_on_hex_hovered)
	SignalBus.hex_right_clicked.connect(_on_hex_right_clicked)
	SignalBus.unit_moved.connect(_on_unit_moved)
	SignalBus.unit_destroyed.connect(_on_unit_destroyed)
	SignalBus.city_selected.connect(_on_city_selected)
	SignalBus.city_deselected.connect(_on_city_deselected)
	SignalBus.city_captured.connect(_on_city_captured)
	SignalBus.turn_started.connect(_on_turn_started)
	SignalBus.diplomacy_proposal.connect(_on_diplomacy_proposal)

	# Center camera
	var center_hex = Vector2i(hex_grid.map_width / 2, hex_grid.map_height / 2)
	camera.position = HexUtils.hex_to_pixel(center_hex, hex_grid.hex_size)

	# Spawn starting cities and units for testing
	_spawn_starting_cities()
	_spawn_starting_units()

	# Initialize AI for non-player factions
	_init_ai()

	# Initial fog of war state
	_refresh_fog()

func _scale_hex(hex: Vector2i) -> Vector2i:
	var sx = float(hex_grid.map_width) / float(BASE_MAP_SIZE.x)
	var sy = float(hex_grid.map_height) / float(BASE_MAP_SIZE.y)
	var scaled = Vector2i(int(round(hex.x * sx)), int(round(hex.y * sy)))
	scaled.x = clampi(scaled.x, 1, hex_grid.map_width - 2)
	scaled.y = clampi(scaled.y, 1, hex_grid.map_height - 2)
	return scaled

func _spawn_starting_cities() -> void:
	for entry in START_CITIES:
		var hex = _scale_hex(entry[1])
		# Any map file works: make sure the city actually sits on land.
		hex_grid.ensure_land(hex, 1)
		city_manager.spawn_city(entry[0], hex, entry[2])

func _spawn_starting_units() -> void:
	for entry in START_UNITS:
		var hex = _scale_hex(entry[1])
		if unit_manager.can_spawn_at(hex, entry[2]):
			unit_manager.spawn_unit(entry[0], hex, entry[2])
		else:
			# Fall back to the nearest hex that accepts the unit.
			for radius in range(1, 5):
				var placed = false
				for offset in HexUtils.hex_range(Vector2i.ZERO, radius):
					var candidate = hex + offset
					if unit_manager.can_spawn_at(candidate, entry[2]):
						unit_manager.spawn_unit(entry[0], candidate, entry[2])
						placed = true
						break
				if placed:
					break

func _init_ai() -> void:
	var ai_script = preload("res://scripts/game/ai/ai_controller.gd")
	for i in range(1, 4):  # Factions 1-3 are AI
		var ai = ai_script.new()
		ai.name = "AI_" + str(i)
		add_child(ai)
		ai.setup(i, unit_manager, city_manager, hex_grid)
		ai_controllers[i] = ai

## --- FOG OF WAR ------------------------------------------------------

## Recompute the player's vision (units + owned cities) and push it to the grid.
func _refresh_fog() -> void:
	if hex_grid == null or not hex_grid.fog_enabled:
		return
	var player = GameManager.selected_faction
	var vision = unit_manager.get_faction_vision(player)
	for city in city_manager.get_faction_cities(player):
		for hex in HexUtils.hex_range(city.hex_position, 2):
			if HexUtils.hex_in_bounds(hex, Vector2i(hex_grid.map_width, hex_grid.map_height)):
				vision[hex] = true
	hex_grid.update_fog(vision)

## --- INPUT HANDLING --------------------------------------------------

func _on_hex_clicked(hex: Vector2i) -> void:
	# Check if clicking on a city first
	var clicked_city = city_manager.get_city_at(hex)
	if clicked_city:
		_handle_city_click(clicked_city)
		return

	var units_here = unit_manager.get_units_at(hex)
	var own_units = units_here.filter(
		func(u): return u.faction_id == GameManager.selected_faction)
	var enemy_units = units_here.filter(
		func(u): return u.faction_id != GameManager.selected_faction)

	match game_state:
		"playing":
			if own_units.size() > 0:
				# Select our own unit (prefer one that has not acted yet)
				var pick = own_units[0]
				for candidate in own_units:
					if not candidate.has_acted:
						pick = candidate
						break
				stack_cycle_index = 0
				unit_manager.select_unit(pick)
				hex_grid.show_movement_range(pick)
				game_state = "unit_selected"
			else:
				# Clicked on empty hex or enemy
				hex_grid.clear_overlays()

		"unit_selected":
			var selected = unit_manager.selected_unit

			if own_units.size() > 0 and hex == selected.hex_position:
				# Cycle through our own stack on this hex
				stack_cycle_index = (stack_cycle_index + 1) % own_units.size()
				var next_unit = own_units[stack_cycle_index]
				unit_manager.select_unit(next_unit)
				hex_grid.show_movement_range(next_unit)
				return

			if enemy_units.size() > 0:
				_try_attack(selected, enemy_units[0])
				return

			# Move to empty hex (or join our own stack)
			if unit_manager.move_unit(selected, hex):
				hex_grid.clear_overlays()
				unit_manager.deselect_unit()
				game_state = "playing"
			else:
				SignalBus.show_message.emit("Can't move there", "error")

		"city_selected":
			# Clicking elsewhere closes city screen
			city_screen.hide()
			city_manager.deselect_city()
			game_state = "playing"

## Attack with the selected unit, respecting range and diplomacy.
func _try_attack(attacker, defender) -> void:
	if not attacker or not defender:
		return

	var dist = HexUtils.hex_distance(attacker.hex_position, defender.hex_position)
	var attack_range = attacker.unit_data.get("range", 1)
	if dist > attack_range:
		SignalBus.show_message.emit("Out of range", "error")
		return

	# Attacking a faction we are at peace with starts a war.
	if defender.faction_id < 4 and not Diplomacy.is_at_war(
			GameManager.selected_faction, defender.faction_id):
		Diplomacy.on_attack(GameManager.selected_faction, defender.faction_id)

	var result = unit_manager.process_combat(attacker, defender)
	if result.size() > 0:
		print("Combat: dealt ", result["damage_dealt"], " took ", result["counter_damage"])
		SignalBus.show_message.emit(
			"-" + str(result["damage_dealt"]) + " to " + str(defender.unit_data.get("name", "unit")),
			"info")

	hex_grid.clear_overlays()
	unit_manager.deselect_unit()
	game_state = "playing"
	_refresh_fog()

func _handle_city_click(city) -> void:
	# Deselect any selected unit
	if game_state == "unit_selected":
		unit_manager.deselect_unit()
		hex_grid.clear_overlays()

	# Select the city
	city_manager.select_city(city)
	game_state = "city_selected"

func _on_hex_hovered(hex: Vector2i) -> void:
	if hex_info_panel:
		hex_info_panel.show_hex(hex)

func _on_hex_right_clicked(hex: Vector2i) -> void:
	# Right click to move selected unit
	if game_state == "unit_selected" and unit_manager.selected_unit:
		if unit_manager.move_unit(unit_manager.selected_unit, hex):
			hex_grid.clear_overlays()
			unit_manager.deselect_unit()
			game_state = "playing"

func _on_unit_moved(unit, _from_hex: Vector2i, _to_hex: Vector2i) -> void:
	# Update movement range display
	if unit == unit_manager.selected_unit:
		hex_grid.show_movement_range(unit)
	_refresh_fog()

func _on_unit_destroyed(unit) -> void:
	if unit == unit_manager.selected_unit:
		unit_manager.deselect_unit()
		hex_grid.clear_overlays()
		game_state = "playing"
	_refresh_fog()

func _on_city_selected(_city) -> void:
	# City screen is handled by the city_screen node itself
	pass

func _on_city_deselected() -> void:
	if game_state == "city_selected":
		game_state = "playing"

func _on_city_captured(_city, _new_owner: int) -> void:
	_refresh_fog()

## --- TURN PIPELINE ---------------------------------------------------

## Runs when the player ends the turn: player phase, diplomacy, then AI.
func _on_turn_started(turn_number: int) -> void:
	# Process city production for the current faction (player)
	_handle_completed(city_manager.process_turn(GameManager.selected_faction))

	# Reset units for the faction
	unit_manager.end_turn(GameManager.selected_faction)

	# Diplomacy upkeep (trade income, war timers, relation drift)
	Diplomacy.process_turn()

	_refresh_fog()

	# AI factions act one after another, yielding to the frame between
	# chunks so the game stays responsive.
	SignalBus.ai_thinking.emit(true, "AI factions are thinking...")
	for faction_id in ai_controllers:
		if faction_id == GameManager.selected_faction:
			continue
		var ai = ai_controllers[faction_id]
		await ai.execute_turn_async()
		if not is_instance_valid(ai):
			continue
		# Process AI city production and unit resets
		_handle_completed(city_manager.process_turn(faction_id))
		unit_manager.end_turn(faction_id)
		await get_tree().process_frame
	SignalBus.ai_thinking.emit(false, "")

	# Update hex grid
	hex_grid.queue_redraw()
	_refresh_fog()

	# Emit turn ended for listeners
	SignalBus.turn_ended.emit(turn_number)

	# Show season warning
	if GameManager.is_rainy():
		SignalBus.show_message.emit("Rainy Season: Movement costs +1", "warning")
	elif GameManager.is_harmattan():
		SignalBus.show_message.emit("Harmattan: Reduced visibility", "warning")
	elif GameManager.current_season == 0:
		SignalBus.show_message.emit("Dry Season: Trade income +25%", "info")

	print("Turn ", turn_number, " started for faction ", GameManager.selected_faction,
			" | Season: ", GameManager.get_season_name())

	# Release the turn lock so the next turn can start.
	GameManager.turn_processing = false

## Spawn units / announce buildings for completed production entries.
func _handle_completed(completed: Array) -> void:
	for entry in completed:
		var city = entry["city"]
		var kind = entry.get("kind", "unit")
		var id = entry.get("id", "")

		if kind == "unit":
			_spawn_unit_near_city(city, id)
			SignalBus.city_production_complete.emit(city, id)
		else:
			var building_name = BuildingData.get_building_name(id)
			SignalBus.show_message.emit(
				str(city.city_data.get("name", "City")) + " completed " + building_name + "!",
				"info")
			print("Building completed: ", building_name, " in ",
					city.city_data.get("name", "?"))
		if is_instance_valid(city):
			city.queue_redraw()

func _spawn_unit_near_city(city, unit_id: String) -> void:
	if not is_instance_valid(city):
		return

	# Prefer an adjacent hex
	for neighbor in HexUtils.hex_neighbors(city.hex_position):
		if unit_manager.can_spawn_at(neighbor, city.faction_id):
			unit_manager.spawn_unit(unit_id, neighbor, city.faction_id)
			_refresh_fog()
			return

	# Otherwise search outwards
	for radius in range(2, 6):
		for offset in HexUtils.hex_range(Vector2i.ZERO, radius):
			var check = city.hex_position + offset
			if unit_manager.can_spawn_at(check, city.faction_id):
				unit_manager.spawn_unit(unit_id, check, city.faction_id)
				_refresh_fog()
				return

## --- DIPLOMACY UI ----------------------------------------------------

func _on_diplomacy_proposal(from_faction: int, to_faction: int, action: String) -> void:
	if proposal_dialog:
		proposal_dialog.queue_proposal(from_faction, to_faction, action)

## --- KEYS ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Escape to deselect
	if event.is_action_pressed("ui_cancel"):
		if game_state == "unit_selected":
			unit_manager.deselect_unit()
			hex_grid.clear_overlays()
			game_state = "playing"
		elif game_state == "city_selected":
			city_screen.hide()
			city_manager.deselect_city()
			game_state = "playing"
