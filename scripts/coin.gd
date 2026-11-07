extends Area2D

## 金币：旋转 + 碰到玩家即收集

signal picked_up


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	rotate(_delta * 4.0)   # 旋转动画


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color.GOLD)
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(0.8, 0.6, 0.0), 1.5)
	draw_circle(Vector2.ZERO, 3.0, Color.WHITE)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		picked_up.emit()
		queue_free()
