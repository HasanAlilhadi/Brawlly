# Builds assets/environment/buildings/armory.glb: the trading post "Bows & Spears" stall (own model, Kenney mini style,
# on tools/blender_kit.py): a log cabin with a red tile roof, a shop window with a counter (arrows, a quiver) under a
# striped awning, a bow on the wall, and in the yard a spear rack, a bow stand, a barrel of arrows and an archery
# target with arrows in it. The bows, spears, arrows, barrel, target and racks are the game's own models
# (tools/blender_props.py, placed with kit.prop(); written into armory.tscn), so they match the rest of the game.
# Run from the project folder:  blender -b --python tools/blender_armory.py [-- --check] [-- --preview out.png]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from blender_kit import *  # palette cells, G* helpers, generic pieces
import blender_props as props  # the game's existing models, placed with kit.prop()
from mathutils import Matrix, Vector

OUTPUT = os.path.join(kit.PROJECT, "assets", "environment", "buildings", "armory.glb")

# --- Layout ------------------------------------------------------------------------------------------------
# Godot stall space, meters: x right, y up, +z toward the trading post center (customers stand at z = 1.7).
# KEEP IN SYNC with the armory "block" in scenes/world/shop_station.gd (collision footprint).
MODEL_SCALE = 1.5
CABIN = (-1.3, 1.3, -2.0, -0.95)      # log line of the walls: x0, x1, z0, z1
LOG_R = 0.075
LOG_STEP = 0.13                       # logs of one wall overlap a little (no gaps)
LOGS = 11
EAVE = 1.68                           # top of the wall plate, where the roof starts
FZ = CABIN[3] + 0.07                  # front face of the front wall logs
YARD_Z = 0.45                         # front edge of the yard


def log(a, b):
	"""One wall log from a to b (Godot points) with lighter cut ends set just beyond the log's end faces."""
	grod("log", a, b, LOG_R, LOG_R, WOOD, 8)
	d = (Vector(b) - Vector(a)).normalized()
	for end, sign in ((a, -1), (b, 1)):
		p = Vector(end) + d * sign * 0.004
		q = Vector(end) + d * sign * 0.012
		grod("log_end", tuple(p), tuple(q), LOG_R * 0.75, LOG_R * 0.75, TAN, 8)


def build():
	x0, x1, z0, z1 = CABIN
	zc = (z0 + z1) * 0.5

	# Ground: stone plinth under the cabin, packed dirt yard in front with flagstones to the door.
	gbox("plinth", x0 - 0.06, x1 + 0.06, 0, 0.12, z0 - 0.06, z1 + 0.06, STONE)
	gbox("yard", x0 - 0.15, x1 + 0.2, 0, 0.025, z1 + 0.06, YARD_Z, TAN, False)
	for x, z, w, d in ((0.85, -0.45, 0.26, 0.2), (0.8, -0.15, 0.24, 0.2), (0.88, 0.17, 0.26, 0.2)):
		gbox("flagstone", x - w / 2, x + w / 2, 0.025, 0.04, z - d / 2, z + d / 2, PALE, False)

	# Log walls: front / back logs and side logs alternate half a log in height and cross at the corners; their
	# ends stick out by alternating lengths (equal ends would put the end faces in one plane: z-fighting).
	for k in range(LOGS):
		y = 0.18 + k * LOG_STEP
		ext = 0.1 + (0.03 if k % 2 else 0.0)
		log((x0 - ext, y, z1), (x1 + ext, y, z1))
		log((x0 - ext, y, z0), (x1 + ext, y, z0))
		y2 = y + LOG_STEP * 0.5
		ext2 = 0.1 + (0.0 if k % 2 else 0.03)
		log((x0, y2, z0 - ext2), (x0, y2, z1 + ext2))
		log((x1, y2, z0 - ext2), (x1, y2, z1 + ext2))

	# Roof: wall plate, red tile gable roof (ridge along x), plank gables.
	gbox("wall_plate", x0 - 0.1, x1 + 0.1, EAVE - 0.08, EAVE, z0 - 0.1, z1 + 0.1, WOOD)
	half, pitch = tile_roof(x0 - 0.14, x1 + 0.14, z0 - 0.1, z1 + 0.1, EAVE, 0.62, rows=3, cell=RED, overhang=0.2)
	for x in (x0 - 0.02, x1 + 0.02):
		facade_prism("gable", [(-(half - 0.22), 0), (half - 0.22, 0), (0, 0.58)], 0.04, TAN, x, EAVE, zc, True,
				yaw=math.radians(90))
	for side in (-1, 1):
		window(x1 + 0.07 if side > 0 else x0 - 0.07, 1.0, zc, yaw=math.radians(90 * side), w=0.3, h=0.32)
	window(0.0, 1.0, z0 - 0.07, yaw=math.radians(180), w=0.3, h=0.32)

	# Shop window with a counter, under a striped awning.
	wx0, wx1 = -1.06, -0.04
	gbox("shop_hole", wx0 + 0.06, wx1 - 0.06, 0.72, 1.28, FZ, FZ + 0.02, DARK, False)
	gbox("shop_frame", wx0, wx1, 1.28, 1.34, FZ, FZ + 0.05, WOOD, False)
	for a, b in ((wx0, wx0 + 0.06), (wx1 - 0.06, wx1)):
		gbox("shop_frame", a, b, 0.72, 1.28, FZ, FZ + 0.05, WOOD, False)
	gbox("counter", wx0 - 0.04, wx1 + 0.04, 0.62, 0.7, FZ, FZ + 0.3, TAN)
	for x in (wx0 + 0.08, wx1 - 0.08):
		gbox("counter_bracket", x - 0.025, x + 0.025, 0.3, 0.62, FZ, FZ + 0.2, WOOD)
	# The game's arrows lying on the counter, a quiver (no model for one yet) with arrows standing in it.
	for i in range(3):
		prop(props.ARROW, (-0.72 + i * 0.03, 0.75 + i * 0.012, FZ + 0.1 + i * 0.07), yaw=math.radians(90) + 0.08 * i,
				scale=props.SCALE_ARROW)
	qx, qz = -0.2, FZ + 0.15
	gcyl("quiver", (qx, 0.86, qz), 0.06, 0.32, RED, 8, True)
	gcyl("quiver_band", (qx, 0.95, qz), 0.064, 0.04, WOOD, 8)
	props.arrows_in(qx, 1.02, qz, count=3, radius=0.025)
	# Awning: alternating white / green slats sloping out from the wall, a scalloped edge, two iron stays.
	aw0, aw1, slats = wx0 - 0.1, wx1 + 0.1, 8
	depth, top, low = 0.5, 1.5, 1.28
	slope = math.hypot(depth, top - low)
	tilt = math.atan2(top - low, depth)
	step = (aw1 - aw0) / slats
	for i in range(slats):
		cell = WHITE if i % 2 else GREEN
		x = aw0 + step * (i + 0.5)
		gcube("awning", (x, (top + low) * 0.5 + 0.015, FZ + depth * 0.5), (step, 0.03, slope), cell, False, pitch=tilt)
		facade_prism("awning_edge", [(-step / 2, 0.0), (0.0, -0.08), (step / 2, 0.0)], 0.02, cell, x, low + 0.01,
				FZ + depth - 0.005, False)
	for x in (aw0 + 0.05, aw1 - 0.05):
		grod("awning_stay", (x, 1.02, FZ), (x, low + 0.02, FZ + depth - 0.03), 0.012, 0.012, SLATE, 6)

	# Door on the right, a bow hanging between it and the window, a sign board with an arrow above the door.
	dx = 0.8
	facade_prism("door_frame", [(-0.28, 0), (0.28, 0), (0.28, 1.0), (-0.28, 1.0)], 0.03, WOOD, dx, 0.12, FZ + 0.005,
			False)
	facade_prism("door", [(-0.23, 0), (0.23, 0), (0.23, 0.95), (-0.23, 0.95)], 0.03, WOOD, dx, 0.12, FZ + 0.02, True)
	for y in (0.35, 0.85):
		gcube("door_band", (dx, y, FZ + 0.045), (0.44, 0.05, 0.02), SLATE, False)
	gcube("door_ring", (dx - 0.14, 0.6, FZ + 0.06), (0.04, 0.04, 0.02), YELLOW, False)
	gbox("door_step", dx - 0.32, dx + 0.32, 0, 0.06, z1 + 0.07, z1 + 0.3, PALE)
	gbox("sign_board", dx - 0.24, dx + 0.24, 1.18, 1.42, FZ, FZ + 0.03, TAN)
	prop(props.ARROW, (dx, 1.3, FZ + 0.09), yaw=math.radians(90), roll=math.radians(90), scale=0.9)
	prop(props.BOW, (0.24, 0.68, FZ + 0.035), yaw=math.radians(90), scale=props.SCALE_BOW)

	# Yard: the weapon rack with spears (left) and one with bows (right); a barrel of arrows by the door; the archery
	# target with arrows in it on the right side.
	props.spear_rack(-0.85, 0.1, spears=5)
	props.bow_rack(0.25, 0.1, bows=3)
	prop(props.BARREL, (1.25, 0.0, -0.6), yaw=0.3, scale=0.95)
	props.arrows_in(1.25, 0.46, -0.6, count=6, radius=0.09)
	tx, tz, tyaw = 1.72, -1.15, math.radians(35)
	prop(props.TARGET, (tx, 0.0, tz), yaw=tyaw, scale=1.4)
	for dx_, y in ((0.05, 0.5), (-0.12, 0.38)):
		c, s_ = math.cos(tyaw), math.sin(tyaw)
		fz_ = 0.3  # in front of the target face, pointing into it
		prop(props.ARROW, (tx + dx_ * c + fz_ * s_, y, tz - dx_ * s_ + fz_ * c), yaw=tyaw + math.pi, scale=props.SCALE_ARROW)

	# Left side: unfinished bow staves leaning on the wall, a crate.
	for i in range(4):
		z = -1.25 + i * 0.07
		grod("stave", (x0 - 0.32, 0.0, z), (x0 - 0.1, 1.15 - i * 0.04, z + 0.02), 0.016, 0.012, TAN, 6, True)
	crate(x0 - 0.3, -0.6, yaw=0.2, s=0.9)


run(build, "armory", OUTPUT, scale=MODEL_SCALE,
		aim=Vector(G(0.2, 0.7, -0.8)) / MODEL_SCALE, dist=3.6, height=3.0)
