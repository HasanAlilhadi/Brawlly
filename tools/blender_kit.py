# Shared toolkit for building own low-poly models in the Kenney mini-kit style (import it from a
# tools/blender_<name>.py script). Run model scripts with
#   blender -b --python tools/blender_<name>.py [-- --check] [-- --preview out.png --yaw 35]
#
# Rules it bakes in (learned the hard way on earlier buildings; keep following them):
# - Texture = the shared Kenney palette (one 32 px cell per surface: flat, or its vertical gradient for soft
#   shading) so the model matches the kits exactly. Sample it LINEARLY (like the kits): "Closest" shows the
#   gradient's pixel rows as stripes on tall faces.
# - Never let two pieces have faces in the same plane that overlap (z-fighting: flicker / see-through look):
#   don't stack boxes inside each other (stairs = one block per step), stop walls at towers instead of running
#   into them, put caps above (not flush with) what they cap, keep decor (stones, patches) from overlapping,
#   make trims stick out or tuck 1 cm in. `check()` finds them all; run `-- --check` after every change: it
#   must print "OVERLAPS 0" and "FLIPPED 0".
# - Single-sided material (backface culling): faces must point outward; `check()` also finds flipped ones.
#   check() compares faces by their bounding boxes, so vary repeated pieces (heights, sizes, a random turn for balls)
#   and keep flat layers at distinct heights; it then only reports real risks.
# - Work in Godot meters with the G* helpers (x right, y up, +z = the model's front), then `finish(scale)`
#   shrinks it to prop space; 1 unit = one Kenney tile; origin at the bottom center.
# - The GLB links the shared palette file instead of embedding a copy (`export()`).
# - Check the result in the game up close too (tests/screenshot_test.gd), not only the Blender preview.
# - Reuse the game's existing models (weapons, barrels, targets, banners…) with prop() instead of modeling copies;
#   model only what doesn't exist yet.
import bpy, bmesh, math, os, sys, json, struct, random
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOREST_PALETTE = os.path.join(PROJECT, "assets", "textures", "palettes", "forest_colormap.png")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# Palette cells of the Kenney forest palette: (column of the flat cell, band). Bands (bottom-up in UV space):
# 0 greys, 1 main colors, 2 blues. The column right of a flat cell holds the same color as a top-light /
# bottom-dark gradient (used when a part is built with gradient=True).
WOOD = (0, 1)
TAN = (2, 1)
PLASTER = (4, 1)
GREEN = (6, 1)
YELLOW = (8, 1)
ORANGE = (10, 1)
RED = (12, 1)
BLUE = (14, 1)
PALE = (0, 0)
MOSS = (2, 0)
DARK = (4, 0)
STONE = (6, 0)
SLATE = (8, 0)
LAVENDER = (10, 0)
WHITE = (12, 0)
SALMON = (14, 0)

rng = random.Random(11)


def _uv(cell, gradient, t):
	col, band = cell
	if gradient:
		return ((col + 1.5) / 16.0, band * 0.25 + 0.02 + 0.21 * t)
	return ((col + 0.5) / 16.0, band * 0.25 + 0.125)


_parts = []


def part(name, bm, cell, gradient=True, matrix=Matrix()):
	"""Turns a bmesh into an object: UVs from `cell` (gradient by height), then `matrix`."""
	uv = bm.loops.layers.uv.verify()
	zs = [v.co.z for v in bm.verts]
	lo, hi = min(zs), max(zs)
	for face in bm.faces:
		for loop in face.loops:
			t = (loop.vert.co.z - lo) / (hi - lo) if hi - lo > 1e-6 else 0.5
			loop[uv].uv = _uv(cell, gradient, t)
	bm.transform(matrix)
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(obj)
	_parts.append(obj)
	return obj


def box(name, center, size, cell, gradient=True, rot_y=0.0, rot_x=0.0, rot_z=0.0):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bm.transform(Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
	rot = Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Rotation(rot_y, 4, "Y") @ Matrix.Rotation(rot_x, 4, "X")
	return part(name, bm, cell, gradient, Matrix.Translation(center) @ rot)


def prism(name, outline, depth, cell, gradient=True, matrix=Matrix()):
	"""Extrudes a 2D outline (x, z pairs, counter-clockwise) `depth` along Blender Y."""
	bm = bmesh.new()
	verts = [bm.verts.new((x, -depth * 0.5, z)) for x, z in outline]
	face = bm.faces.new(verts)
	extruded = bmesh.ops.extrude_face_region(bm, geom=[face])
	moved = [g for g in extruded["geom"] if isinstance(g, bmesh.types.BMVert)]
	bmesh.ops.translate(bm, verts=moved, vec=(0, depth, 0))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return part(name, bm, cell, gradient, matrix)


def cylinder(name, center, radius, depth, cell, segments=8, gradient=False, matrix=Matrix(), top=None):
	"""Cylinder (or a cone / pyramid with `top` radius) along local Z, centered."""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius,
			radius2=radius if top is None else top, depth=depth)
	return part(name, bm, cell, gradient, Matrix.Translation(center) @ matrix)


def G(x, y, z):
	"""Godot point -> Blender point."""
	return (x, -z, y)


def floor_prism(name, outline, y0, y1, cell, gradient=False):
	"""Flat slab from a Godot-space outline [(x, z), ...] (convex, any winding) between heights y0 and y1."""
	bm = bmesh.new()
	low = [bm.verts.new((x, -z, y0)) for x, z in outline]
	high = [bm.verts.new((x, -z, y1)) for x, z in outline]
	n = len(outline)
	bm.faces.new(low)
	bm.faces.new(high)
	for i in range(n):
		bm.faces.new((low[i], low[(i + 1) % n], high[(i + 1) % n], high[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return part(name, bm, cell, gradient)


def gbox(name, x0, x1, y0, y1, z0, z1, cell, gradient=True):
	"""Axis-aligned box from Godot ranges."""
	return box(name, G((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), (x1 - x0, z1 - z0, y1 - y0), cell, gradient)


def gcube(name, center, size, cell, gradient=True, yaw=0.0, pitch=0.0):
	"""Box around a Godot center; size = (x, y, z); yaw about up, pitch about x (same sense in both frames)."""
	return box(name, G(*center), (size[0], size[2], size[1]), cell, gradient, rot_x=pitch, rot_z=yaw)


def gcyl(name, center, radius, height, cell, segments=8, gradient=False, face_z=False):
	"""Upright cylinder (or a disc facing +z when face_z) at a Godot center."""
	m = Matrix.Rotation(math.radians(90), 4, "X") if face_z else Matrix()
	return cylinder(name, G(*center), radius, height, cell, segments, gradient, m)


def facade_prism(name, outline, depth, cell, x, y, z, gradient=True, yaw=0.0):
	"""2D outline (x, y pairs) standing in a wall plane facing +z (yaw turns it), extruded `depth`."""
	return prism(name, outline, depth, cell, gradient, Matrix.Translation(G(x, y, z)) @ Matrix.Rotation(yaw, 4, "Z"))


def arch(w, h, segments=8):
	r = w * 0.5
	pts = [(-r, 0.0), (r, 0.0)]
	for i in range(segments + 1):
		a = math.pi * i / segments
		pts.append((r * math.cos(a), h + r * math.sin(a)))
	return pts


# --- Rounded pieces (for items: lofted cross-sections, rods, balls) ------------------------------------------

def gmat(center, yaw=0.0, pitch=0.0, roll=0.0):
	"""Item frame at a Godot point: local z = up, x = Godot x, y = Godot -z; yaw about up, then pitch about x,
	then roll about the item's thickness axis (same sense as gcube)."""
	return (Matrix.Translation(G(*center)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(pitch, 4, "X")
			@ Matrix.Rotation(roll, 4, "Y"))


def ngon(rx, ry, n=8, phase=None):
	"""Cross-section: n points on an ellipse (counter-clockwise); default phase puts a flat face on each axis."""
	phase = math.pi / n if phase is None else phase
	return [(rx * math.cos(phase + math.tau * i / n), ry * math.sin(phase + math.tau * i / n)) for i in range(n)]


def blade_section(width, thickness):
	"""Flat hexagon with sharp side edges and a center ridge (blades, spear heads)."""
	return ngon(width * 0.5, thickness * 0.5 / math.sin(math.pi / 3), 6, 0.0)


def loft(name, rings, cell, gradient=True, matrix=Matrix()):
	"""Solid through cross-sections along local z: rings = [(z, [(x, y), ...])], same point count, or a single
	point for a sharp tip. Keep it convex (widths bulge, never pinch) so `check()` reads it right."""
	bm = bmesh.new()
	layers = [[bm.verts.new((x, y, z)) for x, y in pts] for z, pts in rings]
	for a, b in zip(layers, layers[1:]):
		if len(a) == 1:
			for i in range(len(b)):
				bm.faces.new((a[0], b[i], b[(i + 1) % len(b)]))
		elif len(b) == 1:
			for i in range(len(a)):
				bm.faces.new((a[i], a[(i + 1) % len(a)], b[0]))
		else:
			for i in range(len(a)):
				bm.faces.new((a[i], a[(i + 1) % len(a)], b[(i + 1) % len(b)], b[i]))
	for layer in (layers[0], layers[-1]):
		if len(layer) >= 3:
			bm.faces.new(layer)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return part(name, bm, cell, gradient, matrix)


def rod(name, a, b, r0, r1=None, cell=WOOD, segments=8, gradient=False, matrix=Matrix()):
	"""Round rod from local point a to b (tapering r0 -> r1; r1 = 0 makes a point), inside `matrix`."""
	a, b = Vector(a), Vector(b)
	d = b - a
	# Local z along the rod, local y as close to up as it gets (lying rods keep a flat face on top).
	z = d.normalized()
	up = Vector((0, 1, 0)) if abs(z.z) > 0.9 else Vector((0, 0, 1))
	y = (up - z * up.dot(z)).normalized()
	x = y.cross(z)
	basis = Matrix((x, y, z)).transposed().to_4x4()
	frame = matrix @ Matrix.Translation(a) @ basis
	r1 = r0 if r1 is None else r1
	end = [(0.0, 0.0)] if r1 <= 0.0 else ngon(r1, r1, segments)
	return loft(name, [(0.0, ngon(r0, r0, segments)), (d.length, end)], cell, gradient, frame)


def grod(name, a, b, r0, r1=None, cell=WOOD, segments=8, gradient=False):
	"""Round rod between two Godot points."""
	return rod(name, G(*a), G(*b), r0, r1, cell, segments, gradient)


def ball(name, center, radius, cell, matrix=Matrix(), subdivisions=1, gradient=False):
	"""Low-poly ball (icosahedron; subdivisions=2 is rounder, e.g. tree crowns) at a local point."""
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
	return part(name, bm, cell, gradient, matrix @ Matrix.Translation(center))


# --- Existing models (props) ---------------------------------------------------------------------------------
# Reuse what the game already has (weapons, barrels, targets, banners…) instead of modeling a second version:
# the game stays consistent. prop() imports the real GLB into the Blender scene (for --check and --preview) and
# run() writes a <name>.tscn next to the building GLB that instances the building plus every prop at its spot.
# Model new geometry only for things the game has no model of (then prefer loft / rod / ball: rounded, pointed).

_props = []        # (res path, godot position, godot basis 3x3 incl. scale, root empty)
_markers = []      # (node name, godot position, yaw): spots the game reads from the scene (e.g. where things get placed)
_solids = []       # ("box", center, size, yaw) / ("cyl", center, radius, height): collision written into the scene
_prop_meshes = []  # imported mesh objects (checked for overlaps with the building, never joined into it)
_G_TO_B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot axes -> Blender axes


def prop(path, pos, yaw=0.0, pitch=0.0, roll=0.0, scale=1.0, export=True):
	"""Places an existing model (res:// path of a GLB) at a Godot point (meters, like every other helper), turned by
	yaw (about up), then pitch (about x), then roll (about z), scaled `scale` (a number or an (x, y, z) triple).
	export=False: only for --check / --preview (e.g. buildings a layout is planned around), not in the scene."""
	sx, sy, sz = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
	rot = Matrix.Rotation(yaw, 3, "Y") @ Matrix.Rotation(pitch, 3, "X") @ Matrix.Rotation(roll, 3, "Z")
	basis = rot @ Matrix.Diagonal((sx, sy, sz))
	before = set(bpy.data.objects)
	bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT, path.replace("res://", "")))
	new = [o for o in bpy.data.objects if o not in before]
	root = bpy.data.objects.new("prop", None)
	bpy.context.collection.objects.link(root)
	for obj in new:
		if obj.parent is None:
			obj.parent = root
	root.matrix_world = Matrix.Translation(G(*pos)) @ (_G_TO_B @ basis @ _G_TO_B.transposed()).to_4x4()
	bpy.context.view_layer.update()
	_prop_meshes.extend(o for o in new if o.type == "MESH")
	if export:
		_props.append((path, Vector(pos), basis, root))
	else:
		_preview_roots.append(root)
	return root


_preview_roots = []


def marker(name, pos, yaw=0.0):
	"""A named Node3D in the scene at a Godot point, turned by yaw: a spot the game places things on."""
	_markers.append((name, Vector(pos), yaw))


def solid_box(x0, x1, y0, y1, z0, z1, yaw=0.0):
	"""Collision box over Godot ranges (turned by yaw about its center), written into the scene's StaticBody3D."""
	_solids.append(("box", Vector(((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)),
			Vector((x1 - x0, y1 - y0, z1 - z0)), yaw))


def solid_cyl(x, z, radius, height, y0=0.0):
	"""Upright collision cylinder standing at (x, y0, z)."""
	_solids.append(("cyl", Vector((x, y0 + height * 0.5, z)), radius, height))


def _write_scene(glb_path, scale):
	"""<building>.tscn: the building GLB plus every prop (in prop space: divided by the model scale)."""
	def res(path):
		return "res://" + os.path.relpath(os.path.abspath(path), PROJECT).replace(os.sep, "/")
	paths = [res(glb_path)] + sorted({p[0] for p in _props})
	ids = {path: str(i + 1) for i, path in enumerate(paths)}
	name = os.path.splitext(os.path.basename(glb_path))[0]
	def fmt(values):
		return ", ".join("%.5g" % (0.0 if abs(v) < 1e-6 else v) for v in values)
	def yaw_transform(pos, yaw):
		m = Matrix.Rotation(yaw, 3, "Y") * (1.0 / scale)
		o = pos * (1.0 / scale)
		return "Transform3D(%s)" % fmt([m[r][c] for r in range(3) for c in range(3)] + [o.x, o.y, o.z])
	subs = []
	for i, solid in enumerate(_solids):
		if solid[0] == "box":
			size = solid[2] * (1.0 / scale)
			subs.append('[sub_resource type="BoxShape3D" id="shape_%d"]\nsize = Vector3(%s)' % (i, fmt(size)))
		else:
			subs.append('[sub_resource type="CylinderShape3D" id="shape_%d"]\nheight = %.5g\nradius = %.5g' % (
					i, solid[3] / scale, solid[2] / scale))
	lines = ["[gd_scene load_steps=%d format=3]" % (len(paths) + len(subs) + 1), ""]
	lines += ['[ext_resource type="PackedScene" path="%s" id="%s"]' % (path, ids[path]) for path in paths]
	if subs:
		lines += [""] + ["\n\n".join(subs)]
	lines += ["", '[node name="%s" type="Node3D"]' % name.title().replace("_", ""), "",
			'[node name="Building" parent="." instance=ExtResource("1")]']
	counts = {}
	for path, pos, basis, _root in _props:
		base = os.path.splitext(os.path.basename(path))[0].title().replace("_", "")
		counts[base] = counts.get(base, 0) + 1
		m = basis * (1.0 / scale)
		o = pos * (1.0 / scale)
		nums = [m[r][c] for r in range(3) for c in range(3)] + [o.x, o.y, o.z]
		lines += ["", '[node name="%s%s" parent="." instance=ExtResource("%s")]' % (
				base, counts[base] if counts[base] > 1 else "", ids[path]),
				"transform = Transform3D(%s)" % ", ".join("%.5g" % (0.0 if abs(v) < 1e-6 else v) for v in nums)]
	for node_name, pos, yaw in _markers:
		lines += ["", '[node name="%s" type="Node3D" parent="."]' % node_name, "transform = " + yaw_transform(pos, yaw)]
	if _solids:
		lines += ["", '[node name="Collision" type="StaticBody3D" parent="."]', "collision_mask = 0"]
		for i, solid in enumerate(_solids):
			yaw = solid[3] if solid[0] == "box" else 0.0
			lines += ["", '[node name="Shape%d" type="CollisionShape3D" parent="Collision"]' % i,
					"transform = " + yaw_transform(solid[1], yaw), 'shape = SubResource("shape_%d")' % i]
	scene = os.path.splitext(glb_path)[0] + ".tscn"
	with open(scene, "w") as f:
		f.write("\n".join(lines) + "\n")
	return scene


# --- Generic pieces -----------------------------------------------------------------------------------------
# (For a game without such models. When the game has its own barrel / target / banner…, prop() that instead.)

def wall(x0, x1, z0, z1, outer, top=1.3, merlons=True, skip=None):
	"""Stone wall segment with a dark plinth, pale walkway cap and merlons along its `outer` edge
	("-x", "+x", "-z", "+z"); `skip` = rects (x0, x1, z0, z1) without merlons (e.g. under the tower)."""
	# Plinth and walkway only stick out on the outer side, so segments meeting at a corner never overlap
	# (overlapping boxes with faces in the same plane flicker: z-fighting).
	def grown(d, tuck=0.0):
		return (x0 - (d if outer == "-x" else -tuck), x1 + (d if outer == "+x" else -tuck),
				z0 - (d if outer == "-z" else -tuck), z1 + (d if outer == "+z" else -tuck))
	px0, px1, pz0, pz1 = grown(0.03, 0.01)
	gbox("plinth", px0, px1, 0, 0.12, pz0, pz1, DARK)
	gbox("wall", x0, x1, 0, top - 0.04, z0, z1, STONE)
	wx0, wx1, wz0, wz1 = grown(0.02)
	gbox("walk", wx0, wx1, top - 0.04, top + 0.02, wz0, wz1, PALE, False)
	if not merlons:
		return
	along_x = (x1 - x0) > (z1 - z0)
	length = (x1 - x0) if along_x else (z1 - z0)
	count = max(2, int(length / 0.38))
	step = length / count
	for k in range(count):
		t = (x0 if along_x else z0) + step * (k + 0.5)
		if along_x:
			x, z = t, (z0 + 0.06 if outer == "-z" else z1 - 0.06)
		else:
			x, z = (x0 + 0.06 if outer == "-x" else x1 - 0.06), t
		if skip and any(a0 <= x <= a1 and b0 <= z <= b1 for a0, a1, b0, b1 in skip):
			continue
		size = (0.19, 0.2, 0.12) if along_x else (0.12, 0.2, 0.19)
		gcube("merlon", (x, top + 0.12, z), size, STONE)


_pilaster_spots = []


def pilasters(x0, x1, z0, z1, outer, every=1.7, sconces=False, height=1.3):
	"""Buttress pilasters (and wall lamps) along the outer face of a wall segment (one per spot)."""
	along_x = (x1 - x0) > (z1 - z0)
	length = (x1 - x0) if along_x else (z1 - z0)
	count = max(1, int(length / every))
	for k in range(count + 1):
		t = (x0 if along_x else z0) + length * k / count
		if along_x:
			face = z0 if outer == "-z" else z1
			sign = -1 if outer == "-z" else 1
			c = (t, height * 0.5, face + sign * 0.05)
			size = (0.22, height, 0.1)
		else:
			face = x0 if outer == "-x" else x1
			sign = -1 if outer == "-x" else 1
			c = (face + sign * 0.05, height * 0.5, t)
			size = (0.1, height, 0.22)
		if any(math.hypot(c[0] - px, c[2] - pz) < 0.35 for px, pz in _pilaster_spots):
			continue  # a corner already has one from the other wall run
		_pilaster_spots.append((c[0], c[2]))
		gcube("pilaster", c, size, STONE)
		cap = (c[0], height - 0.02, c[2])
		gcube("pilaster_cap", cap, (size[0] + 0.05, 0.06, size[2] + 0.05), PALE, False)
		if sconces and 0 < k < count:
			out = (sign * 0.14, 0, 0) if not along_x else (0, 0, sign * 0.14)
			lamp = (c[0] + out[0], 0.9, c[2] + out[2])
			gcube("sconce", (lamp[0], 0.82, lamp[2]), (0.07, 0.06, 0.07), SLATE, False)
			gcube("flame", (lamp[0], 0.9, lamp[2]), (0.06, 0.08, 0.06), ORANGE, False, yaw=math.radians(45))
			gcube("flame", (lamp[0], 0.96, lamp[2]), (0.035, 0.05, 0.035), YELLOW, False, yaw=math.radians(20))


def masonry(axis, plane, sign, u0, u1, y0, y1, count):
	"""Lighter stones set proud of an outer wall face (axis "x": the face is x = plane, running along z).
	Stones never overlap (their faces would share a plane and flicker)."""
	placed = []
	tries = 0
	while len(placed) < count and tries < count * 30:
		tries += 1
		w = rng.uniform(0.12, 0.2)
		h = rng.choice((0.08, 0.1))
		u = rng.uniform(u0 + w, u1 - w)
		y = rng.uniform(y0 + h, y1 - h)
		if any(abs(u - pu) < (w + pw) * 0.5 + 0.02 and abs(y - py) < (h + ph) * 0.5 + 0.02 for pu, py, pw, ph in placed):
			continue
		placed.append((u, y, w, h))
		cell = PALE if rng.random() < 0.6 else STONE
		if axis == "x":
			gcube("stone", (plane + sign * 0.01, y, u), (0.025, h, w), cell, False)
		else:
			gcube("stone", (u, y, plane + sign * 0.01), (w, h, 0.025), cell, False)


def barrel(x, z, s=1.0):
	gcyl("barrel", (x, 0.23 * s, z), 0.17 * s, 0.46 * s, WOOD, 8, True)
	for y in (0.1, 0.36):
		gcyl("barrel_ring", (x, y * s, z), 0.178 * s, 0.035 * s, SLATE, 8)
	gcyl("barrel_top", (x, 0.47 * s, z), 0.14 * s, 0.02, TAN, 8)


def crate(x, z, yaw=0.0, s=1.0):
	gcube("crate", (x, 0.18 * s, z), (0.36 * s, 0.36 * s, 0.36 * s), TAN, True, yaw=yaw)
	for dy in (-0.14, 0.14):
		gcube("crate_band", (x, 0.18 * s + dy * s, z), (0.38 * s, 0.05 * s, 0.38 * s), WOOD, False, yaw=yaw)


def dummy(x, z, yaw=0.0):
	gcube("dummy_post", (x, 0.55, z), (0.07, 1.1, 0.07), WOOD, True, yaw=yaw)
	gcube("dummy_base", (x, 0.03, z), (0.3, 0.06, 0.3), WOOD, False, yaw=yaw)
	gcube("dummy_arms", (x, 0.85, z), (0.56, 0.06, 0.06), WOOD, False, yaw=yaw)
	gcube("dummy_body", (x, 0.72, z), (0.3, 0.36, 0.2), YELLOW, True, yaw=yaw)
	gcube("dummy_belt", (x, 0.62, z), (0.32, 0.05, 0.22), RED, False, yaw=yaw)
	gcube("dummy_head", (x, 1.02, z), (0.18, 0.18, 0.18), YELLOW, True, yaw=yaw + 0.3)


def target(x, y, z, yaw=0.0, r=0.26):
	for i, (rad, cell) in enumerate(((r, WHITE), (r * 0.72, RED), (r * 0.45, WHITE), (r * 0.2, RED))):
		m = Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "X")
		off = 0.012 * i
		cylinder("target", G(x + math.sin(yaw) * off, y, z + math.cos(yaw) * off), rad, 0.04, cell, 12, False, m)


def pennant(x, y, z, height=0.8, yaw=0.0):
	gcube("pole", (x, y + height * 0.5, z), (0.04, height, 0.04), WOOD, False)
	gcube("pole_tip", (x, y + height + 0.03, z), (0.07, 0.06, 0.07), YELLOW, False)
	facade_prism("pennant", [(0.0, 0.0), (0.46, 0.12), (0.0, 0.24)], 0.02, RED, x + 0.02, y + height - 0.3, z,
			True, yaw)


def banner(x, y_top, z, w=0.36, h=0.6, yaw=0.0, depth_dir=1):
	"""Swallowtail banner with a gold shield hanging from a rod, on a wall facing +z (yaw turns it)."""
	c, s = math.cos(yaw), math.sin(yaw)
	nz = depth_dir
	def off(d):
		return (x + s * d * nz, z + c * d * nz)
	rx, rz = off(0.04)
	gcube("banner_rod", (rx, y_top + 0.02, rz), (w + 0.1, 0.04, 0.04), WOOD, False, yaw=yaw)
	bx, bz = off(0.05)
	facade_prism("banner", [(-w / 2, -h), (0.0, -h + 0.13), (w / 2, -h), (w / 2, 0.0), (-w / 2, 0.0)], 0.02, RED,
			bx, y_top, bz, True, yaw)
	sx, sz = off(0.07)
	shield = [(-w * 0.3, -0.1), (w * 0.3, -0.1), (w * 0.3, -h * 0.4), (0.0, -h * 0.62), (-w * 0.3, -h * 0.4)]
	facade_prism("banner_shield", shield, 0.02, YELLOW, sx, y_top, sz, False, yaw)


def window(x, y, z, yaw=0.0, w=0.3, h=0.36):
	"""Wooden-framed window with a cross and shutters, on a wall facing +z (yaw turns it)."""
	c, s = math.cos(yaw), math.sin(yaw)
	def at(dx, d):
		return (x + dx * c + d * s, z - dx * s + d * c)
	gx, gz = at(0, 0.012)
	gcube("glass", (gx, y, gz), (w, h, 0.03), SLATE, False, yaw=yaw)
	fx, fz = at(0, 0.025)
	gcube("win_cross", (fx, y, fz), (w - 0.02, 0.04, 0.02), WOOD, False, yaw=yaw)
	gcube("win_cross", (fx, y, fz), (0.04, h - 0.02, 0.026), WOOD, False, yaw=yaw)
	sx, sz = at(0, 0.03)
	gcube("win_sill", (sx, y - h / 2 - 0.03, sz), (w + 0.1, 0.05, 0.08), WOOD, False, yaw=yaw)
	for side in (-1, 1):
		px, pz = at(side * (w / 2 + 0.08), 0.02)
		gcube("shutter", (px, y, pz), (0.14, h + 0.04, 0.03), WOOD, True, yaw=yaw)


def tile_roof(x0, x1, z0, z1, eave_y, rise, rows=3, cell=ORANGE, overhang=0.22):
	"""Gable roof over the rect, ridge along x, tile rows overlapping down each slope."""
	half = (z1 - z0) * 0.5 + overhang
	cz = (z0 + z1) * 0.5
	pitch = math.atan2(rise, half)
	slope = math.hypot(half, rise)
	length = (x1 - x0) + overhang * 2
	for side in (-1, 1):
		for r in range(rows):
			d = (r + 0.5) * slope / rows
			y = eave_y + rise - d * math.sin(pitch) + 0.02 * r + 0.06
			gcube("tiles", ((x0 + x1) * 0.5, y, cz + side * d * math.cos(pitch)),
					(length - 0.03 * r - (0.012 if side > 0 else 0.0), 0.08, slope / rows + 0.08), cell, True, pitch=side * pitch)
	gcube("ridge", ((x0 + x1) * 0.5, eave_y + rise + 0.12, cz), (length + 0.06, 0.1, 0.12), WOOD, True)
	return half, pitch


def lean_to(x0, x1, z_wall, z_out, y_wall, y_out, cell=ORANGE, posts=None):
	"""Single-slope roof from a wall (z_wall, y_wall) out to z_out (y_out), on wooden posts."""
	depth = abs(z_out - z_wall) + 0.15
	drop = y_wall - y_out
	pitch = math.atan2(drop, depth)
	sign = 1 if z_out > z_wall else -1
	cz = (z_wall + z_out) * 0.5 + sign * 0.07
	for r in range(2):
		t = (r + 0.5) / 2
		gcube("tiles", ((x0 + x1) * 0.5, y_wall - drop * t + 0.04 + 0.015 * r, z_wall + sign * depth * t),
				(x1 - x0 + 0.1 - 0.02 * r, 0.07, math.hypot(depth, drop) / 2 + 0.06), cell, True, pitch=sign * pitch)
	for px in posts or []:
		gcube("post", (px, y_out * 0.5, z_out), (0.09, y_out, 0.09), WOOD, True)
	gcube("beam", ((x0 + x1) * 0.5, y_out - 0.03, z_out), (x1 - x0, 0.08, 0.1), WOOD, False)


# --- Finish, check, export, preview --------------------------------------------------------------------------

def finish(name, scale=1.0, palette=FOREST_PALETTE):
	"""Joins every part into one object, scales it into prop space, one palette material (linear, culled)."""
	# One object; scaled to prop space; one material using the shared palette (fully rough, like the kits).
	bpy.ops.object.select_all(action="DESELECT")
	for obj in _parts:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = _parts[0]
	bpy.ops.object.join()
	house = bpy.context.view_layer.objects.active
	house.name = name
	house.data.name = name
	house.scale = (1.0 / scale,) * 3
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	for root in [p[3] for p in _props] + _preview_roots:
		root.matrix_world = Matrix.Scale(1.0 / scale, 4) @ root.matrix_world
	material = bpy.data.materials.new("colormap")
	material.use_nodes = True
	material.use_backface_culling = True
	nodes = material.node_tree.nodes
	bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Roughness"].default_value = 1.0
	bsdf.inputs["Metallic"].default_value = 0.0
	tex = nodes.new("ShaderNodeTexImage")
	tex.image = bpy.data.images.load(palette)
	# Linear, like the Kenney kits: the gradient cells are 100+ pixel rows, and "Closest" shows every row as a
	# stripe on tall faces (banding). Linear blends them into a smooth shade.
	tex.interpolation = "Linear"
	material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
	house.data.materials.append(material)
	return house


def check():
	"""Lists pairs of faces from different pieces that lie in the same plane, face the same way and overlap:
	those flicker in the game (z-fighting). Run with `-- --check` before joining."""
	buckets = {}
	for obj in _parts + _prop_meshes:
		mw = obj.matrix_world
		for poly in obj.data.polygons:
			n = (mw.to_3x3() @ poly.normal).normalized()
			pts = [mw @ obj.data.vertices[v].co for v in poly.vertices]
			d = n.dot(pts[0])
			key = (round(n.x, 3), round(n.y, 3), round(n.z, 3), round(d, 3))
			if n.z < -0.999:
				continue  # bottom faces sit on something and are never seen from above
			# Bounds in two axes of the plane.
			axis = max(range(3), key=lambda i: abs(n[i]))
			uv_axes = [i for i in range(3) if i != axis]
			us = [p[uv_axes[0]] for p in pts]
			vs = [p[uv_axes[1]] for p in pts]
			buckets.setdefault(key, []).append((obj.name, min(us), max(us), min(vs), max(vs), poly.area))
	hits = []
	for key, faces in buckets.items():
		for i in range(len(faces)):
			for j in range(i + 1, len(faces)):
				a, b = faces[i], faces[j]
				if a[0] == b[0]:
					continue
				ou = min(a[2], b[2]) - max(a[1], b[1])
				ov = min(a[4], b[4]) - max(a[3], b[3])
				if ou > 1e-3 and ov > 1e-3:
					hits.append((ou * ov, a[0], b[0], key))
	hits.sort(reverse=True)
	# Faces pointing into their piece would vanish (back faces are culled); pieces are convex, so a face whose
	# normal points toward the piece's center is flipped.
	flipped = []
	for obj in _parts:
		center = sum((obj.matrix_world @ v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
		for poly in obj.data.polygons:
			n = (obj.matrix_world.to_3x3() @ poly.normal).normalized()
			if n.dot(obj.matrix_world @ poly.center - center) < -1e-4:
				flipped.append(obj.name)
	print("FLIPPED %d %s" % (len(flipped), sorted(set(flipped))[:20]))
	print("OVERLAPS %d" % len(hits))
	for area, a, b, key in hits[:60]:
		print("  %.4f  %s  x  %s  plane %s" % (area, a, b, key))


def export(obj, output, palette=FOREST_PALETTE):
	"""Exports `obj` as a GLB that links the shared palette file (relative uri) instead of embedding a copy."""
	os.makedirs(os.path.dirname(output), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", use_selection=True, export_animations=False)
	_link_palette(output, palette)


def _link_palette(glb_path, texture_path):
	"""Rewrites the GLB so its image is the shared palette file (relative uri) instead of an embedded copy."""
	data = open(glb_path, "rb").read()
	json_len = struct.unpack("<I", data[12:16])[0]
	doc = json.loads(data[20:20 + json_len])
	bin_chunk = data[20 + json_len:]
	bin_len = struct.unpack("<I", bin_chunk[:4])[0]
	blob = bytearray(bin_chunk[8:8 + bin_len])
	rel = os.path.relpath(texture_path, os.path.dirname(os.path.abspath(glb_path)))
	dropped = set()
	for image in doc.get("images", []):
		if "bufferView" in image:
			dropped.add(image.pop("bufferView"))
			image.pop("mimeType", None)
		image["uri"] = rel
	# Remove the embedded image bytes and re-pack the remaining buffer views.
	views = doc["bufferViews"]
	remap, kept, packed = {}, [], bytearray()
	for i, view in enumerate(views):
		if i in dropped:
			continue
		start = view.get("byteOffset", 0)
		chunk = blob[start:start + view["byteLength"]]
		packed += b"\0" * (-len(packed) % 4)
		view["byteOffset"] = len(packed)
		packed += chunk
		remap[i] = len(kept)
		kept.append(view)
	doc["bufferViews"] = kept
	for accessor in doc.get("accessors", []):
		if "bufferView" in accessor:
			accessor["bufferView"] = remap[accessor["bufferView"]]
	packed += b"\0" * (-len(packed) % 4)
	doc["buffers"][0]["byteLength"] = len(packed)
	chunk = json.dumps(doc, separators=(",", ":")).encode()
	chunk += b" " * (-len(chunk) % 4)
	body = struct.pack("<I4s", len(chunk), b"JSON") + chunk + struct.pack("<I4s", len(packed), b"BIN\0") + bytes(packed)
	with open(glb_path, "wb") as f:
		f.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def preview(path, aim, dist=7.5, height=6.2, yaw_degrees=-30.0):
	"""Game-like 3/4 view of the scene (camera `dist` in front of `aim`, raised `height`, turned `yaw`), EEVEE."""
	scene = bpy.context.scene
	scene.render.resolution_x = 900
	scene.render.resolution_y = 900
	world = bpy.data.worlds.new("world")
	world.use_nodes = True
	bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
	bg.inputs["Color"].default_value = (0.44, 0.69, 0.35, 1.0)
	bg.inputs["Strength"].default_value = 0.9
	scene.world = world
	ground = bpy.data.meshes.new("ground")
	bm = bmesh.new()
	bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=max(8.0, dist))
	bm.to_mesh(ground)
	bm.free()
	ground_obj = bpy.data.objects.new("ground", ground)
	gmat = bpy.data.materials.new("grass")
	gmat.use_nodes = True
	next(n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.2, 0.45, 0.15, 1)
	ground.materials.append(gmat)
	scene.collection.objects.link(ground_obj)
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
	sun.data.energy = 3.5
	sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
	scene.collection.objects.link(sun)
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	cam.data.lens = 50
	yaw = math.radians(yaw_degrees)
	aim = Vector(aim)
	cam.location = aim + Vector((math.sin(yaw) * -dist, -math.cos(yaw) * dist, height))
	cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
	scene.collection.objects.link(cam)
	scene.camera = cam
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


def run(build, name, output, scale=1.0, aim=(0.0, 0.0, 0.4), dist=3.6, height=2.9, palette=FOREST_PALETTE):
	"""Standard model script flow: fresh scene, `build()` the parts, optional `--check`, finish, export,
	optional `--preview out.png [--yaw deg]` (aim / dist / height in prop space, Blender coordinates)."""
	rng.seed(11)
	bpy.ops.wm.read_homefile(use_empty=True)
	_parts.clear()
	_pilaster_spots.clear()
	_props.clear()
	_prop_meshes.clear()
	_preview_roots.clear()
	_markers.clear()
	_solids.clear()
	build()
	if "--check" in ARGS:
		check()
	obj = finish(name, scale, palette)
	export(obj, output, palette)
	if _props or _markers or _solids:
		print("SCENE %s (%d props, %d markers, %d collision shapes)" % (_write_scene(output, scale), len(_props),
				len(_markers), len(_solids)))
	print("MODEL %s tris=%d dims=%s -> %s" % (name, sum(len(p.vertices) - 2 for p in obj.data.polygons),
			tuple(round(v, 3) for v in obj.dimensions), output))
	if "--preview" in ARGS:
		yaw = float(ARGS[ARGS.index("--yaw") + 1]) if "--yaw" in ARGS else -30.0
		preview(ARGS[ARGS.index("--preview") + 1], aim, dist, height, yaw)
	return obj
