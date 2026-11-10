extends Area2D

## 经验球：碰到玩家获得经验，磁吸期间会被大范围吸走（事件走 EventBus）

const MAGNET_SPEED := 620.0

var exp_value := 10
var _t := 0.0
var _player: Node = null


func _ready() -> void:
	add_to_group("drop")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	scale = Vector2.ONE * (1.0 + 0.08 * sin(_t * 6.0))

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var p = _player
	if p and p.pickup_active():
		var d: Vector2 = p.global_position - global_position
		if d.length() < p.pickup_radius():
			global_position += d.normalized() * MAGNET_SPEED * delta


func _draw() -> void:
	WorldView.draw_shadow(self, 4.5, 0.2)
	WorldView.body_begin(self, WorldView.LIFT_DROP)
	draw_circle(Vector2.ZERO, 8.0, Color(0.15, 0.75, 1.0))
	draw_circle(Vector2.ZERO, 3.5, Color.WHITE)
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color(0.05, 0.4, 0.8), 1.5)
	WorldView.body_end(self)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		body.gain_exp(exp_value)
		EventBus.exp_orb_picked.emit()
		queue_free()
