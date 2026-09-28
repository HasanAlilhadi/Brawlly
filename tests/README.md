# Automated tests

Run from the project folder (`G` = the Godot binary). Tests start the game normally (autoloads work) via
`test_runner.tscn` and print results with a `HOST` / `CLIENT` / `[time]` prefix. Excluded from exports.

```bash
# Menus: presses the real buttons (Multiplayer → Host → Leave, Play → Start)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/ui_flow_test.gd

# Solo: chest, tree, camp, shop, death
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/solo_test.gd

# AI: orcs keep their targets, the Warlord walks around a house and never gets stuck, tents for small camps,
# point-blank arrows hit an orc / a camp wall right in front of the player
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/ai_test.gd

# World events + army orders + pings + awards (solo)
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/events_test.gd

# Desktop controls: WASD, mouse sword / bow, Space, B shop, touch controls hidden until a real touch
"$G" --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- --test=res://tests/desktop_input_test.gd

# Screenshots of every screen (needs a window, no --headless); add --mobile for the phone layout
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots
"$G" --path . res://tests/test_runner.tscn -- --test=res://tests/screenshot_test.gd --out=/tmp/shots --mobile

# Multiplayer (run both at once): world determinism + camp sync
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_sync_client.gd

# Multiplayer: client-side prediction (instant, smooth, converges with the server)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_predict_client.gd

# Multiplayer downed + revive (goes down, orc can't finish, host revives, bleeds out, respawns)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_revive_client.gd

# Multiplayer versus modes: Team Deathmatch, Capture the Flag, King of the Hill (+ back to lobby)
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_host.gd &
"$G" --headless --path . res://tests/test_runner.tscn -- --test=res://tests/mp_modes_client.gd
```

The multiplayer clients stay in the main menu after their host quits — stop them once the host prints `done`.
