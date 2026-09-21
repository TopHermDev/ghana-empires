## Main game scene controller.
extends Node2D

@onready var hex_grid = $HexGrid
@onready var camera = $Camera2D

func _ready() -> void:
	# Connect to signal bus
	SignalBus.hex_clicked.connect(_on_hex_clicked)
	SignalBus.hex_hovered.connect(_on_hex_hovered)

	# Center camera
	camera.position = Vector2(
		HexUtils.hex_to_pixel(Vector2i(30, 22), 32.0).x,
		HexUtils.hex_to_pixel(Vector2i(30, 22), 32.0).y
	)

func _on_hex_clicked(hex: Vector2i) -> void:
	var terrain = hex_grid.get_terrain(hex)
	print("Clicked hex: ", hex, " terrain: ", terrain)

func _on_hex_hovered(hex: Vector2i) -> void:
	# Could show hex info in UI
	pass
