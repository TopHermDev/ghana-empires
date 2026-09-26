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

## Reference to map_data dictionary (set by UnitManager after spawn).
var map_data: Dictionary = {}

## How many units share this unit's hex (refreshed by UnitManager).
var stack_size: int = 1

## Whether this unit is the one drawing the stack badge.
var is_stack_leader: bool = true

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

## Check if unit can traverse this terrain type.
func can_traverse_terrain(terrain: String) -> bool:
	if TerrainData.is_water(terrain):
		var special = unit_data.get("special", "")
		return special == "amphibious" or special == "naval"
	return true

## Check if unit can move to a hex.
## zoc: hexes exerted by enemy units (entering costs all remaining movement).
## blocked: hexes that may not be entered at all (occupied, over-stacked).
func can_move_to(hex: Vector2i, map_data: Dictionary, zoc: Dictionary = {}, blocked: Dictionary = {}) -> bool:
	if movement_left <= 0:
		return false
	if blocked.has(hex):
		return false

	var terrain = map_data.get(hex, "grassland")
	if not can_traverse_terrain(terrain):
		return false

	# The hex must at least be affordable; a zone of control hex then
	# consumes the whole remaining budget once entered.
	return _base_move_cost(terrain) <= movement_left

## Terrain movement cost including the current season modifier.
func _base_move_cost(terrain: String) -> int:
	return UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()

## Get movement range (all hexes reachable this turn).
func get_movement_range(map_data: Dictionary, zoc: Dictionary = {}, blocked: Dictionary = {}) -> Array:
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

		# A hex entered from a zone of control exhausts all movement,
		# so nothing can be reached beyond it this turn.
		if current_cost >= movement_left:
			continue

		# Check neighbors
		var neighbors = HexUtils.hex_neighbors(current_hex)
		for neighbor in neighbors:
			if visited.has(neighbor) or blocked.has(neighbor):
				continue
			var terrain = map_data.get(neighbor, "grassland")
			if not can_traverse_terrain(terrain):
				continue

			var base_cost = _base_move_cost(terrain)
			# Must be able to afford the step from where we stand.
			if base_cost > movement_left - current_cost:
				continue

			# Stepping into a zone of control burns every remaining point,
			# so the total cost of reaching that hex is the whole budget.
			var new_cost = movement_left if zoc.has(neighbor) else current_cost + base_cost

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

		# Calculate movement cost from actual terrain
		var terrain = map_data.get(next_hex, "grassland")
		var cost = UnitData.get_terrain_cost(terrain) + GameManager.get_season_movement_modifier()
		movement_left = max(0, movement_left - cost)

		# Emit signal
		SignalBus.unit_moved.emit(self, hex_position, next_hex)

		# Update position
		hex_position = next_hex
		position = new_pos

		# Check if path complete
		if current_path.size() == 0:
			is_moving = false
			SignalBus.unit_arrived.emit(self)

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

## Get defense value (including terrain and city bonuses when defending).
func get_defense() -> int:
	return unit_data.get("defense", 0)

## Terrain defense bonus for the hex this unit occupies.
func get_terrain_defense_bonus() -> int:
	return TerrainData.get_defense(map_data.get(hex_position, "grassland"))

## Get vision range.
func get_vision_range() -> int:
	if unit_data.get("special", "") == "extra_vision":
		return 3
	return 2

## --- RENDERING -------------------------------------------------------

## Draw the unit: a faction-specific silhouette, unit glyph and HP bar.
func _draw() -> void:
	var color = _get_faction_color()
	var outline = color.darkened(0.4)

	_draw_faction_shape(color, outline)

	# Unit glyph (first letter of the unit name)
	var font = ThemeDB.fallback_font
	var unit_name: String = unit_data.get("name", "Unit")
	var glyph = unit_name.substr(0, 1)
	var font_size = int(hex_size * 0.55)
	var text_width = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(font, Vector2(-text_width / 2.0, font_size * 0.35), glyph,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, _get_glyph_color())

	# Draw HP bar
	var bar_width = hex_size * 0.8
	var bar_height = 4.0
	var bar_y = -hex_size * 0.5
	var hp_ratio = float(hp) / float(max_hp)

	draw_rect(
		Rect2(Vector2(-bar_width / 2, bar_y), Vector2(bar_width, bar_height)),
		Color(0.2, 0.2, 0.2)
	)
	var hp_color = Color(0.2, 0.8, 0.2) if hp_ratio > 0.5 else Color(0.8, 0.2, 0.2)
	draw_rect(
		Rect2(Vector2(-bar_width / 2, bar_y), Vector2(bar_width * hp_ratio, bar_height)),
		hp_color
	)

	# Stack badge: only the leader of the stack draws it.
	if stack_size > 1 and is_stack_leader:
		var badge_pos = Vector2(hex_size * 0.45, hex_size * 0.45)
		draw_circle(badge_pos, 8.0, Color(0, 0, 0, 0.75))
		var count = str(stack_size)
		var count_width = font.get_string_size(count, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
		draw_string(font, badge_pos + Vector2(-count_width / 2.0, 4.0), count,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

## Silhouette differs per faction so stacks and sides read at a glance.
func _draw_faction_shape(color: Color, outline: Color) -> void:
	var r = hex_size * 0.4
	match faction_id:
		0:  # Ashanti - circle
			draw_circle(Vector2.ZERO, r, color)
			draw_arc(Vector2.ZERO, r, 0, TAU, 32, outline, 2.0)
		1:  # Dagbon - diamond
			var pts = PackedVector2Array([
				Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)
			])
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 2.0)
		2:  # Fante - triangle
			var pts = PackedVector2Array([
				Vector2(0, -r), Vector2(r * 0.9, r * 0.75), Vector2(-r * 0.9, r * 0.75)
			])
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 2.0)
		3:  # Mamprusi - hexagon
			var pts = PackedVector2Array()
			for i in range(6):
				var angle = PI / 3 * i - PI / 2
				pts.append(Vector2(cos(angle), sin(angle)) * r)
			draw_colored_polygon(pts, color)
			draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 2.0)
		_:  # Rebels / neutral - square
			var rect = Rect2(Vector2(-r, -r), Vector2(r * 2, r * 2))
			draw_rect(rect, color)
			draw_rect(rect, outline, false, 2.0)

## Glyph colour that stays readable on the faction colour.
func _get_glyph_color() -> Color:
	match faction_id:
		0: return Color(0.15, 0.1, 0.0)   # on gold
		1: return Color(0.95, 0.92, 0.85) # on brown
		2: return Color(0.95, 0.97, 1.0)  # on blue
		3: return Color(0.95, 0.92, 1.0)  # on purple
		_: return Color(0.1, 0.1, 0.1)

## Get color based on faction.
func _get_faction_color() -> Color:
	match faction_id:
		0: return Color(0.8, 0.65, 0.2)  # Ashanti - Gold
		1: return Color(0.6, 0.4, 0.2)   # Dagbon - Brown
		2: return Color(0.2, 0.5, 0.7)   # Fante - Blue
		3: return Color(0.5, 0.3, 0.6)   # Mamprusi - Purple
		_: return Color(0.5, 0.5, 0.5)   # Rebels - Gray
