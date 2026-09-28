# Project guide for Claude

Godot 4 game, **desktop first (Windows PC)** with Android / iOS still supported (created from the Template project). The Godot editor is driven via the **godot-mcp** server (Coding-Solo/godot-mcp).
See `README.md` for the full folder layout and project defaults.

## Asset pipeline (important)

- The user drops raw assets anywhere in `pre-assets/` (no fixed subfolders — often whole downloaded packs) and tells you.
  That folder has a `.gdignore`, so Godot never sees it.
- Before using an asset: **copy** it into `assets/` (keep the originals in `pre-assets/` unless told otherwise).
- Rename to `snake_case` and drop redundant prefixes: `character-orc.glb` → `assets/characters/orc.glb`,
  `Player Idle 01.png` → `assets/characters/player/player_idle_01.png`.
- Where things go:
  - Characters (sprites or 3D models) → `assets/characters/` (subfolder per character if it has several files)
  - Level pieces & props → `assets/environment/` — one `<theme>/` subfolder per pack/theme when several are mixed (e.g. `environment/dungeon/`)
  - Weapons, pickups, collectibles → `assets/items/` (same `<theme>/` rule)
  - Textures → `assets/textures/`; 3D kit color palettes → `assets/textures/palettes/<theme>_colormap.png`
  - UI → `assets/ui/{icons,buttons,panels}/`, fonts → `assets/fonts/`
  - Sound effects → `assets/audio/sfx/`, music → `assets/audio/music/`, effects → `assets/vfx/`
  - Unclear → ask the user.
- 3D models: prefer **GLB** over FBX/OBJ. When GLBs reference an external texture (e.g. Kenney's `Textures/colormap.png`),
  keep **one** copy in `assets/textures/palettes/` and relink the models with
  `tools/glb_set_texture.py <texture.png> <model.glb>...` instead of copying the texture next to every model.
- Skip pack extras (preview images, `.url` files, `Overview.html`). Record each pack's author and license in `assets/CREDITS.md`.
- Never reference `pre-assets/` from a scene or script (it is not imported, so `res://pre-assets/...` will not load).

## Conventions

- Files & folders: `snake_case` (`player_controller.gd`, `main_menu.tscn`).
- Node names: `PascalCase`. Classes (`class_name`): `PascalCase`.
- GDScript: tabs, static typing where practical (`var speed: float = 200.0`).
- A scene and its main script share a name: `scenes/characters/player.tscn` ↔ `scenes/characters/player.gd`. Reusable, scene-independent scripts go in `scripts/`.
- Singletons live in `scripts/autoload/` and are registered in Project Settings → Autoload.
- Custom `Resource` data (`.tres`) goes in `resources/data/`; UI themes in `resources/themes/`.
- Exports go to `builds/` (ignored by Godot and git).
- Prefer `Transition.change_scene(path)` (fade) over raw scene changes for screen-to-screen moves.
- `change_scene_to_file()` removes the current scene from the tree immediately: change scenes from exactly one
  place per screen (guard with a flag / `is_inside_tree()`), never twice, and don't use `get_tree()` after it.

## Reusable components

Check `scripts/components/` before writing new generic code — touch joystick, touch button,
touch aim stick, 3D health bar, bone pose override, follow camera, floating text, off-screen markers and `MaxWidth` already exist,
plus a main menu and pause menu in `scenes/ui/` (see `README.md`). Touch controls handle input in `_input`
by touch index so the joystick and buttons work together with multi-touch.

## Desktop & mobile notes

- **Desktop first**: design for 1920×1080 landscape with keyboard + mouse (and gamepad); phones must keep working
  (720×1280 portrait UI, touch controls). `Platform` (autoload) picks the layout: `Platform.mobile_layout`,
  `Platform.touch_mode` (+ `touch_mode_changed`). Test the phone layout on a PC with `-- --mobile`.
- Input goes through Input Map actions (`move_*`, `aim_*`, `attack`, `aim_bow`, `shoot`, `shop`, `pause`,
  `toggle_fullscreen`, `army_*`, `ping*`) — add new bindings there, not as hard-coded keys, and list them on the
  Controls page (`scenes/ui/controls_menu.gd`, main menu → Controls). Mouse clicks for gameplay are taken in
  `_unhandled_input` (so clicks on HUD buttons don't attack); ignore events with `device == DEVICE_ID_EMULATION`.
- UI must work in both orientations: anchor to edges, use `MaxWidth` on full-width panels, check both with
  `tests/screenshot_test.gd` (with and without `--mobile`). Touch controls still handle input in `_input` by touch index.
- 3D cameras: FOV applies to the screen's short side (`FollowCamera3D.fit_fov_to_short_side`). "Off-screen"
  distances must hold for the wide desktop view (e.g. `main.gd` `REINFORCE_DISTANCE`).
- Renderer: Forward+ on PC, Mobile on phones (`.mobile` overrides) — keep effects cheap enough for phones.
- Respect safe areas on phones (`DisplayServer.get_display_safe_area()`).
- Exports: `Windows Desktop` preset → `builds/windows/MyGame.exe`; Android / iOS presets unchanged.

## Game architecture (MyGame)

- `main.tscn` → `main.gd` builds the world with `WorldBuilder`, then wires HUD / keyboard / mouse / gamepad input
  to the `Player` each frame (the mouse aims via a ray onto the ground plane: `_cursor_direction()`).
- All characters extend `Unit` (`scenes/characters/unit.gd`): override `_get_move_input()`, `_can_hit()`, `_on_died()`.
  Models face +Z; weapons attach to bones `arm-left` / `arm-right` (one bone per arm, no wrist). While walking/idle the
  weapon arm is held in the `holding-*` pose via `BonePoseOverride3D` with a carry grip (`right_hand_offset/rotation`);
  attacks release the arm and switch to a swing grip in line with the arm (`right_swing_offset/rotation`). Characters
  are scaled 1.25 in their scenes.
- One-arm actions (sword swing, bow shot) play on that arm only while the unit moves (`BonePoseOverride3D.start_live`),
  full-body when standing still. Player colors: `recolor_*` exports + `assets/shaders/palette_recolor.gdshader`
  replace one palette hue (soldier crest h≈0.015, archer hat h≈0.38); new unit types need their own key hue.
- In-game HUD is deliberately compact (PanelCompact / PanelInsetCompact styles): keep new HUD elements small.
  Touch sticks are hidden unless `Platform.touch_mode`.
- Groups: `player`, `friendly` (player + soldiers), `allies` (soldiers), `enemies` (orcs), `enemy_team` (orcs + live camps),
  `camps`, `choppable` (trees). Physics layers are in `GameConfig` (world, player, enemies, allies).
- UI uses the project theme `resources/themes/rpg_theme.tres` (built by `tools/build_rpg_theme.gd` from the Kenney RPG UI
  pack). Style new UI with its type variations instead of per-node overrides; labels on dark wood use `LabelLight`.
  Variations: `PanelBrown` (wood title ribbons), `PanelInset` (list rows), `PanelLight` (cards), `ButtonBeige`,
  `ButtonTab` (toggle tabs), `ButtonSquare`, `KeyCap` + `KeyCapLabel` (key prompts), `HeaderLabel`, `HintLabel`,
  `TitleLabel`, `ProgressBar*`. Round icon badges: `UiKit.medal(icon)` (`scenes/ui/ui_kit.gd`) — prefer the
  white Game Icon Pack glyphs in `assets/ui/icons/game/` (SVG, import `svg/scale=4`, replace `currentColor` with white
  when adding more). Input prompts: `UiKit.prompt("keyboard/w" | "mouse/left" | "xbox/rt" | "touch/tap")` from
  `assets/ui/prompts/` (Kenney Input Prompts, Double size; copy more from pre-assets when needed). Cursors: gauntlet in
  menus (Project Settings), gold sword in matches (main.gd).
- Flow: `main_menu.tscn` (run scene) → `main.tscn`; `PauseMenu` in `main.tscn`, disabled on game over.
- Anything damageable implements `take_damage(amount, attacker = null, is_melee = true)`.
- Economy: `Player.coins`, `Player.upgrade_levels`, `buy_upgrade(def)`; shop items are `UpgradeDef` resources in
  `resources/data/upgrade_catalog.tres` (effects by `id` in `Player._apply_upgrade`). Soldiers read `Player.ally_power`;
  `Player.follower_cap` replaces a fixed cap.
- Squads come from `EnemyRoster` (`resources/data/orc_roster.tres`: filler + RosterEntry share/min_squad/max_count/
  inner_ring). New enemy type = new scene + roster entry. Camps scale orc stats and coins by `Camp.tier` (0..1).
- Targeting uses group `active_enemies` (orcs of awake camps only) — keep it that way for performance with many camps.
  World size/camp count: `GameConfig.world_half` (set from main's exports) — never hard-code the world size.
- Orc types are scenes using the same `enemy.gd` with different exports (thrower = `projectile_scene` set;
  giant = `melee_cleave`, `anim_speed` < 1, big `radius`). `Camp._squad_composition()` decides the mix.
  Melee hits one target unless `melee_cleave`. Thrown spears reuse `arrow_projectile.gd` with a different `hit_mask`.
- **Downed** (`GameConfig.downed_enabled`: online and not deathmatch): `Player.die()` turns into `_go_down()`
  (`is_downed`, crawl speed, out of `player_units`). `GameConfig.is_gone()` treats downed units as gone, so AI and
  aim assist skip them. Revive = teammate within `Player.REVIVE_RANGE` for `REVIVE_TIME`. Only hostile
  player-owned damage finishes a downed player. Signals `went_down` / `revived` → main.gd (announce, Help ping).
  Clips `crawl` (moving) / `downed` (still) come from `assets/characters/animations/archer_downed.glb` (made in Blender on
  the archer armature, copied into the archer library by `Player._add_downed_anims()`); while downed the arm holds stay off and the sword / bow are hidden.
- **World events** (`WorldEvents`, setting `events`): `spawn_goblin()` / `spawn_warlord()` (server; tests call them
  directly). `TreasureGoblin` (NetSpawn kind `goblin`, orc team, flees), `Warlord` (extends `Enemy`, warband orcs
  have `Enemy.warlord` set and follow via `follow_point()`, killer inherits the warband).
- **Army orders**: `Player.army_order` / `army_point` (replicated), `command_army()` / `net_command` RPC; `Ally`
  anchors its formation to the point for CHARGE / HOLD.
- **Stats & awards**: report events with `MatchStats.add(peer, &"stat")` (server; kills / deaths / soldiers lost
  come from `Unit.die()`, damage from `HitFx.report_hit`). New award = a row in `MatchStats.AWARDS`.
- **Pings**: `main._ping()` → server `_on_ping()` (rate-limited) → teammates' `PingMarker`. Things that should get a
  screen-edge arrow + minimap diamond join group `tracked` with metas `marker_color` / `marker_label`.
- Balance reference (base stats, before camp tier 0.75–1.35×): player 150hp, sword 30 (cleaves), arrow 40, regen 6/s;
  soldier 80hp/12; spearman 80/10; swordsman 95/11; thrower 55hp, spear 10; giant 500/26.
- Use `GameConfig.is_gone(node)` for target checks (handles freed nodes).
- AI targeting is sticky: pick targets with `Unit.choose_target(current, candidate, keep_range)` (keeps the current
  one for `TARGET_LOCK_TIME` and switches only to a much closer one). `Enemy.provoke(attacker, direct)`: squad alerts
  never retarget an orc that is already fighting; only a direct hit from a much closer attacker does.
- AI movement goes through `Unit.engage(target)` (spreads attackers around the target) and `Unit.steer(dir)`
  (avoids trees/houses with shape casts sized to the unit's `radius`, sidesteps when stuck, + separation between
  same-side units). Use these for new AI.
- Soldiers: max `GameConfig.MAX_FOLLOWERS` (25) follow in a compact spiral formation (group `followers`); extra freed
  soldiers go to `Player.reserve_soldiers` and `main.gd` spawns them off-screen as slots free up (no idle soldiers in the world).
- Far-away camps pause their orcs (`Camp.activation_range`; downed players still count as near, only dead ones don't) — keep this for mobile performance. Orcs that are
  provoked or walking home (`Enemy.is_busy()`) stay awake. Damage calls `Unit._on_damaged(attacker)`; orcs forward it
  to `Camp.alert(attacker)`, which provokes the whole squad (tuning in `enemy.gd` → "Provoked" exports).

## Multiplayer architecture (read before changing gameplay code)

- **Server-authoritative.** The host (or solo, via `OfflineMultiplayerPeer`, id 1) runs ALL gameplay: AI, damage,
  pickups, camps, scoring. Guard gameplay with `multiplayer.is_server()`; clients only display.
- **Spawning**: never `add_child` gameplay objects directly. Use `NetSpawn.unit(kind, pos, extra)`,
  `NetSpawn.pickup()`, `NetSpawn.projectile()` (server only); `main.gd` spawn functions build them on every peer.
  Freeing a spawned node on the server removes it everywhere — clients must never free units/items themselves.
- **Replication**: each unit scene has a `Sync` MultiplayerSynchronizer (ON_CHANGE) listing replicated props
  (net_position, net_yaw, health, max_health, anim_state, action_token, is_dead + player stats / orc alert_seq).
  New replicated state → add a property with a setter for client visuals AND add it to the scene's Sync config.
  Paused orcs aren't replicated until their camp wakes (saves bandwidth).
  `net_position` / `net_yaw` use REPLICATION_MODE_ALWAYS (unreliable, 20 Hz) — never make continuous values
  ON_CHANGE (reliable → stutter on Wi-Fi packet loss). Keep frequently-changing values quantized (regen heals whole points).
- **Client prediction**: on clients the local Player moves immediately (`Unit._predict`, `enable_prediction()`,
  fed by `main.gd` via `predict_input`) and only corrects real drift from the server position.
- **Static world** (trees, chests, camps, flags, hill) is built identically on every peer from `Net.settings.seed`
  with deterministic names; state changes go through RPCs on those nodes (`_net_*` methods, `call_local`).
- **Teams**: `team_id` on units/camps/projectiles (`GameConfig.ORC_TEAM` = -1 for orcs). Hostility =
  `GameConfig.is_hostile(a, b)`; groups: `players`, `allies`, `player_units` (players+allies), `enemies`,
  `active_enemies`, `camps`, `units`. `owner_peer` = controlling player (kill/camp credit).
- **Input**: `main.gd` reads HUD/keyboard and calls `Player.set_input/attack_melee/shoot` on the server, or the
  `Player.net_*` RPCs from clients (validated by sender). Shop purchases: `Player.request_buy()`.
- **Match flow**: menu → lobby (`Net.open_solo_lobby()` / `host()` / `join()`) → `Net.start_game()` loads main on
  all peers → server waits for every peer's world → spawns players. `Net.return_to_lobby()` after a match.
- **Testing multiplayer**: `-s script` runs skip autoloads (no `Net`), so use a runner scene that starts normally and
  attaches a driver Node — see `tests/` (`tests/README.md`): solo test + host/client pairs on 127.0.0.1.
  Run them after gameplay changes.

## Template sync (important)

Every game is created from the **Template** project (`../Template`, via `tools/new_game.sh`).
When you build something **general-purpose** in a game — a reusable system, component, autoload, helper,
shader, UI widget, project setting, or tool (e.g. audio manager, save system, scene transitions, touch
controls, safe-area UI) — **also add it to the Template** so future games get it:

- Copy it into the same path in `../Template`, stripped of anything game-specific (names, art, tuning values).
- Update the Template's `README.md` / `CLAUDE.md` if it changes how things work.
- Game-specific content (levels, characters, story, art) stays in the game only.
- Tell the user what was added to the Template.

## Orientation

Desktop is always landscape (UI 1920×1080). The phone orientation is set with
`tools/set_orientation.sh portrait|landscape` (phone UI 720×1280 or 1280×720). Don't hard-code screen sizes —
read them from the viewport.
