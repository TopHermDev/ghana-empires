## Main game scene controller.
extends Node2D

@onready var hex_grid = $HexGrid
@onready var camera = $Camera2D

## Unit manager for handling all units.
var unit_manager = null

## Current game state.
var game_state = "playing"  # playing, unit_selected, unit_moving

func _ready() -> void:
	# Create unit manager
	unit_manager = preload("res://scripts/game/unit_manager.gd").new()
	unit_manager.name = "UnitManager"
	add_child(unit_manager)
	unit_manager.setup(hex_grid)

	# Connect to signal bus
	SignalBus.hex_clicked.connect(_on_hex_clicked)
	SignalBus.hex_hovered.connect(_on_hex_hovered)
	SignalBus.hex_right_clicked.connect(_on_hex_right_clicked)
	SignalBus.unit_moved.connect(_on_unit_moved)
	SignalBus.unit_destroyed.connect(_on_unit_destroyed)

	# Center camera
	var center_hex = Vector2i(map_width / 2, map_height / 2)
	camera.position = HexUtils.hex_to_pixel(center_hex, hex_grid.hex_size)

	# Spawn starting units for testing
	_spawn_starting_units()

func _spawn_starting_units() -> void:
	# Ashanti units (bottom center)
	unit_manager.spawn_unit("ashanti_warrior", Vector2i(25, 30), 0)
	unit_manager.spawn_unit("scout", Vector2i(27, 29), 0)

	# Dagbon units (top left)
	unit_manager.spawn_unit("dagbon_raider", Vector2i(15, 10), 1)
	unit_manager.spawn_unit("dagbon_griot", Vector2i(17, 11), 1)

	# Fante units (bottom right, near coast)
	unit_manager.spawn_unit("fante_canoe_warrior", Vector2i(40, 35), 2)
	unit_manager.spawn_unit("scout", Vector2i(38, 34), 2)

	# Mamprusi units (top right)
	unit_manager.spawn_unit("mamprusi_spearman", Vector2i(45, 12), 3)
	unit_manager.spawn_unit("scout", Vector2i(43, 13), 3)

func _on_hex_clicked(hex: Vector2i) -> void:
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

func _input(event: InputEvent) -> void:
	# Escape to deselect
	if event.is_action_pressed("ui_cancel"):
		if game_state == "unit_selected":
			unit_manager.deselect_unit()
			hex_grid.clear_overlays()
			game_state = "playing"
