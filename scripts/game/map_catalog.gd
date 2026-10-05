class_name MapCatalog
extends Resource
## Every playable map, in lobby order (resources/data/maps/map_catalog.tres). New map = a MapDef .tres here.

const CATALOG := "res://resources/data/maps/map_catalog.tres"

@export var maps: Array[MapDef] = []

static var _loaded: MapCatalog


static func all() -> Array[MapDef]:
	if _loaded == null:
		_loaded = load(CATALOG) as MapCatalog
	return _loaded.maps


## The map with `id`, or the first one.
static func find(id: StringName) -> MapDef:
	for map in all():
		if map.id == id:
			return map
	return all()[0]


## The map a mode starts on: one made just for it (Crown Ruins for King of the Hill), else the first that fits.
static func default_for(match_mode: int) -> MapDef:
	var maps := for_mode(match_mode)
	for map in maps:
		if map.modes == [match_mode]:
			return map
	return maps[0]


## Maps playable in `match_mode`.
static func for_mode(match_mode: int) -> Array[MapDef]:
	var list: Array[MapDef] = []
	for map in all():
		if map.supports(match_mode):
			list.append(map)
	return list
