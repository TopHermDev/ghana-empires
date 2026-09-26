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

## Map name (small / medium / large) - which file data/maps loads.
var map_name: String = "medium"

## AI difficulty: "easy", "normal" or "hard".
var ai_difficulty: String = "normal"

## Re-entrancy guard: true while a turn (including AI phases) is running.
var turn_processing: bool = false

## Diplomacy state, managed through the Diplomacy class.
## relations: "a|b" -> attitude (-100 .. 100)
## wars / trades: "a|b" -> true
var relations: Dictionary = {}
var wars: Dictionary = {}
var trades: Dictionary = {}
var war_turns: Dictionary = {}

## Difficulty presets.
const DIFFICULTY_VALUES = {"easy": 0.7, "normal": 1.0, "hard": 1.4}
const DIFFICULTY_INCOME = {"easy": 0.8, "normal": 1.0, "hard": 1.3}

## Initialize a new game.
func new_game(faction_id: int, size: Vector2i) -> void:
	current_turn = 0
	current_season = 0
	selected_faction = faction_id
	map_size = size
	map_name = _map_name_for_size(size)
	game_state = "playing"
	_init_factions()
	SignalBus.game_started.emit()

## Resolve the map file name for a map size.
func _map_name_for_size(size: Vector2i) -> String:
	if size.x <= 40:
		return "small"
	if size.x >= 80:
		return "large"
	return "medium"

## Display name of a faction id (4 = rebels, out of range = Unknown).
func get_faction_name(faction_id: int) -> String:
	if faction_id >= 0 and faction_id < factions.size():
		return str(factions[faction_id]["name"])
	if faction_id == 4:
		return "Rebels"
	return "Unknown"

## Gold of a faction (0 when the faction does not exist).
func get_gold(faction_id: int) -> int:
	if faction_id >= 0 and faction_id < factions.size():
		return int(factions[faction_id].get("gold", 0))
	return 0

## Add (or subtract) gold from a faction.
func add_gold(faction_id: int, amount: int) -> void:
	if faction_id >= 0 and faction_id < factions.size():
		factions[faction_id]["gold"] = int(factions[faction_id].get("gold", 0)) + amount

## Numeric difficulty used by AI logic (1.0 = normal).
func get_difficulty_value() -> float:
	return float(DIFFICULTY_VALUES.get(ai_difficulty, 1.0))

## Income multiplier applied to AI factions only.
func get_ai_income_multiplier() -> float:
	return float(DIFFICULTY_INCOME.get(ai_difficulty, 1.0))

## Advance to the next turn.
func next_turn() -> void:
	# Ignore presses while the previous turn is still being processed.
	if turn_processing:
		return
	turn_processing = true
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
