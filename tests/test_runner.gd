extends Node
## Test harness: `Godot --path . res://tests/test_runner.tscn -- --test=res://tests/<name>.gd`
## Starts like the real game (autoloads work) and attaches the test driver to the root.
func _ready() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			path = arg.substr(7)
	var driver: Node = (load(path) as GDScript).new()
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(driver)
