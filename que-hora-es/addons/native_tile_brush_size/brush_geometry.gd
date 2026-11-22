@tool
extends RefCounted


static func line(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var current := start
	var distance := (finish-start).abs()
	var direction := Vector2i(signi(finish.x-start.x),signi(finish.y-start.y))
	var error := distance.x-distance.y
	while true:
		cells.append(current)
		if current == finish:
			break
		var twice := error*2
		if twice > -distance.y:
			error -= distance.y
			current.x += direction.x
		if twice < distance.x:
			error += distance.x
			current.y += direction.y
	return cells


static func footprint(center: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var offset := Vector2i.ONE * -int((size-1)/2)
	for row in size:
		for column in size:
			var x := column if row%2 == 0 else size-1-column
			cells.append(center+offset+Vector2i(x,row))
	return cells
