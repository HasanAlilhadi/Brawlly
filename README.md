# MyGame

Windows PC game (desktop first) that also runs on Android / iOS, built with Godot 4 from the Template project.

## The game

Multiplayer heroes vs. roaming warbands of orcs and undead (and each other) in a big procedural world (3D, Kenney mini packs). Landscape on PC,
portrait on phones. There is no single player: host a game (alone is fine) or join one.

- **Classes** (picked in the lobby, with a preview of your hero and soldiers; `resources/data/classes/*.tres`, `ClassDef`): each hero fights
  only with its class's weapon, and nothing needs ammo.
  - **Swordsman** (`human.glb`): wide sword swings that cut through crowds. Soldiers: sword and shield.
  - **Spearman** (`keeper.glb`): straight spear stabs that pierce everything in a line. Soldiers: spears (longer reach).
  - **Bowman** (`archer.glb`): fast arrows. **Bow Rain** marks a large area with X, then LMB rains arrows
    into it. Soldiers: archers that stop at range and shoot.
  - **Upgrades sheet** (press **T**, the gamepad View button, click the "T Upgrades" tab at the bottom of the screen or
    the star button next to pause; a coin on the tab means you can afford something): slides up from the
    bottom with two tabs. Everything in the game is bought here. **Army**: recruit a soldier anywhere (50 coins; it
    trains 10 s, then joins you on the spot), **Soldier Damage** / **Soldier Health** (+25% each, 3 levels each) and
    **Command** (+1 army size). **Hero**: **Vitality** (+30 max health), **Potion** (heal 60, buy again and again) and
    your class's upgrades, bought with coins anywhere (free in the Training Field, which also hands out the unlocks):
    - Swordsman: Increase Damage, Fire Rate, **Knock Back or Wave** (pick one: hits shove enemies far back, or each
      swing sends a slash wave through enemies), **Dash Attack** (C: dash through enemies, slashing each), Shield.
    - Spearman: Increase Damage, Fire Rate, **Can Throw** (E switches to throwing spears), Shield. (Bull Run: later.)
    - Bowman: Increase Damage, Fire Rate, Fire Range, **Penetration** (arrows go through up to 2 enemies),
      **Knife** (right mouse: a quick stab up close).
  - **Shields** (bought; Swordsman 150, Spearman 200): hold **right mouse** / LT / the touch shield button to raise it.
    It blocks every hit from the front (the damage goes into the shield) while up; you walk slower and can't attack.
    It breaks when worn out and comes back when you respawn.
  - Every class has a special ability charged by XP: Swordsman Whirlwind, Spearman Bull Rush, and Bowman Bow Rain.
- Melee weapons are aim sticks (drag to keep swinging toward a direction, independent of movement); ranged = drag to
  aim, release to shoot. A tap auto-targets the nearest enemy. **Health** comes from potions (enemy drops, chests).
- **Chests** have five rarities: Common (gray), Uncommon (green), Rare (blue), Epic (purple), and Legendary (gold).
  Higher rarities are tougher and drop progressively more ammo, healing, and coins. The starter chest next to
  each spawn is always Uncommon so every player/team begins with the same reward; world chests roll 55% / 25% / 12% / 6% / 2%.
- **Warbands** (no camps): enemies roam the map in groups — the **size of a band is its power**. Near the start a
  few grunts or skeletons; farther out bigger bands with throwers, archers and elites, tougher too (0.8× → 1.3×);
  the biggest (18+) are led by a boss. Bands march in formation (melee in front, ranged behind) from one spot of
  their ground to the next, rest, and go on. The undead gather around **graveyards** (iron fences, gravestones, a
  crypt — Graveyard Kit). Nothing floats over a band: scout for them. Only **large bands** (10+) show on the
  minimap (skull = undead, axe = orcs; a pulsing ring = a boss leads it). Fallen members return only while the band
  is calm and nobody is near; wipe a band out and it's gone for good. Fell a boss and its whole band is routed.
- **Soldiers** are recruited from the upgrades sheet's Army tab, anywhere: 50 coins each, trained one after another
  (10 s each), then each appears right behind you. They follow and fight for you; dead soldiers never come back.
  Army cap 10 (following + training); **Command** (Army tab) raises it by 1 per level (100 coins each) up to 15.
- **Enemy types** (each its own movement, attacks and abilities, built from components):
  - **Orc Grunt** — runs in and swings. **Orc Spear Thrower** — keeps 4–7 m away, throws spears ahead of you.
  - **Orc Brute** (elite) — huge and slow, cleaves, **charges** along a red lane, **stomps** (red ring), enrages when hurt.
  - **Skeleton Warrior** — quick, circles to your side or back; falls apart once and **gets back up** (hit the bone pile to stop it).
  - **Skeleton Archer** — stays 6–10 m back and shoots arrows.
  - **Zombie** — slow lurching shambler, tanky, **lunges** at you, **bursts** in a toxic cloud when it dies (green ring: step out).
  - **Ghost** — floats through trees and walls in weaving curves, **phases** (hits pass through) when struck.
  - **Vampire** (elite) — circles you, **blinks** behind you in a puff of bats, heals by biting.
  - **Necromancer** (elite) — keeps away, casts slow magic bolts, **raises skeletons** from the ground.
  - Bosses: **Orc Warlord** (charges, stomps, rallies orcs at half health, enrages) and **Vampire Lord** (stalks,
    blinks, blood-bolt volleys, raises the dead at 66% and 33%, life steal, enrages).
- **Aggro**: hitting any member of a band (even with an arrow from far away), or one of them spotting you, alerts the
  whole band (red "!").
  They chase the attacker faster and much farther than usual, and give up only after losing sight for ~10 s.
- **Coins & upgrades**: enemies, chests and bosses give coins, spent anywhere on the upgrades sheet (T / View /
  the star button): the **Hero** tab has your class's upgrades plus Vitality and Potion; the **Army** tab has Recruit,
  Soldier Damage, Soldier Health and Command. There are no shops or towns: each spawn is an open area kept clear of
  warbands, with a starter chest. Items are data: `resources/data/upgrade_catalog.tres` (`sheet` = the tab of a
  non-class item, `classes` = a class upgrade).
- **Difficulty curve**: bands grow from 3 near the start to ~24 at the edges, and with size their strength
  (0.8× → 1.3×) and loot. The lobby's difficulty multiplies it all.
- **Hero**: your sword hits every enemy in front of you; you regenerate health after 5 s without damage.
- **Win**: wipe out every warband. **Lose**: player health reaches 0.

### Multiplayer (local Wi-Fi)

- **Main menu**: your name ("Playing as", remembered), then **Find Game** or **Host Game**.
- **Find Game** (server browser): every game hosted on your network in a table (server, host, mode, players,
  status, a lock for password-protected ones) with search, **Hide full** / **Hide in progress** and **Refresh**.
  Double-click a game (or select it and press Join); locked games ask for the password. **Direct Connect** joins
  by address (`192.168.1.20` or `192.168.1.20:24565`, recent addresses remembered). Refusals say why (full,
  already playing, wrong password).
- **Host Game**: server name, max players (2–8), an optional password, and **Listed** (shows in everyone's Find
  Game) or **Private** (join by address only) → **Create Lobby**. Shows your address; internet play needs UDP
  port 24565 forwarded.
- **Lobby**: players on the left (one slot per seat, host crown, class, Ready; the host can **Kick**), your hero and
  the match settings on the right, the invite address with **Copy** at the top. Players press **Ready up**; the
  host's **Start** shows how many are ready. Kicked / host left → back to the main menu with a notice saying why.
  When the host presses Start, everyone sees a **3-2-1 countdown**, then the screen fades into the match
  (it fades in once your hero has spawned). The host sets **mode**, **warbands** (0–60), **difficulty** (Easy/Normal/Hard/Brutal),
  **starting coins**, and for King of the Hill **teams** (2–4), **hill seconds to win** and **time limit**. Players
  pick teams in King of the Hill, and everyone picks their **class** (each player's class shows in the list).
- **Colors are automatic and relative to you**: you and your soldiers are blue, teammates and their soldiers green,
  enemies red (King of the Hill: each enemy team its own color — red, yellow, purple). Team names follow the same
  rule ("Your team", "Red team") everywhere: lobby, score line, announcements.
- **Maps** (lobby → Map): **Wildlands** — a new procedural forest every match (all modes); **Crown Ruins** — a
  designed King of the Hill arena: the hill in a ruined amphitheater, a ring of walls with eight doors, bases with
  two exits, haunted corner shrines with Rare chests, groves to flank through (rebuild with
  `tools/build_map_crown_ruins.gd`, or edit `scenes/maps/crown_ruins.tscn` in the editor).
- **World events** (lobby → toggle each): treasure goblin, Orc Warlord, invasion waves, **meteor shower** (red
  rings, then burning rocks — star shards drop coins + XP), **thunderstorm** (rain, darkness, lightning strikes),
  **Blood Moon** (a red night: monsters faster and stronger, double loot), **supply drop** (a Legendary crate
  parachutes in — in King of the Hill right by the hill).
- **Modes**: **Co-op vs the Horde** (everyone together, wipe out every warband) and **King of the Hill** (teams
  hold the hill in the middle to earn points). Warbands roam in both and fight everyone. (Deathmatch, Team
  Deathmatch and Capture the Flag were removed for now.)
- **Spawns in multiplayer**: co-op shares one spawn area; King of the Hill gives every team its own, far apart.
- Online matches don't pause (pause menu → Leave Game); players respawn after a few seconds.
- The host's device runs the match; up to 8 players. Joining by IP always works; automatic discovery on iPhone may
  need Apple's multicast entitlement.

### Playing together

- **Downed, not dead** (every online match): at 0 health you crawl for 15 s ("HELP!" over you, a Help ping
  goes out automatically). A teammate standing next to you for 3 s revives you at 40% health (faster with two).
  Orcs ignore downed players; enemy players can finish you. Left alone you bleed out and respawn as usual
  (nothing drops).
- **World events** (lobby → World events, on by default):
  - **Treasure goblin** (~1–1.5 min in, then every ~3 min): a golden goblin near a player that runs from anyone close,
    spills coins with every hit and drops a jackpot when caught; it escapes after ~55 s.
  - **Orc Warlord** (~4–5 min in, then every ~8 min): a boss leading its own warband, marching on a player (in
    versus modes on the leader); the band grows every 25 s. It charges, stomps and rallies more orcs at half
    health. Fell it and its warband is routed, plus a pile of coins.
  - **Waves** (~2 min in): red invasion beacons warn at all four map borders before raiders march in and hunt the
    nearest living player. Waves contain 10, 20, 30, 40, then at most 50 enemies, adding swordsmen, throwers and
    giants as they advance. A new wave starts only after the current one is defeated and a short recovery period.
- **Army orders**: Follow (formation), Charge (run to a point and fight everything there), Hold (guard a point).
  Buttons under the soldier count, keys 1 / 2 / 3 (at the cursor), D-pad on a gamepad.
- **Pings** (online, your team only): Q / middle mouse / the "!" button. Pinging an enemy says "Attack!", a chest
  "Loot!", anywhere else "Here!"; H calls for help. Pings show in the world, on the minimap and as screen-edge arrows.
- **Off-screen arrows** point at the goblin, the Warlord, downed teammates and pings; the nearest boss's health bar shows
  while it's near.
- **Awards** at the end of every match: MVP, Giant Slayer, Medic, Goblin Hunter, Headhunter, Warband Breaker,
  Monster Slayer, Sharpshooter, Moneybags, Lumberjack, Floor Inspector, Where's My Army?, Chatterbox
  (`scripts/game/match_stats.gd`).

### Menus & UI

- Starts at the **main menu** (`scenes/ui/main_menu.tscn`, 3D diorama backdrop from `menu_backdrop.tscn`):
  Find Game (`server_browser.tscn`) · Host Game (`host_menu.tscn`) · Training Field · Controls · Quit.
  Lobby: `lobby.tscn`. These pages share `MenuKit` (`scenes/ui/menu_kit.gd`: page frame, modal dialogs, buttons).
- **Training Field** is a local onboarding area with every hero on display, unlimited special abilities and
  indestructible damage targets. Press **F** beside a hero to switch, or at the Orc Practice station to spawn
  one orc (up to eight alive at once). Orcs never spawn on their own.
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
| Training: choose hero / spawn orc | F beside a hero / orc station | LB | — |
| Class upgrades | T | View | Star button next to pause |
| Sword / spear | Left mouse — swings / thrusts toward the cursor while held · J = nearest enemy | RB / X (nearest enemy) | Weapon stick: drag = direction, tap = nearest |
| Bow / spear throw | Right mouse — hold to aim at the cursor, release to shoot | Right stick aims · RT / A shoots | Aim stick: drag to aim, release to shoot |
| Quick shot (nearest enemy) | K | RT / A without aiming | Tap the aim stick |
| Spearman: thrust ⇄ throw (Can Throw) | E | Y | Small button above the weapon stick |
| Shield (Swordsman, Spearman, bought) | Right mouse (hold; turns toward the cursor) | LT (hold) | Shield button left of the weapon stick |
| Knife (Bowman, bought) | Right mouse | LT | Shield button (shows a blade) |
| Dash Attack (Swordsman, bought) | C (where you move, else toward the cursor) | L3 | Dash button left of the shield button |
| Interact (Training Field: switch hero, practice orc) | F | LB | — |
| Pause | Esc / P | Start | II button / Android back |
| Army orders (follow / charge / hold) | 1 / 2 / 3 (charge / hold at the cursor) | D-pad up / right / down | Buttons under the soldier count |
| Ping · call for help | G or middle mouse · H | D-pad left | "!" button (online) |
| Fullscreen | F11 / Alt+Enter (remembered) | — | — |

All bindings are listed in-game under **main menu → Controls** (`scenes/ui/controls_menu.gd` — update it when
bindings change). Bindings are Input Map actions (Project Settings → Input Map): `move_*`, `aim_*`, `attack`, `aim_bow`, `shoot`,
`switch_weapon`, `block`, `interact`, `pause`, `toggle_fullscreen`, `army_follow` / `army_charge` / `army_hold`, `ping`, `ping_help`. Touch controls appear on a PC only when a touchscreen is used.

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
| Match settings (mode, warbands, difficulty, coins, teams, limits) | Lobby → `Net.settings` (`scripts/autoload/net.gd`) |
| Networking, lobby, profile, LAN discovery | `scripts/autoload/net.gd` (autoload `Net`) |
| Mode rules, scoring, respawns, spawn points | `scenes/main/game_mode.gd`, `scenes/world/capture_flag.gd`, `scenes/world/hill.gd` |
| World generation (trees, chests, graveyards, warband sizes / factions) | `scenes/main/world_builder.gd` |
| Enemy mix per warband | `resources/data/orc_warband.tres`, `undead_warband.tres` (add a RosterEntry for a new enemy type) |
| Upgrades sheet items | `resources/data/upgrade_catalog.tres` + effects in `Player._apply_upgrade()` |
| Win / lose, HUD ↔ player wiring, pings, army orders | `scenes/main/main.gd` |
| Treasure goblin / Orc Warlord timing | `scenes/main/world_events.gd` (+ `treasure_goblin.gd`; the Warlord is `scenes/characters/enemies/orc_warlord.tscn`) |
| Match stats & awards | `scripts/game/match_stats.gd` |
| Character base (health, melee, animations, weapons in hands) | `scenes/characters/unit.gd` |
| Player / soldier AI | `scenes/characters/player.gd`, `ally.gd` (stats in `ally.tscn`) |
| Enemies (composition) | `scenes/characters/enemy.gd` + components in `scripts/enemies/` (movement, attacks, abilities, traits); one scene per type in `scenes/characters/enemies/` |
| Warbands: marching, formation, alerts, respawns, rout | `scenes/world/warband.gd` |
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
