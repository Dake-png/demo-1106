extends Node

## 背包开关按键：独立于主场景，暂停时也能响应 E

signal toggle_pressed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		get_viewport().set_input_as_handled()
		toggle_pressed.emit()
