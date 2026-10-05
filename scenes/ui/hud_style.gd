class_name HudStyle
## In-match HUD design tokens: every HUD size, gap and font size comes from here, so all panels and
## buttons line up and share one scale. Use these instead of numbers in hud.gd / hud.tscn.
## Layout (Hud._apply_design): a column at the top left (stats panel, then the square button row),
## a column at the top right (minimap, warband / soldier stats, army orders), weapon bar at the bottom
## right, match messages top center, "You're down" bottom center.

## Distance from the screen (safe area) edge.
const MARGIN: float = 16.0
## Between neighbouring HUD elements.
const GAP: float = 8.0

## Square icon buttons (pause, shop, ping).
const BUTTON: float = 56.0
## Text buttons in the right column (army orders); fixed so labels never resize them.
const BUTTON_WIDE: Vector2 = Vector2(COLUMN_WIDTH, 44.0)
## Width of the right column (minimap, stats, army buttons) and of the stats panel on the left.
const COLUMN_WIDTH: float = 220.0
const LEFT_WIDTH: float = 260.0

const ICON: float = 32.0
const ICON_SMALL: float = 28.0
## Round medal badges (weapon slots, downed card).
const BADGE: float = 56.0
## Input prompt key caps (Q, 1 / 2 / 3).
const KEY: float = 40.0
const BAR_HEIGHT: float = 18.0
const BAR_HEIGHT_SMALL: float = 12.0

const FONT_SMALL: int = 16
const FONT_BODY: int = 20
const FONT_BUTTON: int = 20
const FONT_TITLE: int = 24
const FONT_HEADLINE: int = 44

## Upgrades sheet (T): at most this wide; one card per class upgrade.
const UPGRADE_SHEET_WIDTH: float = 1480.0
const UPGRADE_CARD: Vector2 = Vector2(228.0, 176.0)
## Its handle at the bottom edge ("T  Upgrades"): height, how much of it hides below the edge, hover lift.
const UPGRADES_TAB_HEIGHT: float = 64.0
## Room on each side of its key and text (the tab is as wide as its content).
const UPGRADES_TAB_PAD: float = 16.0
const UPGRADES_TAB_TUCK: float = 12.0
const UPGRADES_TAB_LIFT: float = 6.0

## Weapon slot in hand vs carried.
const SLOT_ACTIVE: Color = Color.WHITE
const SLOT_INACTIVE: Color = Color(1, 1, 1, 0.4)
