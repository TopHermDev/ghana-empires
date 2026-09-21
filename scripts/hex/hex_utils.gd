## Hex coordinate utilities for offset coordinates (odd-r).
class_name HexUtils

## Convert hex coordinates to pixel position.
static func hex_to_pixel(hex: Vector2i, size: float) -> Vector2:
	var x = size * (sqrt(3.0) * hex.x + sqrt(3.0) / 2.0 * hex.y)
	var y = size * (3.0 / 2.0 * hex.y)
	return Vector2(x, y)

## Convert pixel position to hex coordinates.
static func pixel_to_hex(pixel: Vector2, size: float) -> Vector2i:
	var q = (sqrt(3.0) / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / size
	var r = (2.0 / 3.0 * pixel.y) / size
	return _cube_round(q, -q - r, r)

## Get the 6 neighbors of a hex.
static func hex_neighbors(hex: Vector2i) -> Array:
	var directions = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	return directions.map(func(d: Vector2i) -> Vector2i: return hex + d)

## Get distance between two hexes.
static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2

## Get all hexes within a given radius.
static func hex_range(center: Vector2i, radius: int) -> Array:
	var results = []
	for dx in range(-radius, radius + 1):
		for dy in range(max(-radius, -dx - radius), min(radius, -dx + radius) + 1):
			results.append(center + Vector2i(dx, dy))
	return results

## Get a line of hexes between two points.
static func hex_line(a: Vector2i, b: Vector2i) -> Array:
	var dist = hex_distance(a, b)
	if dist == 0:
		return [a]
	var results = []
	for i in range(dist + 1):
		var t = float(i) / float(dist)
		var x = lerp(float(a.x), float(b.x), t)
		var y = lerp(float(a.y), float(b.y), t)
		var z = lerp(float(-a.x - a.y), float(-b.x - b.y), t)
		results.append(_cube_round(x, z, y))
	return results

## Convert cube coordinates to offset (odd-r).
static func _cube_to_offset(cube: Vector3) -> Vector2i:
	var col = int(cube.x + (cube.z - (int(cube.z) & 1)) / 2)
	var row = int(cube.z)
	return Vector2i(col, row)

## Round fractional cube coordinates to nearest hex.
static func _cube_round(x: float, z: float, y: float) -> Vector2i:
	var rx = round(x)
	var ry = round(y)
	var rz = round(z)
	var x_diff = abs(rx - x)
	var y_diff = abs(ry - y)
	var z_diff = abs(rz - z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return _cube_to_offset(Vector3(rx, ry, rz))

## Check if a hex is within bounds of a map.
static func hex_in_bounds(hex: Vector2i, map_size: Vector2i) -> bool:
	return hex.x >= 0 and hex.x < map_size.x and hex.y >= 0 and hex.y < map_size.y

## Convert offset to cube coordinates (for distance calculations).
static func offset_to_cube(hex: Vector2i) -> Vector3:
	var x = hex.x - (hex.y - (hex.y & 1)) / 2
	var z = hex.y
	var y = -x - z
	return Vector3(x, y, z)
