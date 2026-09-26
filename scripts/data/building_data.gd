## Building definitions, loaded from data/buildings.json.
##
## Effects keys: gold_per_turn, food, production_speed, defense, happiness.
## All effects are permanent for the city that completes the building.
class_name BuildingData

static var buildings: Dictionary = _load()

## Allowed effect keys, used for validation and documentation.
const EFFECT_KEYS = ["gold_per_turn", "food", "production_speed", "defense", "happiness"]

static func _load() -> Dictionary:
	if not FileAccess.file_exists("res://data/buildings.json"):
		push_warning("BuildingData: missing data/buildings.json")
		return {}
	var file = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("BuildingData: could not parse data/buildings.json")
		return {}
	return parsed

## Get a building definition by id.
static func get_building(building_id: String) -> Dictionary:
	return buildings.get(building_id, {})

## Display name of a building.
static func get_building_name(building_id: String) -> String:
	return str(get_building(building_id).get("name", building_id))

## Gold cost of a building.
static func get_cost(building_id: String) -> int:
	return int(get_building(building_id).get("cost", 50))

## Short description of a building.
static func get_description(building_id: String) -> String:
	return str(get_building(building_id).get("description", ""))

## Summed effect value of a set of building ids for one effect key.
## Example: BuildingData.total_effect(["market", "granary"], "gold_per_turn") -> 5
static func total_effect(building_ids: Array, effect_key: String) -> int:
	var total = 0
	for id in building_ids:
		var effects = get_building(id).get("effects", {})
		total += int(effects.get(effect_key, 0))
	return total

## Effects contributed by a single building id (empty dictionary if unknown).
static func get_effects(building_id: String) -> Dictionary:
	return get_building(building_id).get("effects", {})

## True if the id is a known building.
static func is_valid(building_id: String) -> bool:
	return buildings.has(building_id)

## All building ids.
static func ids() -> Array:
	return buildings.keys()
