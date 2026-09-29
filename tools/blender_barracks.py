# Builds assets/environment/buildings/barracks.glb: the trading post Barracks, a walled training compound (own model,
# Kenney mini style): a sandy courtyard where trained soldiers wait, the barracks hall in the front wall (its door faces
# the trading post), a watchtower with stairs, a covered archery range, a gate for the soldiers and training props.
# Low-poly boxes UV-mapped onto the shared forest palette (assets/textures/palettes/forest_colormap.png) the way the
# Kenney kits are: each surface samples one 32 px palette cell (flat, or the cell's vertical gradient for soft shading),
# so it matches the other props exactly. 1 unit = one Kenney tile; origin at the bottom center; the door faces +Z in
# Godot (Blender -Y). The GLB points at the shared palette instead of embedding a copy.
# Run from the project folder:  blender -b --python tools/blender_barracks.py [-- --preview out.png]
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_kit as kit
from blender_kit import *  # palette cells, G* helpers, generic pieces
import blender_props as props  # the game's existing models (spears, racks, barrels, targets…), placed with kit.prop()
from mathutils import Matrix, Vector

OUTPUT = os.path.join(kit.PROJECT, "assets", "environment", "buildings", "barracks.glb")

# --- Layout ------------------------------------------------------------------------------------------------
# Everything below is written in Godot stall space, in meters: x right, y up, z toward the trading post center
# (front). KEEP IN SYNC with the barracks layout constants in scenes/world/shop_station.gd (walls, hall, tower,
# range, pen and gate are also collision / soldier paths there). The finished mesh is scaled down by MODEL_SCALE,
# because the stall scales its props up by that much.
MODEL_SCALE = 1.5
COMPOUND = (-3.3, 3.3, -6.8, 0.6)     # outer walls: x0, x1, z0, z1
WALL_T = 0.3
WALL_H = 1.3
HALL = (-1.7, 1.7, -1.9, 0.6)         # the barracks hall, built into the front wall (door faces the post)
PORCH_D = 0.7                         # porch on the courtyard side of the hall
TOWER = (-3.3, -1.8, -6.8, -5.3)      # watchtower, back-left corner
TOWER_H = 2.6
RANGE = (-1.4, 2.2, -6.5, -5.9)       # covered archery range along the back wall
STAIRS = (-3.0, -2.5, -5.3, -3.4)     # stairs up the left wall to the tower
GATE_Z = -3.95                        # soldiers' gate in the right wall (center, half width)
GATE_HALF = 1.0
SAND = (2, 1)
SAND_LIGHT = (4, 1)


# --- The compound ---------------------------------------------------------------------------------------------

def build():
	X0, X1, Z0, Z1 = COMPOUND
	T = WALL_T

	# Sandy courtyard (with a few darker patches) and a sand apron outside the gate.
	gbox("sand", X0 + T, X1 - T, 0, 0.03, Z0 + T, Z1 - T, SAND, False)
	patches = []
	for _ in range(60):
		if len(patches) >= 9:
			break
		w, d = rng.uniform(0.4, 0.9), rng.uniform(0.3, 0.7)
		x, z = rng.uniform(X0 + 0.8, X1 - 0.8), rng.uniform(-5.6, -2.2)
		if any(abs(x - px) < (w + pw) * 0.5 + 0.05 and abs(z - pz) < (d + pd) * 0.5 + 0.05 for px, pz, pw, pd in patches):
			continue
		patches.append((x, z, w, d))
		gbox("sand_patch", x - w / 2, x + w / 2, 0.03, 0.045, z - d / 2, z + d / 2, SAND_LIGHT, False)
	gbox("apron", X1, X1 + 0.9, 0, 0.025, GATE_Z - GATE_HALF, GATE_Z + GATE_HALF, SAND, False)

	# Walls (merlons on their outer edge), pilasters with wall lamps, masonry.
	tower_skip = [(TOWER[0] - 0.1, TOWER[1] + 0.1, TOWER[2] - 0.1, TOWER[3] + 0.1)]
	wall(X0, X0 + T, TOWER[3], Z1, "-x", skip=tower_skip)
	wall(TOWER[1], X1, Z0, Z0 + T, "-z", skip=tower_skip)
	wall(X1 - T, X1, Z0 + T, GATE_Z - GATE_HALF - 0.5, "+x")
	wall(X1 - T, X1, GATE_Z + GATE_HALF + 0.5, Z1, "+x")
	wall(X0 + T, HALL[0], Z1 - T, Z1, "+z")
	wall(HALL[1], X1 - T, Z1 - T, Z1, "+z")
	pilasters(X0, X0, TOWER[3], Z1, "-x")
	pilasters(TOWER[1], X1, Z0, Z0, "-z")
	pilasters(X1, X1, Z0, GATE_Z - GATE_HALF - 0.3, "+x", every=1.2, sconces=True)
	pilasters(X1, X1, GATE_Z + GATE_HALF + 0.3, Z1, "+x", every=1.2, sconces=True)
	for x0, x1 in ((X0, HALL[0]), (HALL[1], X1)):
		pilasters(x0, x1, Z1, Z1, "+z", every=1.6, sconces=True)
	masonry("x", X0, -1, TOWER[3], Z1, 0.15, WALL_H - 0.1, 14)
	masonry("z", Z0, -1, TOWER[1], X1, 0.15, WALL_H - 0.1, 12)
	masonry("x", X1, 1, Z0, GATE_Z - GATE_HALF - 0.4, 0.15, WALL_H - 0.1, 6)
	masonry("x", X1, 1, GATE_Z + GATE_HALF + 0.4, Z1, 0.15, WALL_H - 0.1, 8)
	for x0, x1 in ((X0, HALL[0]), (HALL[1], X1)):
		masonry("z", Z1, 1, x0 + 0.1, x1 - 0.1, 0.15, WALL_H - 0.1, 4)

	# Gate: two gate towers, a wooden lintel with the banner, doors swung open into the courtyard.
	for side in (-1, 1):
		zc = GATE_Z + side * (GATE_HALF + 0.25)
		gbox("gate_plinth", X1 - 0.38, X1 + 0.23, 0, 0.14, zc - 0.28, zc + 0.28, DARK)
		gbox("gate_tower", X1 - 0.35, X1 + 0.2, 0, 1.95, zc - 0.25, zc + 0.25, STONE)
		gbox("gate_cap", X1 - 0.38, X1 + 0.23, 1.9, 1.97, zc - 0.28, zc + 0.28, PALE, False)
		for dx in (-0.27, 0.12):
			for dz in (-0.17, 0.17):
				gcube("merlon", (X1 + dx, 2.07, zc + dz), (0.13, 0.2, 0.13), STONE)
		gcube("gate_lamp", (X1 + 0.26, 1.2, zc), (0.08, 0.1, 0.08), SLATE, False)
		gcube("flame", (X1 + 0.26, 1.3, zc), (0.07, 0.1, 0.07), ORANGE, False, yaw=math.radians(45))
		gcube("flame", (X1 + 0.26, 1.38, zc), (0.04, 0.06, 0.04), YELLOW, False)
		# Door leaf: hinged at the tower, opened ~80 degrees inward.
		hinge = (X1 - 0.3, zc - side * 0.25)
		ang = math.radians(80)
		dir_x, dir_z = -math.sin(ang), -side * math.cos(ang)
		cx, cz = hinge[0] + dir_x * 0.46, hinge[1] + dir_z * 0.46
		yaw = math.atan2(-dir_z, dir_x)
		gcube("gate_door", (cx, 0.72, cz), (0.92, 1.3, 0.08), WOOD, True, yaw=yaw)
		for y in (0.35, 1.1):
			gcube("door_band", (cx, y, cz), (0.9, 0.07, 0.1), SLATE, False, yaw=yaw)
	gbox("lintel", X1 - 0.35, X1 + 0.2, 1.6, 1.82, GATE_Z - GATE_HALF, GATE_Z + GATE_HALF, WOOD)
	props.wall_banner(X1 + 0.2, GATE_Z, 1.8, yaw=math.radians(90), scale=0.7)

	# Watchtower: stone base, parapet, wooden posts and a pyramid tile roof, flag.
	tx0, tx1, tz0, tz1 = TOWER
	tcx, tcz = (tx0 + tx1) * 0.5, (tz0 + tz1) * 0.5
	gbox("tower_plinth", tx0 - 0.04, tx1 + 0.04, 0, 0.14, tz0 - 0.04, tz1 + 0.04, DARK)
	gbox("tower", tx0, tx1, 0, TOWER_H, tz0, tz1, STONE)
	gbox("tower_ledge", tx0 - 0.06, tx1 + 0.06, TOWER_H - 0.05, TOWER_H + 0.01, tz0 - 0.06, tz1 + 0.06, PALE, False)
	gbox("tower_floor", tx0 + 0.12, tx1 - 0.12, TOWER_H + 0.01, TOWER_H + 0.03, tz0 + 0.12, tz1 - 0.12, WOOD, False)
	for (a0, a1, b0, b1) in ((tx0, tx1, tz0, tz0 + 0.12), (tx0, tx1, tz1 - 0.12, tz1),
			(tx0, tx0 + 0.12, tz0 + 0.12, tz1 - 0.12), (tx1 - 0.12, tx1, tz0 + 0.12, tz1 - 0.12)):
		gbox("tower_parapet", a0, a1, TOWER_H + 0.01, TOWER_H + 0.3, b0, b1, STONE)
	post_h = 1.0
	for dx in (-1, 1):
		for dz in (-1, 1):
			gcube("tower_post", (tcx + dx * 0.62, TOWER_H + post_h * 0.5, tcz + dz * 0.62), (0.1, post_h, 0.1), WOOD)
	roof_y = TOWER_H + post_h
	gbox("tower_eave", tx0 - 0.05, tx1 + 0.05, roof_y - 0.06, roof_y + 0.02, tz0 - 0.05, tz1 + 0.05, WOOD, False)
	cylinder("tower_roof", G(tcx, roof_y + 0.4, tcz), 1.4, 0.8, ORANGE, 4, True,
			Matrix.Rotation(math.radians(45), 4, "Z"), top=0.0)
	prop(props.FLAG, (tcx, roof_y + 0.7, tcz), yaw=math.radians(-90))
	for face in ("+x", "-z", "+z"):
		for y in (0.9, 1.8):
			if face == "+x":
				gcube("slit", (tx1 + 0.01, y, tcz), (0.02, 0.26, 0.06), DARK, False)
			elif face == "-z":
				gcube("slit", (tcx, y, tz0 - 0.01), (0.06, 0.26, 0.02), DARK, False)
	facade_prism("tower_door", arch(0.36, 0.34), 0.03, DARK, -2.75, WALL_H, tz1 + 0.01, False)
	masonry("x", tx0, -1, tz0, tz1, 0.2, TOWER_H - 0.1, 6)
	masonry("z", tz0, -1, tx0, tx1, 0.2, TOWER_H - 0.1, 6)

	# Stairs up the left wall to the tower door.
	sx0, sx1, sz0, sz1 = STAIRS
	steps = 8
	step_run = (sz1 - sz0) / steps
	for i in range(steps):
		back = sz1 - step_run * (i + 1) - (0.01 if i == steps - 1 else 0.0)  # the top step tucks into the tower
		gbox("step", sx0 - 0.01, sx1, 0, WALL_H * (i + 1) / steps, back, sz1 - step_run * i, STONE)
	gbox("stair_rail", sx1, sx1 + 0.06, 0, 0.18, sz0, sz1, DARK, False)

	# Archery range: lean-to on posts, three arched alcoves in the back wall with targets, stumps in front.
	rx0, rx1, rz0, rz1 = RANGE
	for i, x in enumerate((-0.8, 0.4, 1.6)):
		facade_prism("alcove", arch(0.7, 0.35), 0.03, DARK, x, 0.03, rz0 + 0.01, False)
		prop(props.TARGET, (x, 0.03, rz0 + 0.31))
	lean_to(rx0, rx1, rz0, rz1, 1.35, 1.1, posts=(rx0 + 0.05, (rx0 + rx1) * 0.5, rx1 - 0.05))
	prop(props.BARREL, (rx1 + 0.35, 0.03, rz0 + 0.35), yaw=0.5, scale=0.85)
	props.arrows_in(rx1 + 0.35, 0.03 + 0.48 * 0.85, rz0 + 0.35, count=4, radius=0.08)
	for x in (0.1, 1.1):
		gcyl("stump", (x, 0.12, -5.55), 0.17, 0.24, WOOD, 8, True)
		gcyl("stump_top", (x, 0.245, -5.55), 0.15, 0.01, TAN, 8)

	# The barracks hall: stone ground floor, timber-framed upper floor with a jetty, tile roof, chimney.
	hx0, hx1, hz0, hz1 = HALL
	hcx = (hx0 + hx1) * 0.5
	gbox("hall_plinth", hx0 - 0.04, hx1 + 0.04, 0, 0.14, hz0 - 0.04, hz1 + 0.04, DARK)
	gbox("hall", hx0, hx1, 0, 1.3, hz0, hz1, STONE)
	gbox("floor_beam", hx0 - 0.07, hx1 + 0.07, 1.28, 1.4, hz0 - 0.07, hz1 + 0.07, WOOD)
	gbox("upper", hx0 - 0.06, hx1 + 0.06, 1.4, 2.32, hz0 - 0.06, hz1 + 0.06, PLASTER)
	for x in (hx0 - 0.06, hx1 + 0.06):
		for z in (hz0 - 0.06, hz1 + 0.06):
			gcube("frame_post", (x, 1.85, z), (0.1, 0.9, 0.1), WOOD)
	for x in (-0.55, 0.55):
		for z in (hz0 - 0.075, hz1 + 0.075):
			gcube("frame_stud", (x, 1.86, z), (0.07, 0.92, 0.03), WOOD, True)
	for z in (-1.05, -0.25):
		for x in (hx0 - 0.075, hx1 + 0.075):
			gcube("frame_stud", (x, 1.86, z), (0.03, 0.92, 0.07), WOOD, True)
	gbox("top_plate", hx0 - 0.1, hx1 + 0.1, 2.3, 2.4, hz0 - 0.1, hz1 + 0.1, WOOD)
	half, pitch = tile_roof(hx0 - 0.1, hx1 + 0.1, hz0 - 0.1, hz1 + 0.1, 2.4, 0.8, rows=3)
	for x in (hx0 - 0.08, hx1 + 0.04):
		facade_prism("gable", [(-(half - 0.24), 0), (half - 0.24, 0), (0, 0.74)], 0.04, PLASTER, x + 0.02, 2.4,
				(hz0 + hz1) * 0.5, True, yaw=math.radians(90))
		gcube("gable_beam", (x + 0.02, 2.62, (hz0 + hz1) * 0.5), (0.05, 0.06, half * 1.1), WOOD, False)
	gbox("chimney", 1.0, 1.28, 2.2, 3.35, -1.2, -0.92, STONE)
	gbox("chimney_cap", 0.96, 1.32, 3.35, 3.42, -1.24, -0.88, DARK, False)
	masonry("z", hz1, 1, hx0 + 0.1, -0.5, 0.2, 1.2, 4)
	masonry("z", hz1, 1, 0.5, hx1 - 0.1, 0.2, 1.2, 4)
	masonry("x", hx0, -1, hz0 + 0.1, hz1 - 0.1, 0.2, 1.2, 5)
	masonry("x", hx1, 1, hz0 + 0.1, hz1 - 0.1, 0.2, 1.2, 5)
	# Front (the trading post side): arched double door with step, lanterns, banners, upper windows.
	facade_prism("door_arch", arch(0.84, 0.62), 0.04, PALE, hcx, 0.03, hz1 + 0.045, False)
	facade_prism("door_hole", arch(0.72, 0.6), 0.04, DARK, hcx, 0.03, hz1 + 0.06, False)
	for side in (-1, 1):
		leaf = [(0, 0), (side * 0.34, 0), (side * 0.34, 0.6)]
		for i in range(1, 5):
			a = math.pi * 0.5 * i / 4
			leaf.append((side * 0.34 * math.cos(a), 0.6 + 0.34 * math.sin(a)))
		if side < 0:
			leaf.reverse()
		facade_prism("door", leaf, 0.04, WOOD, hcx + side * 0.01, 0.03, hz1 + 0.075, True)
		gcube("door_ring", (hcx + side * 0.08, 0.5, hz1 + 0.105), (0.04, 0.04, 0.02), YELLOW, False)
		gcube("lantern_arm", (hcx + side * 0.62, 0.95, hz1 + 0.07), (0.04, 0.04, 0.14), SLATE, False)
		gcube("lantern", (hcx + side * 0.62, 0.86, hz1 + 0.13), (0.1, 0.13, 0.1), YELLOW, False)
		gcube("lantern_cap", (hcx + side * 0.62, 0.94, hz1 + 0.13), (0.13, 0.03, 0.13), SLATE, False)
		props.wall_banner(hcx + side * 1.15, hz1 + 0.03, 1.26, scale=0.6)
		window(hcx + side * 0.95, 1.85, hz1 + 0.06, w=0.34, h=0.38)
	window(hcx, 1.85, hz1 + 0.06, w=0.3, h=0.38)
	for side in (-1, 1):
		for z in (-1.3, -0.4):
			window(hx0 - 0.06 if side < 0 else hx1 + 0.06, 1.85, z, yaw=math.radians(-90 if side < 0 else 90), w=0.3)
	gbox("hall_step", hcx - 0.55, hcx + 0.55, 0, 0.08, hz1, hz1 + 0.28, PALE)
	# Back (courtyard): door, porch with weapon racks and a bench, upper windows.
	facade_prism("back_door", [(-0.3, 0), (0.3, 0), (0.3, 0.9), (-0.3, 0.9)], 0.04, WOOD, hcx, 0.03, hz0 - 0.065,
			True, yaw=math.radians(180))
	lean_to(hx0 - 0.1, hx1 + 0.1, hz0, hz0 - PORCH_D, 1.36, 1.1, posts=(hx0, -0.55, 0.55, hx1))
	gbox("porch_floor", hx0, hx1, 0, 0.06, hz0 - PORCH_D, hz0, WOOD, False)
	props.spear_rack(-1.05, hz0 - 0.2, yaw=math.radians(180), y=0.06)
	props.spear_rack(1.05, hz0 - 0.2, yaw=math.radians(180), spears=3, y=0.06)
	gbox("bench", -0.6 + 0.1, -0.1 - 0.05, 0.2, 0.26, hz0 - 0.5, hz0 - 0.32, WOOD, False)
	for x in (-0.46, -0.2):
		gbox("bench_leg", x - 0.03, x + 0.03, 0, 0.2, hz0 - 0.46, hz0 - 0.36, WOOD, False)
	for x in (-0.95, 0.0, 0.95):
		window(x, 1.85, hz0 - 0.06, yaw=math.radians(180), w=0.3)

	# Front bays: weapons, barrels and crates on the right; training dummies and hay on the left.
	props.spear_rack(2.35, -0.05, yaw=math.radians(90))
	prop(props.BARREL, (2.62, 0.0, -1.05), scale=0.95)
	prop(props.BARREL, (2.2, 0.0, -1.45), yaw=0.7, scale=0.85)
	crate(2.7, -1.78, yaw=0.3)
	for x, z, yaw in ((-2.5, -0.35, 0.3), (-2.15, -1.3, -0.4)):
		dummy(x, z, yaw)
	gbox("hay", -2.95, -2.45, 0, 0.32, -1.85, -1.55, YELLOW)
	gbox("hay_band", -2.96, -2.44, 0.12, 0.17, -1.86, -1.54, TAN, False)


run(build, "barracks", OUTPUT, scale=MODEL_SCALE,
		aim=Vector(G(0.0, 0.6, (COMPOUND[2] + COMPOUND[3]) * 0.5)) / MODEL_SCALE, dist=7.5, height=6.2)
