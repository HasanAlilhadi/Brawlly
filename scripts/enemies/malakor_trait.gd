class_name MalakorTrait
extends EnemyComponent
## Malakor's four phases (by health share), each one pair of his six arms, the last all of them together:
## 1 (100-75%) Sword Dominance: the upper pair's wide cleaves and a red-lane charge, chasing.
## 2 (75-50%) Phantom Hunter: he backs off (kiting) and the bow pair paints 3 red X zones for a 40-arrow rain,
##   with arrow volleys between.
## 3 (50-25%) Void Archmage: the grimoire pair blinks him behind the archers (he turns on a ranged foe near) and
##   drops dark meteors, void bolts between.
## 4 (25-0%) Apex Chimera: everything at once, a life-siphon aura (foes near him bleed, he drinks it) and his melee
##   life steal goes to LIFE_STEAL_ENRAGED (200% of the damage dealt). Blood Totems rise at 66% and 33% (the
##   Totems summon, any phase). Every phase change: a shout and a shockwave on every peer.
## Actions are switched on and off by node name (PHASE_ACTIONS; EnemyAction.enabled), movement by node (Chase / Kite).

const FX_PHASE: int = 0
const FX_SIPHON: int = 1
const THRESHOLDS: Array[float] = [0.75, 0.5, 0.25]
const PHASE_ACTIONS: Array = [
	["Charge"],
	["ArrowRain", "Volley"],
	["Blink", "Meteors", "VoidBolt"],
	["Charge", "ArrowRain", "Volley", "Blink", "Meteors", "VoidBolt"],
]
const SWITCHED: Array[String] = ["Charge", "ArrowRain", "Volley", "Blink", "Meteors", "VoidBolt"]
const PHASE_NAMES: PackedStringArray = ["Sword Dominance", "Phantom Hunter", "Void Archmage", "Apex Chimera"]
const SHOUTS: PackedStringArray = [
	"Kneel before the Sovereign!",
	"Vaira's bow answers to me now!",
	"Valendor's shadows, take them!",
	"Tyressa's chalice thirsts — I drink your souls!",
]
const LIFE_STEAL: float = 0.35
const LIFE_STEAL_ENRAGED: float = 2.0

## Phase 4 siphon: foes within `siphon_radius` lose `siphon_damage` × power a second, he heals it back × 2.
@export var siphon_radius: float = 6.0
@export var siphon_damage: float = 6.0
## Phase 3: he turns on a ranged foe this close (to blink behind them).
@export var hunt_ranged_within: float = 16.0

## 0..3 (server; -1 until the first tick).
var phase: int = -1
## Server: health each faction took from him (team -> amount) and the faction of the last blow — when he falls,
## ConquestMode.king_slain() gives the match to the faction with the most damage (the killing blow counts extra).
var damage_by_team: Dictionary = {}
var last_team: int = -1

var _siphon_left: float = 1.0
var _hunt_left: float = 0.0


func server_tick(delta: float) -> void:
	var share := enemy.health / maxf(enemy.max_health, 1.0)
	var now := 0
	for limit in THRESHOLDS:
		if share <= limit:
			now += 1
	if now != phase:
		var first := phase < 0
		phase = now
		_apply()
		if not first:
			enemy.shout(SHOUTS[phase])
			enemy.fx(self, FX_PHASE, enemy.global_position, float(phase))
	if phase == 2 or phase == 3:
		_hunt_left -= delta
		if _hunt_left <= 0.0:
			_hunt_left = 3.0
			_hunt_ranged()
	if phase == 3:
		_siphon_left -= delta
		if _siphon_left <= 0.0:
			_siphon_left = 1.0
			_siphon()


func _apply() -> void:
	var on: Array = PHASE_ACTIONS[phase]
	for action_name in SWITCHED:
		var action := enemy.get_node_or_null(action_name) as EnemyAction
		if action:
			action.enabled = on.has(action_name)
	var movement := enemy.get_node_or_null("Kite" if phase == 1 else "Chase") as EnemyMovement
	if movement:
		enemy.movement = movement
	var steal := enemy.get_node_or_null("LifeSteal") as LifeStealTrait
	if steal:
		steal.share = LIFE_STEAL_ENRAGED if phase == 3 else LIFE_STEAL


## Phase 3+: a ranged hero or soldier near becomes his target (the blink lands behind them).
func _hunt_ranged() -> void:
	var best: Unit = null
	var best_d := hunt_ranged_within
	for node in enemy.get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Unit
		if foe == null or GameConfig.is_gone(foe) or not GameConfig.is_hostile(enemy, foe) or not _ranged(foe):
			continue
		var d := enemy.flat_distance_to(foe)
		if d < best_d:
			best_d = d
			best = foe
	if best and best != enemy.target:
		enemy.target = best
		enemy.lock_target()


func _ranged(unit: Unit) -> bool:
	if unit is Ally:
		return (unit as Ally).is_ranged()
	if unit is Player:
		return (unit as Player).holds_ranged()
	return false


func _siphon() -> void:
	var drained := 0.0
	for node in enemy.get_tree().get_nodes_in_group(&"player_units"):
		var foe := node as Unit
		if foe == null or GameConfig.is_gone(foe) or not GameConfig.is_hostile(enemy, foe):
			continue
		if enemy.flat_distance_to(foe) > siphon_radius:
			continue
		var amount := siphon_damage * power()
		foe.take_damage(amount, enemy, false)
		drained += amount
		enemy.fx(self, FX_SIPHON, foe.global_position, 0.0)
	if drained > 0.0:
		enemy.heal(drained * 2.0)


func show_fx(event: int, at: Vector3, value: float) -> void:
	match event:
		FX_PHASE:
			HitFx.shockwave(at, 6.0)
			var tint: Color = [Color(1.0, 0.25, 0.15), Color(0.3, 0.95, 1.0), Color(0.7, 0.3, 1.0), Color(0.3, 1.0, 0.5)][int(value)]
			HitFx.flash(at + Vector3(0, 2.0, 0), HitFx.COMBO_RING, Color(tint, 0.9), 9.0, 0.6, Vector2(0.3, 1.2))
		FX_SIPHON:
			var green := Color(0.35, 1.0, 0.45, 0.9)
			HitFx.flash(at + Vector3(0, 0.9, 0), HitFx.REVIVE_SPARKLE, green, 0.8, 0.3)
			HitFx.flash(enemy.global_position + Vector3(0, 2.6, 0), HitFx.REVIVE_SPARKLE, green, 1.6, 0.35)


func on_hit_taken(attacker: Node, dealt: float) -> void:
	var team: Variant = attacker.get("team_id") if is_instance_valid(attacker) else null
	if team is int and int(team) >= 0:  # a faction's hero, soldier, arrow or siege engine
		damage_by_team[team] = float(damage_by_team.get(team, 0.0)) + dealt
		last_team = team


## He fell: Conquest's match goes to the faction that slew him.
func on_died() -> void:
	var main := enemy.get_tree().current_scene
	var mode := main.get("game_mode") as ConquestMode if main else null
	if mode:
		mode.king_slain(damage_by_team, last_team, enemy.max_health)
