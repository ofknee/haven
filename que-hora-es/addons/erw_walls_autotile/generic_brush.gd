@tool
extends RefCounted

const Solver = preload("rule_engine.gd")
const Variations = preload("generic_variations.gd")
const META := &"erw_walls_generic_cells"
const CORNERS := [Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
const BLOCKED := -2


func protected_cells(layer: TileMapLayer) -> Dictionary:
	var protected := {}
	var settings: Dictionary = layer.get_meta(META, {})
	for state in settings.values():
		var painted: Dictionary = state.get("painted", {})
		for pos: Vector2i in painted:
			if _read_tile(layer, pos) == painted[pos]:
				protected[pos] = true
	return protected


func read_top(layer: TileMapLayer, profile_id: String) -> Dictionary:
	var state: Dictionary = layer.get_meta(META, {}).get(profile_id, {})
	var painted: Dictionary = state.get("painted", {})
	var top := {}
	for pos: Vector2i in state.get("top", []):
		if painted.has(pos) and _read_tile(layer, pos) == painted[pos]:
			top[pos] = true
	return top


func render(layer: TileMapLayer, profile: Dictionary, top: Dictionary, seed_value: int, variations: bool) -> void:
	var settings: Dictionary = layer.get_meta(META, {}).duplicate(true)
	var previous: Dictionary = settings.get(profile.profile_id, {}).get("painted", {})
	for pos: Vector2i in previous:
		if _read_tile(layer, pos) == previous[pos]:
			layer.erase_cell(pos)
	var blocked := {}
	for pos: Vector2i in top.keys():
		if layer.get_cell_source_id(pos) >= 0:
			top.erase(pos)
		for row in range(1, int(profile.height)):
			var below := pos + Vector2i(0, row)
			if layer.get_cell_source_id(below) >= 0:
				blocked[below] = BLOCKED
	var roles := generate(top, profile, seed_value, variations, blocked)
	var painted := Variations.resolve(roles, profile, seed_value, variations)
	for pos: Vector2i in painted:
		var tile: Vector4i = painted[pos]
		layer.set_cell(pos, tile.x, Vector2i(tile.y, tile.z), tile.w)
	if top.is_empty():
		settings.erase(profile.profile_id)
	else:
		settings[profile.profile_id] = {"top": top.keys(), "painted": painted}
	if settings.is_empty():
		layer.remove_meta(META)
	else:
		layer.set_meta(META, settings)


func generate(top: Dictionary, profile: Dictionary, seed_value: int, variations: bool, blocked: Dictionary = {}) -> Dictionary:
	var template: Dictionary = profile.template
	var groups := {}
	for role in template.base_wang:
		var mask: int = 0
		for i in 4:
			if template.base_wang[role][i] == 0:
				mask |= 1 << i
		if not groups.has(mask):
			groups[mask] = []
		groups[mask].append(role)

	var layout := blocked.duplicate()
	var rng := RandomNumberGenerator.new()
	for pos: Vector2i in top.keys():
		var mask := _corner_mask(top, pos)
		if mask == 0:
			# A remnant that belongs to no 2x2 top cannot form a wall.
			top.erase(pos)
			continue
		# Opposite-corner joins have no diagonal piece in the template.
		var candidates: Array = groups.get(mask, groups[15])
		rng.seed = hash([seed_value, pos])
		layout[pos] = _choose(candidates, profile.tile_probabilities, rng, variations)

	var assembled := Solver.new().apply_phase(layout, template.assembly, seed_value)
	for pos: Vector2i in assembled.keys():
		var role: int = assembled[pos]
		if role == BLOCKED:
			assembled.erase(pos)
		elif variations and template.variants.has(role):
			rng.seed = hash([seed_value, pos, role])
			assembled[pos] = _choose([role, template.variants[role]], profile.tile_probabilities, rng, true)
	return assembled


func _corner_mask(top: Dictionary, pos: Vector2i) -> int:
	var mask := 0
	for i in 4:
		var corner: Vector2i = CORNERS[i]
		if top.has(pos + corner) and top.has(pos + Vector2i(corner.x, 0)) and top.has(pos + Vector2i(0, corner.y)):
			mask |= 1 << i
	return mask


func _choose(roles: Array, probabilities: Dictionary, rng: RandomNumberGenerator, variations: bool) -> int:
	var total := 0.0
	for role in roles:
		var probability := float(probabilities.get(role, 1.0))
		if not variations and probability > 0.0:
			return role
		total += probability
	var roll := rng.randf() * total
	for role in roles:
		roll -= float(probabilities.get(role, 1.0))
		if roll < 0.0:
			return role
	return roles[0]


func _read_tile(layer: TileMapLayer, pos: Vector2i) -> Vector4i:
	var coords := layer.get_cell_atlas_coords(pos)
	return Vector4i(layer.get_cell_source_id(pos), coords.x, coords.y, layer.get_cell_alternative_tile(pos))
