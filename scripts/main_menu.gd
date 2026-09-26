## Main menu scene controller.
extends Control

@onready var title_label = $VBoxContainer/TitleLabel
@onready var new_game_button = $VBoxContainer/NewGameButton
@onready var load_game_button = $VBoxContainer/LoadGameButton
@onready var quit_button = $VBoxContainer/QuitButton
@onready var vbox = $VBoxContainer

## Map size options shown in the menu.
const MAP_OPTIONS = [
	["Small (40x30)", Vector2i(40, 30)],
	["Medium (60x45)", Vector2i(60, 45)],
	["Large (80x60)", Vector2i(80, 60)],
]

## AI difficulty options.
const DIFFICULTY_OPTIONS = ["easy", "normal", "hard"]

var map_option: OptionButton
var difficulty_option: OptionButton

func _ready() -> void:
	_build_options()
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

## Insert map size and difficulty pickers above the New Game button.
func _build_options() -> void:
	var insert_at = new_game_button.get_index()

	map_option = OptionButton.new()
	map_option.name = "MapSizeOption"
	for entry in MAP_OPTIONS:
		map_option.add_item(entry[0])
	map_option.select(1)  # Medium by default
	vbox.add_child(map_option)
	vbox.move_child(map_option, insert_at)

	difficulty_option = OptionButton.new()
	difficulty_option.name = "DifficultyOption"
	for label in DIFFICULTY_OPTIONS:
		difficulty_option.add_item(label.capitalize())
	difficulty_option.select(1)  # Normal by default
	vbox.add_child(difficulty_option)
	vbox.move_child(difficulty_option, insert_at + 1)

	# Spacer between the pickers and the buttons
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	vbox.move_child(spacer, insert_at + 2)

func _on_new_game_pressed() -> void:
	var size: Vector2i = MAP_OPTIONS[map_option.selected][1]
	GameManager.ai_difficulty = DIFFICULTY_OPTIONS[difficulty_option.selected]
	GameManager.new_game(0, size)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_load_game_pressed() -> void:
	# TODO: Implement load game (Phase 7)
	print("Load game not yet implemented")

func _on_quit_pressed() -> void:
	get_tree().quit()
