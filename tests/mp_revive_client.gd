extends Node
## Client half of mp_revive_host.gd: checks what this device sees while downed / revived.
var t := 0.0
var was_downed := false
var saw_label := false
var revived_seen := false


func _ready() -> void:
	Net.set_profile("Clienty", 3)
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1")


func _log(m: String) -> void:
	printerr("CLIENT [%.1f] %s" % [t, m])


func _process(delta: float) -> void:
	t += delta
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	var me: Player = main.local_player
	var hud: Hud = main.hud
	if me.is_downed and not was_downed:
		was_downed = true
		await get_tree().create_timer(0.5).timeout
		_log("downed on this device: bleed=%ds, 'You're down' shown=%s, speed=%.2f" % [me.bleed_seconds, hud._downed_panel.visible, me.move_speed])
	elif not me.is_downed and was_downed and not me.is_dead:
		was_downed = false
		_log("back up: health %.0f/%.0f, label hidden=%s" % [me.health, me.max_health, not hud._downed_panel.visible])
