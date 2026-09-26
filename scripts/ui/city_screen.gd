## City screen - shows city details and production options.
extends PanelContainer

var city_name_label: Label
var population_label: Label
var gold_label: Label
var production_label: Label
var production_bar: ColorRect
var production_bar_bg: ColorRect
var happiness_label: Label
var happiness_bar: ColorRect
var happiness_bar_bg: ColorRect
var buildings_label: Label
var owner_label: Label
var build_options_container: VBoxContainer
var close_button: Button

var current_city = null

## Available units to build (shown per faction).
var build_options: Array = []

## Set by game.gd so the panel knows which faction the player controls.
var player_faction: int = 0

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

	# Happiness
	happiness_label = Label.new()
	happiness_label.name = "Happiness"
	happiness_label.text = "Happiness: 60"
	vbox.add_child(happiness_label)

	happiness_bar_bg = ColorRect.new()
	happiness_bar_bg.name = "HappyBarBG"
	happiness_bar_bg.custom_minimum_size = Vector2(380, 6)
	happiness_bar_bg.color = Color(0.2, 0.2, 0.2)
	vbox.add_child(happiness_bar_bg)

	happiness_bar = ColorRect.new()
	happiness_bar.name = "HappyBar"
	happiness_bar.custom_minimum_size = Vector2(380, 6)
	happiness_bar.color = Color(0.2, 0.8, 0.3)
	vbox.add_child(happiness_bar)

	# Owner / status line
	owner_label = Label.new()
	owner_label.name = "Owner"
	owner_label.text = ""
	owner_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(owner_label)

	# Buildings already built
	buildings_label = Label.new()
	buildings_label.name = "Buildings"
	buildings_label.text = "Buildings: none"
	buildings_label.add_theme_font_size_override("font_size", 12)
	buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(buildings_label)

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
	population_label.text = "Population: %d / food %d" % [
		current_city.population, current_city.get_food()]
	gold_label.text = "Gold/turn: %d  (base %d + %d from resources)" % [
		current_city.get_income(), current_city.gold_per_turn, current_city.resource_gold]

	# Happiness
	var mood = current_city.get_happiness_label()
	happiness_label.text = "Happiness: %d (%s)" % [current_city.happiness, mood]
	happiness_bar.custom_minimum_size.x = 380.0 * float(current_city.happiness) / 100.0
	if current_city.happiness >= 50:
		happiness_bar.color = Color(0.2, 0.8, 0.3)
	elif current_city.happiness >= 30:
		happiness_bar.color = Color(0.9, 0.8, 0.2)
	else:
		happiness_bar.color = Color(0.9, 0.2, 0.2)

	# Owner
	var owned = current_city.faction_id == player_faction
	if owned:
		owner_label.text = "Your city"
		owner_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		owner_label.text = "Owned by " + GameManager.get_faction_name(current_city.faction_id)
		owner_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))

	# Buildings
	if current_city.buildings.is_empty():
		buildings_label.text = "Buildings: none"
	else:
		var names = current_city.buildings.map(func(b): return BuildingData.get_building_name(b))
		var extra = ""
		if not current_city.constructing.is_empty():
			extra = "  (+%s building)" % BuildingData.get_building_name(current_city.constructing)
		buildings_label.text = "Buildings: " + ", ".join(names) + extra

	# Work in progress
	if current_city.producing.is_empty() and current_city.constructing.is_empty():
		production_label.text = "Producing: Nothing"
		production_bar.custom_minimum_size.x = 0
	else:
		production_label.text = "Producing: " + current_city.get_work_description()
		var ratio = current_city.get_production_ratio()
		production_bar.custom_minimum_size.x = 380.0 * ratio

func _populate_build_options() -> void:
	# Clear existing options
	for child in build_options_container.get_children():
		child.queue_free()

	if not current_city:
		return

	# Only the owner may build; others get an info-only view.
	if current_city.faction_id != player_faction:
		build_options_container.add_child(_make_note(
			"You do not own this city."))
		return

	# Get faction name
	var faction_names = ["ashanti", "dagbon", "fante", "mamprusi"]
	var faction_name = "neutral"
	if current_city.faction_id < faction_names.size():
		faction_name = faction_names[current_city.faction_id]

	# Units
	build_options_container.add_child(_make_section_header("Units"))
	for key in UnitData.units:
		var unit = UnitData.units[key]
		var unit_faction = unit.get("faction", "neutral")
		if unit_faction == faction_name or unit_faction == "neutral":
			var btn = Button.new()
			btn.text = unit["name"] + " (Cost: " + str(unit["cost"]) + " gold)"
			btn.custom_minimum_size = Vector2(0, 30)
			btn.pressed.connect(_on_build_pressed.bind(key))
			build_options_container.add_child(btn)

	# Buildings
	build_options_container.add_child(_make_section_header("Buildings"))
	var any_building = false
	for key in BuildingData.ids():
		if current_city.has_building(key):
			continue
		any_building = true
		var building = BuildingData.get_building(key)
		var btn = Button.new()
		btn.text = "%s (%d gold) - %s" % [
			BuildingData.get_building_name(key),
			BuildingData.get_cost(key),
			_describe_effects(BuildingData.get_effects(key)),
		]
		btn.custom_minimum_size = Vector2(0, 30)
		btn.disabled = not current_city.constructing.is_empty()
		btn.pressed.connect(_on_construct_pressed.bind(key))
		build_options_container.add_child(btn)

	if not any_building:
		build_options_container.add_child(_make_note("All buildings constructed."))

	if not current_city.constructing.is_empty():
		build_options_container.add_child(_make_note(
			"Construction under way: " + BuildingData.get_building_name(current_city.constructing)))

func _make_section_header(text: String) -> Label:
	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 13)
	return header

func _make_note(text: String) -> Label:
	var note = Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return note

## Human readable effect summary, e.g. "+5 gold, +1 defense".
func _describe_effects(effects: Dictionary) -> String:
	var parts = []
	var labels = {
		"gold_per_turn": "gold/turn",
		"food": "food",
		"production_speed": "production",
		"defense": "defense",
		"happiness": "happiness",
	}
	for key in effects:
		parts.append("+%d %s" % [int(effects[key]), labels.get(key, key)])
	return ", ".join(parts) if parts.size() > 0 else "no effects"

## Start a building project (gold is paid up front, like units).
func _on_construct_pressed(building_id: String) -> void:
	if not current_city:
		return
	if not current_city.can_build(building_id):
		SignalBus.show_message.emit("Cannot build that here", "error")
		return

	var cost = BuildingData.get_cost(building_id)
	var faction_id = current_city.faction_id
	if GameManager.get_gold(faction_id) < cost:
		SignalBus.show_message.emit("Not enough gold!", "error")
		return

	GameManager.add_gold(faction_id, -cost)
	current_city.start_construction(building_id)
	_populate_build_options()
	_update_display()
	SignalBus.show_message.emit(
		"Building " + BuildingData.get_building_name(building_id) + "...", "info")

func _on_build_pressed(unit_id: String) -> void:
	if not current_city:
		return

	# Guard: don't silently restart production and lose progress.
	if not current_city.producing.is_empty():
		SignalBus.show_message.emit(
			"Already producing " + current_city.get_work_description(), "error")
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
