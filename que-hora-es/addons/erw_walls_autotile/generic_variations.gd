@tool
extends RefCounted

const Tiles = preload("generic_tiles.gd")


static func compile(profile: Dictionary, template: Dictionary, tileset: TileSet) -> Array:
	var groups := {}
	for variant: Dictionary in profile.get("variations", []):
		var ids := variant.keys()
		ids.sort()
		var anchor: int = ids[0]
		var key := str(ids)
		if not groups.has(key):
			var offsets := {}
			var base := {}
			for role in ids:
				offsets[template.slots[role] - template.slots[anchor]] = role
				base[role] = profile.tiles[role]
			groups[key] = {"anchor": anchor, "offsets": offsets, "choices": [base],
				"weights": [_probability(tileset, base[anchor])]}
		groups[key].choices.append(variant)
		groups[key].weights.append(_probability(tileset, variant[anchor]))
	var result := groups.values()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.offsets.size() > b.offsets.size())
	return result


static func resolve(roles: Dictionary, profile: Dictionary, seed_value: int, enabled: bool) -> Dictionary:
	var tiles := {}
	var groups: Array = profile.get("variation_groups", []) if enabled else []
	var anchors := {}
	for group: Dictionary in groups:
		anchors[group.anchor] = []
	for position: Vector2i in roles:
		var role: int = roles[position]
		tiles[position] = profile.tiles[role]
		if anchors.has(role):
			anchors[role].append(position)
	var claimed := {}
	var rng := RandomNumberGenerator.new()
	for group: Dictionary in groups:
		for position: Vector2i in anchors[group.anchor]:
			if not _matches(position, group.offsets, roles, claimed):
				continue
			rng.seed = hash([seed_value, position, group.anchor])
			var choice: Dictionary = group.choices[_pick(group.weights, rng)]
			for offset: Vector2i in group.offsets:
				var target := position + offset
				tiles[target] = choice[group.offsets[offset]]
				claimed[target] = true
	return tiles


static func _matches(position: Vector2i, offsets: Dictionary, roles: Dictionary, claimed: Dictionary) -> bool:
	for offset: Vector2i in offsets:
		var target := position + offset
		if claimed.has(target) or roles.get(target) != offsets[offset]:
			return false
	return true


static func _pick(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight: float in weights:
		total += weight
	var roll := rng.randf() * total
	for index in weights.size():
		roll -= float(weights[index])
		if roll < 0.0:
			return index
	return 0


static func _probability(tileset: TileSet, tile: Vector4i) -> float:
	var data := Tiles.tile_data(tileset, tile)
	return data.probability if data != null else 1.0
