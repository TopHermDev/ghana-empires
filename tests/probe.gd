extends SceneTree

## Loads every script in the project and reports parse failures.
func _initialize() -> void:
	var failures = 0
	var total = 0
	var stack = ["res://"]
	var files = []

	while stack.size() > 0:
		var dir_path = stack.pop_back()
		var dir = DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = dir.get_next()
				continue
			var full = dir_path.path_join(entry)
			if dir.current_is_dir():
				stack.append(full)
			elif entry.ends_with(".gd"):
				files.append(full)
			entry = dir.get_next()
		dir.list_dir_end()

	files.sort()
	for path in files:
		total += 1
		var script = load(path)
		if script == null:
			print("PARSE FAIL: ", path)
			failures += 1

	print("SCRIPTS: ", total, " loaded, ", failures, " failed")
	quit(1 if failures > 0 else 0)
