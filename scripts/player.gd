extends CharacterBody2D

## 玩家角色：WASD 移动 / 空格冲刺 / 鼠标瞄准 / 左键射击

# --- 可调参数 ---
const SPEED := 260.0           # 走路速度 (px/s)
const DASH_SPEED := 700.0      # 冲刺速度
const DASH_DURATION := 0.18     # 冲刺持续 (秒)
const DASH_COOLDOWN := 0.8     # 冲刺冷却 (秒)
const BULLET_SPEED := 650.0    # 子弹速度
const FIRE_COOLDOWN := 0.18    # 射击间隔 (秒)
const MAX_HP := 100

# --- 内部状态 ---
var hp := MAX_HP
var dash_remaining := 0.0
var dash_cooldown := 0.0
var fire_timer := 0.0
var invuln_timer := 0.0        # 被击中后的无敌帧

# --- 信号 ---
signal health_changed(current: int, maximum: int)
signal coin_collected
signal bullet_spawned(origin: Vector2, direction: Vector2)


func _physics_process(delta: float) -> void:
	# 冷却计时
	dash_remaining = max(0.0, dash_remaining - delta)
	dash_cooldown  = max(0.0, dash_cooldown  - delta)
	fire_timer     = max(0.0, fire_timer     - delta)
	invuln_timer   = max(0.0, invuln_timer   - delta)

	# 1. 移动方向
	var input_dir := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down")  - Input.get_action_strength("ui_up")
	).normalized()

	if dash_remaining > 0.0:
		# 冲刺阶段：保持冲刺方向
		pass  # velocity 已在 _input 里设好
	else:
		velocity = input_dir * SPEED

	# 2. 空格冲刺（top-down 的"跳"等价物）
	if Input.is_action_just_pressed("ui_accept") and dash_cooldown <= 0.0 and dash_remaining <= 0.0:
		var dash_dir := input_dir if input_dir != Vector2.ZERO else -transform.x
		velocity = dash_dir * DASH_SPEED
		dash_remaining = DASH_DURATION
		dash_cooldown = DASH_COOLDOWN
		invuln_timer = max(invuln_timer, DASH_DURATION)   # 冲刺期间无敌

	move_and_slide()

	# 3. 射击
	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		var bullet_dir := (get_global_mouse_position() - global_position).normalized()
		bullet_spawned.emit(global_position, bullet_dir)
		fire_timer = FIRE_COOLDOWN

	# 4. 碰撞检测（自动收集金币由 coin.gd 主动检测玩家区域）
	#    这里只负责通知血量变化
	health_changed.emit(hp, MAX_HP)


func _draw() -> void:
	# 简单的角色视觉：身体圆 + 朝向三角
	var body_color := Color.CYAN if invuln_timer <= 0.0 else Color.YELLOW
	draw_circle(Vector2.ZERO, 14.0, body_color)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 20, Color.BLACK, 2.0)
	# 瞄准方向三角
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	var tri := PackedVector2Array([aim_dir * 18.0, aim_dir.rotated(0.4) * 10.0, aim_dir.rotated(-0.4) * 10.0])
	draw_colored_polygon(tri, Color.WHITE)


func take_damage(amount: int) -> void:
	if invuln_timer > 0.0:
		return
	hp -= amount
	invuln_timer = 0.5
	health_changed.emit(hp, MAX_HP)
	if hp <= 0:
		get_tree().reload_current_scene()
