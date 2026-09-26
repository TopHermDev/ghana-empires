## A* pathfinding for hex grids.
class_name HexPathfinder

## Find path from start to goal using A*.
## Returns array of hex positions, or empty array if no path found.
## zoc: hexes entered at the cost of all remaining movement (zone of control).
## blocked: hexes that may not be entered at all (occupied, over-stacked).
static func find_path(start: Vector2i, goal: Vector2i, map_data: Dictionary,
		max_cost: int = 999, zoc: Dictionary = {}, blocked: Dictionary = {}) -> Array:
	# Priority queue: binary min-heap on f: [{hex, f, g}]
	var open = []
	var closed = {}
	var came_from = {}
	var g_score = {}

	var debug = OS.get_environment("GE_PF_DEBUG") != ""
	var expanded = 0
	var pushes = 0
	var max_open = 0

	# Initialize start node
	g_score[start] = 0
	_heap_push(open, {"hex": start, "f": _heuristic(start, goal), "g": 0})

	while open.size() > 0:
		# Node with the lowest f score (heap pop, not a full re-sort: a
		# sort per pop is O(n^2 log n) and freezes on whole-map searches).
		var current = _heap_pop(open)
		var current_hex = current["hex"]

		# Check if we reached the goal
		if current_hex == goal:
			if debug:
				print("PF found h0=", _heuristic(start, goal), " expanded=", expanded,
						" pushes=", pushes, " max_open=", max_open)
			return _reconstruct_path(came_from, current_hex)

		# Skip processed nodes and stale heap entries
		if closed.has(current_hex):
			continue
		if not g_score.has(current_hex) or current["g"] > g_score[current_hex]:
			continue
		closed[current_hex] = true
		expanded += 1
		max_open = max(max_open, open.size())

		# Explore neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if closed.has(neighbor):
				continue
			if blocked.has(neighbor):
				continue
			# Stay on the map: hexes outside map_data are not real, but
			# .get() would default them to grassland and A* would wander
			# across an infinite plain.
			if not map_data.has(neighbor):
				continue

			# Check terrain cost
			var terrain = map_data.get(neighbor, "grassland")
			var move_cost = UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()

			# The step must be affordable from where we stand.
			if move_cost > max_cost - g_score[current_hex]:
				continue

			var tentative_g = g_score[current_hex] + move_cost

			# Zone of control: stepping in burns every remaining movement
			# point, so nothing beyond that hex can be reached this turn.
			if zoc.has(neighbor):
				tentative_g = max_cost

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

			_heap_push(open, {"hex": neighbor, "f": f, "g": tentative_g})
			pushes += 1

	if debug:
		print("PF NO-PATH expanded=", expanded, " pushes=", pushes, " max_open=", max_open)

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
static func get_reachable(start: Vector2i, map_data: Dictionary, max_cost: int,
		zoc: Dictionary = {}, blocked: Dictionary = {}) -> Dictionary:
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

		if current_cost >= max_cost:
			continue

		# Explore neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if not visited.has(neighbor) and not blocked.has(neighbor) and map_data.has(neighbor):
				var terrain = map_data.get(neighbor, "grassland")
				var move_cost = UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()
				# The step must be affordable from where we stand.
				if move_cost > max_cost - current_cost:
					continue
				var new_cost = current_cost + move_cost
				# Zone of control burns all remaining movement on entry.
				if zoc.has(neighbor):
					new_cost = max_cost

				if new_cost <= max_cost:
					open.append({"hex": neighbor, "cost": new_cost})

	return reachable

## Get path cost (total movement cost).
static func get_path_cost(path: Array, map_data: Dictionary) -> int:
	var cost = 0
	for i in range(path.size()):
		if i > 0:
			var terrain = map_data.get(path[i], "grassland")
			cost += UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()
	return cost

## --- binary min-heap on "f" ------------------------------------------

## Push a {hex, f, g} item onto the heap.
static func _heap_push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var i = heap.size() - 1
	while i > 0:
		var parent = (i - 1) / 2
		if heap[parent]["f"] <= heap[i]["f"]:
			break
		var tmp = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent

## Pop the lowest-f item off the heap.
static func _heap_pop(heap: Array) -> Dictionary:
	var top = heap[0]
	var last = heap.pop_back()
	if heap.size() == 0:
		return top

	heap[0] = last
	var i = 0
	while true:
		var left = 2 * i + 1
		var right = 2 * i + 2
		var smallest = i
		if left < heap.size() and heap[left]["f"] < heap[smallest]["f"]:
			smallest = left
		if right < heap.size() and heap[right]["f"] < heap[smallest]["f"]:
			smallest = right
		if smallest == i:
			break
		var tmp = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return top
