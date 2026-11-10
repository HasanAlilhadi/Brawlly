# Automated tests

Run from the project folder (`G` = the Godot binary). Tests start the game normally (autoloads work) via
`test_runner.tscn` and print results with a `HOST` / `CLIENT` / `[time]` prefix. Excluded from exports.

```bash
# Conquest: zones, territories, raids, treasury + lords, rations / meals, couriers + routes, the M map, barracks, squads,
# guards (unguarded places fall), raids battering gates, march order, walls, siege, the Demon's Lair victory
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_test.gd
# Conquest heroes: start Unarmed, buy a weapon (swapped in place: coins, Vitality, health, soldiers carry over), levels
# from kills reset by a new weapon, the wizard's bolts and healer's heals; the left supplies panel, its flows and card
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_hero_test.gd
# Conquest zones: the outer zone only has small plain warbands far apart, world events only reach the inner zones
# (due with every hero outside they wait; the Blood Moon spares the outside), no invasion waves; demons: respawn
# by zone (2 min outside, wiped-out bands come back), full bands campaign (a village falls, a Citadel's gate is
# hammered but it never falls), a walled-in target sends a grunt to batter the gate, the King's four lieutenants
# (strong armies, the Mender heals), their rally to the Lair and home again
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_zones_test.gd
# Conquest frame cost: the hero walks to the Lair, then stands in a horde (100 monsters, 30 soldiers); the host's frame
# and the worst frame stay in budget (--probe / --kinds=a,b --window=s: what each kind of node costs; a window, no
# --headless: also the renderer's CPU / GPU time)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_perf_test.gd
# The commanders' brain (BattleBrain): the picks on a hand-made snapshot (an army spreads over the foes, the foe
# hitting the hero first, shooters the wounded + a second choice, monsters the nearest / the weakest / the nearest
# hero for wave monsters, a healer's patient), soldiers and monsters take their targets from its orders and pick no
# fight with it switched off, a hit still provokes at once; steering: three tries, around a wall, walled in = stays
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/battle_brain_test.gd
# Conquest gates: a held gate opens for its soldier with demons at it; soldiers ordered into a rival's walled Citadel
# go to its gate and hit it (no pressing against the wall), and march in once it is down
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_gates_test.gd
# Conquest place upgrades: Walls / Workshops / Barracks / Storehouse bought with a place's treasury, three levels,
# refused without gold or where they don't fit, sent with the places' numbers, kept when the place changes hands
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/conquest_upgrades_test.gd
# Malakor, the Six-Armed Sovereign: rules the Lair (4.8 m, six arms, clips), his four phases, the red-X arrow rain and
# dark meteors, Blood Totems at 66% that heal him, the phase-4 life siphon; the four risen champions lead the armies
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/malakor_test.gd
# Conquest screenshots (window): HUD + supplies panel with its Weapons card, walls + siege engines at an enemy gate,
# Army tab, Hero tab with the weapons to buy, the King's four lieutenants, one lieutenant's army, Malakor up close
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_shots_test.gd --out=/tmp/shots
# Conquest's own main-menu section: its hub page (own look + Lair backdrop) → Host Conquest Game (16 players) → its
# lobby (four faction cards, Join) → Leave back to the hub; classic lobbies have no Conquest (--out=<dir>: screenshots)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_menu_test.gd
# Menus: presses the real buttons (Host Game → Create Lobby → Leave, Find Game → Back, Host Game → Create Lobby → Start; no Play button)
# Every test plays a Swordsman unless --class=<swordsman|bowman> (test_runner.gd)
# Host/client pairs: add --port=<N> to both (e.g. 24575) when a game is already running on this PC (it holds 24565),
# and no --fixed-fps (it races ahead of real time and the connection times out)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/ui_flow_test.gd

# Training Field: menu entry, unlimited special ability, permanent damage targets, F-only manual orc spawning, switch hero at the gallery
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/training_test.gd

# Bowman Bow Rain: placed ground area, server-authoritative falling arrows, duration and cleanup
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/bow_rain_test.gd

# Solo: chest, tree, a warband wiped out (gives no soldiers), no warband near the spawn, Vitality / potions bought anywhere, recruits (queue 10 s each, then join behind you, army cap 10 → 15 with Command), death
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/solo_test.gd

# AI: a band next to a downed player stays awake, enemies keep their targets, the Warlord walks around a wall and never
# gets stuck, point-blank arrows hit an orc / a brute right in front of the player
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ai_test.gd

# Warbands + enemy types: bands (sizes, factions, graveyards, none near the spawn, far ones paused), marching,
# formation, one alert sends the band; every type's moves (thrower kites, brute charge / stomp / enrage, skeleton
# flanks / reassembles, archer, zombie lunge / death burst, ghost float / phase, vampire blink / life steal,
# necromancer summon / bolts), bosses rout their band when they fall
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/enemy_test.gd

# Maps + world events: Crown Ruins (layout, team bases, shrine bands, chests, trees, walls stop shots, base → hill
# walk, scoring), the events list setting, meteor / lightning hurt, storm rain + darkness, Blood Moon, supply drop
# (with a window and --shot=<png>: a zoomed-out look at the map)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/map_events_test.gd

# Class balance bench (prints a table, no pass/fail): real DPS single / crowd / line, ability damage per use,
# knife / dash / wave, soldier DPS, maxed upgrades, camera reach per zoom. Run it for both classes.
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/balance_test.gd --class=swordsman

# Soldiers: archers shoot from half the hero's bow range / step back / walk around a
# wall in the way / line up behind the hero, swordsmen spread over orcs and defend the hero first, a soldier
# trapped in a cup of walls follows the hero's trail out, soldiers only walk or run (--shots=<dir> with a window: frames of a stab)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ally_test.gd

# Animals: every species' model / size / team, orcs ignore them, shy herds flee together, the wild pig rams (damage +
# shove) and calms down, soldiers fight an angry wild pig only, 3..8 coins + ~20% health drops, herds respawn
# (--shot=<png> with a window: a close look at every species)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/animal_test.gd

# World events + army orders + pings + awards (solo)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/events_test.gd

# Army orders obeyed mid-fight (HOLD / FOLLOW drop the fight at once), KILL on the orc under the cursor
# (key 4, HUD Kill + click), CHARGE after the kill, a KILL that misses charges there
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/army_test.gd

# Desktop controls (Swordsman; --class=bowman for the bow): WASD, mouse swing (aim wedge), E does nothing with one weapon, right mouse shield (Bowman: aim + shoot), K, F does nothing in a match, T opens / closes the upgrades sheet (Hero + Army cards), camera zoom per weapon, R rotates the camera 90°, touch controls hidden until a real touch
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd --class=bowman

# Shield (Swordsman): blocks from the front only while up, slower, no attacks, breaks, back on respawn
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_test.gd

# Shield motion: carried upright on the forearm, swings when running, bobs / sways while up (walk clip), a blocked hit recoils and settles
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_motion_test.gd

# Screenshots of every screen (needs a window, no --headless); add --mobile for the phone layout
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots --mobile

# Multiplayer (run both at once): world determinism + warband sync (losses, wiped out) + a client recruits a soldier that joins it
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_client.gd

# Multiplayer: client-side prediction (instant, smooth, converges with the server)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_client.gd

# Multiplayer downed + revive (goes down, orc can't finish, host revives, bleeds out (keeps weapons and coins), respawns)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_client.gd

# Last Stand (solo): ten circles from the seed (clear, a gold vein in each), one hero needed alone, the clock pauses
# outside and keeps its progress, held circles pay coins + make enemies stronger, assault squads, gold veins (per hit,
# run dry, grow back), the Warlord on the last circle, victory (--defeat: no respawn, defeat; --map=<id>; a designed map uses its own circles)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/last_stand_test.gd
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/last_stand_test.gd --defeat --map=gravemoor

# Every map × every mode: landmarks / layout with collision, spawns and objectives clear (room in every circle),
# gold veins at every spawn and none inside walls, map light + minimap color, warbands
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/maps_test.gd

# Map screenshots (spawn, nearest landmark, a gold vein, the first circle) — needs a window, keep it off-screen
"$G" --path . --position -4000,-4000 --resolution 1280x720 res://tests/test_runner.tscn -- --test=res://tests/map_shots_test.gd --out=/tmp/shots

# Multiplayer Last Stand (Gravemoor): same world on both (compare the SIG lines), a two-hero circle waits for both,
# a downed hero nobody revives stays dead and spectates, the circle then needs one, defeat on both screens
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/last_stand_mp_test.gd --role=host --port=24715 &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/last_stand_mp_test.gd --role=client --port=24715

# Multiplayer Conquest: a squad made on the host reaches the client (leader + banner, out of the army, its map card);
# the client's Train and squad orders reach the server and come back, an unguarded place counts down on the client;
# the client buys a bow and binds its new hero (HUD, camera, prediction), the supplies flows reach it
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_mp_test.gd --role=host --port=24725 &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/conquest_mp_test.gd --role=client --port=24725

# Multiplayer King of the Hill: one spawn area per team (no warbands near), hill score, game over (+ back to lobby)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_client.gd

# Class upgrades (T sheet): cards per class, buying anywhere, damage / fire rate, and per class: shield, Knock Back
# (locks Wave), Wave, Dash Attack · Can Throw · Fire Range, Penetration (3 orcs), Knife
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_test.gd --class=swordsman
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_test.gd --class=bowman
# Class upgrades online: client buys via the server, predicted dash, the host's Fire Range seen on the client
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_mp_test.gd --role=host --class=bowman --port=24705 &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_mp_test.gd --role=client --class=swordsman --port=24705

# Server browser + lobby: client finds the locked game, wrong password refused, right one joins, Ready, host kicks → notice
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/lobby_test.gd --role=host --port=24685 &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/lobby_test.gd --role=client --port=24685

# Multiplayer abilities: all classes, host/client casts, repeated casts, active-spawn visuals and authoritative impacts
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/ability_multiplayer_test.gd --role=host --port=24675 &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/ability_multiplayer_test.gd --role=client --port=24675
```

The multiplayer clients stay in the main menu after their host quits — stop them once the host prints `done`.
