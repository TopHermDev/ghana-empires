## Global game state manager. Autoload singleton.
extends Node

## Current turn number.
var current_turn: int = 0

## Current season index (0=dry, 1=harmattan, 2=rainy, 3=early_dry).
var current_season: int = 0

## Season names.
var seasons = ["Dry Season", "Harmattan", "Rainy Season", "Early Dry"]

## Active factions.
var factions: Array = []

## Currently selected faction index.
var selected_faction: int = 0

## Game state.
var game_state: String = "menu"  # menu, playing, paused, game_over

## Map size.
var map_size: Vector2i = Vector2i(60, 45)

## Initialize a new game.
func new_game(faction_id: int, size: Vector2i) -> void:
	current_turn = 0
	current_season = 0
	selected_faction = faction_id
	map_size = size
	game_state = "playing"
	_init_factions()
	SignalBus.game_started.emit()

## Advance to the next turn.
func next_turn() -> void:
	current_turn += 1
	current_season = (current_turn % 4)
	SignalBus.turn_started.emit(current_turn)

## Get current season name.
func get_season_name() -> String:
	return seasons[current_season]

## Check if it's rainy season (movement penalty).
func is_rainy() -> bool:
	return current_season == 2

## Check if it's harmattan (morale penalty).
func is_harmattan() -> bool:
	return current_season == 1

## Get movement cost modifier for current season.
## Rainy season: +1 to all movement costs (applied as flat addition).
func get_season_movement_modifier() -> int:
	if is_rainy():
		return 1
	return 0

## Get trade income modifier for current season.
## Dry season: +25% trade income.
func get_season_trade_modifier() -> float:
	match current_season:
		0: return 1.25  # Dry season: +25%
		_: return 1.0

## Initialize faction data.
func _init_factions() -> void:
	factions = [
		{"id": 0, "name": "Ashanti", "gold": 200, "cities": [], "units": []},
		{"id": 1, "name": "Dagbon", "gold": 150, "cities": [], "units": []},
		{"id": 2, "name": "Fante", "gold": 180, "cities": [], "units": []},
		{"id": 3, "name": "Mamprusi", "gold": 160, "cities": [], "units": []},
	]

## Save game state to dictionary.
func save_state() -> Dictionary:
	return {
		"turn": current_turn,
		"season": current_season,
		"factions": factions.duplicate(true),
		"map_size": map_size,
	}

## Load game state from dictionary.
func load_state(data: Dictionary) -> void:
	current_turn = data.get("turn", 0)
	current_season = data.get("season", 0)
	factions = data.get("factions", [])
	map_size = data.get("map_size", Vector2i(60, 45))
	game_state = "playing"
