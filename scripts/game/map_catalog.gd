class_name MapCatalog
## The battlefields (lobby setting "map", an index into MAPS). Every map works with every mode: a map only
## changes the look (ground, light, trees, border, scattered decor) and the landmarks WorldBuilder lays out
## (`landmarks`: outcrops / graveyards / ruins); the rules, spawns, camps, hill and circles come from the mode.
## New map = a MAPS row (+ a `WorldBuilder._add_<landmarks>()` when it brings a new kind of landmark).

const FOREST := "res://assets/environment/forest/%s.glb"
const GRAVEYARD := "res://assets/environment/graveyard/%s.glb"
const ARENA := "res://assets/environment/arena/%s.glb"
const DUNGEON := "res://assets/environment/dungeon/%s.glb"

const MAPS: Array[Dictionary] = [
	{
		"id": &"greenwood",
		"name": "Greenwood",
		"hint": "Rolling meadows between thick forests and mossy rock outcrops.",
		"ground": Color(0.44, 0.69, 0.35),
		"minimap": Color(0.16, 0.3, 0.14, 0.85),
		"sky": Color(0.58, 0.78, 0.92),
		"ambient": Color(0.85, 0.9, 1.0),
		"ambient_energy": 0.55,
		"sun": Color(1.0, 1.0, 1.0),
		"sun_energy": 1.1,
		"fog_density": 0.0,
		"trees": [FOREST % "tree", FOREST % "tree_high"],
		"tree_density": 1.0,
		"tree_scale": Vector2(1.0, 1.4),
		"border": FOREST % "fence",
		"border_step": 1.05,
		"decor": [
			[FOREST % "patch_grass", 420, 0.8, 1.6],
			[FOREST % "patch_dirt", 90, 0.8, 1.4],
			[FOREST % "plant", 650, 1.0, 1.8],
			[FOREST % "stones", 110, 0.5, 0.9],
		],
		"landmarks": &"outcrops",
	},
	{
		"id": &"gravemoor",
		"name": "Gravemoor",
		"hint": "A misty moor at dusk: pine woods, fenced graveyards and lantern-lit crypts.",
		"ground": Color(0.3, 0.47, 0.31),
		"minimap": Color(0.13, 0.19, 0.15, 0.85),
		"sky": Color(0.33, 0.31, 0.44),
		"ambient": Color(0.72, 0.76, 1.0),
		"ambient_energy": 0.6,
		"sun": Color(1.0, 0.82, 0.64),
		"sun_energy": 0.95,
		"fog_color": Color(0.42, 0.46, 0.62),
		"fog_density": 0.0045,
		# Mostly evergreen, a few turned red (pine_fall).
		"trees": [GRAVEYARD % "pine", GRAVEYARD % "pine", GRAVEYARD % "pine_crooked", GRAVEYARD % "pine_crooked",
				GRAVEYARD % "pine_fall"],
		"tree_density": 0.85,
		"tree_scale": Vector2(1.0, 1.35),
		"border": GRAVEYARD % "iron_fence_border",
		"border_step": 1.0,
		# The fence sits at the back of its tile (z -0.4..-0.25): this moves it onto the edge.
		"border_offset": 0.325,
		"decor": [
			[FOREST % "patch_grass", 260, 0.8, 1.5],
			[FOREST % "plant", 380, 0.9, 1.6],
			[GRAVEYARD % "rocks", 120, 0.8, 1.4],
			[GRAVEYARD % "debris", 90, 0.9, 1.4],
			[GRAVEYARD % "pumpkin", 45, 1.0, 1.5],
			[GRAVEYARD % "pumpkin_tall", 30, 1.0, 1.4],
			[GRAVEYARD % "trunk", 40, 1.0, 1.5],
		],
		"landmarks": &"graveyards",
	},
	{
		"id": &"sunstone",
		"name": "Sunstone Ruins",
		"hint": "Sun-baked sand around the broken courtyards and colonnades of a fallen kingdom.",
		"ground": Color(0.74, 0.66, 0.47),
		"minimap": Color(0.4, 0.33, 0.2, 0.85),
		"sky": Color(0.86, 0.8, 0.66),
		"ambient": Color(1.0, 0.95, 0.86),
		"ambient_energy": 0.6,
		"sun": Color(1.0, 0.93, 0.78),
		"sun_energy": 1.15,
		"fog_density": 0.0,
		"trees": [ARENA % "tree"],
		"tree_density": 0.35,
		"tree_scale": Vector2(1.2, 1.7),
		"border": ARENA % "border_straight",
		"border_step": 1.0,
		"decor": [
			[ARENA % "bricks", 150, 0.7, 1.2],
			[DUNGEON % "stones", 120, 0.6, 1.1],
			[ARENA % "floor_detail", 90, 0.9, 1.3],
			[FOREST % "plant", 300, 0.9, 1.5],
		],
		"landmarks": &"ruins",
	},
]


static func get_map(index: int) -> Dictionary:
	return MAPS[clampi(index, 0, MAPS.size() - 1)]


static func names() -> PackedStringArray:
	var result := PackedStringArray()
	for map in MAPS:
		result.append(map.name)
	return result
