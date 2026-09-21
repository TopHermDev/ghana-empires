## Unit controller - represents a single unit on the map.
extends Node2D

## Unit data dictionary.
var unit_data: Dictionary = {}

## Current hex position.
var hex_position: Vector2i = Vector2i(0, 0)

## Current HP.
var hp: int = 100

## Maximum HP.
var max_hp: int = 100

## Movement points remaining this turn.
var movement_left: int = 2

## Maximum movement per turn.
var max_movement: int = 2

## Faction owner id.
var faction_id: int = 0

## Whether this unit has acted this turn.
var has_acted: bool = false

## Path to follow (array of hex positions).
var current_path: Array = []

## Animation state.
var is_moving: bool = false
var move_timer: float = 0.0
var move_speed: float = 0.1  # Seconds per hex

## Visual representation.
var hex_size: float = 32.0

## Initialize unit with data.
func setup(data: Dictionary, pos: Vector2i, faction: int, size: float) -> void:
	unit_data = data
	hex_position = pos
	faction_id = faction
	hex_size = size

	hp = data.get("hp", 100)
	max_hp = hp
	max_movement = data.get("movement", 2)
	movement_left = max_movement

	# Set position from hex
	position = HexUtils.hex_to_pixel(pos, size)

## Reset movement for new turn.
func reset_turn() -> void:
	movement_left = max_movement
	has_acted = false

## Check if unit can move to a hex.
func can_move_to(hex: Vector2i, map_data: Dictionary) -> bool:
	if movement_left <= 0:
		return false

	var terrain = map_data.get(hex, "grassland")
	var cost = UnitData.get_terrain_cost(terrain)
	return cost <= movement_left

## Get movement range (all hexes reachable this turn).
func get_movement_range(map_data: Dictionary) -> Array:
	var reachable = []
	var visited = {}
	var queue = [{"hex": hex_position, "cost": 0}]

	while queue.size() > 0:
		var current = queue.pop_front()
		var current_hex = current["hex"]
		var current_cost = current["cost"]

		if visited.has(current_hex):
			continue
		visited[current_hex] = true

		if current_cost > 0:
			reachable.append({"hex": current_hex, "cost": current_cost})

		# Check neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if not visited.has(neighbor):
				var terrain = map_data.get(neighbor, "grassland")
				var move_cost = UnitData.get_terrain_cost(terrain)
				var new_cost = current_cost + move_cost

				if new_cost <= movement_left:
					queue.append({"hex": neighbor, "cost": new_cost})

	return reachable

## Start moving along a path.
func move_along_path(path: Array) -> void:
	if path.size() == 0:
		return
	current_path = path
	is_moving = true
	move_timer = 0.0

## Process movement animation.
func _process(delta: float) -> void:
	if not is_moving or current_path.size() == 0:
		return

	move_timer += delta
	if move_timer >= move_speed:
		move_timer = 0.0
		var next_hex = current_path.pop_front()
		var new_pos = HexUtils.hex_to_pixel(next_hex, hex_size)

		# Calculate movement cost
		var terrain = "grassland"  # TODO: Get from map_data
		var cost = UnitData.get_terrain_cost(terrain)
		movement_left = max(0, movement_left - cost)

		# Emit signal
		SignalBus.unit_moved.emit(self, hex_position, next_hex)

		# Update position
		hex_position = next_hex
		position = new_pos

		# Check if path complete
		if current_path.size() == 0:
			is_moving = false

## Take damage.
func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	if hp <= 0:
		SignalBus.unit_destroyed.emit(self)
		queue_free()

## Heal unit.
func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)

## Get attack value.
func get_attack() -> int:
	return unit_data.get("attack", 0)

## Get defense value.
func get_defense() -> int:
	return unit_data.get("defense", 0)

## Get vision range.
func get_vision_range() -> int:
	if unit_data.get("special", "") == "extra_vision":
		return 3
	return 2

## Draw the unit.
func _draw() -> void:
	# Draw unit circle
	var color = _get_faction_color()
	draw_circle(Vector2.ZERO, hex_size * 0.4, color)
	draw_arc(Vector2.ZERO, hex_size * 0.4, 0, TAU, 32, color.darkened(0.3), 2.0)

	# Draw HP bar
	var bar_width = hex_size * 0.8
	var bar_height = 4.0
	var bar_y = -hex_size * 0.5
	var hp_ratio = float(hp) / float(max_hp)

	draw_rect(
		Vector2(-bar_width / 2, bar_y),
		Vector2(bar_width, bar_height),
		Color(0.2, 0.2, 0.2)
	)
	draw_rect(
		Vector2(-bar_width / 2, bar_y),
		Vector2(bar_width * hp_ratio, bar_height),
		Color(0.2, 0.8, 0.2) if hp_ratio > 0.5 else Color(0.8, 0.2, 0.2)
	)

	# Draw unit initial
	var initial = unit_data.get("name", "U")[0]
	# Note: In Godot 4, we'd use a Label node for text, but for simplicity
	# we'll just draw the colored circle for now

## Get color based on faction.
func _get_faction_color() -> Color:
	match faction_id:
		0: return Color(0.8, 0.65, 0.2)  # Ashanti - Gold
		1: return Color(0.6, 0.4, 0.2)   # Dagbon - Brown
		2: return Color(0.2, 0.5, 0.7)   # Fante - Blue
		3: return Color(0.5, 0.3, 0.6)   # Mamprusi - Purple
		_: return Color(0.5, 0.5, 0.5)   # Neutral - Gray
