## Main game scene controller.
extends Node2D

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

## AI controllers for non-player factions.
var ai_controllers: Dictionary = {}

## Current game state.
## States: playing, unit_selected, unit_moving, city_selected
var game_state = "playing"

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

	# Connect to signal bus
	SignalBus.hex_clicked.connect(_on_hex_clicked)
	SignalBus.hex_hovered.connect(_on_hex_hovered)
	SignalBus.hex_right_clicked.connect(_on_hex_right_clicked)
	SignalBus.unit_moved.connect(_on_unit_moved)
	SignalBus.unit_destroyed.connect(_on_unit_destroyed)
	SignalBus.city_selected.connect(_on_city_selected)
	SignalBus.city_deselected.connect(_on_city_deselected)
	SignalBus.turn_started.connect(_on_turn_started)

	# Center camera
	var center_hex = Vector2i(hex_grid.map_width / 2, hex_grid.map_height / 2)
	camera.position = HexUtils.hex_to_pixel(center_hex, hex_grid.hex_size)

	# Spawn starting cities and units for testing
	_spawn_starting_cities()
	_spawn_starting_units()

	# Initialize AI for non-player factions
	_init_ai()

func _spawn_starting_cities() -> void:
	# Ashanti cities (center-south)
	city_manager.spawn_city("kumasi", Vector2i(28, 30), 0)
	city_manager.spawn_city("ejisu", Vector2i(30, 32), 0)
	city_manager.spawn_city("bonwire", Vector2i(26, 29), 0)

	# Dagbon cities (north-west)
	city_manager.spawn_city("yendi", Vector2i(15, 8), 1)
	city_manager.spawn_city("nalerigu", Vector2i(13, 10), 1)

	# Fante cities (south-east, near coast)
	city_manager.spawn_city("elmina", Vector2i(42, 36), 2)
	city_manager.spawn_city("cape_coast", Vector2i(40, 38), 2)

	# Mamprusi cities (north-east)
	city_manager.spawn_city("mampong", Vector2i(45, 10), 3)
	city_manager.spawn_city("larabanga", Vector2i(47, 12), 3)

func _spawn_starting_units() -> void:
	# Ashanti units (near Kumasi)
	unit_manager.spawn_unit("ashanti_warrior", Vector2i(27, 30), 0)
	unit_manager.spawn_unit("scout", Vector2i(29, 31), 0)

	# Dagbon units (near Yendi)
	unit_manager.spawn_unit("dagbon_raider", Vector2i(14, 8), 1)
	unit_manager.spawn_unit("dagbon_griot", Vector2i(16, 9), 1)

	# Fante units (near Elmina)
	unit_manager.spawn_unit("fante_canoe_warrior", Vector2i(41, 36), 2)
	unit_manager.spawn_unit("scout", Vector2i(43, 37), 2)

	# Mamprusi units (near Mampong)
	unit_manager.spawn_unit("mamprusi_spearman", Vector2i(44, 10), 3)
	unit_manager.spawn_unit("scout", Vector2i(46, 11), 3)

func _init_ai() -> void:
	var ai_script = preload("res://scripts/game/ai/ai_controller.gd")
	for i in range(1, 4):  # Factions 1-3 are AI
		var ai = ai_script.new()
		ai.name = "AI_" + str(i)
		add_child(ai)
		ai.setup(i, unit_manager, city_manager, hex_grid)
		ai_controllers[i] = ai

func _on_hex_clicked(hex: Vector2i) -> void:
	# Check if clicking on a city first
	var clicked_city = city_manager.get_city_at(hex)
	if clicked_city:
		_handle_city_click(clicked_city)
		return

	var clicked_unit = unit_manager.get_unit_at(hex)

	match game_state:
		"playing":
			if clicked_unit and clicked_unit.faction_id == GameManager.selected_faction:
				# Select our own unit
				unit_manager.select_unit(clicked_unit)
				hex_grid.show_movement_range(clicked_unit)
				game_state = "unit_selected"
			else:
				# Clicked on empty hex or enemy
				hex_grid.clear_overlays()

		"unit_selected":
			if clicked_unit and clicked_unit == unit_manager.selected_unit:
				# Deselect
				unit_manager.deselect_unit()
				hex_grid.clear_overlays()
				game_state = "playing"
			elif clicked_unit and clicked_unit.faction_id != GameManager.selected_faction:
				# Attack enemy unit
				var result = unit_manager.process_combat(unit_manager.selected_unit, clicked_unit)
				if result.size() > 0:
					print("Combat: dealt ", result["damage_dealt"], " took ", result["counter_damage"])
					hex_grid.clear_overlays()
					unit_manager.deselect_unit()
					game_state = "playing"
			else:
				# Move to empty hex
				if unit_manager.move_unit(unit_manager.selected_unit, hex):
					hex_grid.clear_overlays()
					unit_manager.deselect_unit()
					game_state = "playing"

		"city_selected":
			# Clicking elsewhere closes city screen
			city_screen.hide()
			city_manager.deselect_city()
			game_state = "playing"

func _handle_city_click(city) -> void:
	# Deselect any selected unit
	if game_state == "unit_selected":
		unit_manager.deselect_unit()
		hex_grid.clear_overlays()

	# Select the city
	city_manager.select_city(city)
	game_state = "city_selected"

func _on_hex_hovered(hex: Vector2i) -> void:
	# Could show terrain info in UI
	pass

func _on_hex_right_clicked(hex: Vector2i) -> void:
	# Right click to move selected unit
	if game_state == "unit_selected" and unit_manager.selected_unit:
		if unit_manager.move_unit(unit_manager.selected_unit, hex):
			hex_grid.clear_overlays()
			unit_manager.deselect_unit()
			game_state = "playing"

func _on_unit_moved(unit, from_hex: Vector2i, to_hex: Vector2i) -> void:
	# Update movement range display
	if unit == unit_manager.selected_unit:
		hex_grid.show_movement_range(unit)

func _on_unit_destroyed(unit) -> void:
	if unit == unit_manager.selected_unit:
		unit_manager.deselect_unit()
		hex_grid.clear_overlays()
		game_state = "playing"

func _on_city_selected(city) -> void:
	# City screen is handled by the city_screen node itself
	pass

func _on_city_deselected() -> void:
	if game_state == "city_selected":
		game_state = "playing"

func _on_turn_started(turn_number: int) -> void:
	# Process city production for the current faction (player)
	var completed = city_manager.process_turn(GameManager.selected_faction)

	# Spawn completed units near their cities
	for entry in completed:
		var city = entry["city"]
		var unit_id = entry["unit_id"]
		_spawn_unit_near_city(city, unit_id)
		SignalBus.city_production_complete.emit(city, unit_id)

	# Reset units for the faction
	unit_manager.end_turn(GameManager.selected_faction)

	# Process AI turns for all non-player factions
	for faction_id in ai_controllers:
		if faction_id != GameManager.selected_faction:
			var ai = ai_controllers[faction_id]
			ai.execute_turn()
			# Process AI city production and unit resets
			var ai_completed = city_manager.process_turn(faction_id)
			for entry in ai_completed:
				var city = entry["city"]
				var unit_id = entry["unit_id"]
				_spawn_unit_near_city(city, unit_id)
			unit_manager.end_turn(faction_id)

	# Update hex grid
	hex_grid.queue_redraw()

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

func _spawn_unit_near_city(city, unit_id: String) -> void:
	# Find an adjacent empty hex to spawn the unit
	var neighbors = HexUtils.hex_neighbors(city.hex_position)
	for neighbor in neighbors:
		if HexUtils.hex_in_bounds(neighbor, Vector2i(hex_grid.map_width, hex_grid.map_height)):
			if unit_manager.get_unit_at(neighbor) == null:
				unit_manager.spawn_unit(unit_id, neighbor, city.faction_id)
				return
	# If all adjacent hexes are full, try 2-hex radius
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var check = city.hex_position + Vector2i(dx, dy)
			if HexUtils.hex_in_bounds(check, Vector2i(hex_grid.map_width, hex_grid.map_height)):
				if unit_manager.get_unit_at(check) == null:
					unit_manager.spawn_unit(unit_id, check, city.faction_id)
					return

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
