## Terrain type definitions, loaded from data/terrain.json.
## Single source of truth for movement cost, defense and colour of terrain.
class_name TerrainData

## Raw terrain definitions keyed by terrain id.
static var terrain: Dictionary = _load_terrain()

## Terrain id by single-character map code (see data/maps/*.json).
static var code_map: Dictionary = _build_code_map()

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("TerrainData: missing " + path + ", using defaults")
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("TerrainData: could not parse " + path)
		return {}
	return parsed

static func _load_terrain() -> Dictionary:
	var data = _load_json("res://data/terrain.json")
	if data.is_empty():
		return {
			"grassland": {"name": "Grassland", "code": "g", "color": [0.4, 0.7, 0.3],
				"move_cost": 1, "defense": 0, "water": false},
		}
	return data

static func _build_code_map() -> Dictionary:
	var result = {}
	for id in terrain:
		var code = terrain[id].get("code", "")
		if code != "":
			result[code] = id
	return result

## Get a terrain definition by id (empty dictionary if unknown).
static func get_terrain(terrain_id: String) -> Dictionary:
	return terrain.get(terrain_id, {})

## Movement cost of a terrain type.
static func get_move_cost(terrain_id: String) -> int:
	return int(get_terrain(terrain_id).get("move_cost", 1))

## Defensive bonus provided by terrain when defending on it.
static func get_defense(terrain_id: String) -> int:
	return int(get_terrain(terrain_id).get("defense", 0))

## True for ocean/coast (naval and amphibious units only).
static func is_water(terrain_id: String) -> bool:
	return bool(get_terrain(terrain_id).get("water", false))

## Display colour of a terrain type.
static func get_color(terrain_id: String) -> Color:
	var raw = get_terrain(terrain_id).get("color", [1, 1, 1])
	return Color(float(raw[0]), float(raw[1]), float(raw[2]))

## Display name of a terrain type.
static func get_terrain_name(terrain_id: String) -> String:
	return str(get_terrain(terrain_id).get("name", terrain_id))

## Convert a single-character map code to a terrain id.
static func code_to_id(code: String) -> String:
	return code_map.get(code, "grassland")

## Convert a terrain id to its single-character map code.
static func id_to_code(terrain_id: String) -> String:
	return str(get_terrain(terrain_id).get("code", "g"))

## All terrain ids.
static func ids() -> Array:
	return terrain.keys()
