## Signal bus for game events. Autoload singleton.
extends Node

## Game flow signals.
signal game_started
signal game_over(winner_id: int)
signal turn_started(turn_number: int)
signal turn_ended(turn_number: int)
signal phase_changed(phase: String)

## Unit signals.
signal unit_moved(unit, from_hex: Vector2i, to_hex: Vector2i)
signal unit_arrived(unit)
signal unit_attacked(attacker, defender, damage: int)
signal unit_destroyed(unit)
signal unit_selected(unit)
signal unit_deselected

## City signals.
signal city_captured(city, new_owner: int)
signal city_production_complete(city, item: String)
signal city_population_changed(city, old_pop: int, new_pop: int)
signal city_selected(city)
signal city_deselected

## Map signals.
signal hex_clicked(hex: Vector2i)
signal hex_hovered(hex: Vector2i)
signal hex_unhovered
signal hex_right_clicked(hex: Vector2i)

## AI thinking / turn processing status (shown while AI factions act).
signal ai_thinking(active: bool, text: String)

## Diplomacy signals.
signal diplomacy_proposal(from_faction: int, to_faction: int, action: String)
signal diplomacy_resolved(from_faction: int, to_faction: int, action: String, accepted: bool)
signal war_declared(attacker: int, defender: int)
signal peace_signed(faction_a: int, faction_b: int)
signal trade_established(faction_a: int, faction_b: int)

## City revolt (city changed owner because of low happiness).
signal city_revolted(city, new_owner: int)

## UI signals.
signal ui_update_requested
signal show_message(text: String, type: String)
