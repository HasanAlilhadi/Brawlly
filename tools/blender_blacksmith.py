# Builds assets/environment/buildings/blacksmith.glb: the trading post Blacksmith, a small forge workshop (own model,
# Kenney mini style, on tools/blender_kit.py): a stone-and-timber house with a tile roof, an open workshop under a
# lean-to in front of it (the customer side) with the glowing forge and its chimney, bellows, an anvil on a stump,
# a quenching trough, a grindstone and swords / shields on display (the game's own models), and a hanging sign.
# Run from the project folder:  blender -b --python tools/blender_blacksmith.py [-- --check] [-- --preview out.png]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from blender_kit import *  # palette cells, G* helpers, generic pieces
import blender_props as props  # the game's existing models (swords, shields, barrels…), placed with kit.prop()
from mathutils import Matrix, Vector

OUTPUT = os.path.join(kit.PROJECT, "assets", "environment", "buildings", "blacksmith.glb")

# --- Layout ------------------------------------------------------------------------------------------------
# Godot stall space, meters: x right, y up, +z toward the trading post center (customers stand at z = 1.7).
# KEEP IN SYNC with the blacksmith collision in scenes/world/shop_station.gd (HOUSE / WORKSHOP rects).
MODEL_SCALE = 1.5
HOUSE = (-1.5, 1.5, -2.1, -0.9)       # x0, x1, z0, z1
HOUSE_H = 1.75                        # wall height (eaves)
FRONT = 0.4                           # the lean-to's posts (front edge of the workshop)
FORGE = (-1.45, -0.55, -0.9, -0.15)   # stone forge against the house, left
CANOPY_X = -0.3                       # the canopy over the forge ends here (x) ...
CANOPY_Z = 0.0                        # ... and here (z)
EMBER = (10, 1)                       # glowing coals (orange gradient)


def anvil(x, z, yaw=0.0):
	gcyl("anvil_stump", (x, 0.2, z), 0.2, 0.4, WOOD, 8, True)
	gcyl("anvil_stump_top", (x, 0.405, z), 0.17, 0.01, TAN, 8)
	c, s = math.cos(yaw), math.sin(yaw)
	gcube("anvil_foot", (x, 0.46, z), (0.26, 0.1, 0.18), SLATE, True, yaw=yaw)
	gcube("anvil_waist", (x, 0.55, z), (0.14, 0.08, 0.11), DARK, False, yaw=yaw)
	gcube("anvil_face", (x, 0.63, z), (0.34, 0.09, 0.15), SLATE, True, yaw=yaw)
	# Horn: a wedge sticking out of the face's +x end.
	horn = [(0.0, -0.045), (0.16, -0.01), (0.16, 0.01), (0.0, 0.045)]
	hx, hz = x + c * 0.17, z - s * 0.17
	facade_prism("anvil_horn", horn, 0.08, SLATE, hx, 0.63, hz, True, yaw=yaw)
	# A red-hot bar and the hammer lying on it.
	gcube("hot_bar", (x - c * 0.03, 0.69, z - s * 0.03 + 0.02), (0.2, 0.025, 0.03), ORANGE, False, yaw=yaw + 0.15)
	gcube("hammer_handle", (x + 0.05, 0.695, z + 0.06), (0.03, 0.03, 0.2), WOOD, False, yaw=yaw - 0.4)
	gcube("hammer_head", (x + 0.1, 0.705, z + 0.15), (0.1, 0.05, 0.05), DARK, False, yaw=yaw - 0.4)


def build():
	hx0, hx1, hz0, hz1 = HOUSE
	hcx, hcz = (hx0 + hx1) * 0.5, (hz0 + hz1) * 0.5

	# Workshop floor: packed dirt with stepping flagstones (flagstones never overlap).
	gbox("yard", hx0, hx1 + 0.05, 0, 0.025, hz1, FRONT + 0.15, TAN, False)
	for x, z, w, d in ((-0.05, 0.28, 0.3, 0.22), (-0.45, 0.12, 0.24, 0.2), (0.55, 0.3, 0.26, 0.2)):
		gbox("flagstone", x - w / 2, x + w / 2, 0.025, 0.04, z - d / 2, z + d / 2, PALE, False)

	# House: stone ground course, plaster above with a timber frame, gable tile roof (ridge along x).
	gbox("house_plinth", hx0 - 0.04, hx1 + 0.04, 0, 0.12, hz0 - 0.04, hz1 + 0.04, DARK)
	gbox("house_stone", hx0, hx1, 0, 0.8, hz0, hz1, STONE)
	gbox("house_beam", hx0 - 0.05, hx1 + 0.05, 0.78, 0.88, hz0 - 0.05, hz1 + 0.05, WOOD)
	gbox("house_upper", hx0 - 0.03, hx1 + 0.03, 0.88, HOUSE_H, hz0 - 0.03, hz1 + 0.03, PLASTER)
	for x in (hx0 - 0.05, hx1 + 0.05):
		for z in (hz0 - 0.05, hz1 + 0.05):
			gcube("frame_post", (x, (0.88 + HOUSE_H - 0.01) * 0.5, z), (0.08, HOUSE_H - 0.89, 0.08), WOOD)
	for x in (-0.55, 0.55):
		gcube("frame_stud", (x, (0.88 + HOUSE_H) * 0.5, hz0 - 0.045), (0.06, HOUSE_H - 0.9, 0.03), WOOD)
	for side in (-1, 1):
		x = hx1 + 0.045 if side > 0 else hx0 - 0.045
		gcube("frame_brace", (x, (0.88 + HOUSE_H) * 0.5, hcz), (0.03, 0.06, 1.0), WOOD, False,
				pitch=math.radians(35))
	masonry("x", hx0, -1, hz0 + 0.1, hz1 - 0.1, 0.18, 0.72, 4)
	masonry("x", hx1, 1, hz0 + 0.1, hz1 - 0.1, 0.18, 0.72, 4)
	masonry("z", hz0, -1, hx0 + 0.1, hx1 - 0.1, 0.18, 0.72, 7)
	gbox("top_plate", hx0 - 0.08, hx1 + 0.08, HOUSE_H - 0.02, HOUSE_H + 0.06, hz0 - 0.08, hz1 + 0.08, WOOD)
	half, pitch = tile_roof(hx0 - 0.08, hx1 + 0.08, hz0 - 0.08, hz1 + 0.08, HOUSE_H + 0.06, 0.7, rows=3,
			overhang=0.2)
	for x in (hx0 - 0.06, hx1 + 0.02):
		facade_prism("gable", [(-(half - 0.22), 0), (half - 0.22, 0), (0, 0.64)], 0.04, PLASTER, x + 0.02,
				HOUSE_H + 0.06, hcz, True, yaw=math.radians(90))
	# Side windows and a back window.
	for side in (-1, 1):
		window(hx1 + 0.03 if side > 0 else hx0 - 0.03, 1.3, hcz, yaw=math.radians(90 * side), w=0.3, h=0.32)
	window(0.6, 1.3, hz0 - 0.03, yaw=math.radians(180), w=0.3, h=0.32)
	window(-0.6, 1.3, hz0 - 0.03, yaw=math.radians(180), w=0.3, h=0.32)

	# Front wall (inside the workshop): door, a display board with swords and shields.
	fz = hz1 + 0.03
	facade_prism("door_frame", [(-0.3, 0), (0.3, 0), (0.3, 0.95), (-0.3, 0.95)], 0.03, WOOD, 0.95, 0.12, fz + 0.015,
			False)
	facade_prism("door", [(-0.25, 0), (0.25, 0), (0.25, 0.9), (-0.25, 0.9)], 0.03, WOOD, 0.95, 0.12, fz + 0.04, True)
	for y in (0.35, 0.8):
		gcube("door_band", (0.95, y, fz + 0.06), (0.46, 0.05, 0.02), SLATE, False)
	gcube("door_ring", (0.8, 0.55, fz + 0.075), (0.04, 0.04, 0.02), YELLOW, False)
	window(0.95, 1.42, fz, w=0.28, h=0.26)
	gbox("display", -0.35, 0.55, 0.95, 1.6, fz, fz + 0.03, WOOD)
	# The game's own sword and round shield (blade up, origin at the grip).
	for x, dy in ((-0.2, 0.0), (0.08, 0.03)):  # different heights: their guards never share a plane
		prop(props.SWORD, (x, 1.1 + dy, fz + 0.1), scale=props.SCALE_SWORD)
	prop(props.SHIELD, (0.36, 1.3, fz + 0.075), scale=0.8)

	# Forge: stone hearth with glowing coals, a stone hood and a chimney through the roof, bellows beside it.
	fx0, fx1, fz0, fz1 = FORGE
	fcx, fcz = (fx0 + fx1) * 0.5, (fz0 + fz1) * 0.5
	gbox("forge_plinth", fx0 - 0.03, fx1 + 0.03, 0, 0.1, fz0 + 0.02, fz1 + 0.03, DARK)
	gbox("forge", fx0, fx1, 0, 0.55, fz0 + 0.01, fz1, STONE)
	gbox("forge_rim", fx0 - 0.02, fx1 + 0.02, 0.55, 0.62, fz0 + 0.01, fz1 + 0.02, PALE, False)
	gbox("coals", fx0 + 0.1, fx1 - 0.1, 0.62, 0.64, fz0 + 0.1, fz1 - 0.1, EMBER, False)
	for x, z, s in ((-1.12, -0.5, 0.09), (-0.88, -0.42, 0.07), (-1.0, -0.62, 0.08)):
		gcube("ember", (x, 0.68, z), (s, 0.06, s), YELLOW, False, yaw=x * 3.0)
	gcube("flame", (fcx, 0.74, fcz - 0.08), (0.12, 0.12, 0.12), ORANGE, False, yaw=math.radians(45))
	gcube("flame", (fcx, 0.84, fcz - 0.1), (0.07, 0.1, 0.07), YELLOW, False, yaw=math.radians(20))
	# Hood: a tapered stone funnel over the back half, then the chimney up past the roof ridge.
	cylinder("hood", G(fcx, 1.25, fz0 + 0.26), 0.36, 0.5, STONE, 4, True,
			Matrix.Rotation(math.radians(45), 4, "Z"), top=0.17)
	hood_z = fz0 + 0.26
	gbox("hood_band", fcx - 0.27, fcx + 0.27, 0.98, 1.03, hood_z - 0.27, hood_z + 0.27, DARK, False)
	gbox("chimney", fcx - 0.15, fcx + 0.15, 1.5, HOUSE_H + 1.05, hood_z - 0.15, hood_z + 0.15, STONE)
	gbox("chimney_cap", fcx - 0.19, fcx + 0.19, HOUSE_H + 1.05, HOUSE_H + 1.12, hood_z - 0.19, hood_z + 0.19, DARK,
			False)
	for y, dz in ((2.0, -0.05), (2.35, 0.06)):
		gcube("chimney_stone", (fcx - 0.05 - dz, y, hood_z + 0.16), (0.12, 0.08, 0.02), PALE, False)
	# Bellows: two boards and a leather bag, nozzle into the forge's side.
	bx, bz = fx1 + 0.28, -0.35
	gcube("bellows_leg", (bx, 0.15, bz), (0.3, 0.3, 0.24), WOOD, True)
	gcube("bellows_low", (bx, 0.33, bz), (0.4, 0.04, 0.26), WOOD, False, yaw=0.0)
	gcube("bellows_bag", (bx, 0.4, bz), (0.34, 0.1, 0.22), SALMON, True)
	gcube("bellows_top", (bx, 0.48, bz), (0.42, 0.04, 0.27), WOOD, False, pitch=math.radians(-6))
	gcube("bellows_nozzle", (bx - 0.24, 0.37, bz), (0.12, 0.04, 0.04), SLATE, False)
	gcube("bellows_handle", (bx + 0.26, 0.52, bz), (0.12, 0.03, 0.05), WOOD, False)

	# Anvil in the middle of the workshop, quenching trough and grindstone on the right.
	anvil(0.3, -0.1, yaw=math.radians(-12))
	# Trough: a wooden box with water.
	tx, tz = 1.2, -0.45
	gbox("trough", tx - 0.2, tx + 0.2, 0, 0.3, tz - 0.3, tz + 0.3, WOOD)
	gbox("trough_water", tx - 0.16, tx + 0.16, 0.3, 0.31, tz - 0.26, tz + 0.26, BLUE, False)
	gbox("trough_band", tx - 0.21, tx + 0.21, 0.12, 0.17, tz - 0.31, tz + 0.31, SLATE, False)
	# Grindstone: a stone wheel on a wooden frame with a crank.
	gx, gz = 1.05, 0.15
	for dz in (-0.12, 0.12):
		gcube("grind_leg", (gx, 0.22, gz + dz), (0.06, 0.44, 0.06), WOOD, True)
	gcube("grind_base", (gx, 0.04, gz), (0.3, 0.08, 0.34), WOOD, False)
	m = Matrix.Rotation(math.radians(90), 4, "X")
	cylinder("grindstone", G(gx, 0.42, gz), 0.2, 0.08, PALE, 12, False, m)
	cylinder("grind_axle", G(gx, 0.42, gz), 0.03, 0.28, DARK, 6, False, m)
	gcube("grind_crank", (gx, 0.36, gz + 0.16), (0.03, 0.12, 0.03), WOOD, False)

	# A small tiled canopy over the forge only (the rest of the workshop stays open, so the game's top-down camera
	# sees the anvil and tools); a signpost at the front left with a hanging board.
	lean_to(hx0 - 0.02, CANOPY_X, hz1 + 0.03, CANOPY_Z, HOUSE_H - 0.05, 1.35, posts=(hx0 + 0.06, CANOPY_X - 0.06))
	px, pz = hx0 + 0.12, FRONT
	gcube("sign_post", (px, 0.65, pz), (0.08, 1.3, 0.08), WOOD, True)
	gcube("sign_post_cap", (px, 1.32, pz), (0.11, 0.04, 0.11), WOOD, False)
	sx = px + 0.36
	gcube("sign_arm", (px + 0.22, 1.24, pz), (0.4, 0.05, 0.05), WOOD, False)
	for dx in (-0.1, 0.1):
		gcube("sign_chain", (sx + dx, 1.185, pz), (0.015, 0.07, 0.015), SLATE, False)
	gcube("sign_board", (sx, 1.04, pz), (0.34, 0.22, 0.04), TAN, True)
	# Anvil icon on both faces of the board.
	for side in (-1, 1):
		zf = pz + side * 0.025
		gcube("sign_anvil", (sx, 1.07, zf), (0.18, 0.04, 0.01), DARK, False)
		gcube("sign_anvil", (sx, 1.02, zf), (0.06, 0.06, 0.01), DARK, False)
		gcube("sign_anvil", (sx, 0.975, zf), (0.14, 0.03, 0.01), DARK, False)

	# Outside: firewood / charcoal pile on the left, a barrel and ore crate on the right.
	for dx, y, length in ((-0.08, 0.065, 0.6), (0.08, 0.065, 0.6), (0.0, 0.18, 0.54)):
		cylinder("log", G(hx0 - 0.3 + dx, y, -0.5), 0.065, length, WOOD, 6, True,
				Matrix.Rotation(math.radians(90), 4, "X"))
	prop(props.BARREL, (hx1 + 0.28, 0.0, -1.25), yaw=0.4, scale=0.95)
	crate(hx1 + 0.28, -0.6, yaw=0.25, s=0.8)
	for x, z in ((hx1 + 0.22, -0.66), (hx1 + 0.34, -0.55)):
		gcube("ore", (x, 0.33, z), (0.09, 0.07, 0.09), SLATE, True, yaw=x * 5)


run(build, "blacksmith", OUTPUT, scale=MODEL_SCALE,
		aim=Vector(G(0.0, 0.7, -0.8)) / MODEL_SCALE, dist=3.6, height=3.0)
