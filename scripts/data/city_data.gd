## City data definitions.
class_name CityData

## City definition.
class CityType:
	var id: String
	var name: String
	var faction: String
	var population: int
	var gold_per_turn: int
	var production_speed: int

	func _init(data: Dictionary = {}) -> void:
		id = data.get("id", "village")
		name = data.get("name", "Village")
		faction = data.get("faction", "neutral")
		population = data.get("population", 1)
		gold_per_turn = data.get("gold_per_turn", 5)
		production_speed = data.get("production_speed", 1)

## All city definitions.
static var cities = {
	# Ashanti Cities
	"kumasi": {
		"id": "kumasi",
		"name": "Kumasi",
		"faction": "ashanti",
		"population": 5,
		"gold_per_turn": 25,
		"production_speed": 2,
	},
	"ejisu": {
		"id": "ejisu",
		"name": "Ejisu",
		"faction": "ashanti",
		"population": 3,
		"gold_per_turn": 12,
		"production_speed": 1,
	},
	"bonwire": {
		"id": "bonwire",
		"name": "Bonwire",
		"faction": "ashanti",
		"population": 2,
		"gold_per_turn": 8,
		"production_speed": 1,
	},

	# Dagbon Cities
	"yendi": {
		"id": "yendi",
		"name": "Yendi",
		"faction": "dagbon",
		"population": 4,
		"gold_per_turn": 18,
		"production_speed": 2,
	},
	"nalerigu": {
		"id": "nalerigu",
		"name": "Nalerigu",
		"faction": "dagbon",
		"population": 3,
		"gold_per_turn": 10,
		"production_speed": 1,
	},

	# Fante Cities
	"elmina": {
		"id": "elmina",
		"name": "Elmina",
		"faction": "fante",
		"population": 4,
		"gold_per_turn": 22,
		"production_speed": 2,
	},
	"cape_coast": {
		"id": "cape_coast",
		"name": "Cape Coast",
		"faction": "fante",
		"population": 3,
		"gold_per_turn": 15,
		"production_speed": 1,
	},

	# Mamprusi Cities
	"mampong": {
		"id": "mampong",
		"name": "Mampong",
		"faction": "mamprusi",
		"population": 4,
		"gold_per_turn": 16,
		"production_speed": 2,
	},
	"larabanga": {
		"id": "larabanga",
		"name": "Larabanga",
		"faction": "mamprusi",
		"population": 2,
		"gold_per_turn": 8,
		"production_speed": 1,
	},

	# Neutral
	"village": {
		"id": "village",
		"name": "Village",
		"faction": "neutral",
		"population": 1,
		"gold_per_turn": 3,
		"production_speed": 1,
	},
}

## Get city definition by id.
static func get_city(city_id: String) -> Dictionary:
	return cities.get(city_id, {})

## Get all cities for a faction.
static func get_faction_cities(faction: String) -> Array:
	var result = []
	for key in cities:
		if cities[key].get("faction", "") == faction:
			result.append(cities[key])
	return result
