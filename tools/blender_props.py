# The game's existing models, for own building scripts (tools/blender_<name>.py): place these with kit.prop()
# instead of modeling a second sword / bow / barrel, so every copy in the game looks the same. Positions are Godot
# meters like the kit's helpers; scales are the model's own units -> meters. Use the sizes the game shows them at
# (SCALE_*: spear projectile / pickups, the held sword) so a display matches what players carry. Only model what
# isn't listed here (and isn't in assets/) yet.
import math
from blender_kit import prop

SWORD = "res://assets/items/dungeon/sword.glb"            # the player's sword: blade up (+y), origin at the grip
BOW = "res://assets/items/forest/bow.glb"                 # the player's bow: stands on its lower tip, curve in y-z
SPEAR = "res://assets/items/dungeon/spear.glb"            # the player's spear: upright, 0.6 tall
ARROW = "res://assets/items/forest/arrow.glb"             # centered, head toward +z, 0.46 long
SHIELD = "res://assets/items/dungeon/shield_round.glb"    # disc facing ±z, radius 0.19
BARREL = "res://assets/environment/dungeon/barrel.glb"    # radius 0.26, 0.48 tall
TARGET = "res://assets/environment/forest/target.glb"     # archery target on legs, faces +z, 0.58 tall
WEAPON_RACK = "res://assets/environment/arena/weapon_rack.glb"  # 0.72 wide rail, 0.47 tall
WALL_BANNER = "res://assets/environment/dungeon/banner.glb"     # hangs 0.23..0.88 up, its back 0.53 behind the origin
FLAG = "res://assets/environment/forest/flag.glb"         # flag on a 0.75 pole, flies toward +x
POTION = "res://assets/items/dungeon/potion.glb"          # the health potion pickup: bottle, radius 0.16, 0.4 tall
POT = "res://assets/environment/dungeon/pot.glb"          # clay pot, 0.6 x 0.4, 0.43 tall
TABLE = "res://assets/environment/dungeon/table.glb"      # 0.88 x 0.64 top, 0.31 tall
PLANT = "res://assets/environment/forest/plant.glb"       # small leafy plant, 0.17 tall

SCALE_SWORD = 1.25   # held by a 1.25-scaled character
SCALE_BOW = 1.4
SCALE_SPEAR = 1.3    # spear projectile
SCALE_ARROW = 1.2
SCALE_POTION = 1.1    # potion pickup is 1.2


def _at(x, z, yaw, dx, dz):
	c, s = math.cos(yaw), math.sin(yaw)
	return x + dx * c + dz * s, z - dx * s + dz * c


def spear_rack(x, z, yaw=0.0, spears=4, rack_scale=1.1, spear_scale=SCALE_SPEAR, y=0.0):
	"""The weapon rack with spears standing in front of its rail, leaning back on it (front = +z, turned by yaw;
	`y` = the floor it stands on)."""
	prop(WEAPON_RACK, (x, y, z), yaw=yaw, scale=rack_scale)
	rail = 0.47 * rack_scale
	width = 0.72 * rack_scale
	lean = math.atan2(0.1, rail)
	for i in range(spears):
		dx = -width * 0.38 + width * 0.76 * i / max(1, spears - 1)
		px, pz = _at(x, z, yaw, dx, 0.1 + (i % 2) * 0.012)
		prop(SPEAR, (px, y, pz), yaw=yaw + (i % 2) * 0.4, pitch=-lean, scale=spear_scale)


def bow_rack(x, z, yaw=0.0, bows=3, rack_scale=1.1, bow_scale=SCALE_BOW):
	"""The weapon rack with bows standing in front of it, leaning back on the rail (front = +z, turned by yaw)."""
	prop(WEAPON_RACK, (x, 0.0, z), yaw=yaw, scale=rack_scale)
	rail = 0.47 * rack_scale
	width = 0.72 * rack_scale
	lean = math.atan2(0.14, rail)
	for i in range(bows):
		dx = -width * 0.3 + width * 0.6 * i / max(1, bows - 1)
		px, pz = _at(x, z, yaw, dx, 0.13 + (i % 2) * 0.015)
		# Each turned a little differently: parallel copies side by side can share face planes (z-fighting).
		prop(BOW, (px, 0.0, pz), yaw=yaw + math.pi / 2 + (i - (bows - 1) / 2) * 0.15, roll=-lean, scale=bow_scale)


def arrows_in(x, top_y, z, count=6, radius=0.07, scale=SCALE_ARROW):
	"""Arrows standing head-down in something round (a barrel, a quiver) whose top is at top_y."""
	for i in range(count):
		a = i * math.tau / count
		prop(ARROW, (x + math.cos(a) * radius, top_y + 0.11 * scale + (i % 2) * 0.03, z + math.sin(a) * radius),
				yaw=a, pitch=math.pi / 2 - 0.12, scale=scale)


def wall_banner(x, z, y_top, yaw=0.0, scale=0.75):
	"""The dungeon wall banner hanging (top at y_top) on a wall face through (x, z) that faces +z turned by yaw."""
	px, pz = _at(x, z, yaw, 0.0, 0.53 * scale + 0.005)
	prop(WALL_BANNER, (px, y_top - 0.88 * scale, pz), yaw=yaw, scale=scale)
