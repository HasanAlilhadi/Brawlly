extends Node
## Client prediction check: instant response, smooth motion, converges with the server after stopping.
var t := 0.0
var phase := 0
var pt := 0.0
var start_x := 0.0
var samples: Array[float] = []
var first_move_frame := -1
var frame := 0

func _ready() -> void:
	Net.profile.name = "Clienty"
	await get_tree().create_timer(1.0).timeout
	Net.join("127.0.0.1")

func _log(m: String) -> void:
	printerr("CLIENT [%.2f] %s" % [t, m])

func _physics_process(delta: float) -> void:
	t += delta; pt += delta
	var main := get_tree().current_scene
	if main == null or main.name != "Main" or main.get("local_player") == null:
		return
	var me: Player = main.local_player
	var hud: Hud = main.get_node("HUD")
	match phase:
		0:
			if pt > 1.0:
				_log("predicted=%s collision_mask=%d" % [me.is_predicted, me.collision_mask])
				start_x = me.global_position.x; frame = 0; phase = 1; pt = 0
		1:
			hud.joystick.output = Vector2(1, 0)
			frame += 1
			samples.append(me.global_position.x)
			if first_move_frame < 0 and me.global_position.x > start_x + 0.01:
				first_move_frame = frame
			if pt > 2.0:
				hud.joystick.output = Vector2.ZERO
				var backwards := 0
				for i in range(1, samples.size()):
					if samples[i] < samples[i - 1] - 0.001: backwards += 1
				_log("moved %.2f units in 2s; first movement on frame %d; backward steps=%d; anim=%s" % [me.global_position.x - start_x, first_move_frame, backwards, me.anim.current_animation])
				phase = 2; pt = 0
		2:
			if pt > 1.0:
				_log("after stopping: shown x=%.3f, server x=%.3f, gap=%.3f; anim=%s" % [me.global_position.x, me.net_position.x, absf(me.global_position.x - me.net_position.x), me.anim.current_animation])
				_log("enemies visible=%d warbands=%d my health=%.0f/%.0f" % [get_tree().get_nodes_in_group(&"enemies").size(), get_tree().get_nodes_in_group(&"warbands").size(), me.health, me.max_health])
				phase = 3
