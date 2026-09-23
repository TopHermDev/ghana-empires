## Unit info panel - shows selected unit details in bottom-left corner.
extends PanelContainer

var unit_name_label: Label
var hp_label: Label
var hp_bar: ColorRect
var hp_bar_bg: ColorRect
var attack_label: Label
var defense_label: Label
var movement_label: Label
var status_label: Label

var current_unit = null

func _ready() -> void:
	_build_ui()
	hide()

	# Connect signals
	SignalBus.unit_selected.connect(_on_unit_selected)
	SignalBus.unit_deselected.connect(_on_unit_deselected)

func _build_ui() -> void:
	# Position: bottom-left
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 10
	offset_bottom = -10
	offset_top = -160
	offset_right = 220
	custom_minimum_size = Vector2(210, 150)

	# Main container
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Unit name
	unit_name_label = Label.new()
	unit_name_label.name = "UnitName"
	unit_name_label.text = "Unit Name"
	vbox.add_child(unit_name_label)

	# HP bar background
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.name = "HPBarBG"
	hp_bar_bg.custom_minimum_size = Vector2(200, 8)
	hp_bar_bg.color = Color(0.2, 0.2, 0.2)
	vbox.add_child(hp_bar_bg)

	# HP bar fill
	hp_bar = ColorRect.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(200, 8)
	hp_bar.color = Color(0.2, 0.8, 0.2)
	vbox.add_child(hp_bar)

	# HP label
	hp_label = Label.new()
	hp_label.name = "HP"
	hp_label.text = "HP: 100/100"
	hp_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hp_label)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Attack
	attack_label = Label.new()
	attack_label.name = "Attack"
	attack_label.text = "Attack: 8"
	attack_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(attack_label)

	# Defense
	defense_label = Label.new()
	defense_label.name = "Defense"
	defense_label.text = "Defense: 6"
	defense_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(defense_label)

	# Movement
	movement_label = Label.new()
	movement_label.name = "Movement"
	movement_label.text = "Movement: 2/2"
	movement_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(movement_label)

	# Status
	status_label = Label.new()
	status_label.name = "Status"
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(status_label)

func _on_unit_selected(unit) -> void:
	current_unit = unit
	_update_display()
	show()

func _on_unit_deselected() -> void:
	current_unit = null
	hide()

func _update_display() -> void:
	if not current_unit:
		return

	unit_name_label.text = current_unit.unit_data.get("name", "Unknown Unit")

	var hp = current_unit.hp
	var max_hp = current_unit.max_hp
	hp_label.text = "HP: " + str(hp) + "/" + str(max_hp)

	# Update HP bar
	var ratio = float(hp) / float(max_hp)
	hp_bar.custom_minimum_size.x = 200.0 * ratio
	if ratio > 0.5:
		hp_bar.color = Color(0.2, 0.8, 0.2)
	elif ratio > 0.25:
		hp_bar.color = Color(0.8, 0.8, 0.2)
	else:
		hp_bar.color = Color(0.8, 0.2, 0.2)

	attack_label.text = "Attack: " + str(current_unit.get_attack())
	defense_label.text = "Defense: " + str(current_unit.get_defense())
	movement_label.text = "Movement: " + str(current_unit.movement_left) + "/" + str(current_unit.max_movement)

	if current_unit.has_acted:
		status_label.text = "Acted this turn"
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif current_unit.is_moving:
		status_label.text = "Moving..."
		status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
	else:
		status_label.text = "Ready"
		status_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))

func _process(_delta: float) -> void:
	# Live-update HP display if unit is taking damage
	if current_unit and is_visible():
		_update_display()
