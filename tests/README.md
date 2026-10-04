# Automated tests

Run from the project folder (`G` = the Godot binary). Tests start the game normally (autoloads work) via
`test_runner.tscn` and print results with a `HOST` / `CLIENT` / `[time]` prefix. Excluded from exports.

```bash
# Menus: presses the real buttons (Host Game → Create Lobby → Leave, Find Game → Back, Host Game → Create Lobby → Start; no Play button)
# Every test plays a Swordsman unless --class=<swordsman|spearman|bowman> (test_runner.gd)
# Host/client pairs: add --port=<N> to both (e.g. 24575) when a game is already running on this PC (it holds 24565),
# and no --fixed-fps (it races ahead of real time and the connection times out)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/ui_flow_test.gd

# Training Field: menu entry, unlimited special ability, permanent damage targets, F-only manual orc spawning, switch hero at the gallery
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/training_test.gd

# Spearman Bull Rush: three-second shield charge, front protection, heavy steering, correct spear grip, one hit per target, passes through real orcs
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/bull_rush_test.gd --class=spearman

# Bowman Bow Rain: placed ground area, server-authoritative falling arrows, duration and cleanup
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/bow_rain_test.gd

# Solo: chest, tree, camp (gives no soldiers), trading post (buy only at the right stall), barracks (queue 10 s each, pen, take at the gate, 8 soldiers leave the pen, army cap 10 → 15), death
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/solo_test.gd

# AI: orcs keep their targets, the Warlord walks around a house and never gets stuck, tents for small camps,
# point-blank arrows hit an orc / a camp wall right in front of the player
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ai_test.gd

# Class balance bench (prints a table, no pass/fail): real DPS single / crowd / line, ability damage per use,
# javelin / knife / dash / wave, soldier DPS, maxed upgrades, camera reach per zoom. Run it for all three classes.
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/balance_test.gd --class=swordsman

# Soldiers: spear soldiers only stab, archers shoot from half the hero's bow range / step back / walk around a
# wall in the way / line up behind the hero, swordsmen spread over orcs and defend the hero first, a soldier
# trapped in a cup of walls follows the hero's trail out, soldiers only walk or run (--shots=<dir> with a window: frames of a stab)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ally_test.gd

# World events + army orders + pings + awards (solo)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/events_test.gd

# Army orders obeyed mid-fight (HOLD / FOLLOW drop the fight at once), KILL on the orc under the cursor
# (key 4, HUD Kill + click), CHARGE after the kill, a KILL that misses charges there
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/army_test.gd

# Desktop controls (Spearman): WASD, mouse thrust (aim wedge) / E → throw, K, F at a trading post stall, camera zoom per weapon, R rotates the camera 90°, touch controls hidden until a real touch
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd --class=spearman

# Shield (Swordsman, or --class=spearman): blocks from the front only while up, slower, no attacks, breaks, back on respawn
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_test.gd

# Shield motion: carried upright on the forearm, swings when running, bobs / sways while up (walk clip), a blocked hit recoils and settles
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/shield_motion_test.gd

# Screenshots of every screen (needs a window, no --headless); add --mobile for the phone layout
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots --mobile

# Multiplayer (run both at once): world determinism + camp sync + a client buys / takes a barracks soldier
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_client.gd

# Multiplayer: client-side prediction (instant, smooth, converges with the server)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_client.gd

# Multiplayer downed + revive (goes down, orc can't finish, host revives, bleeds out (keeps weapons and coins), respawns)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_client.gd

# Multiplayer King of the Hill: team towns, hill score, game over (+ back to lobby)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_client.gd

# Class upgrades (T sheet): cards per class, buying anywhere, damage / fire rate, and per class: shield, Knock Back
# (locks Wave), Wave, Dash Attack · Can Throw · Fire Range, Penetration (3 orcs), Knife
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_test.gd --class=swordsman
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/class_upgrades_test.gd --class=spearman
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
