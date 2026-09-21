## A* pathfinding for hex grids.
class_name HexPathfinder

## Find path from start to goal using A*.
## Returns array of hex positions, or empty array if no path found.
static func find_path(start: Vector2i, goal: Vector2i, map_data: Dictionary, max_cost: int = 999) -> Array:
	# Priority queue: [{hex, f, g}]
	var open = []
	var closed = {}
	var came_from = {}
	var g_score = {}

	# Initialize start node
	g_score[start] = 0
	var h = _heuristic(start, goal)
	open.append({"hex": start, "f": h, "g": 0})

	while open.size() > 0:
		# Find node with lowest f score
		open.sort_custom(func(a, b): return a["f"] < b["f"])
		var current = open.pop_front()
		var current_hex = current["hex"]

		# Check if we reached the goal
		if current_hex == goal:
			return _reconstruct_path(came_from, current_hex)

		# Skip if already processed
		if closed.has(current_hex):
			continue
		closed[current_hex] = true

		# Explore neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if closed.has(neighbor):
				continue

			# Check terrain cost
			var terrain = map_data.get(neighbor, "grassland")
			var move_cost = UnitData.get_terrain_cost(terrain)
			var tentative_g = g_score[current_hex] + move_cost

			# Skip if exceeds max cost
			if tentative_g > max_cost:
				continue

			# Skip if already found a better path
			if g_score.has(neighbor) and tentative_g >= g_score[neighbor]:
				continue

			# This is the best path so far
			came_from[neighbor] = current_hex
			g_score[neighbor] = tentative_g
			var f = tentative_g + _heuristic(neighbor, goal)

			# Add to open list
			open.append({"hex": neighbor, "f": f, "g": tentative_g})

	# No path found
	return []

## Heuristic: hex distance (admissible for A*).
static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return HexUtils.hex_distance(a, b)

## Reconstruct path from came_from map.
static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var path = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path

## Check if a path exists between two hexes.
static func has_path(start: Vector2i, goal: Vector2i, map_data: Dictionary, max_cost: int = 999) -> bool:
	return find_path(start, goal, map_data, max_cost).size() > 0

## Get all reachable hexes from a start position within a cost limit.
## Returns dictionary of {hex: cost}.
static func get_reachable(start: Vector2i, map_data: Dictionary, max_cost: int) -> Dictionary:
	var reachable = {}
	var open = [{"hex": start, "cost": 0}]
	var visited = {}

	while open.size() > 0:
		var current = open.pop_front()
		var current_hex = current["hex"]
		var current_cost = current["cost"]

		if visited.has(current_hex):
			continue
		visited[current_hex] = true

		if current_cost > 0:
			reachable[current_hex] = current_cost

		# Explore neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if not visited.has(neighbor):
				var terrain = map_data.get(neighbor, "grassland")
				var move_cost = UnitData.get_terrain_cost(terrain)
				var new_cost = current_cost + move_cost

				if new_cost <= max_cost:
					open.append({"hex": neighbor, "cost": new_cost})

	return reachable

## Get path cost (total movement cost).
static func get_path_cost(path: Array, map_data: Dictionary) -> int:
	var cost = 0
	for i in range(path.size()):
		if i > 0:
			var terrain = map_data.get(path[i], "grassland")
			cost += UnitData.get_terrain_cost(terrain)
	return cost
