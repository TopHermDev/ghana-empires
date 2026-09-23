## City screen - shows city details and production options.
extends PanelContainer

var city_name_label: Label
var population_label: Label
var gold_label: Label
var production_label: Label
var production_bar: ColorRect
var production_bar_bg: ColorRect
var build_options_container: VBoxContainer
var close_button: Button

var current_city = null

## Available units to build (shown per faction).
var build_options: Array = []

func _ready() -> void:
	_build_ui()
	hide()

	# Connect signals
	SignalBus.city_selected.connect(_on_city_selected)

func _build_ui() -> void:
	# Position: center of screen
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -200
	offset_top = -180
	offset_right = 200
	offset_bottom = 180
	custom_minimum_size = Vector2(400, 360)

	# Main container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Header row with close button
	var header = HBoxContainer.new()
	vbox.add_child(header)

	city_name_label = Label.new()
	city_name_label.name = "CityName"
	city_name_label.text = "City Name"
	city_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(city_name_label)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Population
	population_label = Label.new()
	population_label.name = "Population"
	population_label.text = "Population: 1"
	vbox.add_child(population_label)

	# Gold income
	gold_label = Label.new()
	gold_label.name = "GoldIncome"
	gold_label.text = "Gold/turn: 5"
	vbox.add_child(gold_label)

	# Current production
	production_label = Label.new()
	production_label.name = "Production"
	production_label.text = "Producing: Nothing"
	vbox.add_child(production_label)

	# Production bar background
	production_bar_bg = ColorRect.new()
	production_bar_bg.name = "ProdBarBG"
	production_bar_bg.custom_minimum_size = Vector2(380, 8)
	production_bar_bg.color = Color(0.2, 0.2, 0.2)
	vbox.add_child(production_bar_bg)

	# Production bar fill
	production_bar = ColorRect.new()
	production_bar.name = "ProdBar"
	production_bar.custom_minimum_size = Vector2(0, 8)
	production_bar.color = Color(0.8, 0.6, 0.1)
	vbox.add_child(production_bar)

	# Separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Build options header
	var build_header = Label.new()
	build_header.text = "Build:"
	build_header.add_theme_font_size_override("font_size", 13)
	vbox.add_child(build_header)

	# Build options container (scrollable)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	build_options_container = VBoxContainer.new()
	build_options_container.name = "BuildOptions"
	build_options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(build_options_container)

func _on_city_selected(city) -> void:
	current_city = city
	_populate_build_options()
	_update_display()
	show()

func _update_display() -> void:
	if not current_city:
		return

	city_name_label.text = current_city.city_data.get("name", "Unknown City")
	population_label.text = "Population: " + str(current_city.population)
	gold_label.text = "Gold/turn: " + str(current_city.gold_per_turn)

	if current_city.producing.is_empty():
		production_label.text = "Producing: Nothing"
		production_bar.custom_minimum_size.x = 0
	else:
		var unit_info = UnitData.get_unit(current_city.producing)
		var name = unit_info.get("name", current_city.producing)
		var turns = current_city.production_turns_left
		production_label.text = "Producing: " + name + " (" + str(turns) + " turns)"
		var ratio = current_city.get_production_ratio()
		production_bar.custom_minimum_size.x = 380.0 * ratio

func _populate_build_options() -> void:
	# Clear existing options
	for child in build_options_container.get_children():
		child.queue_free()

	if not current_city:
		return

	# Get faction name
	var faction_names = ["ashanti", "dagbon", "fante", "mamprusi"]
	var faction_name = "neutral"
	if current_city.faction_id < faction_names.size():
		faction_name = faction_names[current_city.faction_id]

	# Get available units for this faction + neutral
	for key in UnitData.units:
		var unit = UnitData.units[key]
		var unit_faction = unit.get("faction", "neutral")
		if unit_faction == faction_name or unit_faction == "neutral":
			var btn = Button.new()
			btn.text = unit["name"] + " (Cost: " + str(unit["cost"]) + " gold)"
			btn.custom_minimum_size = Vector2(0, 30)
			btn.pressed.connect(_on_build_pressed.bind(key))
			build_options_container.add_child(btn)

func _on_build_pressed(unit_id: String) -> void:
	if not current_city:
		return

	# Check if we have enough gold
	var unit_info = UnitData.get_unit(unit_id)
	var cost = unit_info.get("cost", 40)
	if GameManager.factions.size() > current_city.faction_id:
		var gold = GameManager.factions[current_city.faction_id].get("gold", 0)
		if gold < cost:
			SignalBus.show_message.emit("Not enough gold!", "error")
			return

	# Deduct gold
	GameManager.factions[current_city.faction_id]["gold"] -= cost

	# Start production
	current_city.start_production(unit_id)
	_update_display()

func _on_close_pressed() -> void:
	hide()
	current_city = null
	SignalBus.city_deselected.emit()
