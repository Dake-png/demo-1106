extends Area2D

## 子弹：直线飞行，撞墙或超时销毁

const SPEED := 650.0
const LIFETIME := 1.5

var velocity := Vector2.ZERO
var _life := 0.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_life += delta
	if _life > LIFETIME:
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color.ORANGE)
	draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 16, Color.YELLOW, 1.5)
