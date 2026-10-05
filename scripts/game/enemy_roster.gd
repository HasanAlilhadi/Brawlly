class_name EnemyRoster
extends Resource
## What a warband of one faction is made of (see Warband._compose): `entries` take their share of the band
## once it is big enough (so bigger bands field stronger creatures); `filler` makes up the rest. New enemy
## type = a scene in scenes/characters/enemies/ + a RosterEntry here.

@export var filler: PackedScene
@export var entries: Array[RosterEntry] = []
