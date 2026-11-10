extends Area2D

## Boss 的远程魔法弹

var velocity := Vector2.ZERO
var damage := 18

var _life := 0.0
var _t := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_life += delta
	_t += delta
	if _life > 4.0:
		queue_free()


func _draw() -> void:
	var pulse := 8.0 + sin(_t * 10.0) * 1.5
	draw_circle(Vector2.ZERO, pulse, Color(0.65, 0.2, 0.9, 0.9))
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.9, 0.3))
	draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 16, Color(0.95, 0.85, 1.0), 1.5)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.take_damage(damage)
		queue_free()
