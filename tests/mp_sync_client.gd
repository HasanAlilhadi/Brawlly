extends Node
var t := 0.0
var phase := 0
var pt := 0.0
func _ready() -> void:
	Net.profile.name = "Clienty"
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
	var bands := get_tree().get_nodes_in_group(&"warbands")
	bands.sort_custom(func(a, b): return a.name < b.name)
	match phase:
		0:
			if main.get("local_player") != null and pt > 1.0:
				var sig := ""
				for c in bands: sig += "%s@%d,%d/%d " % [c.name, int(c._origin.x), int(c._origin.z), c.size]
				_log("warbands: " + sig)
				_log("trees=%d chests=%d seed=%d" % [get_tree().get_nodes_in_group(&"choppable").size(), main.get_node("World").get_children().filter(func(n): return n is Chest).size(), Net.settings.seed])
				phase = 1; pt = 0
		1:
			if bands[0].alive < bands[0].size and phase == 1:
				_log("saw %s drop to %d of %d" % [bands[0].name, bands[0].alive, bands[0].size])
				phase = 2
		2:
			if bands[0].is_dead:
				var hud: Hud = main.get_node("HUD")
				_log("saw %s wiped out by %d; HUD bands='%s' toast='%s'" % [bands[0].name, bands[0].defeated_by(), hud.bands_label.text, hud.toast_label.text])
				phase = 3; pt = 0
		3:
			var me: Player = main.local_player
			var recruit: UpgradeDef = Player.CATALOG.upgrades.filter(func(d): return d.id == &"recruit")[0]
			if me.coins >= 100 and me.can_buy(recruit):
				me.request_buy(recruit)
				_log("recruited a soldier from the upgrades sheet")
				phase = 4; pt = 0
		4:
			var me: Player = main.local_player
			if me.followers().size() > 0:
				_log("the soldier joined after %.1fs: following %d (training %d, coins %d)" % [pt, me.followers().size(), me.soldiers_training, me.coins])
				phase = 6; pt = 0
			elif pt > 14: _log("FAIL no soldier joined (training %d)" % me.soldiers_training); phase = 6; pt = 0
		6:
			var raiders := get_tree().get_nodes_in_group(&"wave_enemies")
			if raiders.size() >= 10:
				_log("saw replicated wave: %d raiders, wave=%d" % [raiders.size(), (raiders[0] as Enemy).wave_number])
				phase = 7
			elif pt > 25:
				_log("FAIL no replicated wave enemies")
				phase = 7
