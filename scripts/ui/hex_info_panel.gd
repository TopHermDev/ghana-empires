## Hex info panel - shows terrain, movement cost and resources for the
## hovered hex, bottom-right corner. Reads fog state so unexplored hexes
## reveal nothing.
extends PanelContainer

var title_label: Label
var terrain_label: Label
var stats_label: Label
var resource_label: Label
var details_label: Label
var occupant_label: Label

var hex_grid = null
var unit_manager = null
var city_manager = null

var last_hex: Vector2i = Vector2i(-1, -1)

func setup(grid, units, cities) -> void:
	hex_grid = grid
	unit_manager = units
	city_manager = cities

func _ready() -> void:
	_build_ui()
	hide()
	SignalBus.hex_hovered.connect(_on_hex_hovered)

func _build_ui() -> void:
	# Position: bottom-right, clear of the unit panel on the left.
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_right = -10
	offset_bottom = -10
	offset_left = -250
	offset_top = -175
	custom_minimum_size = Vector2(240, 165)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 3)
	add_child(vbox)

	title_label = _make_label(vbox, "Hex", 15)
	terrain_label = _make_label(vbox, "Terrain", 13)
	stats_label = _make_label(vbox, "", 12)
	resource_label = _make_label(vbox, "", 12)
	occupant_label = _make_label(vbox, "", 12)
	details_label = _make_label(vbox, "", 11)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_label(parent: Node, text: String, size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _on_hex_hovered(hex: Vector2i) -> void:
	show_hex(hex)

## Display everything known about a hex.
func show_hex(hex: Vector2i) -> void:
	if hex_grid == null:
		return
	last_hex = hex
	var info = hex_grid.get_hex_info(hex)

	if not info["in_bounds"]:
		hide()
		return

	show()
	title_label.text = "Hex (%d, %d)" % [hex.x, hex.y]

	if not info["explored"]:
		terrain_label.text = "Unexplored"
		terrain_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		stats_label.text = ""
		resource_label.text = ""
		occupant_label.text = ""
		details_label.text = "Send a unit to reveal this hex."
		return

	terrain_label.remove_theme_color_override("font_color")
	terrain_label.text = str(info["name"])
	stats_label.text = "Move cost: %d    Defense: +%d" % [info["move_cost"], info["defense"]]

	var resource = info["resource"]
	if resource.size() > 0:
		resource_label.text = "%s  (+%d gold, +%d food)" % [
			resource["name"], resource["gold"], resource["food"]]
		resource_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	else:
		resource_label.text = "No resource"
		resource_label.remove_theme_color_override("font_color")

	# Occupants are only shown while the hex is currently visible.
	occupant_label.text = ""
	if info["visible"] and unit_manager and city_manager:
		var parts = []
		var city = city_manager.get_city_at(hex)
		if city:
			parts.append(GameManager.get_faction_name(city.faction_id) + " city")
		var units = unit_manager.get_units_at(hex)
		if units.size() > 0:
			parts.append(str(units.size()) + " unit(s)")
		occupant_label.text = ", ".join(parts) if parts.size() > 0 else "Empty"

	details_label.text = str(info["description"])
