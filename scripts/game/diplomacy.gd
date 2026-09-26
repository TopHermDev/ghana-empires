## Diplomacy state and rules: relations, war, peace and trade agreements.
##
## State lives on GameManager (autoload) so it survives scene changes;
## this class owns the rules and the signals around it. game.gd injects
## the managers into the static references below so strength estimates
## can be made without an instance.
class_name Diplomacy

## Managers injected by game.gd (used for strength estimates).
static var unit_manager = null
static var city_manager = null

## Gold granted to both sides of an active trade agreement each turn.
const TRADE_INCOME: int = 4

## Relations drift toward neutral by this amount each turn.
const DECAY: int = 2

## Attitude thresholds (relation value -> label).
const ALLIED_AT: int = 60
const FRIENDLY_AT: int = 25
const UNFRIENDLY_AT: int = -25
const HOSTILE_AT: int = -55

## Historical starting attitudes, so rivalries exist from turn one.
## [faction_a, faction_b, relation]
const INITIAL_RIVALRIES = [
	[0, 2, -25],  # Ashanti vs Fante: coastal trade rivalry
	[1, 3, -20],  # Dagbon vs Mamprusi: northern rivalry
	[0, 1, -12],  # Ashanti vs Dagbon: uneasy border
	[0, 3, 8],    # Ashanti vs Mamprusi: cautious respect
	[2, 3, 6],    # Fante vs Mamprusi: trade partners
	[1, 2, 0],    # Dagbon vs Fante: little contact
]

## Reset all diplomacy state to neutral.
static func reset() -> void:
	GameManager.relations.clear()
	GameManager.wars.clear()
	GameManager.trades.clear()
	GameManager.war_turns.clear()

	for a in range(4):
		for b in range(a + 1, 4):
			GameManager.relations[_key(a, b)] = 0

	for pair in INITIAL_RIVALRIES:
		GameManager.relations[_key(pair[0], pair[1])] = pair[2]

## Canonical key for an unordered pair of factions.
static func _key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]

## Attitude between two factions (-100 .. 100).
static func get_relation(a: int, b: int) -> int:
	return int(GameManager.relations.get(_key(a, b), 0))

## Shift the attitude between two factions (clamped).
static func adjust_relation(a: int, b: int, delta: int) -> void:
	var key = _key(a, b)
	var value = clampi(get_relation(a, b) + delta, -100, 100)
	GameManager.relations[key] = value

## True when the two factions are at war.
static func is_at_war(a: int, b: int) -> bool:
	if a == b:
		return false
	return bool(GameManager.wars.get(_key(a, b), false))

## True when the two factions have an active trade agreement.
static func is_trading(a: int, b: int) -> bool:
	if a == b:
		return false
	return bool(GameManager.trades.get(_key(a, b), false))

## Turns the pair has been at war (0 when at peace).
static func war_turns(a: int, b: int) -> int:
	return int(GameManager.war_turns.get(_key(a, b), 0))

## --- ACTIONS ---------------------------------------------------------

## Start a war (unilateral).
static func declare_war(a: int, b: int) -> void:
	if a == b or is_at_war(a, b):
		return
	var key = _key(a, b)
	GameManager.wars[key] = true
	GameManager.war_turns[key] = 0
	GameManager.trades.erase(key)
	adjust_relation(a, b, -40)

	SignalBus.war_declared.emit(a, b)
	SignalBus.show_message.emit(
		GameManager.get_faction_name(a) + " declares war on " +
		GameManager.get_faction_name(b) + "!", "warning")
	print("War declared: ", a, " -> ", b)

## End a war between two factions.
static func make_peace(a: int, b: int) -> void:
	if not is_at_war(a, b):
		return
	var key = _key(a, b)
	GameManager.wars.erase(key)
	GameManager.war_turns.erase(key)
	adjust_relation(a, b, 25)

	SignalBus.peace_signed.emit(a, b)
	SignalBus.show_message.emit(
		GameManager.get_faction_name(a) + " and " +
		GameManager.get_faction_name(b) + " sign peace.", "info")
	print("Peace signed: ", a, " <-> ", b)

## Start a trade agreement (both sides gain income).
static func establish_trade(a: int, b: int) -> void:
	if a == b or is_trading(a, b) or is_at_war(a, b):
		return
	var key = _key(a, b)
	GameManager.trades[key] = true
	adjust_relation(a, b, 20)

	SignalBus.trade_established.emit(a, b)
	SignalBus.show_message.emit(
		"Trade agreement: " + GameManager.get_faction_name(a) + " and " +
		GameManager.get_faction_name(b) + ".", "info")
	print("Trade established: ", a, " <-> ", b)

## Dissolve a trade agreement.
static func end_trade(a: int, b: int) -> void:
	GameManager.trades.erase(_key(a, b))

## Propose something to another faction. Proposals aimed at the player are
## routed to the proposal dialog; AI-to-AI proposals are answered here.
static func propose(from: int, to: int, action: String) -> void:
	if from == to:
		return

	if to == GameManager.selected_faction:
		# Player decides through the dialog.
		SignalBus.diplomacy_proposal.emit(from, to, action)
		return

	var accepted = _ai_accepts(from, to, action)
	apply_proposal(from, to, action, accepted)

## Apply the outcome of a proposal (accepted or declined).
static func apply_proposal(from: int, to: int, action: String, accepted: bool) -> void:
	if not accepted:
		adjust_relation(to, from, -5)
		SignalBus.diplomacy_resolved.emit(from, to, action, false)
		return

	match action:
		"peace":
			make_peace(from, to)
		"trade":
			establish_trade(from, to)
		_:
			push_warning("Diplomacy: unknown proposal action " + action)
			return
	SignalBus.diplomacy_resolved.emit(from, to, action, true)

## Whether an AI faction accepts a peace or trade proposal.
static func _ai_accepts(from: int, to: int, action: String) -> bool:
	var relation = get_relation(to, from)

	match action:
		"peace":
			if not is_at_war(from, to):
				return false
			# Tired of war, or clearly losing.
			var war_weariness = war_turns(from, to) >= 5
			var losing = estimate_strength(to) < estimate_strength(from) * 0.7
			return war_weariness or losing or relation > -40
		"trade":
			if is_at_war(from, to):
				return false
			return relation > UNFRIENDLY_AT
	return false

## Rough power score: military units + cities + gold.
static func estimate_strength(faction_id: int) -> int:
	var score = 0
	if unit_manager:
		for unit in unit_manager.get_faction_units(faction_id):
			score += int(unit.unit_data.get("attack", 0)) + \
					int(unit.unit_data.get("defense", 0)) + 4
	if city_manager:
		score += city_manager.get_faction_cities(faction_id).size() * 12
	score += int(GameManager.get_gold(faction_id) / 25)
	return score

## --- TURN Processing -------------------------------------------------

## Called once per turn: war timers drift, relations decay, trade pays out.
static func process_turn() -> void:
	# Tick war durations
	for key in GameManager.war_turns.keys():
		GameManager.war_turns[key] = int(GameManager.war_turns[key]) + 1

	# Trade income for both sides of every agreement
	for key in GameManager.trades.keys():
		var parts = key.split("|")
		var a = int(parts[0])
		var b = int(parts[1])
		GameManager.add_gold(a, TRADE_INCOME)
		GameManager.add_gold(b, TRADE_INCOME)

	# Relations relax slowly back toward neutral
	for key in GameManager.relations.keys():
		var value = int(GameManager.relations[key])
		if value > 0:
			GameManager.relations[key] = max(0, value - DECAY)
		elif value < 0:
			GameManager.relations[key] = min(0, value + DECAY)

## A faction attacked someone: relations sour, war starts if needed.
static func on_attack(attacker: int, defender: int) -> void:
	adjust_relation(attacker, defender, -25)
	if not is_at_war(attacker, defender):
		declare_war(attacker, defender)

## Human-readable attitude between two factions.
static func attitude_label(a: int, b: int) -> String:
	if is_at_war(a, b):
		return "At War"
	var relation = get_relation(a, b)
	if relation >= ALLIED_AT:
		return "Allied"
	if relation >= FRIENDLY_AT:
		return "Friendly"
	if relation <= HOSTILE_AT:
		return "Hostile"
	if relation <= UNFRIENDLY_AT:
		return "Unfriendly"
	if is_trading(a, b):
		return "Trading"
	return "Neutral"
