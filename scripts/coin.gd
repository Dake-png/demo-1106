extends Area2D

## 金币：旋转 + 碰到玩家即收集（收集事件走 EventBus）

var _player: Node = null


func _ready() -> void:
	add_to_group("drop")
	body_entered.connect(_on_body_entered)


const MAGNET_SPEED := 620.0


func _process(delta: float) -> void:
	rotate(delta * 4.0)   # 旋转动画
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var p = _player
	if p and p.pickup_active():
		var d: Vector2 = p.global_position - global_position
		if d.length() < p.pickup_radius():
			global_position += d.normalized() * MAGNET_SPEED * delta


func _draw() -> void:
	# 小物件立体化：淡阴影 + 抬升 + 压扁的币面（旋转时像倾倒的硬币）
	WorldView.draw_shadow(self, 4.5, 0.2)
	draw_set_transform(Vector2(0.0, -WorldView.LIFT_DROP), 0.0, Vector2(1.0, 0.72))
	draw_circle(Vector2.ZERO, 8.0, Color.GOLD)
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color(0.8, 0.6, 0.0), 1.5)
	draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		EventBus.coin_picked.emit()
		queue_free()
