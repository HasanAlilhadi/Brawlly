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
- **Own models** are built by scripts `tools/blender_<name>.py` on top of `tools/blender_kit.py` (palette cells,
  Godot-space box/prism/cylinder helpers, generic pieces: walls, windows, roofs, banners, barrels…, `run()`):
  `blender -b --python tools/blender_<name>.py -- --check [--preview out.png --yaw 35]`. Rules (see the kit's header):
  texture = the shared Kenney palette, one cell per surface, sampled **linearly** ("Closest" stripes tall faces);
  **no overlapping coplanar faces** (z-fighting: flicker / see-through — one block per stair step, walls stop at
  towers, caps sit above what they cap, decor never overlaps); single-sided, outward faces; `--check` must print
  `OVERLAPS 0` and `FLIPPED 0`; then look at it **up close in the game** (`tests/screenshot_test.gd`: add a close-up
  shot), not only in the Blender preview. Model in Godot meters, 1 unit = one tile after the prop scale, origin
  bottom center, front = +Z; the GLB links the shared palette; the output goes to `assets/environment/<theme>/`.
  Layouts of several pieces use `marker()` spots (Node3Ds the game places things on), `solid_box()` / `solid_cyl()`
  collision and `prop(export=False)` for neighbours `--check` should see. (The town, trading-post stalls and their
  model scripts were removed on 2026-10-04 — in git history before then, as working examples of the kit.)
  **Reuse existing models**: anything the game already has (the player's sword / bow / spear / arrows, shields,
  barrels, targets, weapon racks, banners, flags — listed with their in-game sizes in `tools/blender_props.py`) is
  placed with `kit.prop()`, never modeled again; `run()` then also writes `<name>.tscn` (the GLB + those models),
  which is what the game loads. Model only what doesn't exist yet, and then rounded / pointed with `loft` / `rod` /
  `ball` (convex pieces), not plain boxes. The game camera looks down steeply: keep what matters out from under big
  roofs — open yards, small canopies.
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
touch aim stick, 3D health bar, bone pose override, follow camera, fly camera, floating text, off-screen markers and `MaxWidth` already exist,
plus a main menu and pause menu in `scenes/ui/` (see `README.md`). Touch controls handle input in `_input`
by touch index so the joystick and buttons work together with multi-touch.

## Desktop & mobile notes

- **Desktop first**: design for 1920×1080 landscape with keyboard + mouse (and gamepad); phones must keep working
  (720×1280 portrait UI, touch controls). `Platform` (autoload) picks the layout: `Platform.mobile_layout`,
  `Platform.touch_mode` (+ `touch_mode_changed`). Test the phone layout on a PC with `-- --mobile`.
- Input goes through Input Map actions (`move_*`, `aim_*`, `attack`, `aim_bow`, `block`, `shoot`, `switch_weapon`, `interact`, `pause`,
  `toggle_fullscreen`, `rotate_camera`, `army_*`, `ping*`, `dash` C / L3, `upgrades` T / View) — add new bindings there, not as hard-coded keys, and list them on the
  Controls page (`scenes/ui/controls_menu.gd`, main menu → Controls). Mouse clicks for gameplay are taken in
  `_unhandled_input` (so clicks on HUD buttons don't attack); ignore events with `device == DEVICE_ID_EMULATION`.
- `interact` is F on keyboard (LB on gamepad); only the Training Field uses it (switch hero at a pedestal, Orc Practice)
  — matches have nothing to interact with. The Orc Practice station
  spawns exactly one server-owned orc per press, up to eight living orcs; there is no automatic spawn timer.
- UI must work in both orientations: anchor to edges, use `MaxWidth` on full-width panels, check both with
  `tests/screenshot_test.gd` (with and without `--mobile`). Touch controls still handle input in `_input` by touch index.
- 3D cameras: FOV applies to the screen's short side (`FollowCamera3D.fit_fov_to_short_side`). "Off-screen"
  distances must hold for the wide desktop view (e.g. `WorldEvents.goblin_distance`). Camera zoom (main.gd):
  offset × `DESKTOP_CAMERA_ZOOM` (desktop) × `camera.zoom` = `CAMERA_ZOOM` 1.2 + `WEAPON_CAMERA_ZOOM` (spear +0.1, bow +0.2),
  with the bow × the Fire Range gain (`RANGE_CAMERA_ZOOM` × (`Player.aim_range_scale()` − 1)): see as far as you shoot.
  R (`rotate_camera`) orbits the camera 90° (`FollowCamera3D.rotate_step`): screen-space input (WASD, sticks,
  touch) goes through `camera.to_world()` / `main._screen_to_world()`; the minimap turns with the view; world labels
  that stack must use screen-space `Label3D.offset`, not height, so they hold from every side.
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
  full-body when standing still. The player's sword slash uses no clip (Kenney's melee clip twists the arm so the blade
  points at the ground): `Player._sword_slash` keeps the arm held and sweeps it (left to right) with `BonePoseOverride3D.pose_offset`
  (`SLASH_*` keys: arm sweep / raise, body twist / lunge, and blade directions in the body's space — the grip is
  solved from them each frame, turning around `sword_grip_point` so the handle stays in the fist). Player colors: `recolor_*` exports + `assets/shaders/palette_recolor.gdshader`
  replace one palette hue (soldier crest h≈0.015; per class in its ClassDef: archer hat h≈0.38, human shirt h≈0.65,
  keeper overalls h≈0.435); new unit types need their own key hue. Weapons in hand (under a BoneAttachment3D) are never recolored.
- In-game HUD is deliberately compact (PanelCompact / PanelInsetCompact styles) and follows the **HUD design system**:
  every size, gap and font size comes from `HudStyle` (`scenes/ui/hud_style.gd`) — no numbers in hud.gd / hud.tscn.
  `Hud._apply_design()` stacks the HUD into a left column (stats, square buttons) and a right column (minimap,
  stats, army orders); buttons have fixed sizes (`BUTTON`, `BUTTON_WIDE`). New HUD elements join a column.
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
- **Modes** (`Net.Mode`): `COOP` and `KING_OF_THE_HILL` only (the only team mode, `Net.is_team_mode()`); rules in
  `GameMode` (`scenes/main/game_mode.gd`). Deathmatch, Team Deathmatch and Capture the Flag were removed (in git
  history before 2026-10-04) and may come back; a new mode = a `Net.Mode` value + MODE_NAMES / MODE_HINTS /
  SCORE_LIMIT_LABELS + `lobby.gd` SCORE_LIMITS + its branches in `GameMode`.
- Flow: `main_menu.tscn` (run scene) → Find Game (`server_browser.tscn`) or Host Game (`host_menu.tscn`) → lobby →
  `main.tscn`; `PauseMenu` in `main.tscn`, disabled on game over. Menu pages are built in code with `MenuKit`
  (`scenes/ui/menu_kit.gd`: `frame()` page = title + tools + body + bottom buttons, `dialog()` modals) and lay out
  for phones with `MenuKit.is_compact()`. `Net.host(options)` takes the server options (name, max_players,
  password, listed → `Net.server_info`, synced); `Net.join(address, port, password)`; refusals before the lobby
  come back as `connection_failed(reason)` (`Net.WRONG_PASSWORD` re-asks), later ones (kicked, host left) set
  `Net.leave_reason`, which the main menu shows. Lobby ready flags: `Net.set_ready()` / `players[peer].ready`;
  `Net.kick(peer)` (host). Bump `Net.GAME_ID` when the join handshake changes (older builds then don't list).
  **Multiplayer only**: no single player in any menu. `Net.open_offline_lobby()` (offline peer) exists only for tests and
  running `main.tscn` directly from the editor.
- **Classes** (`ClassDef` resources in `resources/data/classes/`, listed in `class_catalog.tres`): Swordsman (`human.glb`,
  sword), Spearman (`keeper.glb`, spear thrust; javelin throw with Can Throw, E / Y toggles), Bowman (`archer.glb`, bow). Picked with
  `ClassPicker` (lobby only, with an `ArmyPreview`) → `Net.set_class()` → profile `class` + `Net.players[peer].class` → spawn data
  `class` → `Player.set_class()` (every peer, before entering the tree: swaps the Model, sets `weapons`, hand items,
  recolor hue, `hand_offset`). Soldiers carry `ClassDef.ally_weapon` (`Ally.weapon` from spawn data, `Ally.WEAPON_STATS`;
  archers shoot from `Ally.archer_range()`, spear soldiers only stab). A class is locked to its weapons; nothing has ammo. `keeper.glb` is a rigid
  Graveyard Kit model skinned onto the human's armature by `tools/blender_keeper_rig.py` (same bones and clips).
- Anything damageable implements `take_damage(amount, attacker = null, is_melee = true)`.
- **Weapons**: `Player.WEAPONS` rows (melee: `arc` / `reach` / `cooldown`): sword (melee 36 / 0.5 s, 80° wedge, cleaves),
  spear (stab 42 = `spear_damage` / 0.65 s, a straight 0.8 m × 2.6 m lane with a pointed end that pierces a line; `HitFx.stab` streak, not the sword's sweep), javelin (the spear thrown: `player_spear`
  projectile, `spear_cooldown` 1.1 s), bow (arrows 22, 0.4 s). No ammo anywhere (no ammo pickups, shop items or counters).
  Weapon damage / speed / range come only from the class upgrades (below).
  Chests are broken open by any weapon (group `breakable`, 60 hp), not opened by walking up. Shots fly at 0.55–0.7 m, so
  anything hittable needs collision up to `GameConfig.HIT_HEIGHT` (1 m); aimed shots fly exactly where aimed (no snapping); a quick shot / tap with no aim auto-targets the nearest enemy. Melee hits exactly the aim marker (`Player.melee_outline()` → `_melee_query` prism + `_melee_indicator`: a `melee_arc()` fan or a `melee_lane()` lane, out to `melee_reach()`), aimed where the swing started (`Unit._melee_dir`); other units keep the sphere in `Unit._melee_query`. The player carries `Player.weapons` (from the class) and holds one
  (`weapon_index`, replicated); `switch_weapon()` (server; E / Y / HUD button via `request_switch_weapon`). Melee / shoot
  functions refuse the weapon not in hand; attack keys and left mouse use the one in hand. The sword slash
  (`_sword_slash`) and the spear stab (`_spear_thrust`, `THRUST_*` keys: the spear slides straight out along the lane, aimed from its BoneAttachment3D — `get_bone_global_pose()` outside the skeleton update misses the holding-pose modifier; nothing moves sideways, the hero never steps forward; the lane is fixed when the stab starts: `_thrust_dir`, the body holds still via `Unit._facing_locked()`, re-aiming counts for the next stab — `tests/spear_aim_test.gd`) are procedural; other units use clips. The Bowman's bow is placed upright in the body's frame after
  every skeleton update (`Player._place_bow`, `BOW_*` constants) with an arrow nocked (`NOCK_POSITION`): a shot
  leaves from that arrow toward the aim line `aim_range` ahead, and the next arrow is nocked after the cooldown.
  New weapon = a `WEAPONS` row + its model in `_weapon_items` + an icon in `Hud._weapon_icons` + a class that carries it.
- **Special abilities** (X / R3 / touch ability button, action `ability`): enemies drop XP orbs (`Pickup.Kind.XP`,
  `Enemy.xp_drop()`: `xp_value` or max_health × `Enemy.XP_PER_HEALTH`, split into orbs of ≤ `XP_ORB`); `Player.xp`
  (replicated) fills up to `ClassDef.ability_xp` (10) and `use_ability()` (server; `request_ability()`) spends it.
  Ability per class in its ClassDef (`ability` id, `ability_name`, `ability_icon`, `ability_duration`); `ability_active`
  is replicated, `_apply_ability()` shows it on every peer. Swordsman `whirlwind`: spins (`_whirlwind_pose`, skeleton
  turned by `_spin_angle`), hits everything within `WHIRLWIND_RADIUS` every `WHIRLWIND_TICK`, slower, no attack / block.
  Spearman `bull_rush`: shield charge with limited steering that damages each crossed target once; enemy
  bodies do not block the charge, but walls and fences still do. Bowman `bow_rain`:
  X enters local cursor placement; LMB confirms a server-clamped target, then server-spawned arrows fall throughout
  the replicated circular ground marker for the ability duration. All 100 arrows fall from above to random points inside the
  marker; they do not track targets. Arrows fall one by one, with jittered angle/radius strata in each
  10-arrow run so the whole circle fills evenly. Bowman keeps normal bow aim and shooting during the rain.
  Each peer draws a brief entry flash and local hit burst for rain arrows;
  only the server applies projectile damage.
  New ability = ClassDef fields + a branch in `_update_ability` / `_apply_ability`. Test: `tests/ability_test.gd`.
- **VFX**: `HitFx.flash(at, texture, color, size, …)` pops a billboard sprite from `assets/vfx/particles/` (Kenney Particle Pack;
  additive, or `additive = false` for smoke). Used for hit sparks, death / camp smoke, combo ring, revive sparkle. Ground
  decals use `assets/vfx/light_masks/` (revive range ring). Touch controls are skinned from `assets/ui/touch/` (set in `hud.gd`).
- **Combo hits**: `Enemy.take_damage` — a player hit within `combo_window` (1 s) of a teammate's hit on the same orc deals
  `combo_damage_multiplier` (1.5×) and pops "COMBO!" for everyone (`HitFx.report_combo` → `main._net_combo`). Soldiers don't count.
- **Upgrades sheet**: everything is bought anywhere from the upgrades bottom sheet (`UpgradeSheet`,
  scenes/ui/upgrade_sheet.gd, in the HUD: T / gamepad View / the star button next to pause; `Hud.toggle_upgrades()`;
  slides in / out, `_slide()` / `_place()`; its handle `UpgradesTab` sits on the bottom edge, center: "T  Upgrades",
  a pulsing coin while something other than a potion is affordable, tucks away while the sheet is open). There are
  no shops, stalls or towns. Two tabs: **Hero** = the class upgrades (`Player.class_upgrades()`), then the
  `UpgradeDef.sheet == &"hero"` items (Vitality, Potion — a consumable, buyable again and again while hurt);
  **Army** = the `sheet == &"army"` items (`Player.sheet_items(tab)`): Recruit (a wide card with the army size and
  the training countdown), Soldier Damage / Soldier Health (3 levels each × +25% `ally_damage` / `ally_health`) and
  Command. A recruit trains `SOLDIER_TRAIN_TIME`, then spawns behind the player and follows (`_finish_training`,
  `soldier_ready`). New sheet item = a catalog row with `sheet` + its effect in `Player._apply_upgrade`.
- **Class upgrades** (`UpgradeDef.classes` set; in `upgrade_catalog.tres`, Hero tab): their effects are recomputed from the replicated `upgrade_levels` on every
  peer (`Player._apply_class_upgrades()`: damage, Fire Rate = shorter cooldowns + `anim_speed`, `aim_range`, `arrow_pierce`,
  `knockback_power`, `sword_wave`, `dash_damage`, `knife_damage`, the carried `weapons`); `_apply_upgrade` only refills a
  newly bought shield. Swordsman: sword_damage, sword_rate, sword_knockback / sword_wave (pick one: `UpgradeDef.excludes`),
  sword_dash (C: `Player.dash()` / `request_dash()`, predicted on the owner's client, `dash_active` replicated for the
  trail, passes through enemies), shield. Spearman: spear_damage, spear_rate, spear_throw (adds "javelin" to `weapons`),
  shield (Bull Run: planned). Bowman: bow_damage, bow_rate, bow_range (+ arrow `lifetime_scale`), bow_pierce (projectile
  `pierce`), knife (right mouse / LT / the touch shield button: `knife_attack()`, the dungeon sword scaled down as the
  knife; `KNIFE_REACH` / `KNIFE_ARC` shorter and narrower than the sword, `knife_outline()`; its orange fan shows while held, `set_knife_aim()`; no arrows while stabbing). No hero owns a shield / throw / knife / dash until bought; the Training Field grants those
  (`Player.TRAINING_UNLOCKS`) and makes class upgrades free. Tests: `grant_upgrade(id)`; `class_upgrades_test.gd`
  (`--class=`), `class_upgrades_mp_test.gd`. New class upgrade = a catalog row with `classes` + its effect in
  `_apply_class_upgrades`.
- Economy: `Player.coins`, `Player.upgrade_levels`, `buy_upgrade(def)` / `request_buy(def)`; items are `UpgradeDef`
  resources in `resources/data/upgrade_catalog.tres` (effects by `id` in `Player._apply_upgrade` /
  `_apply_class_upgrades`), all sold on the upgrades sheet; `Player.can_buy()` (also checked on the server) only
  needs coins, a living hero and a useful, not maxed item.
- **Spawn areas**: `WorldBuilder` keeps `SPAWN_SAFE_RADIUS` (14 m) around every spawn point free of trees / camps /
  chests / scatter, no camp within `spawn_camp_distance` (24 m), and puts one Uncommon starter chest at
  `spawn + STARTER_CHEST_OFFSET` (the same for every spawn). King of the Hill has one spawn area per team
  (`GameMode.world_spawn_points()` = `team_bases`).
- **Soldiers come only from recruiting** (the upgrades sheet's Army tab; camps and the Warlord's warband
  are routed — they `die()` and drop loot).
  Recruit (50, constant) → `Player.soldiers_training` (replicated count; a queue — one after another,
  `GameConfig.SOLDIER_TRAIN_TIME` each) → the server spawns an `Ally` right behind the player, which follows at once.
  `army_size()` = followers + training ≤ `follower_cap`
  (`GameConfig.BASE_FOLLOWER_CAP` 10, Command +1 per level, 100 constant, max 15). Soldiers read
  `Player.ally_damage` / `ally_health`.
- Squads come from `EnemyRoster` (`resources/data/orc_roster.tres`: filler + RosterEntry share/min_squad/max_count/
  inner_ring). New enemy type = new scene + roster entry. Camps scale orc stats and coins by `Camp.tier` (0..1).
- Targeting uses group `active_enemies` (orcs of awake camps only) — keep it that way for performance with many camps.
  World size/camp count: `GameConfig.world_half` (set from main's exports) — never hard-code the world size.
- Orc types are scenes using the same `enemy.gd` with different exports (thrower = `projectile_scene` set;
  giant = `melee_cleave`, `anim_speed` < 1, big `radius`). `Camp._squad_composition()` decides the mix.
  Melee hits one target unless `melee_cleave`. Thrown spears reuse `arrow_projectile.gd` with a different `hit_mask`.
- **Downed** (`GameConfig.downed_enabled`: every online match): `Player.die()` turns into `_go_down()`
  (`is_downed`, crawl speed, out of `player_units`). `GameConfig.is_gone()` treats downed units as gone, so AI and
  aim assist skip them. Revive = teammate within `Player.REVIVE_RANGE` for `REVIVE_TIME`. Only hostile
  player-owned damage finishes a downed player. Signals `went_down` / `revived` → main.gd (announce, Help ping).
- **Shields** (`ClassDef.shield` / `shield_health` / `shield_center`; Swordsman round 150, Spearman rectangle 200, on the
  left arm; owned only after the "shield" class upgrade, `Player.owns_shield()`): `block` action (right mouse / LT / `Hud.shield_button`) → `set_input(..., block)` / `net_input` →
  `Player.shield_up` (replicated with `shield_health`). Up: `Player._shield_blocks` soaks every hit from within
  `BLOCK_ARC` of the facing into `shield_health` (breaks at 0, back on `revive` while owned), `BLOCK_SPEED`,
  no attacks, the hero turns toward the cursor / right stick, the shield placed by `_place_shield` after each skeleton update
  (carried: upright on the forearm, face out; up: in front of the chest; blended by `_shield_raise`; both ride the
  torso bone's bob / sway; a block knocks it back via `_shield_recoil` — never re-blend the arms on a hit). Items a subclass places every
  frame return true from `Unit._places_item()` so the arm blends never tween them (Euler tweens fought the placement:
  the shield / bow flipped). `ClassDef.shield_scale` (Spearman 1.5). Block FX:
  `HitFx.block_impact` (ring, metal sparks, "Blocked"). Walks (no sprint clip) behind it. Tests: `shield_test.gd`,
  `shield_motion_test.gd`. Right mouse with a ranged weapon in hand still aims.
- **Deaths drop nothing**: weapons come from the class and coins stay.
  Clips `crawl` (moving) / `downed` (still) come from `assets/characters/animations/archer_downed.glb` (made in Blender on
  the archer armature, copied into each class model's library by `Player._add_downed_anims()`, track paths re-rooted); while downed the arm holds stay off and the sword / bow are hidden.
- **World events** (`WorldEvents`, setting `events`): `spawn_goblin()` / `spawn_warlord()` (server; tests call them
  directly). `TreasureGoblin` (NetSpawn kind `goblin`, orc team, flees), `Warlord` (extends `Enemy`, warband orcs
  have `Enemy.warlord` set and follow via `follow_point()`, its warband is routed when it falls).
- **Army orders**: `Player.army_order` / `army_point` (replicated), `command_army()` / `net_command` RPC; `Ally`
  anchors its formation to the point for CHARGE / HOLD. Orders are always obeyed: every order bumps
  `Player.order_serial` (server) and each soldier (`Ally._obey`, checked every frame) drops its target and walks to
  its new spot without fighting (`Ally._regroup`: until within `regroup_arrive` of its slot or `regroup_time`).
  KILL (key 4 / B / HUD Kill → click): `Player.kill_target_near(point)` picks the hostile at the point
  (`army_target`, replicated as `army_target_path` for the red mark in main.gd); everyone hunts it, and once it's
  gone the order becomes CHARGE where it fell; no enemy at the point → plain CHARGE. The mouse pick is on screen
  (`main._kill_pick`, models stand up); the HUD Kill button with a mouse waits for the next world click (`_kill_picking`).
- **Showcase** (`scenes/showcase/showcase.tscn`, run with F6): a world (dev only) to fly around (`FlyCamera3D`) with one station per demo. A demo = a scene extending `ShowcaseDemo` (title, description, camera view, area) instanced under `Demos`; they're laid out in a row, keys 1–9 fly to them. Demos so far: `demos/speed_race` (class running speeds). Put new demonstrations here.
- **Stats & awards**: report events with `MatchStats.add(peer, &"stat")` (server; kills / deaths / soldiers lost
  come from `Unit.die()`, damage from `HitFx.report_hit`). New award = a row in `MatchStats.AWARDS`.
- **Minimap** (`scenes/ui/minimap.gd`): shows only friends (players / soldiers not `GameConfig.is_hostile` to you),
  camps as tent badges, the hill (group `hill`, holder color). Tracked
  nodes can set meta `marker_icon` (Texture2D, drawn in a round badge) + `marker_portrait` (a face). Faces are rendered
  with `tools/render_portrait.gd` into `assets/ui/icons/portraits/` (Warlord).
- **Pings**: `main._ping()` → server `_on_ping()` (rate-limited) → teammates' `PingMarker`. Things that should get a
  screen-edge arrow + minimap diamond join group `tracked` with metas `marker_color` / `marker_label`.
- **Class balance** (measure with `tests/balance_test.gd --class=<id>`: real DPS on still orcs, crits off — rerun all three
  after any weapon / ability / upgrade change). Rule: melee hits hardest, reach costs a little damage, range costs
  more; speeds close enough that melee catches the Bowman; the three abilities deal about the same on a crowd.
  Base (150 hp each, regen 6/s): Swordsman 3.7 m/s, sword 72 dps (crowd ~3×), shield 150, Whirlwind 180 per enemy
  (~1080 on 6); Spearman 3.5 m/s, spear 68 dps with 2.6 m reach (pierces ~2), javelin ~38 dps, shield 200, Bull Rush
  4 × spear damage = 168 per enemy crossed (~1000 on 6); Bowman 3.6 m/s, bow 58 dps at 12 m, no shield, knife 44 dps,
  Bow Rain ~110 per enemy on 6 (+ it keeps shooting, ~950). Damage +20% × 5 and Fire Rate +15% × 3 are the same for
  every class (maxed ×2.9 for all). Soldiers: sword 80 hp / 12 dps, spear 80 / ~10.5 (1.45 m reach), bow 65 / ~9.6 (from
  half the hero's bow range). Orcs (before camp tier 0.75–1.35×): spearman 80/10; swordsman 95/11; thrower 55hp,
  spear 10; giant 500/26.
- Use `GameConfig.is_gone(node)` for target checks (handles freed nodes).
- AI targeting is sticky: pick targets with `Unit.choose_target(current, candidate, keep_range)` (keeps the current
  one for `TARGET_LOCK_TIME` and switches only to a much closer one). `Enemy.provoke(attacker, direct)`: squad alerts
  never retarget an orc that is already fighting; only a direct hit from a much closer attacker does.
- AI movement goes through `Unit.engage(target)` (spreads attackers around the target) and `Unit.steer(dir)`
  (avoids trees/houses with shape casts sized to the unit's `radius`, sidesteps when stuck, + separation between
  same-side units; keeps going around the same side up to 90° before switching, `STEER_ANGLES`). Use these for new AI.
  `Unit.chase_avoid_mask`: extra layers `engage()` steers around while still chasing (soldiers: enemies, so they go
  around orcs in the way). Soldiers commit to their target (`Ally._commit_target`: no switching to a closer enemy
  until it's dead or out of range) — orcs keep the sticky `choose_target` rule.
- Soldiers follow in a compact spiral formation (`Ally._update_slot`), at most `Player.follower_cap` (10–15) per player;
  archers stand in rows of five behind the hero (against its walking direction, `_heading`).
- **Soldier AI** (`scenes/characters/ally.gd`, test `tests/ally_test.gd`): targets come from `Ally._best_enemy()` (teamwork:
  enemies whose `target` is the hero count `DEFEND_BONUS` m closer, a squadmate `GUARD_BONUS`; melee soldiers add
  `CROWD_PENALTY` per squadmate on the same enemy so they spread; archers prefer the wounded and a clear line);
  melee soldiers commit (`_commit_target`) but switch to an enemy hitting the hero / a squadmate. Archers shoot from
  `archer_range()` = `ARCHER_RANGE_SHARE` (half) × their hero's `aim_range`, look out from the hero, only with a clear
  line of fire (`_clear_shot`; otherwise they walk around what blocks it) and step back from an enemy within
  `ARCHER_KEEP_AWAY` while shooting. Spear soldiers only stab (`melee_anims` "spear-stab" → `_spear_stab`: the spear
  level and straight ahead after each skeleton update, plus a `HitFx.stab` streak) — never thrown. Following: the
  server records `Player.trail` (a point every 0.8 m); a soldier whose straight way to its slot is blocked
  (`_clear_walk`) walks to the newest trail point it can reach (`_trail_point`), so it follows the hero around
  walls and buildings that local steering alone can't get out of. Speed: exactly two, run (`move_speed`) and walk (`walk_share` × it, walk clip, the last `walk_distance` m to
  the slot) — `_get_move_input` snaps every move to one of them; no catch-up / charge boost.
- Far-away camps pause their orcs (`Camp.activation_range`; downed players still count as near, only dead ones don't) — keep this for mobile performance. Orcs that are
  provoked or walking home (`Enemy.is_busy()`) stay awake. Damage calls `Unit._on_damaged(attacker)`; orcs forward it
  to `Camp.alert(attacker)`, which provokes the whole squad (tuning in `enemy.gd` → "Provoked" exports).

## Multiplayer architecture (read before changing gameplay code)

- **Server-authoritative.** The host (or the offline test peer, `OfflineMultiplayerPeer`, id 1) runs ALL gameplay: AI, damage,
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
- **Static world** (trees, chests, camps, hill) is built identically on every peer from `Net.settings.seed`
  with deterministic names; state changes go through RPCs on those nodes (`_net_*` methods, `call_local`).
- **Colors are per device, relative to the local player** (nobody picks one): `Net.color_of(peer)` (you blue,
  teammates green, enemies red), `Net.team_color(team)` / `Net.team_label(team)` ("Your team" green; enemy teams red /
  yellow / purple). Unit colors are computed in `main._spawn_unit` on every peer from `owner_peer` — never send a
  color in spawn data for players / soldiers. Server-made text (announcements, match over) names teams with
  `{team:N}` / `{label:N}` tokens that `Net.localize()` resolves on each device.
- **Teams**: `team_id` on units/camps/projectiles (`GameConfig.ORC_TEAM` = -1 for orcs). Hostility =
  `GameConfig.is_hostile(a, b)`; groups: `players`, `allies`, `player_units` (players+allies), `enemies`,
  `active_enemies`, `camps`, `units`. `owner_peer` = controlling player (kill/camp credit).
- **Input**: `main.gd` reads HUD/keyboard and calls `Player.set_input/attack_melee/shoot` on the server, or the
  `Player.net_*` RPCs from clients (validated by sender). Purchases: `Player.request_buy()`.
- **Match flow**: menu → lobby (`Net.host()` / `join()`; tests: `open_offline_lobby()`) → `Net.start_game()` loads main on
  all peers → server waits for every peer's world → spawns players. `Net.return_to_lobby()` after a match.
- **Testing multiplayer**: `-s script` runs skip autoloads (no `Net`), so use a runner scene that starts normally and
  attaches a driver Node — see `tests/` (`tests/README.md`): offline tests + host/client pairs on 127.0.0.1. Tests play a
  Swordsman unless `--class=<id>` is passed to `test_runner.tscn`. `--port=<N>` (Net.port) lets a pair run while a
  game is open on this PC; no `--fixed-fps` for pairs (headless physics then races real time and the join times out).
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
