# MyGame

Windows PC game (desktop first) that also runs on Android / iOS, built with Godot 4 from the Template project.

## The game

Multiplayer heroes vs. orc camps (and each other) in a big procedural world (3D, Kenney mini packs). Landscape on PC,
portrait on phones. There is no single player: host a game (alone is fine) or join one.

- **Classes** (picked in the lobby, with a preview of your hero and soldiers; `resources/data/classes/*.tres`, `ClassDef`): each hero fights
  only with its class's weapon, and nothing needs ammo.
  - **Swordsman** (`human.glb`): wide sword swings that cut through crowds, and a round shield. Soldiers: sword and shield.
  - **Spearman** (`keeper.glb`): straight spear stabs that pierce everything in a line; **E** switches to throwing spears
    (to become a purchase later), and a tall rectangular shield. Soldiers: spears (longer reach).
  - **Bowman** (`archer.glb`): fast arrows. Soldiers: archers that stop at range and shoot.
  - **Shields** (Swordsman 150, Spearman 200): hold **right mouse** / LT / the touch shield button to raise it. It
    blocks every hit from the front (the damage goes into the shield) while up; you walk slower and can't attack.
    It breaks when worn out and comes back when you respawn (buying a new one: planned).
  - Planned, not built yet: per-class upgrades and one special ability per class.
- Melee weapons are aim sticks (drag to keep swinging toward a direction, independent of movement); ranged = drag to
  aim, release to shoot. A tap auto-targets the nearest enemy. **Health** comes from potions (orc drops, chests).
- **Chests** have five rarities: Common (gray), Uncommon (green), Rare (blue), Epic (purple), and Legendary (gold).
  Higher rarities are tougher and drop progressively more ammo, healing, and coins. Town starter chests are always
  Uncommon so every player/team begins with the same reward; world chests roll 55% / 25% / 12% / 6% / 2%.
- **Orc camps**: small squads (≤ 7) live in a tent, bigger ones in a house. Each camp has a squad (≈4–6 near the start up to 20–25 at the edges; bigger squads get a bigger, tougher house). Killed orcs respawn after 10 s
  until the house is destroyed. Destroying it routes the surviving orcs (they fall and drop their loot) and
  spills coins.
- **Soldiers** are bought at the trading post's **Barracks** (a walled training compound): 50 coins each, trained
  one after another (10 s each), then they wait in its courtyard until you take them at its gate (E / tap) or with
  the Barracks shop's **Take** button. They follow and fight for
  you; dead soldiers never come back. Army cap 10 (following + in the pen + training); **Command** raises it by 1
  per level (100 coins each) up to 15.
- **Orc types**: Spearman (basic; carries the arena sword), Swordsman (tougher, faster attacks; orc sword), Spear Thrower (throws spears from ~8 units,
  backs off when you close in), Giant (huge, slow, heavy punches that hit everything in front). Camps mix them:
  ~25% swordsmen, ~20% throwers, rest spearmen, plus 1 giant at 10+ orcs and 2 at 18+.
- **Aggro**: hitting an orc or its camp (even with an arrow from far away) alerts the whole squad (red "!").
  They chase the attacker faster and much farther than usual, and give up only after losing sight for ~10 s.
- **Coins & the town**: orcs, chests and destroyed camps give coins. Each spawn is a town (always the same layout:
  a paved square with the Barracks north, Blacksmith + Healer west, Bows & Spears east; kept away from orc camps)
  with one stall per trade: Blacksmith (Sharp Blade: sword), Bows & Spears (Keen Points: arrows and spears),
  Healer (Potion, Vitality) and Barracks (Recruit, Drill Soldiers, Command).
  Walk up to a stall and press B (or tap its button) to open its shop. Items are data:
  `resources/data/upgrade_catalog.tres` (`stalls` = which stalls sell it); stalls are `scenes/world/shop_station.gd`.
- **Difficulty curve**: each camp has a tier (distance from the start). Orcs are 0.75× strength near the start up to
  1.35× at the edges; squads grow from ~4 to ~24. The house shows how many orcs are still alive; bigger camps are
  bigger squares on the minimap. Fallen orcs don't respawn while their camp is under attack.
- **Hero**: your sword hits every orc in front of you; you regenerate health after 5 s without damage.
- **Win**: destroy every camp. **Lose**: player health reaches 0.

### Multiplayer (local Wi-Fi)

- **Main menu → Multiplayer**: set your **name**, then
  **Host Game** or **Join** — pick a game found on your Wi-Fi, or type the host's IP (shown in the host's lobby).
- **Lobby**: when the host presses Start, everyone sees a **3-2-1 countdown**, then the screen fades into the match
  (it fades in once your hero has spawned). The host sets **mode**, **orc camps** (0–60), **difficulty** (Easy/Normal/Hard/Brutal),
  **starting coins**, and for versus modes **teams** (2–4), **score to win** and **time limit**. Players pick teams
  in team modes, and everyone picks their **class** (each player's class shows in the list).
- **Colors are automatic and relative to you**: you and your soldiers are blue, teammates and their soldiers green,
  enemies red (team modes: each enemy team its own color — red, yellow, purple). Team names follow the same rule
  ("Your team", "Red team") everywhere: lobby, score line, towns, flags, announcements.
- **Modes**: Co-op vs Orcs · Deathmatch · Team Deathmatch · Capture the Flag · King of the Hill. Orcs stay in every
  mode and fight everyone. Destroying a camp gives its soldiers to whoever landed the last hit.
- **Towns in multiplayer**: co-op uses one shared town, Deathmatch gives every player a private town, and team modes
  give every team one shared town. A colored compass ring and entrance label identify the owner; other players can
  enter the town but cannot use its shops or Barracks.
- Online matches don't pause (pause menu → Leave Game); players respawn after a few seconds.
- The host's device runs the match; up to 8 players. Joining by IP always works; automatic discovery on iPhone may
  need Apple's multicast entitlement.

### Playing together

- **Downed, not dead** (online co-op + team modes): at 0 health you crawl for 15 s ("HELP!" over you, a Help ping
  goes out automatically). A teammate standing next to you for 3 s revives you at 40% health (faster with two).
  Orcs ignore downed players; enemy players can finish you. Left alone you bleed out and respawn as usual
  (nothing drops). Deathmatch keeps instant deaths.
- **World events** (lobby → World events, on by default):
  - **Treasure goblin** (~1–1.5 min in, then every ~3 min): a golden goblin near a player that runs from anyone close,
    spills coins with every hit and drops a jackpot when caught; it escapes after ~55 s.
  - **Orc Warlord** (~4–5 min in, then every ~8 min): a huge boss marching on a player (in versus modes on the leader)
    with a warband that grows every 25 s. It stomps everyone around it. Whoever lands the final blow gets its
    surviving warband as soldiers, plus a pile of coins.
  - **Waves** (~2 min in): red invasion beacons warn at all four map borders before raiders march in and hunt the
    nearest living player. Waves contain 10, 20, 30, 40, then at most 50 enemies, adding swordsmen, throwers and
    giants as they advance. A new wave starts only after the current one is defeated and a short recovery period.
- **Army orders**: Follow (formation), Charge (run to a point and fight everything there), Hold (guard a point).
  Buttons under the soldier count, keys 1 / 2 / 3 (at the cursor), D-pad on a gamepad.
- **Pings** (online, your team only): Q / middle mouse / the "!" button. Pinging an enemy says "Attack!", a chest
  "Loot!", anywhere else "Here!"; H calls for help. Pings show in the world, on the minimap and as screen-edge arrows.
- **Off-screen arrows** point at the goblin, the Warlord, downed teammates and pings; the Warlord's health bar shows
  while it's near.
- **Awards** at the end of every match: MVP, Warlord Slayer, Medic, Goblin Hunter, Headhunter, Camp Crusher,
  Orc Slayer, Sharpshooter, Moneybags, Lumberjack, Floor Inspector, Where's My Army?, Chatterbox
  (`scripts/game/match_stats.gd`).

### Menus & UI

- Starts at the **main menu** (`scenes/ui/main_menu.tscn`, 3D camp backdrop from `menu_backdrop.tscn`):
  Training Field · Multiplayer (`multiplayer_menu.tscn`) · Controls · Quit. Lobby: `lobby.tscn`.
- **Training Field** is a local onboarding area with every hero on display, unlimited special abilities and
  indestructible damage targets. Stand beside a hero and press **F** to switch to it.
- **Pause**: the II button (top left), Esc, or Android back → Resume / Restart / Main menu. Auto-pauses when the
  app goes to the background.
- UI look: Kenney RPG UI pack via `resources/themes/rpg_theme.tres` (set as the project theme). Regenerate it with
  `Godot --headless --path . -s res://tools/build_rpg_theme.gd`. Variations: `PanelBrown`, `PanelInset`,
  `PanelInsetBrown`, `PanelLight`, `ButtonBeige`, `ButtonTab`, `ButtonSquare`, `KeyCap`/`KeyCapLabel`, `LabelLight`,
  `HeaderLabel`, `HintLabel`, `TitleLabel`, `ProgressBarGreen/Blue/Yellow`; buttons show a gold focus ring for
  keyboard / gamepad. Icon medals: `UiKit.medal()` (Game Icon Pack
  glyphs, `assets/ui/icons/game/`), input prompt images: `UiKit.prompt()` (Kenney Input Prompts, `assets/ui/prompts/`).

### Controls

| Action | Keyboard + mouse (PC) | Gamepad | Touch (phones) |
|---|---|---|---|
| Move | WASD / arrow keys | Left stick | Drag on the left side |
| Choose training hero | F while beside a displayed hero | — | — |
| Sword / spear | Left mouse — swings / thrusts toward the cursor while held · J = nearest enemy | RB / X (nearest enemy) | Weapon stick: drag = direction, tap = nearest |
| Bow / spear throw | Right mouse — hold to aim at the cursor, release to shoot | Right stick aims · RT / A shoots | Aim stick: drag to aim, release to shoot |
| Quick shot (nearest enemy) | K | RT / A without aiming | Tap the aim stick |
| Spearman: thrust ⇄ throw | E | Y | Small button above the weapon stick |
| Shield (Swordsman, Spearman) | Right mouse (hold; turns toward the cursor) | LT (hold) | Shield button left of the weapon stick |
| Use a stall | B | LB / View | Stall button |
| Pause | Esc / P | Start | II button / Android back |
| Army orders (follow / charge / hold) | 1 / 2 / 3 (charge / hold at the cursor) | D-pad up / right / down | Buttons under the soldier count |
| Ping · call for help | G or middle mouse · H | D-pad left | "!" button (online) |
| Fullscreen | F11 / Alt+Enter (remembered) | — | — |

All bindings are listed in-game under **main menu → Controls** (`scenes/ui/controls_menu.gd` — update it when
bindings change). Bindings are Input Map actions (Project Settings → Input Map): `move_*`, `aim_*`, `attack`, `aim_bow`, `shoot`,
`switch_weapon`, `block`, `interact`, `training_interact`, `pause`, `toggle_fullscreen`, `army_follow` / `army_charge` / `army_hold`, `ping`, `ping_help`. Touch controls appear on a PC only when a touchscreen is used.

### Desktop vs. mobile (`scripts/autoload/platform.gd`, autoload `Platform`)

- **PC**: UI laid out for 1920×1080 landscape (scales to any window; 1600×900 default window, resizable),
  Forward+ renderer, 4× MSAA, camera 25% further out.
- **Phones**: UI 720×1280 portrait, Mobile renderer, 2× MSAA, touch controls (renderer / MSAA use the `.mobile`
  project-setting overrides).
- Test the phone layout on a PC: `"$G" --path . -- --mobile` (mouse emulates touch).
- Several instances side by side: `-- --tile=N` (0..3) puts the window in one screen corner (Debug → Customize Run Instances → 4 instances, arguments `-- --tile=0` … `-- --tile=3`).
- Menus adapt to both: `MaxWidth` caps full-width panels on wide screens; the main menu puts its buttons on the left
  in landscape; 3D cameras apply their FOV to the screen's short side (`FollowCamera3D.fit_fov_to_short_side`).

### Where things live

| What | File |
|---|---|
| Match settings (mode, camps, difficulty, coins, teams, limits) | Lobby → `Net.settings` (`scripts/autoload/net.gd`) |
| Networking, lobby, profile, LAN discovery | `scripts/autoload/net.gd` (autoload `Net`) |
| Mode rules, scoring, respawns, spawn points | `scenes/main/game_mode.gd`, `scenes/world/capture_flag.gd`, `scenes/world/hill.gd` |
| World generation (trees, chests, camp tiers/squad sizes) | `scenes/main/world_builder.gd` |
| Enemy mix per camp | `resources/data/orc_roster.tres` (add a RosterEntry for a new enemy type) |
| Shop items | `resources/data/upgrade_catalog.tres` + effects in `Player._apply_upgrade()` |
| Win / lose, HUD ↔ player wiring, pings, army orders | `scenes/main/main.gd` |
| Treasure goblin / Orc Warlord timing | `scenes/main/world_events.gd` (+ `treasure_goblin.gd`, `warlord.gd` in `scenes/characters/`) |
| Match stats & awards | `scripts/game/match_stats.gd` |
| Character base (health, melee, animations, weapons in hands) | `scenes/characters/unit.gd` |
| Player / orc AI / soldier AI | `scenes/characters/player.gd`, `enemy.gd`, `ally.gd` (stats in the `.tscn` files: `enemy.tscn` spearman, `enemy_swordsman.tscn`, `enemy_thrower.tscn`, `enemy_giant.tscn`, `ally.tscn`) |
| Camp spawning, respawn, conversion to soldiers | `scenes/world/camp.gd` |
| Trees, chests, pickups, arrows | `scenes/world/`, `scenes/items/`, `scenes/combat/` |
| HUD, minimap | `scenes/ui/` |

## Orientation

Desktop is always landscape. The phone orientation is set with `tools/set_orientation.sh portrait|landscape`
(phone UI 720×1280 or 1280×720).

## Folder structure

```
.
├── project.godot        # Engine config (Forward+ on PC / Mobile renderer on phones)
├── export_presets.cfg   # Windows + Android + iOS export presets
├── .mcp.json            # godot-mcp server config for Claude
├── icon.svg             # Placeholder app icon — replace per game
├── tools/               # Helper scripts (ignored by Godot)
│   ├── set_orientation.sh
│   ├── glb_set_texture.py           # Point 3D models at a shared palette texture
│   ├── blender_kit.py               # Toolkit for own Blender models in the Kenney palette style (+ overlap check)
│   ├── blender_barracks.py          # Builds the Barracks compound model (uses blender_kit.py)
│   ├── blender_blacksmith.py        # Builds the Blacksmith workshop model (uses blender_kit.py)
│   ├── blender_armory.py            # Builds the Bows & Spears cabin model (uses blender_kit.py)
│   ├── blender_healer.py            # Builds the Healer cottage model (uses blender_kit.py)
│   ├── blender_town.py              # Builds the town at every spawn (square, decor, stall spots, collision)
│   ├── blender_props.py             # The game's existing models (paths + in-game sizes) for building scripts
│   ├── render_portrait.gd           # Render a round head portrait of a model (map / HUD icons)
│   ├── install_export_templates.py  # Download only the export templates you need (Windows/Android/iOS…)
│   └── run_ios.sh       # Export, sign and launch the game on a connected iPhone
├── pre-assets/          # DROP ZONE: put raw assets/packs here, any layout (ignored by Godot)
├── assets/              # Cleaned, renamed, game-ready assets (imported by Godot)
│   ├── characters/      # archer, human, orc, soldier, ghost, keeper, skeleton, vampire, zombie; pets/ (animated GLB)
│   ├── environment/     # arena/  dungeon/  forest/  graveyard/  (level pieces & props)
│   ├── items/           # arena/  dungeon/  forest/  graveyard/  (weapons, shields, pickups)
│   ├── textures/        # palettes/ — one colormap per kit
│   ├── CREDITS.md       # Asset authors & licenses
│   ├── ui/              # icons/  buttons/  panels/
│   ├── fonts/
│   ├── audio/           # sfx/  music/
│   ├── vfx/
│   └── shaders/         # highlight_glow.gdshader: pulsing "you can use this" glow (material_overlay)
├── scenes/              # .tscn files
│   ├── main/            # Entry scene (main.tscn)
│   ├── levels/  characters/  ui/  components/
├── scripts/             # .gd files
│   ├── autoload/        # Singletons (GameManager, AudioManager, SaveManager…)
│   ├── components/      # Reusable behaviour scripts
│   └── utils/           # Helpers / static functions
├── resources/           # .tres files
│   ├── themes/          # UI themes
│   └── data/            # Custom Resources (stats, level data, configs)
├── addons/              # Godot plugins
├── tests/               # Automated test drivers (see tests/README.md, excluded from exports)
└── builds/              # Exported EXE/APK/IPA (ignored by Godot and git)
```

## Reusable components (`scripts/components/`, `scenes/ui/`)

| Script | What it does |
|---|---|
| `touch_joystick.gd` (`TouchJoystick`) | Floating virtual joystick, multi-touch safe. Read `output` (Vector2). |
| `touch_button.gd` (`TouchButton`) | Round on-screen button with icon + badge text, multi-touch safe. Poll `is_held` or use `pressed`/`released`. |
| `touch_aim_stick.gd` (`TouchAimStick`) | Twin-stick aim button: drag to aim (`output`, `is_aiming`), release fires `aim_released(dir)`; tap → `tapped`, drag back to center → `cancelled`. |
| `health_bar_3d.gd` (`HealthBar3D`) | Camera-facing health bar over 3D objects; hides when full (optional `auto_hide_delay`). `set_ratio()`. |
| `bone_pose_override_3d.gd` (`BonePoseOverride3D`) | SkeletonModifier3D that holds chosen bones in a pose sampled from an animation (e.g. arm in a "holding" pose while legs walk), or plays them live from another animation (`start_live`, e.g. swing only the arm while running); blend with `influence`. |
| `floating_text_3d.gd` (`FloatingText3D`) | Pop-up text in the 3D world that arcs up and fades ("+5" coins, damage numbers). Pooled, max 24 on screen. `FloatingText3D.spawn(parent, pos, text, color, size, emphasized)`. |
| `follow_camera_3d.gd` (`FollowCamera3D`) | Fixed-angle smooth follow camera (top-down / isometric). Set `target`, call `snap()`, `shake()`; `zoom` (offset multiplier, eases in) zooms in / out; `rotate_step(±1)` orbits exactly 90° (turn screen input with `to_world(v)`). FOV covers the screen's short side (same view on phones and monitors). |
| `fly_camera_3d.gd` (`FlyCamera3D`) | Free-fly camera: hold right mouse to look, `move_*` actions to fly, E / Q up / down, Shift fast, wheel = speed; `fly_to(at, target)` glides to a view. Used by the showcase. |
| `offscreen_markers.gd` (`OffscreenMarkers`) | Screen-edge arrows (label + distance) to nodes in the "tracked" group (metas `marker_color`, `marker_label`). |
| `max_width.gd` (`MaxWidth`) | Attach to a full-width menu panel: centered and at most `max_width` wide on wide screens, `margin` on each side on phones. |
| `scripts/autoload/platform.gd` (autoload `Platform`) | Desktop / mobile setup: UI size per device, `mobile_layout`, `touch_mode` (+ `touch_mode_changed`), fullscreen toggle (F11 / Alt+Enter, saved), `-- --mobile` test flag, `-- --tile=N` window in a screen corner. |
| `scripts/autoload/transition.gd` (autoload `Transition`) | Screen fades: `await Transition.fade_out()`, `fade_in()`, `change_scene(path)` (fade out → switch → fade in; pass `false` to let the new scene fade in when ready). |
| `scenes/ui/main_menu.tscn` | Main menu (title from Project Settings name, Play → `game_scene`, Quit hidden on iOS/web). Add any background as a child. |
| `scenes/ui/pause_menu.tscn` (`PauseMenu`) | Pause overlay (Resume / Restart / Main menu). `open()`, Esc / `pause` action / Android back, auto-pause when the app is backgrounded on mobile, `set_hint(text)` for a controls line. Instance it in the game scene. |

## Asset workflow

1. Drop raw files or whole downloaded packs into `pre-assets/` — any layout — and tell Claude.
2. Claude (or you) reviews them, renames to `snake_case`, and moves/copies them into `assets/`.
3. Only files in `assets/` are used by the game.

`pre-assets/` contains a `.gdignore` file, so Godot never imports it — no clutter, no `.import` files.

## Project defaults

| Setting | PC (default) | Phones |
|---|---|---|
| Renderer | Forward+ | Mobile (`rendering_method.mobile`) |
| UI base size | 1920 × 1080 landscape | 720 × 1280 portrait (or 1280 × 720, see Orientation) |
| Stretch | `canvas_items` / `expand` | same |
| Window | 1600 × 900, resizable, F11 fullscreen | fullscreen |
| MSAA 3D | 4× | 2× |
| Input | keyboard + mouse, gamepad | touch (on a PC the mouse emulates touch only with `-- --mobile`) |
| Texture compression | S3TC/BPTC | ETC2/ASTC |

## Exporting

| Platform | Preset | Output | Needs |
|---|---|---|---|
| Windows | `Windows Desktop` | `builds/windows/MyGame.exe` (x86_64, one file with the game data embedded) | Nothing extra — exports from macOS too |
| Android | `Android` | `builds/android/<Game>.apk` (arm64) | Android SDK + JDK set in Editor Settings → Export → Android |
| iOS | `iOS` | `builds/ios/<Game>.xcodeproj` (project only) | Xcode + your Apple Team ID in the iOS preset; `tools/run_ios.sh` builds, signs and launches it on a connected iPhone (free Apple ID works; trust the developer on the phone once) |

Export templates: run `tools/install_export_templates.py` once per Godot version (default: Windows + Android +
iOS; or name platforms, e.g. `tools/install_export_templates.py windows`). It downloads only those templates
instead of the whole 1.3 GB archive and can resume if interrupted.

Command line: `"$G" --headless --path . --export-release "Windows Desktop" builds/windows/MyGame.exe`.
The Windows `.exe` keeps Godot's icon and has no version info (`application/modify_resources` is off because it
needs `rcedit`). To brand it, install rcedit (Editor Settings → Export → Windows), add an `.ico`, and turn it on.

Before publishing to a store, add a release keystore (Android) and bump `version/code` / `version/name`.
Keystores are git-ignored — back them up somewhere safe.
