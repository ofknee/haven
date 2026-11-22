@tool
extends RefCounted
## Rules use atlas-local tile IDs; absent dictionary keys represent empty cells.


func generate(base: Dictionary, profile: Dictionary, seed_value: int = 1, variations: bool = true) -> Dictionary:
	var result := base.duplicate()
	for i in profile.phases.size():
		if i == 2 and not variations:
			continue
		result = apply_phase(result, profile.phases[i], seed_value)
	return result


func apply_phase(cells: Dictionary, phase: Dictionary, seed_value: int = 1, force_probability: bool = false) -> Dictionary:
	var result := cells.duplicate()
	# A nonsequential rule map matches against one snapshot, then applies outputs in
	# authored order. Sequential maps observe earlier writes, including within a rule.
	for rule in phase.rules:
		if rule.disabled:
			continue
		var read_map: Dictionary = result if phase.match_in_order else cells
		var anchors := _candidates(read_map, rule.inputs)
		for origin in anchors:
			if not _matches(read_map, rule.inputs, origin):
				continue
			if not force_probability and not _passes_probability(rule, origin, seed_value):
				continue
			for cell: Vector3i in rule.outputs:
				var pos: Vector2i = origin + Vector2i(cell.x, cell.y)
				if cell.z == -1:
					result.erase(pos)
				else:
					result[pos] = cell.z
	return result


func _candidates(cells: Dictionary, inputs: Array) -> Array[Vector2i]:
	var anchor := Vector3i.ZERO
	var found := false
	for cell: Vector3i in inputs:
		if cell.z >= 0:
			anchor = cell
			found = true
			break
	var candidates: Array[Vector2i] = []
	if not found:
		return candidates # Converted profiles require an exact anchor for each rule.
	for pos: Vector2i in cells:
		if cells[pos] == anchor.z:
			candidates.append(pos - Vector2i(anchor.x, anchor.y))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return candidates


func _matches(cells: Dictionary, inputs: Array, origin: Vector2i) -> bool:
	for cell: Vector3i in inputs:
		if int(cells.get(origin + Vector2i(cell.x, cell.y), -1)) != cell.z:
			return false
	return true


func _passes_probability(rule: Dictionary, origin: Vector2i, seed_value: int) -> bool:
	if rule.probability >= 1.0:
		return true
	if rule.probability <= 0.0:
		return false
	# Stable per position and rule: editing one wall does not reroll the entire map.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, rule.id, origin])
	return rng.randf() < rule.probability

