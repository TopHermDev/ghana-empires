## Main menu scene controller.
extends Control

@onready var title_label = $VBoxContainer/TitleLabel
@onready var new_game_button = $VBoxContainer/NewGameButton
@onready var load_game_button = $VBoxContainer/LoadGameButton
@onready var quit_button = $VBoxContainer/QuitButton

func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_new_game_pressed() -> void:
	# For now, start a new game with default settings
	GameManager.new_game(0, Vector2i(60, 45))
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")

func _on_load_game_pressed() -> void:
	# TODO: Implement load game
	print("Load game not yet implemented")

func _on_quit_pressed() -> void:
	get_tree().quit()
