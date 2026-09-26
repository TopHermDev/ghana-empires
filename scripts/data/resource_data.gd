## Map resource definitions, loaded from data/resources.json.
class_name ResourceData

static var resources: Dictionary = _load()

static func _load() -> Dictionary:
	if not FileAccess.file_exists("res://data/resources.json"):
		push_warning("ResourceData: missing data/resources.json")
		return {}
	var file = FileAccess.open("res://data/resources.json", FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("ResourceData: could not parse data/resources.json")
		return {}
	return parsed

## Get a resource definition by id.
static func get_resource(resource_id: String) -> Dictionary:
	return resources.get(resource_id, {})

## Display name of a resource.
static func get_resource_name(resource_id: String) -> String:
	return str(get_resource(resource_id).get("name", resource_id))

## Short glyph drawn on the map for a resource.
static func get_glyph(resource_id: String) -> String:
	return str(get_resource(resource_id).get("glyph", "?"))

## Gold yield of a resource (per adjacent friendly city, per turn).
static func get_gold(resource_id: String) -> int:
	return int(get_resource(resource_id).get("gold", 0))

## Food yield of a resource (per adjacent friendly city, per turn).
static func get_food(resource_id: String) -> int:
	return int(get_resource(resource_id).get("food", 0))

## Display colour of a resource.
static func get_color(resource_id: String) -> Color:
	var raw = get_resource(resource_id).get("color", [1, 1, 1])
	return Color(float(raw[0]), float(raw[1]), float(raw[2]))

## Terrain types a resource may appear on.
static func get_terrains(resource_id: String) -> Array:
	return get_resource(resource_id).get("terrains", [])

## True if the id is a known resource.
static func is_valid(resource_id: String) -> bool:
	return resources.has(resource_id)

## All resource ids.
static func ids() -> Array:
	return resources.keys()
