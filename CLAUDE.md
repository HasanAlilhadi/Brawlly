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
  **Reuse existing models**: anything the game already has (the player's sword / bow / arrows, spears, shields,
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
  offset × `DESKTOP_CAMERA_ZOOM` (desktop) × `camera.zoom` = `CAMERA_ZOOM` 1.2 + `WEAPON_CAMERA_ZOOM` (bow +0.2),
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
  replace one palette hue (soldier crest h≈0.015; per class in its ClassDef: archer hat h≈0.38, human shirt h≈0.65);
  new unit types need their own key hue. Weapons in hand (under a BoneAttachment3D) are never recolored.
- In-game HUD is deliberately compact (PanelCompact / PanelInsetCompact styles) and follows the **HUD design system**:
  every size, gap and font size comes from `HudStyle` (`scenes/ui/hud_style.gd`) — no numbers in hud.gd / hud.tscn.
  `Hud._apply_design()` stacks the HUD into a left column (stats, square buttons) and a right column (minimap,
  stats, army orders); buttons have fixed sizes (`BUTTON`, `BUTTON_WIDE`). New HUD elements join a column.
  Touch sticks are hidden unless `Platform.touch_mode`.
- Groups: `player`, `friendly` (player + soldiers), `allies` (soldiers), `enemies` (orcs and undead), `warbands`,
  `bosses`, `choppable` (trees). Physics layers are in `GameConfig` (world, player, enemies, allies).
- UI uses the project theme `resources/themes/rpg_theme.tres` (built by `tools/build_rpg_theme.gd` from the Kenney RPG UI
  pack). Style new UI with its type variations instead of per-node overrides; labels on dark wood use `LabelLight`.
  Variations: `PanelBrown` (wood title ribbons), `PanelInset` (list rows), `PanelLight` (cards), `ButtonBeige`,
  `ButtonTab` (toggle tabs), `ButtonSquare`, `KeyCap` + `KeyCapLabel` (key prompts), `HeaderLabel`, `HintLabel`,
  `TitleLabel`, `ProgressBar*`. Round icon badges: `UiKit.medal(icon)` (`scenes/ui/ui_kit.gd`) — prefer the
  white Game Icon Pack glyphs in `assets/ui/icons/game/` (SVG, import `svg/scale=4`, replace `currentColor` with white
  when adding more). Input prompts: `UiKit.prompt("keyboard/w" | "mouse/left" | "xbox/rt" | "touch/tap")` from
  `assets/ui/prompts/` (Kenney Input Prompts, Double size; copy more from pre-assets when needed). Cursors: gauntlet in
  menus (Project Settings), gold sword in matches (main.gd).
- **Modes** (`Net.Mode`): `COOP`, `KING_OF_THE_HILL` and `CONQUEST` (the team modes, `Net.is_team_mode()`; Conquest is PC only), `LAST_STAND`
  (co-op, `Net.is_coop_mode()`: everyone team 0); rules in `GameMode` (`scenes/main/game_mode.gd`). Deathmatch,
  Team Deathmatch and Capture the Flag were removed (in git history before 2026-10-04) and may come back; a new
  mode = a `Net.Mode` value + MODE_NAMES / MODE_HINTS / SCORE_LIMIT_LABELS + `lobby.gd` SCORE_LIMITS + its branches
  in `GameMode` (bump `Net.GAME_ID`: older builds can't show it).
- **Conquest** (PC only; `ConquestMode` extends GameMode, `scenes/modes/conquest/`; main.gd creates it only for
  this mode, GameMode itself is untouched; test `tests/conquest_test.gd`, screenshots `tests/conquest_shots_test.gd`).
  **Its own section of the main menu**: the Conquest button opens a page (what it is; Find / Host Conquest Game →
  `Net.conquest_section`); `Net.host()` then makes a Conquest lobby (four factions, `ConquestMode.DEFAULT_TIME` /
  `DEFAULT_SCORE`, no mode choice); the classic Find / Host and their lobby offer only `Net.CLASSIC_MODES`; the
  server browser lists only the section's games (`Net.in_section`). Test `tests/conquest_menu_test.gd`.
  Demons infest the land; 4 factions (`FACTIONS`, forced in `setup()` and `Net.set_setting`) start from Citadels in
  the corners of a `WORLD_HALF` 300 (600 m) procedural map (`world_half_for()`, main.gd; designed maps keep their size
  and bases) with `BAND_FACTOR` × the lobby's warbands, and push toward the **Demon's Lair** in the middle (Kind.THRONE: walled, a `BOSS_SIZE` Vampire Lord + the
  biggest garrison). **Zones**: seven square rings (`ConquestMode.zone_of`, `ZONE_EDGES`; `TerritoryNode.zone`):
  zone 6 by the corners (Citadels, `CORNER` 0.86) down to zone 1 and the Lair (0); per zone `TerritoryNode.ZONE_*`
  rows — walls / gate health (none in zone 1: `_build_houses()` instead), production (`output()`), demon strength,
  garrison size, capture time (`capture_time()`), extra wave rows: outside strong walls, rich, weak demons; inside
  no walls, poor, strong demons. **Raids** (`ConquestMode._raid`, server timer `RAID_EVERY`): every held place but
  the Citadels, guarded or not, rolls `ZONE_RAID` (the Lair / zone 1 most, zone 6 least); `raid_place()` sends demons
  from the middle's side that walk to the place (`Enemy.follow_point` → `_raid_goal`: the gate's `outside_point()`
  while it stands); `_batter()` (server, every second) has raiders at a standing gate hit it (`TerritoryGate.batter`,
  `BATTER_DAMAGE` × power: demons can't hurt it as units), then sends them in; demons in a held ring with none of the
  holder's units and the gate down take it back (`TerritoryNode.DEMONS` capturer → `_overrun()`: INFESTED, the
  raiders are the garrison). **Guards**: a held place (not a Citadel) with none of the holder's heroes / soldiers in
  its ring counts down `TerritoryNode.ZONE_UNGUARDED` (20 s in zone 1 … 120 s in zone 6; `unguarded_left`, in
  `_net_state`, counted down on clients; `_update_guard`, server, every second; announced) → `_abandon()`: INFESTED,
  garrison when a hero comes. Label / map card ("UNGUARDED", a blinking red ring) / HUD ("N UNGUARDED") show it.
  `TerritoryNode.unguarded_falls` = false in tests that leave places alone.
  `_plan_territories()` (seed, every peer; order: Citadels 0..3, Lair 4, then Cities, Outposts, Villages spread
  over zones 1..6 by ring area, `_zone_share`; counts scale with map area): `CITIES` 40 cycling
  `TerritoryNode.Specialty` IRON (weapons) / LUMBER (arrows) / FARM (food), `OUTPOSTS`, `VILLAGES`, names from
  `NAME_FRONTS` × `NAME_BACKS`. `TerritoryNode` (`Territory_<n>`, group
  `territories`, kind rows `INFO`): INFESTED (the garrison — `WAVE_TYPES` rows + the Lair's `boss` — spawns only
  when a hero comes within `GARRISON_RANGE`: no idle demons on the big map; all dead → NEUTRAL), NEUTRAL / OWNED
  (one faction's standing units in the ring, none of the owner's, the gate broken → captured, `_net_state`).
  Cities (outside zone 1), Citadels and the Lair are walled (`_build_walls`: INFO "walls" box pieces at `radius()`, group
  `conquest_walls`, alternating heights so crossing tops never z-fight); the piece facing the map's middle is a
  `TerritoryGate` (group `breakable`; own faction can't hurt it, non-`siege` attackers deal `HAND_SHARE`; solid
  (`shut`, `_net_shut`) while held or INFESTED (the demons bar it: walled places are stormed) and standing; a held
  one opens for the holder's units while no foe is within `FOE_RANGE`). The navigation mesh is baked with the walls, without the gates (`hide_from_navigation`).
  **Supplies** (`LogisticsManager`, server tick 5 s, `_net_stock` totals + barracks to all): every held place adds
  its `output()` (kind + `SPECIALTY_OUTPUT`) to its OWN `store` (no shared stockpile; `KEY_NAMES` food / weapons =
  keys food / equipment; no arrows: bows and staffs are weapons; Iron and Lumber Cities both make weapons, zone
  output `ZONE_OUTPUT` 0.5 in zone 1 up to 2.2 in zone 6).
  Weapons wear by battle (`Ally.weapon_uses`: a battle ends `BATTLE_END` s after the soldier's last attack, then
  counts once; −`WEAR_LOSS` damage every `WEAR_STEP`, broken after `WEAPON_LIFE` = 8 → `BROKEN_POWER`); by a supply
  point a soldier worn `REARM_AT` (2) or more gets a new weapon for one weapons supply (`_rearm`); HUD "N need new
  weapons". Soldiers carry rations (`Ally.rations`, ≤ `MAX_RATIONS`, a
  recruit `START_RATIONS`): every `MEAL_TICKS` (40 ticks = 200 s) each eats one; one with none dies of hunger (10
  soldiers, 8 rations: 2 die; announced). Rations (one per soldier per tick) and new weapons come only from the supply point a soldier
  stands near (`supply_source()`: a held place with food, else a caravan with cargo, else a held place); no ration
  left → `STARVE_SPEED`. Soldiers leaving a barracks take `MUSTER_FOOD` food each from its store, an unarmed one
  also `MUSTER_EQUIPMENT` weapons (`_available` caps how many leave; spawn data "rations"). HUD: "Meal in m:ss", "N WITHOUT FOOD".
  Gates rebuild from their place's own weapons. **Gold & lords**: every place also makes gold (INFO "gold" ×
  zone) into its own `treasury` (≤ `TREASURY_CAP`); its `lord` (peer id, in `_net_state`) is the hero who took it;
  `_update_lord()` (server, every second): the lord keeps it while they or their soldiers stand in the ring, an
  unguarded place goes to the faction's hero who walks in, a lord who left the faction / game loses it. F
  (`interact`, main.gd → `Player.request_withdraw` → `ConquestMode.withdraw` → `TerritoryNode.withdraw`): the lord
  standing in the ring takes the treasury as coins (HUD line "F: take N gold"). `LogisticsManager._places()` sends
  every place's barracks (people, armed + rank per class, `train_kind`), treasury, couriers, route and store to all peers with `_net_stock` (`PLACE_FIELDS` ints
  each). **Couriers & routes**: every place has `courier_total` couriers (1, more bought on the map for
  `LogisticsManager.COURIER_COST`, ≤ `COURIER_MAX`), `couriers` of them at home, and a `route` (`ROUTE_NONE`,
  `ROUTE_ARMY` = its lord's army, or a place index). `_run_routes()` each tick sends a courier at home with a load
  (`_send_courier`: `CaravanUnit.CARGO` at most) along the route; a caravan has `home` / `dest` (spawn data): it
  delivers (`_deliver` → `LogisticsManager.unload`, store cap), walks home on the navigation mesh (`_drive_to`) and is
  a courier at home again (`courier_home`); killed → `courier_lost`. **The M map** (`ConquestMap`,
  scenes/modes/conquest/conquest_map.gd, made by main.gd `_bind_local_player` in Conquest, action `map` = M): zone
  rings, every place in its holder's color (gold ring = yours to lord), routes as arrows, couriers, you; click a place
  for its card (or a squad's shield for the squad's card); its lord / the General / anyone while it has no lord gives orders through
  `Player.request_place_action` → `ConquestMode.place_action` (withdraw — the lord, from anywhere; muster — `arg` a
  class: `MAP_TAKE` of it from that barracks, `LogisticsManager.muster_from`; train — `arg` the class its people are
  armed with or `NO_TRAINING`; route; courier). **Caravans** (`CaravanUnit`, NetSpawn kind `caravan`, "cargo", owner
  = the escorted hero; a cow with crates): ≥ `DISPATCH_MIN` of a hero's soldiers beyond every supply point →
  `_dispatch` loads one at `_best_depot` (held place within `CONVOY_RANGE` with the most goods, food counted
  double); it follows the hero and supplies soldiers within `SUPPLY_RANGE`; killed by a rival → `store(team, cargo,
  at)` into their nearest place; by demons → lost; empty / no hero → home, hands back, leaves via `die()`
  (`_retired`) — never `queue_free` a unit others may target. **Barracks** (every place, `clear_barracks()` on capture):
  `people` come in unarmed (`INFO.pool` × `ZONE_PEOPLE` every `POOL_EVERY` ticks, `growth` keeps the fraction; ≤ INFO
  `pool_cap`, a Citadel starts with `START_PEOPLE`); its commander picks a class on the map (`train_kind`,
  `TerritoryNode.SOLDIER_KINDS` sword / bow / wizard / healer): `LogisticsManager._train` arms `ARM_PER_TICK` people a
  tick with it (a weapon each from the store) into `armed[k]`; only armed ones train (`drill[k]`, average seconds,
  diluted by newcomers → `ranks[k]`); unarmed people never do. Leaving: armed ones first with
  `Ally.rank_for_drill(drill[k])`, then people armed on the spot (rank 0). The faction's **General**
  (`general_of()`: its hero with the lowest peer id) buys "Muster" (Army tab, free, `UpgradeDef.modes` [Conquest]):
  `muster()` takes up to `MUSTER_BATCH` from the nearest barracks (armed of any class first); they spawn there
  (`"muster": true` → `Ally.mustering`) and walk to the General on the navigation mesh (`_think_muster`,
  `_nav_move`), joining within `MUSTER_JOIN`; people it arms on the spot get `muster_kind()`: Iron → swordsmen,
  Lumber → archers, Farm → healers, the rest a mix. Ranks from drill: `DRILL_SECONDS`; spawn data "rank" →
  `Ally.start_rank`. **Squads** (`ConquestSquads`, scenes/modes/conquest/squads.gd, the mode's `squads`
  child; test phase 12 of conquest_test + `tests/conquest_mp_test.gd` online): the map's Take sends a squad of
  `SIZES` 4 / 8 of one class (place_action muster `arg` = class + 10 × size index; `muster_from(player, place, kind,
  size)` → `create()`; spawn data "squad" / "squad_leader", the best ranked leads). `Ally.squad` / `squad_leader`
  are in ally.tscn's Sync (the leader's banner, `_show_banner`). Squad soldiers are not in `Player.followers()`
  (`Player.soldiers()` = all; `army_size()` counts them) and ignore the hero's army orders: `_think_squad` — the
  leader walks to `goal()` on the navigation mesh, the rest follow it, then ring the goal and guard it
  (`GUARD`). Orders (`Player.request_squad_action` → `command()`: its hero or the General): go (a place; there it
  becomes HOLD), hold (a point), join (`_join`: they muster back to the hero). A fallen leader → the best ranked
  left leads (`_check`, server, every second; also `_net_squads` to every peer). The M map draws them as shields at
  their leader (count inside, yours outlined, a dashed line to the goal) with their own card. Held places raise every faction hero's army cap (`INFO.cap`, added to
  the replicated `follower_cap` as a change only, ≤ `CAP_BONUS_MAX` 30: max army 80 — measured headless, a soldier
  costs the host ~0.15 ms a frame, a paused warband ~0.1 ms) and score points (the Lair 25 a tick). **Ranks**
  (`Ally.progression`, every mode): `Unit.take_damage` calls `attacker.credit_kill()` on a killing blow;
  `RANK_KILLS` 2 / 5 / 10 / 20 → ranks I–IV (`RANK_NAMES`), each +`RANK_BONUS` 15% health and damage
  (`refresh_army_bonus`); `rank` is in ally.tscn's Sync (badge Label3D + sparkle). **Siege engines** (`SiegeEngine`,
  NetSpawn kind `siege`, "engine" ram / catapult; primitive placeholder models): Army tab (`siege_ram` 120,
  `siege_catapult` 180, Conquest only, one of each in the field); group `siege` + `player_units`; they trail their
  hero on the navigation mesh (`_drive_to`); target = the gate of the walled place the hero's army order points at
  (within `ORDER_REACH` of its ring, any distance: `_ordered_gate`), else the nearest within `seek` — a rival's or
  an infested one; the ram rams it (`_net_ram`), the catapult lobs boulders from `reach`
  (`_net_boulder`, splash on hostile units). Win: hold the Lair `THRONE_WIN_TICKS` (60 = 5 min) in a row
  (`on_logistics_tick`), every Citadel, the score limit (lobby 500–6000, default 2500), or lead at the time limit
  (lobby default `CONQUEST_TIME` 45 min). HUD: `score_text()` = the score line, "F: take N gold" and the Lair's
  holder; everything else is in **`ConquestPanel`** (scenes/modes/conquest/conquest_panel.gd, made by main.gd with
  the map, in `Hud.left_column`): the hero (weapon, level, kills to the next), the faction's food / weapons / gold
  (treasuries) / people (barracks) with "+in −out a minute", status lines (General, cap bonus, next meal) and red
  warnings (hungry, worn weapons, unguarded). Hovering a row (a tap on touch) opens a card beside it: where it comes
  from and where it goes. The numbers come from `LogisticsManager.note(team, key, reason, amount)` (+ in, − out;
  moves between a faction's own places / caravans are not noted), kept for the last `FLOW_TICKS` (12 = a minute)
  and sent per minute as the stock entry's "flow" ({key: {"in": {reason: n}, "out": {reason: n}}}); a new spending
  = a `note()` where it happens. **Heroes have no class in Conquest** (`Player.classless`, spawn data; the lobby
  hides the class picker): they spawn as `Player.START_CLASS` (Unarmed: fists, `WEAPONS.fists` `power` 0.35 of the
  sword) and buy a weapon on the Hero tab (`UpgradeDef.sheet == &"weapon"`: `arm_sword` / `arm_bow` 30,
  `arm_wizard` / `arm_healer` 45 coins; `Player.ARM_CLASSES` → the Conquest-only ClassDefs `unarmed`, `wizard`
  (`staff`: magic bolts), `healer` (`heal_staff`: heals the most wounded friend within `heal_radius` of the aim
  point, else a weak bolt), plus swordsman / bowman; `ClassDef.conquest_only`, never in `ClassDef.pickable()`).
  Buying one = `main.rearm_player()` (server): the old hero leaves, a new one of that class spawns at the same
  spot and takes `Player.carry_state()` (coins, health share, Vitality / army upgrades, army cap, training queue,
  orders, trail); its level and weapon (class) upgrades start over. Soldiers, squads, lords and the General go by
  peer id, so they stay; main.gd forgets a local hero that leaves the tree until the new one binds. **Levels**:
  `Player.credit_kill()` (from `Unit.take_damage`; not animals; a healer's `HEALS_PER_KILL` heals = one) → `hero_kills`
  / `hero_level` (replicated) at `LEVEL_KILLS` (10 levels), each +`LEVEL_BONUS` 8% of the base health (healed) and
  damage / healing (`_apply_class_upgrades`); the name label shows "Lv N". Test `tests/conquest_hero_test.gd`.
- **Last Stand** (`GameMode`, test `tests/last_stand_test.gd` + `--defeat`, online `tests/last_stand_mp_test.gd`):
  a procedural world is `main.LAST_STAND_WORLD_SCALE` (1.15×) bigger; `GameMode._plan_circles()` plans `CIRCLE_COUNT`
  (10) circles from the seed (every peer knows them; WorldBuilder keeps `world_clear_radius()` around each and puts
  a gold vein inside each edge, `world_vein_spots()`; warbands may roam near them: `bands_avoid_clear_areas`), each
  farther out; a designed map brings its own (`MapDef.hold_circles`). One `HoldCircle` node (scenes/world/
  hold_circle.gd, groups `hold_circles` + `tracked`) moves from circle to circle. Server: the clock
  (`circle_time` → `circle_seconds`, 60) runs only while ≥ `circle_required` standing heroes are inside; outside it
  pauses and keeps its progress. `circle_required` = a rolled share of the heroes still alive (`living_players()`:
  not dead; downed count) — about half on the first circle up to all on the last — clamped to those alive.
  State reaches every peer by `_net_circle` (clients run the clock between updates). A held circle pays every
  living hero `CIRCLE_REWARD` + `CIRCLE_REWARD_STEP` × index coins and raises `GameConfig.orc_strength` (base ×
  `circle_strength(i)` = 1 + 0.12 i) for everything spawned after; while a standing hero is within
  `ASSAULT_ENGAGE_RANGE`, `_send_assault()` sends squads (`wave_enemy`: hunt the nearest player, capped)
  from out of sight, drawn from `WorldEvents.WAVE_TYPES` (one more row every `ASSAULT_ROW_EVERY` circles); the last
  circle spawns the Warlord's warband (`WorldEvents.spawn_warlord`). Border waves are off (main drops "waves" from
  the events list). No respawns (`uses_respawn()` false): main `_on_player_died` → `on_player_fell`;
  a downed hero with nobody standing to revive them (`_check_wipe`) dies at once; nobody left = Defeat, all ten
  held = Victory. A fallen local hero spectates (`main._update_spectating` / `_spectate_next`: attack / switch
  weapon / click / tap = next teammate; `Hud.show_spectating`). HUD: `Hud._objective_panel` (top center, sizes in
  `HudStyle.OBJECTIVE_*`) reads `GameMode` every frame (`set_objective_source`); minimap draws the circle + its
  held share.
- Flow: `main_menu.tscn` (run scene) → Find Game (`server_browser.tscn`) or Host Game (`host_menu.tscn`) — or the
  Conquest page's Find / Host Conquest Game (same scenes, `Net.conquest_section`) → lobby →
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
  sword) and Bowman (`archer.glb`, bow) — `ClassDef.pickable()`; Unarmed / Wizard / Healer are Conquest-only
  (bought as weapons there, see Conquest). Picked with
  `ClassPicker` (lobby only, with an `ArmyPreview`) → `Net.set_class()` → profile `class` + `Net.players[peer].class` → spawn data
  `class` → `Player.set_class()` (every peer, before entering the tree: swaps the Model, sets `weapons`, hand items,
  recolor hue, `hand_offset`). Soldiers come in four kinds, each its own Army-tab recruit card (`Player.RECRUIT_WEAPONS`: `recruit` sword,
  `recruit_bow`, `recruit_wizard`, `recruit_healer`; queued kinds in `Player._training_kinds`, server) →
  `Ally.weapon` from spawn data, `Ally.WEAPON_STATS`; bow / wizard / healer are `is_ranged()` (back rows, keep away):
  archers shoot arrows from `Ally.archer_range()`, wizards `magic_bolt`s from `WIZARD_RANGE_SHARE` of it, healers never
  fight and heal the most wounded friend within `HEAL_SIGHT` (`_find_patient` / `_heal_move`). `ClassDef.ally_weapon`
  is only the lobby preview now. **Ranks** in every mode
  (`Ally.progression`): kills (a healer: every `HEALS_PER_KILL` heals) → `RANK_KILLS` ranks I–IV, +`RANK_BONUS` each. A class is locked to its weapons; nothing has ammo.
- Anything damageable implements `take_damage(amount, attacker = null, is_melee = true)`.
- **Weapons**: `Player.WEAPONS` rows (melee: `arc` / `reach` / `cooldown`): sword (melee 36 / 0.5 s, 80° wedge, cleaves),
  bow (arrows 22, 0.4 s). No ammo anywhere (no ammo pickups, shop items or counters).
  Weapon damage / speed / range come only from the class upgrades (below).
  Chests are broken open by any weapon (group `breakable`, 60 hp), not opened by walking up. Shots fly at 0.55–0.7 m, so
  anything hittable needs collision up to `GameConfig.HIT_HEIGHT` (1 m); aimed shots fly exactly where aimed (no snapping); a quick shot / tap with no aim auto-targets the nearest enemy. Melee hits exactly the aim marker (`Player.melee_outline()` → `_melee_query` prism + `_melee_indicator`: a `melee_arc()` fan out to `melee_reach()`), aimed where the swing started (`Unit._melee_dir`); other units keep the sphere in `Unit._melee_query`. The player carries `Player.weapons` (from the class) and holds one
  (`weapon_index`, replicated); `switch_weapon()` (server; E / Y / HUD button via `request_switch_weapon`; no class carries two
  weapons right now, so it does nothing and the touch switch button stays hidden). Melee / shoot
  functions refuse the weapon not in hand; attack keys and left mouse use the one in hand. The sword slash
  (`_sword_slash`) is procedural; other units use clips. The Bowman's bow is placed upright in the body's frame after
  every skeleton update (`Player._place_bow`, `BOW_*` constants) with an arrow nocked (`NOCK_POSITION`): a shot
  leaves from that arrow toward the aim line `aim_range` ahead, and the next arrow is nocked after the cooldown.
  New weapon = a `WEAPONS` row + its model in `_weapon_items` + an icon in `Hud._weapon_icons` + a class that carries it.
- **Special abilities** (X / R3 / touch ability button, action `ability`): enemies drop XP orbs (`Pickup.Kind.XP`,
  `Enemy.xp_drop()`: `xp_value` or max_health × `Enemy.XP_PER_HEALTH`, split into orbs of ≤ `XP_ORB`); `Player.xp`
  (replicated) fills up to `ClassDef.ability_xp` (10) and `use_ability()` (server; `request_ability()`) spends it.
  Ability per class in its ClassDef (`ability` id, `ability_name`, `ability_icon`, `ability_duration`); `ability_active`
  is replicated, `_apply_ability()` shows it on every peer. Swordsman `whirlwind`: spins (`_whirlwind_pose`, skeleton
  turned by `_spin_angle`), hits everything within `WHIRLWIND_RADIUS` every `WHIRLWIND_TICK`, slower, no attack / block.
  Bowman `bow_rain`:
  X enters local cursor placement; LMB confirms a server-clamped target, then server-spawned arrows fall throughout
  the replicated circular ground marker for the ability duration. All 100 arrows fall from above to random points inside the
  marker; they do not track targets. Arrows fall one by one, with jittered angle/radius strata in each
  10-arrow run so the whole circle fills evenly. Bowman keeps normal bow aim and shooting during the rain.
  Each peer draws a brief entry flash and local hit burst for rain arrows;
  only the server applies projectile damage.
  New ability = ClassDef fields + a branch in `_update_ability` / `_apply_ability`. Test: `tests/ability_test.gd`.
- **VFX**: `HitFx.flash(at, texture, color, size, …)` pops a billboard sprite from `assets/vfx/particles/` (Kenney Particle Pack;
  additive, or `additive = false` for smoke). Used for hit sparks, death smoke, combo ring, revive sparkle. Enemy telegraphs: `HitFx.ground_warning()` (a disc filling a ring: when full, the attack lands), `lane_warning()` (a charge), `shockwave()`. Ground
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
  trail, passes through enemies), shield. Bowman: bow_damage, bow_rate, bow_range (+ arrow `lifetime_scale`), bow_pierce (projectile
  `pierce`), knife (right mouse / LT / the touch shield button: `knife_attack()`, the dungeon sword scaled down as the
  knife; `KNIFE_REACH` / `KNIFE_ARC` shorter and narrower than the sword, `knife_outline()`; its orange fan shows while held, `set_knife_aim()`; no arrows while stabbing). No hero owns a shield / knife / dash until bought; the Training Field grants those
  (`Player.TRAINING_UNLOCKS`) and makes class upgrades free. Tests: `grant_upgrade(id)`; `class_upgrades_test.gd`
  (`--class=`), `class_upgrades_mp_test.gd`. New class upgrade = a catalog row with `classes` + its effect in
  `_apply_class_upgrades`.
- Economy: `Player.coins`, `Player.upgrade_levels`, `buy_upgrade(def)` / `request_buy(def)`; items are `UpgradeDef`
  resources in `resources/data/upgrade_catalog.tres` (effects by `id` in `Player._apply_upgrade` /
  `_apply_class_upgrades`), all sold on the upgrades sheet; `Player.can_buy()` (also checked on the server) only
  needs coins, a living hero and a useful, not maxed item.
- **Gold veins** (`GoldVein`, scenes/world/gold_vein.gd/.tscn, model `tools/blender_gold_vein.py` → assets/
  environment/gold/: a rock + separate crystals that shrink as it is mined): the steady coin source on every map
  and mode. Group `breakable` (any weapon hits it) + `gold_veins` (minimap gold dots). Every hit (≥ `HIT_COOLDOWN`
  apart) drops `COINS_PER_HIT` coins (+1 on a crit) as a pickup until `MAX_GOLD` is mined; after `REGROW_DELAY`
  it grows back `REGROW_STEP` per `REGROW_EVERY`; state by `_net_gold` (static world node). One at every spawn
  (`WorldBuilder.STARTER_VEIN_OFFSET`, the same for every team), one in every Last Stand circle, ~14 per
  reference area elsewhere on procedural maps, `MapDef.vein_spots` on designed ones (moved clear of the layout's
  boxes: `WorldBuilder._clear_of`). Award "Gold Digger" (`MatchStats` stat `mined`).
- **Spawn areas**: `WorldBuilder` keeps `SPAWN_SAFE_RADIUS` (14 m) around every spawn point free of trees / warbands /
  chests / scatter, no warband starts or marches within `spawn_band_distance` (24 m), and puts one Uncommon starter chest at
  `spawn + STARTER_CHEST_OFFSET` (the same for every spawn). King of the Hill has one spawn area per team
  (`GameMode.world_spawn_points()` = `team_bases`).
- **Soldiers come only from recruiting** (the upgrades sheet's Army tab; a band whose boss falls is routed —
  they `die()` and drop loot).
  Recruit (10, constant) → `Player.soldiers_training` (replicated count; a queue — one after another,
  `GameConfig.SOLDIER_TRAIN_TIME` (5 s) each) → the server spawns an `Ally` right behind the player, which follows at once.
  `army_size()` = followers + training ≤ `follower_cap`
  (`GameConfig.BASE_FOLLOWER_CAP` 30, Command +5 per level, 100 constant, 4 levels: max 50; keep it there —
  a host simulating 100 soldiers spent ~13 ms a frame on them, measured headless). Soldiers read
  `Player.ally_damage` / `ally_health`.
- **Warbands** (`Warband`, scenes/world/warband.gd; they replaced the camps — none left): roaming groups whose
  **size is their power**. `WorldBuilder._add_warbands()` places `band_count` (lobby "Warbands", setting
  `band_count`) of them: 3 members near the spawns up to 24 far away (`_band_size_at`), `tier` = size share → stats
  0.8–1.3× (× difficulty); the undead around graveyards (one marches out of each graveyard gate), orcs elsewhere.
  What a band is made of: `EnemyRoster` (`resources/data/orc_warband.tres`, `undead_warband.tres`: `filler` +
  RosterEntry share / min_squad / max_count / `leader` (bosses, 18+) / `rear` (ranged)) → `Warband._compose()`
  (runs on every peer, so `has_boss` is known everywhere). Formation (`_formation()`, +Z = marching direction):
  leader in the middle, melee in a blob, ranged in rows behind. The band (a Node3D: its position is the
  anchor) walks between open waypoints of its `territory` (prefers a clear path, `_path_clear`), rests, goes on;
  members `follow_point()` their slot at the band's walking pace, carrying the band's velocity (`Enemy.drift`:
  they walk along with it, no stop-go at the slot). One member spots or is hit by a foe →
  `band.alert()` → everyone hunts (FIGHT; `_coordinate()` each second: at most `MAX_ON_ONE` plain melee members on
  one foe, the rest take the next foe near; those on one foe get evenly spaced `_slot_angle`s around it —
  they surround it); 2.5 s after the fight it regroups where they stand. Members stuck
  behind something for 4 s → regroup + another waypoint. Fallen members respawn one by one only while the band
  is calm and unseen; all dead → `defeated` (co-op is won when every band is). A boss's death routs its band
  (`BossTrait` → `Warband.rout()`). Event bands (`replicated` = false, server only): `quarry` (marches on a
  player), `leader_scene`, `reinforce_interval`, `strength_override`, `track_leader` — the Warlord event.
  Clients get position / alive via `_net_state` (0.5 s) and the defeat by RPC. **Nothing floats over a band**;
  only bands with ≥ `Warband.LARGE_SIZE` (10) alive show on the minimap.
- **Enemies are built by composition** (`Enemy`, scenes/characters/enemy.gd + child components from
  `scripts/enemies/`; every scene in `scenes/characters/enemies/`): one `EnemyMovement` (ChaseMovement
  [`shoulders_through`], KiteMovement, FlankMovement, ShambleMovement, FloatMovement, StalkMovement), `EnemyAction`s
  tried by `priority` each frame — attacks (MeleeAttack: the Unit melee_* exports; ProjectileAttack: `projectile`
  kind spear / enemy_arrow / bolt / blood_bolt, lead, volley) and abilities (ChargeAbility, StompAbility,
  BlinkAbility, SummonAbility [cooldown and/or `health_thresholds`], PhaseAbility) — and traits (LifeStealTrait,
  ReassembleTrait, DeathBurstTrait, EnrageTrait, BossTrait, RecolorTrait). Hooks (`EnemyComponent`): `server_tick`,
  `blocks_hit`, `blocks_attacks`, `on_damaged`, `on_hit_dealt`, `prevents_death`, `on_died`, `on_death_visuals`
  (every peer), `show_fx` (every peer, sent with `enemy.fx(self, event, at, value)`); `enemy.shout(text)` for a
  battle cry. Damage scales with `power()` (spawn "strength"). Collapsed skeletons are `is_downed` (AI ignores
  them, a hit finishes them). `prefers_weak` (skeleton warriors, vampires): they pick the most wounded foe near
  (`find_weakest`). KiteMovement steps sideways to a spot with a clear line of fire when the shot is blocked. Graveyard Kit models are rigid (no Skeleton3D): hand items ride the `arm-right` node
  in the swing grip (`Unit._attach_rigid_item`), no holding poses. Types: Orc Grunt (melee), Orc Spear Thrower
  (kites, spears), Orc Brute (elite: charge, stomp, enrage), Skeleton Warrior (flanks, reassembles once),
  Skeleton Archer (kites, arrows), Zombie (shambles, lunges, bursts on death), Ghost (floats through walls, phases
  through hits), Vampire (elite: stalks, blinks behind you, life steal), Necromancer (elite: kites, bolts, raises
  skeletons), and the bosses Orc Warlord (charge, stomp, rally at half health, enrage) and Vampire Lord (stalks,
  blinks, blood-bolt volleys, raises the dead at 66 / 33 %, life steal, enrage). **New enemy type** = a scene in
  scenes/characters/enemies/ (Unit exports + components; copy one) + a RosterEntry. **New behavior** = a component
  in scripts/enemies/. Test: `tests/enemy_test.gd`.
- Targeting uses group `active_enemies` (members of awake bands only) — keep it that way for performance.
  World size: `GameConfig.world_half` (from the band count) — never hard-code the world size.
- **Graveyards** (`WorldBuilder._add_graveyards()`, one per ~6 bands, 1..5): Graveyard Kit pieces (`GRAVEYARD_SCALE`
  1.5) — iron fence square (gate gap +Z, one fallen gap), gravestone rows with mounds / pumpkins / candles, a crypt
  between obelisks, lightposts at the gate, crooked pines outside, a dark earth disc; solid pieces get box collision
  (`_graveyard_piece(solid = true)`, at least `HIT_HEIGHT` tall).
- **Downed** (`GameConfig.downed_enabled`: every online match; Last Stand: bleeding out is final): `Player.die()` turns into `_go_down()`
  (`is_downed`, crawl speed, out of `player_units`). `GameConfig.is_gone()` treats downed units as gone, so AI and
  aim assist skip them. Revive = teammate within `Player.REVIVE_RANGE` for `REVIVE_TIME`. Only hostile
  player-owned damage finishes a downed player. Signals `went_down` / `revived` → main.gd (announce, Help ping).
- **Animation clips** (Unit `_play_locomotion`): idle / walk / sprint only switch once the new clip has been wanted
  for `_locomotion_settle()` (0.18 s; players 0) — AI hovering at a threshold never flickers. Health set while
  spawning isn't a hit (`_spawned`): no squash (it used to leave units below 100 hp at the wrong size).
- **X-ray**: heroes (`Unit.enable_xray()`, from Player._ready) show a flat silhouette in their color where walls /
  cover hide them from the angled camera (`assets/shaders/xray_silhouette.gdshader`, the next pass of the hit-flash
  overlay; the overlay writes stencil 1 so the silhouette never tints the hero's own body).
- **Shields** (`ClassDef.shield` / `shield_health` / `shield_center`; Swordsman round 150, on the
  left arm; owned only after the "shield" class upgrade, `Player.owns_shield()`): `block` action (right mouse / LT / `Hud.shield_button`) → `set_input(..., block)` / `net_input` →
  `Player.shield_up` (replicated with `shield_health`). Up: `Player._shield_blocks` soaks every hit from within
  `BLOCK_ARC` of the facing into `shield_health` (breaks at 0, back on `revive` while owned), `BLOCK_SPEED`,
  no attacks, the hero turns toward the cursor / right stick, the shield placed by `_place_shield` after each skeleton update
  (carried: upright on the forearm, face out; up: in front of the chest; blended by `_shield_raise`; both ride the
  torso bone's bob / sway; a block knocks it back via `_shield_recoil` — never re-blend the arms on a hit). Items a subclass places every
  frame return true from `Unit._places_item()` so the arm blends never tween them (Euler tweens fought the placement:
  the shield / bow flipped). `ClassDef.shield_scale` (1 for the Swordsman's round shield). Block FX:
  `HitFx.block_impact` (ring, metal sparks, "Blocked"). Walks (no sprint clip) behind it. Tests: `shield_test.gd`,
  `shield_motion_test.gd`. Right mouse with a ranged weapon in hand still aims.
- **Deaths drop nothing**: weapons come from the class and coins stay.
  Clips `crawl` (moving) / `downed` (still) come from `assets/characters/animations/archer_downed.glb` (made in Blender on
  the archer armature, copied into each class model's library by `Player._add_downed_anims()`, track paths re-rooted); while downed the arm holds stay off and the sword / bow are hidden.
- **Animals** (`Animal`, scenes/characters/animal.gd/.tscn, NetSpawn kind `animal` with "species" + "home"; test
  `tests/animal_test.gd`): Kenney Cube Pets from `assets/characters/pets/` (clips idle / walk / run / eat), team
  `GameConfig.ANIMAL_TEAM` (-2: heroes and soldiers can hit them, orcs and animals ignore each other — `is_hostile`),
  layer enemies, group `animals`. Species rows in `Animal.SPECIES` (model, temper, health, walk / run speed, scale,
  radius); `set_species()` on every peer before entering the tree puts the pet in a scaled "Model" holder (some clips
  key the pet root's scale) and sets health then (Unit._ready lowering it from 100 would play the hit squash). Shy
  (pig, cow, deer, fox): graze around `home` (walk, eat), run from heroes / soldiers within `FLEE_RANGE` or who hit
  them, the herd bolts together (`alarm`). Wild (hog): anyone within `AGGRO_RANGE` or who hits it → wind-up, a
  straight `CHARGE_SPEED` dash that rams the first hero / soldier (`damage`, `Unit.shove()` — pushes even heroes,
  whose knockback_taken is 0; the owner's predicting client gets it by RPC), rest, again until `CALM_TIME` after the
  target got away; while angry it is in `active_enemies` and its `target` is set, so soldiers defend against it.
  Deaths drop `COINS_MIN`..`COINS_MAX` (3..8) coins and a health potion `HEALTH_DROP_CHANCE` (20%). Far from every
  hero (`SLEEP_RANGE`) they stand still. **Herds** (`AnimalHerd`, scenes/world/animal_herd.gd, group `herds`):
  `WorldBuilder._add_herds()` places `herd_count` (16) of them, species in turn, away from spawns (wild pigs twice
  as far) and warbands; main starts them with the warbands; a wiped-out herd comes back `RESPAWN_TIME` later when no
  hero is within `RESPAWN_CLEAR`. New species = a `SPECIES` row + `AnimalHerd.SIZES`.
- **Maps** (`MapDef` in `resources/data/maps/`, listed in `map_catalog.tres`; lobby "Map", setting `map` = the
  id; **every map is playable in every mode** — keep `MapDef.modes` empty; test `tests/maps_test.gd` = every map ×
  every mode, screenshots `tests/map_shots_test.gd`): **Wildlands** (procedural forest, rock outcrops), **Gravemoor**
  (procedural: Graveyard Kit pines, misty dusk light, `graveyard_share` 2.5 → many graveyards, mostly undead),
  **Sunstone Ruins** (procedural: sand, Mini Arena ruined courtyards + colonnades, few graveyards, orc country) and
  **Crown Ruins** (designed). A procedural map is looks + landmarks: MapDef "Look" (sky / ambient / sun / fog,
  minimap color → `main._apply_map`, which the Weather blends from) and "Procedural" (tree models / density / scale,
  border model / step / offset, decor list, `landmarks` → `WorldBuilder._add_outcrops` / `_add_ruins`,
  `graveyard_share`, `graveyard_ground`, `stray_undead`); landmarks only go where `_is_free()` (spawns, objectives,
  wave gates stay clear). Repeated landmark models go through `WorldBuilder._batch()` (chunked MultiMeshes) with
  plain collision from `_solid_box` / `_solid_cylinder` / `_run()` (one box per unbroken wall stretch; bodies named
  `Solid_<n>`); counts scale with the world's area (`_area_scale()`). New procedural map = a MapDef .tres (+ a
  landmark builder for a new kind of landmark).
  A designed map = `layout` scene built by `tools/build_map_<id>.gd` (`-s`, from
  `KitProps.place()` kit pieces with box collision; editable in the editor, rebuild to regenerate) with a `Markers`
  node: `TeamBase_<n>`, `Band_<x>` (metas size / faction / territory), `Chest_<x>` (rarity), `Tree_<x>`, `Herd_<x>` (species; every map has animals), `Hill`;
  `WorldBuilder._build_layout()` fills them; MapDef also holds `world_half`, `team_bases` (GameMode uses them; co-op
  modes spawn at the first), `wave_entries`, `ground_color`, and for every mode to work: `hold_circles` (the ten
  Last Stand circles, in order; heroes need room to stand in each) and `vein_spots`. Units always stand at y = 0:
  maps make "height" with walls and cover, no ramps.
  Crown Ruins design rules (keep them when editing): rotational symmetry (any team count is fair), the hill =
  arena with rim columns + center statue, inner ring with 4 wide lane doors + 4 narrow flank gaps, bases with a
  front cover wall and two side exits, shrines (Rare chest + undead band) on the diagonals, groves (trees, rocks,
  Common chests) as flank routes; base → hill ≈ 11 s. Test: `tests/map_events_test.gd`.
- **World events** (`WorldEvents`, setting `events` = a list of ids, one lobby toggle each; `WorldEvents.EVENTS`
  rows [id, name, hint, icon]; old true / false still read by `ids_from_setting`): goblin, warlord, waves,
  meteors (`start_meteor_shower()` / `drop_meteor()`: ring → impact hurts every unit, star shards), storm
  (`start_storm()` / `strike_lightning()`: rain + darkness + lightning), blood_moon (`start_blood_moon()`:
  `GameConfig.blood_moon` → enemies `BLOOD_MOON_SPEED` / `_DAMAGE`, ×2 loot), supply_drop (`drop_supplies()`: a
  Legendary `SupplyDrop_<n>` chest made on every peer by RPC, by the hill in KotH, tracked). Visuals: `Weather`
  (scenes/main/weather.gd, every peer: light blends, rain particles, bolts, meteors, scorch marks, parachute
  crate). New event = an EVENTS row + its timer in `_process` + a `start_*` function. `spawn_goblin()` /
  `spawn_warlord()` (server; tests call them directly). `TreasureGoblin` (NetSpawn kind `goblin`, orc team, flees); the Orc Warlord event = a server-only
  `Warband` (`warlord_band`, its leader `warlord` = orc_warlord.tscn, tracked on the minimap) that marches on a player
  and grows on the way; routed when the Warlord falls. Waves: `WAVE_TYPES` rows join wave by wave.
- **Army orders**: `Player.army_order` / `army_point` (replicated), `command_army()` / `net_command` RPC; `Ally`
  anchors its formation to the point for CHARGE / HOLD. Orders are always obeyed: every order bumps
  `Player.order_serial` (server) and each soldier (`Ally._obey`, checked every frame) drops its target and walks to
  its new spot without fighting (`Ally._regroup`: until within `regroup_arrive` of its slot or `regroup_time`).
  KILL (key 4 / B / HUD Kill → click): `Player.kill_target_near(point)` picks the hostile at the point
  (`army_target`, replicated as `army_target_path` for the red mark in main.gd); everyone hunts it, and once it's
  gone the order becomes CHARGE where it fell; no enemy at the point → plain CHARGE. The mouse pick is on screen
  (`main._kill_pick`, models stand up); the HUD Kill button with a mouse waits for the next world click (`_kill_picking`).
  MARCH (Conquest only: key 5 `army_march` / HUD March, no gamepad button yet): `Player.march_point()` = the
  territory nearest the cursor, any distance (no territories → main ignores the key). Soldiers get a
  NavigationAgent3D on their first march (`Ally._think_march` / `_march_move`; straight line while there is no
  path), fight only within `aggro_range` on the way, then patrol a `PATROL_RADIUS` ring and guard `MARCH_GUARD`.
  The navigation mesh is baked by `ConquestMode._bake_navigation()` (server, async, gates hidden; static
  colliders on world / fence layers + a double-sided ground quad — a one-sided one left the ground unwalkable).
- **Showcase** (`scenes/showcase/showcase.tscn`, run with F6): a world (dev only) to fly around (`FlyCamera3D`) with one station per demo. A demo = a scene extending `ShowcaseDemo` (title, description, camera view, area) instanced under `Demos`; they're laid out in a row, keys 1–9 fly to them. Demos so far: `demos/speed_race` (class running speeds). Put new demonstrations here.
- **Stats & awards**: report events with `MatchStats.add(peer, &"stat")` (server; kills / deaths / soldiers lost
  come from `Unit.die()`, damage from `HitFx.report_hit`). New award = a row in `MatchStats.AWARDS`.
- **Minimap** (`scenes/ui/minimap.gd`): shows only friends (players / soldiers not `GameConfig.is_hostile` to you),
  large warbands (≥ 10 alive: skull = undead, axe = orcs, a pulsing ring when a boss leads it; small ones never
  show), the hill (group `hill`, holder color). Tracked
  nodes can set meta `marker_icon` (Texture2D, drawn in a round badge) + `marker_portrait` (a face). Faces are rendered
  with `tools/render_portrait.gd` into `assets/ui/icons/portraits/` (Warlord).
- **Pings**: `main._ping()` → server `_on_ping()` (rate-limited) → teammates' `PingMarker`. Things that should get a
  screen-edge arrow + minimap diamond join group `tracked` with metas `marker_color` / `marker_label`.
- **Class balance** (measure with `tests/balance_test.gd --class=<id>`: real DPS on still orcs, crits off — rerun both
  after any weapon / ability / upgrade change). Rule: melee hits hardest, reach costs a little damage, range costs
  more; speeds close enough that melee catches the Bowman; both abilities deal about the same on a crowd.
  Base (150 hp each, regen 6/s): Swordsman 3.7 m/s, sword 72 dps (crowd ~3×), shield 150, Whirlwind 180 per enemy
  (~1080 on 6); Bowman 3.5 m/s, bow 58 dps at 12 m, no shield, knife 44 dps,
  Bow Rain ~110 per enemy on 6 (+ it keeps shooting, ~950). Damage +20% × 5 and Fire Rate +15% × 3 are the same for
  every class (maxed ×2.9 for all). Soldiers (× `Ally.BASE_POWER` 1.25 health and damage): sword 100 hp / 15 dps, bow 81 / ~12 (from
  half the hero's bow range). Enemies (hp / damage, before the band's 0.8–1.3× and difficulty): Orc Grunt 80/10;
  Thrower 55, spear 10; Brute 420/24 cleave (stomp 26, charge 28); Skeleton Warrior 60/9 (gets up once at 50%);
  Skeleton Archer 45, arrow 9; Zombie 130/14 (lunge 16, burst 16); Ghost 50/9; Vampire 170/15 (60% life steal);
  Necromancer 90, bolt 12; Vampire Lord 1400/30; Orc Warlord 1800/36.
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
- Soldiers follow in a compact spiral formation (`Ally._update_slot`), at most `Player.follower_cap` (30–50) per player;
  archers stand in rows of five behind the hero (against its walking direction, `_heading`).
- **Soldier AI** (`scenes/characters/ally.gd`, test `tests/ally_test.gd`): targets come from `Ally._best_enemy()` (teamwork:
  enemies whose `target` is the hero count `DEFEND_BONUS` m closer, a squadmate `GUARD_BONUS`; melee soldiers add
  `CROWD_PENALTY` per squadmate on the same enemy so they spread; archers prefer the wounded and a clear line);
  melee soldiers commit (`_commit_target`) but switch to an enemy hitting the hero / a squadmate. Archers shoot from
  `archer_range()` = `ARCHER_RANGE_SHARE` (half) × their hero's `aim_range`, look out from the hero, only with a clear
  line of fire (`_clear_shot`; otherwise they walk around what blocks it) and step back from an enemy within
  `ARCHER_KEEP_AWAY` while shooting. Following: the
  server records `Player.trail` (a point every 0.8 m); a soldier whose straight way to its slot is blocked
  (`_clear_walk`) walks to the newest trail point it can reach (`_trail_point`), so it follows the hero around
  walls and buildings that local steering alone can't get out of. Speed: exactly two, run (`move_speed`) and walk (`walk_share` × it, walk clip, the last `walk_distance` m to
  the slot) — `_get_move_input` snaps every move to one of them; no catch-up / charge boost. Exception: following
  a hero who is moving, a soldier near its slot keeps pace (`_match_pace`: the hero's speed + a little per m behind,
  never past its own run) — otherwise it flips run / walk at the slot's edge and stutters behind.
- Far-away bands pause their members (`Warband.activation_range`; downed players still count as near, only dead ones
  don't) — keep this for mobile performance; a paused band keeps walking and moves its members along
  (`_snap_members`, no simulation). Members that are provoked or walking back (`Enemy.is_busy()`) stay awake. Damage
  calls `Unit._on_damaged(attacker)`; enemies forward it to `Warband.alert(attacker)`, which provokes the whole band
  (tuning in `enemy.gd` → "Provoked" exports).

## Multiplayer architecture (read before changing gameplay code)

- **Server-authoritative.** The host (or the offline test peer, `OfflineMultiplayerPeer`, id 1) runs ALL gameplay: AI, damage,
  pickups, warbands, scoring. Guard gameplay with `multiplayer.is_server()`; clients only display.
- **Spawning**: never `add_child` gameplay objects directly. Use `NetSpawn.unit(kind, pos, extra)`,
  `NetSpawn.pickup()`, `NetSpawn.projectile()` (server only); `main.gd` spawn functions build them on every peer.
  Freeing a spawned node on the server removes it everywhere — clients must never free units/items themselves.
- **Replication**: each unit scene has a `Sync` MultiplayerSynchronizer (ON_CHANGE) listing replicated props
  (net_position, net_yaw, health, max_health, anim_state, action_token, is_dead + player stats / enemy alert_seq).
  New replicated state → add a property with a setter for client visuals AND add it to the scene's Sync config.
  Paused enemies aren't replicated until their band wakes (saves bandwidth). One-shot enemy effects go through
  `Enemy.fx()` / `shout()` RPCs (no replicated state per component).
  `net_position` / `net_yaw` use REPLICATION_MODE_ALWAYS (unreliable, 20 Hz) — never make continuous values
  ON_CHANGE (reliable → stutter on Wi-Fi packet loss). Keep frequently-changing values quantized (regen heals whole points).
- **Client prediction**: on clients the local Player moves immediately (`Unit._predict`, `enable_prediction()`,
  fed by `main.gd` via `predict_input`) and only corrects real drift from the server position.
- **Static world** (trees, chests, graveyards, warbands, hill) is built identically on every peer from `Net.settings.seed`
  with deterministic names; state changes go through RPCs on those nodes (`_net_*` methods, `call_local`).
- **Colors are per device, relative to the local player** (nobody picks one): `Net.color_of(peer)` (you blue,
  teammates green, enemies red), `Net.team_color(team)` / `Net.team_label(team)` ("Your team" green; enemy teams red /
  yellow / purple). Unit colors are computed in `main._spawn_unit` on every peer from `owner_peer` — never send a
  color in spawn data for players / soldiers. Server-made text (announcements, match over) names teams with
  `{team:N}` / `{label:N}` tokens that `Net.localize()` resolves on each device.
- **Teams**: `team_id` on units/projectiles (`GameConfig.ORC_TEAM` = -1 for every enemy, `ANIMAL_TEAM` = -2). Hostility =
  `GameConfig.is_hostile(a, b)`; groups: `players`, `allies`, `player_units` (players+allies), `enemies`,
  `active_enemies`, `warbands`, `units`, `animals`, `herds`. `owner_peer` = controlling player (kill / band credit).
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
