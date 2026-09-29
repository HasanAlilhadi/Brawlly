# Builds assets/environment/buildings/town.glb + town.tscn: the town every spawn point gets (always the same layout,
# never turned): a paved square with a compass mosaic in the middle (kept open: players spawn there, the CTF flag
# stands there), the Barracks at its north end, Blacksmith + Healer on the west side, Bows & Spears on the east,
# a well and a market stall in the south-east, a statue, lamp posts with bunting, benches, flower planters, hedges
# and a south road through an entrance arch; the game's choppable trees stand on its "Tree_<n>" markers.
# The scene also carries the spots the game places things on (markers "Stall_<id>", "StarterChest") and the
# collision of the decoration; the stalls themselves are separate ShopStation nodes (scenes/world/town.gd).
# Existing models (fences, flags, barrels, pots, plants, rocks, statue, shield) are placed with kit.prop();
# the buildings are loaded only for --check / --preview (export=False) to lay the town out around them.
# Run from the project folder:  blender -b --python tools/blender_town.py [-- --check] [-- --preview out.png]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from blender_kit import *  # palette cells, G* helpers, generic pieces
import blender_props as props
from mathutils import Matrix, Vector

OUTPUT = os.path.join(kit.PROJECT, "assets", "environment", "buildings", "town.glb")

# --- Layout ------------------------------------------------------------------------------------------------
# Town space, meters: x east, y up, +z south (toward the default camera); the spawn point is the origin.
STALL_SCALE = 1.5  # ShopStation.MODEL_SCALE
STALLS = {         # stall id -> (x, z, yaw degrees; yaw turns the building's front (+z) toward the square)
	"barracks": (0.0, -5.4, 0.0),
	"blacksmith": (-7.4, -1.6, 90.0),
	"healer": (-7.4, 4.2, 90.0),
	"armory": (7.4, -1.6, -90.0),
}
SQUARE = (-6.7, 6.7, -4.4, 6.6)  # the paved square: x0, x1, z0, z1
ROAD = (-1.2, 1.2, 6.6, 12.0)    # the road south out of town
MOSAIC_R = 2.3
MONUMENT = (0.0, 4.6)
CHEST = (2.3, -2.9)
ARCH_Z = 10.4
LAMPS = [(-5.9, -3.8), (5.9, -3.8), (-6.2, 1.3), (6.2, 1.3), (-6.2, 6.3), (6.2, 6.3)]
TREES = [(-4.9, -6.8, 1.0), (-5.6, -11.2, 1.15), (5.8, -11.6, 1.1), (8.9, -6.2, 1.05), (-10.3, 1.4, 1.1),
		(10.3, 1.4, 0.95), (-4.6, 9.0, 1.0), (4.6, 9.0, 1.05), (-9.8, 8.4, 1.2), (10.0, 8.6, 1.1)]
BENCHES = [(-4.2, 0.3, 1), (4.2, 0.3, -1)]  # x, z, which way the seat faces (+1 = east)
PLANTERS = [(-4.4, -3.1), (4.4, -3.1), (-3.6, 3.3), (3.6, 3.3)]
WELL = (7.9, 4.3)
MARKET = (8.3, 7.4)
LIQUID = (14, 1)
TAN_DEEP = (3, 1)  # middle of the tan gradient column: a deeper peach
ROPE_Y = 2.05


def _building_rects():
	"""Ground rects (x0, x1, z0, z1) the buildings cover, from their real models (imported for the check only)."""
	rects = []
	for stall_id, (x, z, yaw) in STALLS.items():
		root = prop("res://assets/environment/buildings/%s.glb" % stall_id, (x, 0.0, z), yaw=math.radians(yaw),
				scale=STALL_SCALE, export=False)
		pts = [o.matrix_world @ Vector(c) for o in root.children_recursive if o.type == "MESH" for c in o.bound_box]
		xs = [p.x for p in pts]
		zs = [-p.y for p in pts]
		rects.append((min(xs) - 0.1, max(xs) + 0.1, min(zs) - 0.1, max(zs) + 0.1))
		marker("Stall_%s" % stall_id, (x, 0.0, z), math.radians(yaw))
	return rects


def paving(x0, x1, z0, z1, skip, tile=0.5, gap=0.05):
	"""Cobbles in running bond over a grout base; `skip(x, z)` leaves holes (mosaic, buildings)."""
	gbox("grout", x0, x1, 0.0, 0.012, z0, z1, SLATE, False)
	rows = int((z1 - z0) / tile)
	for r in range(rows + 1):
		a = z0 + 0.03 + r * tile
		b = min(a + tile - gap, z1 - 0.03)
		if b - a < 0.15:
			continue
		offset = tile * 0.5 if r % 2 else 0.0
		x = x0 - offset
		while x < x1:
			c, d = max(x, x0 + 0.03), min(x + tile - gap, x1 - 0.03)
			x += tile
			if d - c < 0.15 or any(skip(px, pz) for px, pz in ((c, a), (d, a), (c, b), (d, b), ((c + d) * 0.5, (a + b) * 0.5))):
				continue
			roll = rng.random()
			cell = TAN if roll < 0.45 else (TAN_DEEP if roll < 0.7 else (PLASTER if roll < 0.9 else SALMON))
			gbox("cobble", c, d, 0.012, 0.018 + rng.random() * 0.008, a, b, cell, False)  # below the mosaic tops


def mosaic(cx, cz):
	"""Compass rose in the middle of the square (flat, walkable)."""
	m = Matrix.Translation(G(cx, 0.0, cz))
	for i, (r, top, cell) in enumerate(((MOSAIC_R, 0.028, STONE), (MOSAIC_R - 0.2, 0.033, RED),
			(MOSAIC_R - 0.34, 0.037, TAN))):
		cylinder("mosaic_ring", G(cx, (0.012 + top) * 0.5, cz), r, top - 0.012, cell, 32)
	for k in range(8):  # eight points: long gold ones on the axes, short orange ones between
		long = k % 2 == 0
		a = k * math.pi / 4
		ro, ri, top = (1.75, 0.42, 0.047) if long else (1.15, 0.38, 0.042)
		top += 0.003 * ((k // 2) % 2)  # neighbors at different heights
		pts = [(0.0, 0.0)]
		for da, r in ((-math.pi / 8, ri), (0.0, ro), (math.pi / 8, ri)):
			pts.append((cx + math.sin(a + da) * r, cz - math.cos(a + da) * r))
		pts[0] = (cx, cz)
		floor_prism("mosaic_point", pts, 0.037, top, YELLOW if long else ORANGE)
	cylinder("mosaic_eye", G(cx, 0.049, cz), 0.3, 0.008, BLUE, 16)


def lamp_post(x, z):
	loft("lamp_base", [(0.0, ngon(0.17, 0.17, 8)), (0.18, ngon(0.15, 0.15, 8)), (0.26, ngon(0.09, 0.09, 8))], STONE,
			True, Matrix.Translation(G(x, 0.0, z)))
	grod("lamp_pole", (x, 0.25, z), (x, 2.12, z), 0.045, 0.035, DARK, 8)
	gcube("lamp_floor", (x, 2.14, z), (0.2, 0.04, 0.2), DARK, False)
	gcube("lamp_glass", (x, 2.27, z), (0.14, 0.22, 0.14), YELLOW, True)
	for dx in (-0.075, 0.075):
		for dz in (-0.075, 0.075):
			grod("lamp_frame", (x + dx, 2.16, z + dz), (x + dx, 2.37, z + dz), 0.011, 0.011, DARK, 6)
	cylinder("lamp_cap", G(x, 2.45, z), 0.16, 0.14, DARK, 4, False, Matrix.Rotation(math.radians(45), 4, "Z"), top=0.0)
	ball("lamp_finial", Vector(G(x, 2.55, z)), 0.03, DARK)
	solid_cyl(x, z, 0.15, 2.4)


def bunting(a, b, sag=0.35, spacing=0.34):
	"""A sagging rope between two lamp tops with little triangular flags."""
	ax, az = a
	bx, bz = b
	length = math.hypot(bx - ax, bz - az)
	yaw = math.atan2(-(bz - az), bx - ax)
	steps = 8
	def at(t):
		return (ax + (bx - ax) * t, ROPE_Y - sag * 4 * t * (1 - t), az + (bz - az) * t)
	for i in range(steps):
		r = 0.008 if i % 2 else 0.01  # neighbors never share a face plane
		grod("rope", at(i / steps), at((i + 1) / steps), r, r, TAN, 4)
	colors = (RED, YELLOW, BLUE, WHITE, GREEN)
	count = int(length / spacing)
	for i in range(1, count):
		t = i / count
		x, y, z = at(t)
		facade_prism("pennant_flag", [(-0.08, 0.0), (0.0, -0.17), (0.08, 0.0)], 0.004, colors[i % len(colors)],
				x, y - 0.005, z, False, yaw)


def bench(x, z, facing):
	"""Wooden bench along z on stone feet; the seat faces east (facing +1) or west (-1)."""
	for dz in (-0.45, 0.45):
		gbox("bench_foot", x - 0.18, x + 0.18, 0.0, 0.36, z + dz - 0.07, z + dz + 0.07, STONE)
	for i, dx in enumerate((-0.1, 0.1)):
		gbox("bench_slat", x + dx - 0.085, x + dx + 0.085, 0.36, 0.42, z - 0.65, z + 0.65, WOOD, False)
	back = x - facing * 0.2
	for dz in (-0.45, 0.45):
		gbox("bench_post", back - 0.03, back + 0.03, 0.42, 0.8, z + dz - 0.04, z + dz + 0.04, WOOD)
	for y in (0.58, 0.74):
		gbox("bench_back", back - 0.02 - facing * 0.03, back + 0.02 - facing * 0.03, y - 0.05, y + 0.05, z - 0.62,
				z + 0.62, WOOD, False)
	solid_box(x - 0.25, x + 0.25, 0.0, 0.8, z - 0.66, z + 0.66)


def flowers(x0, x1, z0, z1, y, count):
	colors = (RED, YELLOW, WHITE, SALMON, LAVENDER)
	for i in range(count):
		fx = rng.uniform(x0, x1)
		fz = rng.uniform(z0, z1)
		h = rng.uniform(0.1, 0.18)
		grod("stem", (fx, y, fz), (fx, y + h, fz), 0.008, 0.008, GREEN, 4)
		turn = Matrix.Translation(G(fx, y + h + 0.02, fz)) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z")
		ball("flower", Vector(), 0.03 + 0.003 * (i % 4), colors[i % len(colors)], turn)


def planter(x, z):
	gbox("planter", x - 0.5, x + 0.5, 0.0, 0.34, z - 0.3, z + 0.3, STONE)
	gbox("planter_rim", x - 0.54, x + 0.54, 0.34, 0.4, z - 0.34, z + 0.34, PALE, False)
	gbox("planter_soil", x - 0.46, x + 0.46, 0.4, 0.41, z - 0.26, z + 0.26, DARK, False)
	for dx in (-0.25, 0.22):
		prop(props.PLANT, (x + dx, 0.41, z), yaw=dx * 7, scale=1.3)
	flowers(x - 0.42, x + 0.42, z - 0.2, z + 0.2, 0.41, 7)
	solid_box(x - 0.54, x + 0.54, 0.0, 0.5, z - 0.34, z + 0.34)


def hedge(x0, x1, z, width=0.5, height=0.58):
	"""Rounded hedge along x."""
	m = Matrix.Translation(G(x0, height * 0.5, z)) @ Matrix.Rotation(math.radians(90), 4, "Y")
	loft("hedge", [(0.0, ngon(height * 0.5, width * 0.5, 8)), (x1 - x0, ngon(height * 0.5, width * 0.5, 8))], GREEN,
			False, m)
	flowers(x0 + 0.1, x1 - 0.1, z - 0.05, z + 0.05, height - 0.02, int((x1 - x0) * 2))
	solid_box(x0, x1, 0.0, height, z - width * 0.5, z + width * 0.5)


def well(x, z):
	loft("well_ring", [(0.0, ngon(0.64, 0.64, 12)), (0.6, ngon(0.6, 0.6, 12))], STONE, True, Matrix.Translation(G(x, 0.0, z)))
	cylinder("well_rim", G(x, 0.635, z), 0.66, 0.07, PALE, 12)
	cylinder("well_water", G(x, 0.675, z), 0.46, 0.01, LIQUID, 12)
	for dx in (-0.56, 0.56):
		gcube("well_post", (x + dx, 0.85, z), (0.1, 1.7, 0.1), WOOD, True)
	grod("well_winch", (x - 0.62, 1.32, z), (x + 0.62, 1.32, z), 0.035, 0.035, WOOD, 8)
	grod("well_crank", (x + 0.62, 1.32, z), (x + 0.62, 1.18, z + 0.12), 0.015, 0.015, SLATE, 6)
	grod("well_rope", (x, 1.3, z), (x, 1.02, z), 0.008, 0.008, TAN, 4)
	loft("bucket", [(0.0, ngon(0.08, 0.08, 8)), (0.16, ngon(0.1, 0.1, 8))], WOOD, True, Matrix.Translation(G(x, 0.86, z)))
	gcyl("bucket_band", (x, 0.95, z), 0.102, 0.025, SLATE, 8)
	tile_roof(x - 0.7, x + 0.7, z - 0.42, z + 0.42, 1.68, 0.36, rows=2, cell=RED, overhang=0.12)
	solid_cyl(x, z, 0.72, 1.2)


def market_stall(x, z):
	"""Produce stall facing west (toward the square): counter with crates of fruit under a striped canopy."""
	gbox("market_counter", x - 0.3, x + 0.3, 0.0, 0.66, z - 0.75, z + 0.75, TAN)
	gbox("market_top", x - 0.35, x + 0.35, 0.66, 0.72, z - 0.8, z + 0.8, WOOD, False)
	for dx in (-0.36, 0.36):
		for dz in (-0.78, 0.78):
			gcube("market_post", (x + dx, 0.8, z + dz), (0.07, 1.6, 0.07), WOOD, True)
	slats, depth = 8, 1.9
	step = depth / slats
	tilt = math.atan2(0.3, 1.0)
	for i in range(slats):
		zc = z - depth / 2 + step * (i + 0.5)
		box("market_canopy", G(x + 0.02, 1.72, zc), (1.12, step, 0.03), RED if i % 2 else WHITE, False, rot_y=-tilt)
	fruit = (RED, YELLOW, GREEN)
	for i, dz in enumerate((-0.45, 0.0, 0.45)):
		gbox("fruit_box", x - 0.22, x + 0.22, 0.72, 0.84, z + dz - 0.19, z + dz + 0.19, WOOD, False)
		for k in range(7):
			a = k * 2.4
			r = 0.04 + 0.1 * (k % 3) / 2
			ball("fruit", Vector(G(x + math.cos(a) * r, 0.87 + (0.03 if k % 3 == 0 else 0.0), z + dz + math.sin(a) * r)),
					0.055, fruit[i])
	crate(x + 0.2, z + 1.25, yaw=0.3, s=0.9)
	prop(props.BARREL, (x + 0.35, 0.0, z - 1.25), yaw=0.8, scale=0.9)
	solid_box(x - 0.4, x + 0.4, 0.0, 1.0, z - 0.85, z + 0.85)


def arch(z):
	"""Entrance arch over the south road: stone pillars with flags, a beam with the town shield, fences."""
	for side in (-1, 1):
		px = side * 1.75
		gbox("arch_plinth", px - 0.3, px + 0.3, 0.0, 0.14, z - 0.3, z + 0.3, DARK)
		gbox("arch_pillar", px - 0.25, px + 0.25, 0.0, 2.1, z - 0.25, z + 0.25, STONE)
		gbox("arch_cap", px - 0.3, px + 0.3, 2.1, 2.18, z - 0.3, z + 0.3, PALE, False)
		masonry("z", z + 0.25, 1, px - 0.2, px + 0.2, 0.25, 2.0, 5)
		prop(props.FLAG, (px, 2.18, z), yaw=math.radians(-90 if side < 0 else 90))
		solid_box(px - 0.3, px + 0.3, 0.0, 2.2, z - 0.3, z + 0.3)
		for i in range(4):
			fx = side * (2.72 + i * 1.34)
			prop("res://assets/environment/forest/fence.glb", (fx, 0.0, z), scale=1.2)
		solid_box(min(side * 2.05, side * 6.95), max(side * 2.05, side * 6.95), 0.0, 0.5, z - 0.12, z + 0.12)
	gbox("arch_beam", -2.1, 2.1, 1.86, 2.08, z - 0.13, z + 0.13, WOOD)
	prop(props.SHIELD, (0.0, 1.66, z + 0.2), scale=1.1)
	for side in (-1, 1):
		grod("arch_chain", (side * 1.25, 1.86, z + 0.05), (side * 1.25, 1.66, z + 0.05), 0.008, 0.008, SLATE, 4)
		gcube("arch_lantern", (side * 1.25, 1.58, z + 0.05), (0.12, 0.16, 0.12), YELLOW, True)
		gcube("arch_lantern_cap", (side * 1.25, 1.68, z + 0.05), (0.15, 0.04, 0.15), DARK, False)


def build():
	rects = _building_rects()
	marker("StarterChest", (CHEST[0], 0.0, CHEST[1]), math.radians(-20))

	def in_rects(x, z):
		return any(a <= x <= b and c <= z <= d for a, b, c, d in rects)

	def square_skip(x, z):
		return (math.hypot(x, z) < MOSAIC_R + 0.12 or math.hypot(x - MONUMENT[0], z - MONUMENT[1]) < 0.9
				or in_rects(x, z))

	paving(*SQUARE, square_skip)
	paving(*ROAD, lambda x, z: False)
	mosaic(0.0, 0.0)

	# Monument: the statue on a round plinth south of the mosaic.
	mx, mz = MONUMENT
	loft("monument", [(0.0, ngon(0.78, 0.78, 12)), (0.34, ngon(0.72, 0.72, 12))], STONE, True, Matrix.Translation(G(mx, 0.0, mz)))
	cylinder("monument_cap", G(mx, 0.375, mz), 0.78, 0.07, PALE, 12)
	prop("res://assets/environment/arena/statue.glb", (mx, 0.41, mz), scale=1.3)
	solid_cyl(mx, mz, 0.8, 1.8)

	for x, z in LAMPS:
		lamp_post(x, z)
	for a, b in ((LAMPS[0], LAMPS[2]), (LAMPS[2], LAMPS[4]), (LAMPS[1], LAMPS[3]), (LAMPS[3], LAMPS[5]),
			(LAMPS[4], (-1.9, 6.9)), ((1.9, 6.9), LAMPS[5])):
		bunting(a, b)
	for x, z in ((-1.9, 6.9), (1.9, 6.9)):
		lamp_post(x, z)
	for x, z, facing in BENCHES:
		bench(x, z, facing)
	for x, z in PLANTERS:
		planter(x, z)
	for i, (x, z, s) in enumerate(TREES):  # the game's own choppable trees stand on these (WorldBuilder)
		marker("Tree_%d" % i, (x, 0.0, z))
	hedge(-6.4, -2.35, 7.25)
	hedge(2.35, 6.4, 7.25)
	floor_prism("yard", [(6.95, 2.9), (9.3, 2.9), (9.8, 3.5), (9.8, 8.6), (9.3, 9.1), (6.95, 9.1)], 0.0, 0.012, TAN)
	well(*WELL)
	prop(props.POT, (WELL[0] - 0.95, 0.0, WELL[1] + 0.35), yaw=0.5, scale=1.1)
	market_stall(*MARKET)
	arch(ARCH_Z)

	# Odds and ends by the buildings: barrels, crates, pots, rocks around the edges.
	prop(props.BARREL, (-3.9, 0.0, -5.2), yaw=0.3, scale=0.95)
	prop(props.BARREL, (-4.45, 0.0, -5.5), yaw=1.1, scale=0.85)
	crate(3.95, -5.2, yaw=0.4)
	crate(4.1, -5.65, yaw=-0.2, s=0.8)
	prop(props.POT, (-6.1, 0.0, 2.6), yaw=1.0, scale=1.0)
	prop(props.POT, (6.0, 0.0, 2.7), yaw=-0.4, scale=1.0)
	for x, z, yaw, s in ((-11.5, -4.5, 0.4, 1.1), (11.6, -3.8, 1.9, 0.9), (-11.8, 5.0, 2.6, 1.0), (11.4, 11.0, 0.9, 1.2),
			(-7.5, 11.6, 1.4, 0.9), (7.2, -12.6, 0.2, 1.0), (-7.8, -12.2, 2.2, 1.1)):
		prop("res://assets/environment/forest/rocks_low.glb", (x, 0.0, z), yaw=yaw, scale=s)
		solid_cyl(x, z, 0.45 * s, 0.5 * s)


run(build, "town", OUTPUT, scale=1.0, aim=Vector(G(0.0, 0.0, -0.5)), dist=21.0, height=24.0)
