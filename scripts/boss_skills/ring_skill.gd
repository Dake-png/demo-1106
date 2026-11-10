extends Node2D

## 红圈技能组件：每隔 interval 停止移动 charge 秒，释放扩张到 max_radius 的红圈
## 圈扩到最大后延迟 damage_delay 秒结算：圈内玩家被击碎护盾 + 碎盾 debuff + 固定伤害
## 参数：interval / first_delay / charge / max_radius（px）/ damage_delay / damage

var boss: Node
var cfg := {}
var _timer := 0.0
var _state := 0          # 0=冷却 1=扩张 2=延迟结算
var _radius := 0.0
var _hold := 0.0
var _hit := false


func setup(owner_boss: Node, config: Dictionary) -> void:
	boss = owner_boss
	cfg = config
	_timer = float(cfg.get("first_delay", 10.0))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(boss) or boss.is_dead():
		return
	if _state == 0:
		_timer -= delta
		if _timer <= 0.0:
			_start()
		return

	var max_radius := float(cfg.get("max_radius", 600.0))
	if _state == 1:
		var charge := maxf(0.01, float(cfg.get("charge", 5.0)))
		_radius = minf(max_radius, _radius + max_radius / charge * delta)
		queue_redraw()
		if _radius >= max_radius - 0.01:
			_state = 2
			_hold = maxf(0.0, float(cfg.get("damage_delay", 1.0)))
			queue_redraw()
		return

	# 圈已到最大范围：延迟结束后结算
	_hold -= delta
	if _hold <= 0.0:
		_try_hit()
		_finish()


func _start() -> void:
	_state = 1
	_radius = 0.0
	_hit = false
	boss.movement_locked = true
	queue_redraw()


func _try_hit() -> void:
	if _hit:
		return
	var player: Node2D = boss.player
	if not player:
		return
	if boss.global_position.distance_to(player.global_position) > _radius:
		return
	_hit = true
	if player.has_method("break_shield"):
		player.break_shield()
	player.take_damage(int(cfg.get("damage", 40)))


func _finish() -> void:
	_state = 0
	_radius = 0.0
	boss.movement_locked = false
	_timer = maxf(1.0, float(cfg.get("interval", 10.0))
		- float(cfg.get("charge", 5.0)) - float(cfg.get("damage_delay", 1.0)))
	queue_redraw()


func _draw() -> void:
	if _state == 0:
		return
	var fill := Color(0.9, 0.08, 0.05, 0.18)
	var edge := Color(0.95, 0.15, 0.1, 0.9)
	if _state == 2:
		# 延迟结算阶段：加深颜色作为危险提示
		fill = Color(0.95, 0.05, 0.02, 0.32)
		edge = Color(1.0, 0.3, 0.1, 1.0)
	draw_circle(Vector2.ZERO, _radius, fill)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, edge, 4.0)
