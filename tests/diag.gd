extends SceneTree
## Thin entry for tests/diag_case.gd (see mvp_test.gd for why).

func _initialize() -> void:
	var case_script = load("res://tests/diag_case.gd")
	if case_script == null:
		print("could not load diag_case")
		quit(3)
		return
	root.add_child(case_script.new())
	create_timer(120.0).timeout.connect(func(): print("diag timeout"); quit(2))
