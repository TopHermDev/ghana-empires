extends Node
## Diagnostic: watch what AI factions actually do turn by turn.

var gm = null
var sb = null
var game = null
var unit_manager = null
var city_manager = null
var hex_grid = null

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	gm = get_tree().root.get_node("GameManager")
	sb = get_tree().root.get_node("SignalBus")
	gm.new_game(0, Vector2i(60, 45))

	var scene = load("res://scenes/game/game.tscn")
	game = scene.instantiate()
	get_tree().root.add_child(game)
	hex_grid = game.get_node("HexGrid")
	unit_manager = game.get_node("UnitManager")
	city_manager = game.get_node("CityManager")

	for i in range(5):
		await get_tree().process_frame

	print("AI controllers: ", game.ai_controllers.keys())
	for f in game.ai_controllers:
		var ai = game.ai_controllers[f]
		print("  faction ", f, " difficulty=", ai.difficulty, " personality=", ai.personality)

	var start_positions = {}
	for u in unit_manager.units:
		start_positions[u.get_instance_id()] = [u.hex_position, u.faction_id, u.unit_data.get("name", "?")]

	for turn in range(8):
		var before = {}
		for u in unit_manager.units:
			before[u.get_instance_id()] = u.hex_position
		gm.next_turn()
		var waited = 0
		while gm.turn_processing and waited < 4000:
			await get_tree().process_frame
			waited += 1
		for j in range(20):
			await get_tree().process_frame

		var moved = 0
		var idle = []
		for u in unit_manager.units:
			if before.has(u.get_instance_id()) and before[u.get_instance_id()] != u.hex_position:
				moved += 1
			else:
				idle.append("%s(f%d,mv%d,acted%s)" % [
					u.unit_data.get("name", "?"), u.faction_id,
					u.movement_left, str(u.has_acted)])
		print("turn %d: moved=%d idle=%s" % [gm.current_turn, moved, str(idle)])

	print("FINAL positions of original units:")
	for u in unit_manager.units:
		var id = u.get_instance_id()
		if start_positions.has(id):
			print("  ", start_positions[id][2], " f", start_positions[id][1],
					": ", start_positions[id][0], " -> ", u.hex_position,
					" (moved=", start_positions[id][0] != u.hex_position, ")")
	print("units total: ", unit_manager.units.size())
	get_tree().quit(0)
