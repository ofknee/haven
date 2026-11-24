extends Node

enum States {
	START,
	GAME,
}
signal state_changed(new_state:States)
var state: States = States.START :
	set(val):
		if state != val: return
		state = val
		state_changed.emit(val)


var wood: int = 0



signal level_change(new_level: int)
var level : int:
	set(val):
		level = val
		level_change.emit(val)
