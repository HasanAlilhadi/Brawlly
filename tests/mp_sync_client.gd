extends Node
var t := 0.0
var phase := 0
var pt := 0.0
func _ready() -> void:
	Net.set_profile("Clienty", 3)
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1")
func _log(m: String) -> void:
	printerr("CLIENT [%.1f] %s" % [t, m])
func _process(delta: float) -> void:
	t += delta; pt += delta
	var main := get_tree().current_scene
	if main == null or main.name != "Main":
		if phase > 0 and phase < 9: _log("left game"); phase = 9
		return
	var camps := get_tree().get_nodes_in_group(&"camps")
	camps.sort_custom(func(a, b): return a.name < b.name)
	match phase:
		0:
			if main.get("local_player") != null and pt > 1.0:
				var sig := ""
				for c in camps: sig += "%s@%d,%d " % [c.name, int(c.global_position.x), int(c.global_position.z)]
				_log("camps: " + sig)
				_log("trees=%d chests=%d seed=%d" % [get_tree().get_nodes_in_group(&"choppable").size(), main.get_node("World").get_children().filter(func(n): return n is Chest).size(), Net.settings.seed])
				phase = 1; pt = 0
		1:
			if camps[0].health < camps[0].max_health and phase == 1:
				_log("saw %s health drop to %.0f/%.0f (alive label %d)" % [camps[0].name, camps[0].health, camps[0].max_health, camps[0].alive])
				phase = 2
		2:
			if camps[0].is_dead:
				var hud: Hud = main.get_node("HUD")
				_log("saw %s destroyed by %d; HUD camps='%s' toast='%s'" % [camps[0].name, camps[0].destroyed_by(), hud.camps_label.text, hud.toast_label.text])
				phase = 3
