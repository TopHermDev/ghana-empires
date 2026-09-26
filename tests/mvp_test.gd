extends SceneTree
##
## MVP acceptance test entry point for GhanaEmpires (roadmap Phases 0-5).
##
## Run:  godot --headless --path . --script res://tests/mvp_test.gd
##
## This script is compiled before the engine registers autoloads, so it must
## not reference GameManager, SignalBus or any class_name script directly -
## those identifiers do not exist yet at compile time. The actual test lives
## in tests/mvp_case.gd and is loaded at runtime, after autoloads exist.
##
## Exit codes: 0 = pass, 1 = test failures, 2 = watchdog timeout,
##             3 = test case failed to load.
##

## Seconds before the watchdog assumes the test hung and gives up.
const WATCHDOG_SECONDS: float = 180.0

func _initialize() -> void:
	print("MVP test entry: loading case...")
	var case_script = load("res://tests/mvp_case.gd")
	if case_script == null:
		print("TEST FAIL - could not load tests/mvp_case.gd")
		quit(3)
		return

	var case = case_script.new()
	root.add_child(case)

	# If the test coroutine dies (script error) or hangs, do not wait forever.
	create_timer(WATCHDOG_SECONDS).timeout.connect(func():
		if not case.finished:
			print("TEST FAIL - watchdog timeout after ", WATCHDOG_SECONDS, "s")
			quit(2)
	)
