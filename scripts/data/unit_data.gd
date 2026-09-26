## Unit data definitions.
class_name UnitData

## Unit type definition.
class UnitType:
	var id: String
	var name: String
	var faction: String
	var attack: int
	var defense: int
	var movement: int
	var hp: int
	var max_hp: int
	var range: int
	var cost: int
	var era: String
	var special: String

	func _init(data: Dictionary = {}) -> void:
		id = data.get("id", "unknown")
		name = data.get("name", "Unknown Unit")
		faction = data.get("faction", "neutral")
		attack = data.get("attack", 5)
		defense = data.get("defense", 5)
		movement = data.get("movement", 2)
		hp = data.get("hp", 100)
		max_hp = hp
		range = data.get("range", 1)
		cost = data.get("cost", 50)
		era = data.get("era", "early")
		special = data.get("special", "")

## All unit definitions.
static var units = {
	# Ashanti Units
	"ashanti_warrior": {
		"id": "ashanti_warrior",
		"name": "Akofena Warrior",
		"faction": "ashanti",
		"attack": 8,
		"defense": 6,
		"movement": 2,
		"hp": 100,
		"range": 1,
		"cost": 50,
		"era": "early",
		"special": "bonus_vs_infantry"
	},
	"ashanti_musketeer": {
		"id": "ashanti_musketeer",
		"name": "Musketeer",
		"faction": "ashanti",
		"attack": 14,
		"defense": 8,
		"movement": 2,
		"hp": 80,
		"range": 2,
		"cost": 120,
		"era": "mid",
		"special": "ranged"
	},
	"ashanti_guard": {
		"id": "ashanti_guard",
		"name": "Golden Guard",
		"faction": "ashanti",
		"attack": 18,
		"defense": 14,
		"movement": 2,
		"hp": 120,
		"range": 1,
		"cost": 200,
		"era": "late",
		"special": "immune_morale"
	},

	# Dagbon Units
	"dagbon_raider": {
		"id": "dagbon_raider",
		"name": "Dagomba Raider",
		"faction": "dagbon",
		"attack": 7,
		"defense": 4,
		"movement": 3,
		"hp": 80,
		"range": 1,
		"cost": 45,
		"era": "early",
		"special": "first_strike"
	},
	"dagbon_horse_archer": {
		"id": "dagbon_horse_archer",
		"name": "Horse Archer",
		"faction": "dagbon",
		"attack": 10,
		"defense": 5,
		"movement": 4,
		"hp": 70,
		"range": 3,
		"cost": 130,
		"era": "mid",
		"special": "ranged_cavalry"
	},
	"dagbon_griot": {
		"id": "dagbon_griot",
		"name": "Griot",
		"faction": "dagbon",
		"attack": 0,
		"defense": 2,
		"movement": 2,
		"hp": 50,
		"range": 1,
		"cost": 60,
		"era": "early",
		"special": "intelligence"
	},

	# Fante Units
	"fante_canoe_warrior": {
		"id": "fante_canoe_warrior",
		"name": "Canoe Warrior",
		"faction": "fante",
		"attack": 6,
		"defense": 4,
		"movement": 2,
		"hp": 80,
		"range": 1,
		"cost": 50,
		"era": "early",
		"special": "amphibious"
	},
	"fante_musketman": {
		"id": "fante_musketman",
		"name": "Musketman",
		"faction": "fante",
		"attack": 12,
		"defense": 7,
		"movement": 2,
		"hp": 75,
		"range": 2,
		"cost": 110,
		"era": "mid",
		"special": "ranged"
	},
	"fante_war_canoe": {
		"id": "fante_war_canoe",
		"name": "War Canoe",
		"faction": "fante",
		"attack": 10,
		"defense": 8,
		"movement": 3,
		"hp": 90,
		"range": 1,
		"cost": 140,
		"era": "mid",
		"special": "naval"
	},

	# Mamprusi Units
	"mamprusi_spearman": {
		"id": "mamprusi_spearman",
		"name": "Mamprusi Spearman",
		"faction": "mamprusi",
		"attack": 6,
		"defense": 8,
		"movement": 2,
		"hp": 100,
		"range": 1,
		"cost": 40,
		"era": "early",
		"special": "bonus_vs_cavalry"
	},
	"mamprusi_royal_guard": {
		"id": "mamprusi_royal_guard",
		"name": "Royal Guard",
		"faction": "mamprusi",
		"attack": 14,
		"defense": 12,
		"movement": 2,
		"hp": 110,
		"range": 1,
		"cost": 140,
		"era": "mid",
		"special": "capital_bonus"
	},
	"mamprusi_elephant": {
		"id": "mamprusi_elephant",
		"name": "Siege Elephant",
		"faction": "mamprusi",
		"attack": 18,
		"defense": 10,
		"movement": 2,
		"hp": 150,
		"range": 1,
		"cost": 220,
		"era": "late",
		"special": "siege_terror"
	},

	# Generic/Neutral
	"warrior": {
		"id": "warrior",
		"name": "Warrior",
		"faction": "neutral",
		"attack": 5,
		"defense": 5,
		"movement": 2,
		"hp": 100,
		"range": 1,
		"cost": 40,
		"era": "early",
		"special": ""
	},
	"scout": {
		"id": "scout",
		"name": "Scout",
		"faction": "neutral",
		"attack": 3,
		"defense": 2,
		"movement": 3,
		"hp": 60,
		"range": 1,
		"cost": 30,
		"era": "early",
		"special": "extra_vision"
	},
}

## Get unit definition by id.
static func get_unit(unit_id: String) -> Dictionary:
	return units.get(unit_id, {})

## Get all units for a faction.
static func get_faction_units(faction: String) -> Array:
	var result = []
	for key in units:
		if units[key].get("faction", "") == faction or units[key].get("faction", "") == "neutral":
			result.append(units[key])
	return result

## Get terrain movement cost (delegates to TerrainData / data/terrain.json).
static func get_terrain_cost(terrain: String) -> int:
	return TerrainData.get_move_cost(terrain)
