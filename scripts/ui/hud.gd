## HUD - top bar showing turn info, gold, and end turn button.
extends CanvasLayer

## Labels.
var turn_label: Label
var season_label: Label
var gold_label: Label
var faction_label: Label
var end_turn_button: Button
var message_label: Label
var ai_label: Label

func _ready() -> void:
	layer = 10
	_build_ui()
	_update_display()

	# Connect signals
	SignalBus.turn_started.connect(_on_turn_started)
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.show_message.connect(_on_show_message)
	SignalBus.ai_thinking.connect(_on_ai_thinking)
	SignalBus.city_captured.connect(func(_c, _o): _update_display())
	SignalBus.city_revolted.connect(func(_c, _o): _update_display())

func _build_ui() -> void:
	# Top bar panel
	var panel = PanelContainer.new()
	panel.name = "TopBar"
	add_child(panel)

	# Anchors: full width, top 40px
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 40)
	panel.offset_bottom = 40

	# Layout
	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)

	# Faction name
	faction_label = Label.new()
	faction_label.name = "FactionLabel"
	faction_label.text = "Ashanti"
	hbox.add_child(faction_label)

	# Separator
	var sep1 = VSeparator.new()
	hbox.add_child(sep1)

	# Turn counter
	turn_label = Label.new()
	turn_label.name = "TurnLabel"
	turn_label.text = "Turn: 1"
	hbox.add_child(turn_label)

	# Separator
	var sep2 = VSeparator.new()
	hbox.add_child(sep2)

	# Season
	season_label = Label.new()
	season_label.name = "SeasonLabel"
	season_label.text = "Dry Season"
	hbox.add_child(season_label)

	# Separator
	var sep3 = VSeparator.new()
	hbox.add_child(sep3)

	# Gold
	gold_label = Label.new()
	gold_label.name = "GoldLabel"
	gold_label.text = "Gold: 200 (+5/turn)"
	hbox.add_child(gold_label)

	# Spacer
	var spacer = Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# End Turn button
	end_turn_button = Button.new()
	end_turn_button.name = "EndTurnButton"
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(120, 30)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	hbox.add_child(end_turn_button)

	# Message label (bottom center, for notifications)
	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.offset_top = -80
	message_label.offset_bottom = -50
	message_label.offset_left = -200
	message_label.offset_right = 200
	message_label.horizontal_alignment = 1
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	message_label.visible = false
	add_child(message_label)

	# "AI thinking..." indicator (centred, above the message label)
	ai_label = Label.new()
	ai_label.name = "AILabel"
	ai_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ai_label.offset_top = 50
	ai_label.offset_bottom = 80
	ai_label.offset_left = -200
	ai_label.offset_right = 200
	ai_label.horizontal_alignment = 1
	ai_label.add_theme_font_size_override("font_size", 16)
	ai_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	ai_label.visible = false
	add_child(ai_label)

func _on_ai_thinking(active: bool, text: String) -> void:
	ai_label.text = text
	ai_label.visible = active
	# Block starting another turn while factions are still acting.
	end_turn_button.disabled = active
	if not active:
		_update_display()

func _update_display() -> void:
	if not turn_label:
		return

	turn_label.text = "Turn: " + str(GameManager.current_turn + 1)
	season_label.text = GameManager.get_season_name()

	# Color code season label
	match GameManager.current_season:
		0: season_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))  # Dry: gold
		1: season_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5))  # Harmattan: dusty
		2: season_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.9))  # Rainy: blue
		3: season_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.4))  # Early dry: green

	if GameManager.factions.size() > GameManager.selected_faction:
		var faction = GameManager.factions[GameManager.selected_faction]
		faction_label.text = faction["name"]
		var income = _get_faction_income()
		# Apply season modifier to displayed income
		var season_mod = GameManager.get_season_trade_modifier()
		var display_income = int(income * season_mod)
		gold_label.text = "Gold: " + str(faction["gold"]) + " (+" + str(display_income) + "/turn)"

func _get_faction_income() -> int:
	var income = 0
	var city_manager = get_node_or_null("/root/Game/CityManager")
	if city_manager:
		for city in city_manager.get_faction_cities(GameManager.selected_faction):
			income += city.get_income()
	return income

func _on_end_turn_pressed() -> void:
	if GameManager.turn_processing:
		return
	GameManager.next_turn()

func _on_turn_started(turn_number: int) -> void:
	_update_display()

func _on_game_started() -> void:
	_update_display()

func _on_show_message(text: String, type: String) -> void:
	message_label.text = text
	message_label.visible = true
	# Auto-hide after 2 seconds
	get_tree().create_timer(2.0).timeout.connect(func(): message_label.visible = false)
