## Dialog for incoming diplomacy proposals (peace and trade offers).
## Proposals are queued so nothing is lost while one is on screen.
extends PanelContainer

var message_label: Label
var accept_button: Button
var decline_button: Button

## Queued proposals: [{from, to, action}]
var queue: Array = []
var current = null

func _ready() -> void:
	_build_ui()
	hide()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -220
	offset_top = -90
	offset_right = 220
	offset_bottom = 90
	custom_minimum_size = Vector2(440, 180)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var header = Label.new()
	header.name = "Header"
	header.text = "Diplomatic Proposal"
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	message_label = Label.new()
	message_label.name = "Message"
	message_label.text = ""
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message_label)

	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)

	accept_button = Button.new()
	accept_button.name = "AcceptButton"
	accept_button.text = "Accept"
	accept_button.custom_minimum_size = Vector2(140, 34)
	accept_button.pressed.connect(_on_accept)
	buttons.add_child(accept_button)

	decline_button = Button.new()
	decline_button.name = "DeclineButton"
	decline_button.text = "Decline"
	decline_button.custom_minimum_size = Vector2(140, 34)
	decline_button.pressed.connect(_on_decline)
	buttons.add_child(decline_button)

## Add a proposal to the queue and show it if nothing is on screen.
func queue_proposal(from_faction: int, to_faction: int, action: String) -> void:
	queue.append({"from": from_faction, "to": to_faction, "action": action})
	if current == null:
		_show_next()

func _show_next() -> void:
	if queue.is_empty():
		current = null
		hide()
		return

	current = queue.pop_front()
	var proposer = GameManager.get_faction_name(current["from"])
	var text: String
	match current["action"]:
		"peace":
			text = "%s proposes a peace treaty. Accept?" % proposer
		"trade":
			text = "%s proposes a trade agreement (+%d gold/turn to both). Accept?" % [
				proposer, Diplomacy.TRADE_INCOME]
		_:
			text = "%s proposes: %s. Accept?" % [proposer, current["action"]]

	message_label.text = text
	show()

func _on_accept() -> void:
	if current:
		Diplomacy.apply_proposal(current["from"], current["to"], current["action"], true)
	current = null
	_show_next()

func _on_decline() -> void:
	if current:
		Diplomacy.apply_proposal(current["from"], current["to"], current["action"], false)
	current = null
	_show_next()
