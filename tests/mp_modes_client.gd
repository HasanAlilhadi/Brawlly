extends Node
var t := 0.0
var saw_respawn := false
var last_scene := ""
var last_score := ""
func _ready() -> void:
	Net.set_profile("Clienty")
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1")
func _log(m: String) -> void:
	printerr("CLIENT [%.1f] %s" % [t, m])
func _process(delta: float) -> void:
	t += delta
	var main := get_tree().current_scene
	if main == null: return
	if main.name != last_scene:
		last_scene = main.name
		_log("scene -> %s" % main.name)
		saw_respawn = false
	if main.name != "Main": return
	var hud: Hud = main.get_node("HUD")
	if hud.respawn_label.visible and not saw_respawn:
		saw_respawn = true
		_log("respawn overlay: '%s'" % hud.respawn_label.text)
	if hud.score_label.text != last_score and hud.score_panel.visible:
		last_score = hud.score_label.text
		if not last_score.ends_with("0") or true:
			pass
	if hud.end_panel.visible and hud.end_title.text != "" and not hud.has_meta("logged"):
		hud.set_meta("logged", true)
		_log("END: '%s' / '%s'  score line '%s'  restart visible=%s  toasts last='%s'" % [hud.end_title.text, hud.end_subtitle.text, hud.score_label.text, hud.restart_button.visible, hud.toast_label.text])
