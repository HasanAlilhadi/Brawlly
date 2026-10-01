extends Node
## Test harness: `Godot --path . res://tests/test_runner.tscn -- --test=res://tests/<name>.gd`
## Starts like the real game (autoloads work) and attaches the test driver to the root.
## The local player is a Swordsman unless `--class=<ClassDef id>` says otherwise (not the saved profile's).
func _ready() -> void:
	var path := ""
	var hero := &"swordsman"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			path = arg.substr(7)
		elif arg.begins_with("--class="):
			hero = StringName(arg.substr(8))
	Net.profile["class"] = hero
	var driver: Node = (load(path) as GDScript).new()
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(driver)
