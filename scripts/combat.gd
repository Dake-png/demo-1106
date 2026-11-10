extends Node

## 战斗结算：子弹生成、命中判定、范围伤害与 effect 结算。
## 击杀计数 / 掉落 / UI 等业务仍由 main.gd 处理。

const BulletScene := preload("res://scenes/bullet.tscn")
const WEAPONS := preload("res://scripts/weapon_data.gd")
const EFFECTS := preload("res://scripts/effect_data.gd")

var fx: Node        # 特效层：子弹 / 范围圈始终压在实体之上（由 main 传入 Fx 层）
var player
var dmg_numbers: Node
var sfx: Callable
var _last_hit_stop := 0   # 上次顿帧时间（毫秒），用于冷却


func setup(fx_host: Node, p, numbers: Node, sfx_cb: Callable) -> void:
	fx = fx_host
	player = p
	dmg_numbers = numbers
	sfx = sfx_cb


func spawn_bullet(origin: Vector2, direction: Vector2, damage: float, crit_stacks: int) -> void:
	var w: Dictionary = player.current_weapon()
	var bullet := BulletScene.instantiate()
	bullet.position = origin
	bullet.SPEED = player.BULLET_SPEED * WEAPONS.bullet_speed_mult(w)
	bullet.velocity = direction * bullet.SPEED
	bullet.damage = damage * WEAPONS.bullet_damage_mult(w)
	bullet.crit_stacks = crit_stacks
	bullet.bullet_shape = String(w.get("bullet_shape", "circle"))
	# 巨型化药水：子弹大小 × 倍率、穿透 + 加算
	bullet.bullet_size = WEAPONS.bullet_radius_px(w) * float(player.mod_mul("bullet_scale"))
	bullet.aoe_radius = WEAPONS.aoe_radius(w)
	bullet.pierce = int(w.get("pierce", 0)) + int(round(float(player.mod_add("pierce"))))
	bullet.effects = w.get("apply", [])
	sfx.call("crit" if crit_stacks >= 2 else "shoot")
	fx.add_child(bullet)
	bullet.body_entered.connect(_on_bullet_hit_body.bind(bullet))
	bullet.area_entered.connect(_on_bullet_hit_area.bind(bullet))

	# 对自身施加的 effect：每发子弹结算一次
	_apply_effects(bullet, player, true)


func _on_bullet_hit_body(body: Node, bullet: Node) -> void:
	_bullet_hit(body, bullet)


func _on_bullet_hit_area(area: Area2D, bullet: Node) -> void:
	_bullet_hit(area.get_parent(), bullet)


# 命中结算：范围伤害 + 穿透；同一敌人只结算一次
func _bullet_hit(target: Node, bullet: Node) -> void:
	if not is_instance_valid(bullet) or target == null:
		return
	if not target.is_in_group("enemy") or bullet.hit_targets.has(target):
		return
	bullet.hit_targets.append(target)
	_damage_enemy(target, bullet)
	if bullet.aoe_radius > 0.0:
		_aoe_damage(target.global_position, bullet)
	if bullet.pierce > 0:
		bullet.pierce -= 1
		bullet.on_pierced()
	else:
		bullet.queue_free()


func _damage_enemy(target: Node, bullet: Node) -> void:
	_apply_effects(bullet, target, false)
	var dmg := int(bullet.damage)
	var crit: bool = bullet.crit_stacks > 0
	target.take_damage(dmg, crit)   # 冰冻 debuff：暴击时额外增伤
	dmg_numbers.spawn_damage(bullet.global_position, dmg, bullet.crit_stacks)
	sfx.call("hit")
	_impact(crit)


## 打击反馈：顿帧（暴击更重）+ 暴击震屏；120ms 冷却避免连射时卡顿
func _impact(crit: bool) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_stop >= 120:
		_last_hit_stop = now
		_hit_stop(0.55 if crit else 0.8, 0.05 if crit else 0.03)
	if crit and player and player.has_method("shake"):
		player.shake(3.0)


func _hit_stop(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	# 忽略时间缩放与暂停，保证一定恢复
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## 按武器 apply 配置施加 effect：self_target=true 对玩家本身，false 对命中敌人
func _apply_effects(bullet: Node, target: Node, self_target: bool) -> void:
	if not is_instance_valid(target) or not target.has_method("apply_effect"):
		return
	for cfg in bullet.effects:
		var targets: Array = cfg.get("targets", [])
		if not targets.has("self" if self_target else "enemy"):
			continue
		var times: int = EFFECTS.roll_count(float(cfg.get("chance", 1.0)))
		if times <= 0:
			continue
		var positive := bool(cfg.get("positive", true))
		var effect_id := String(cfg.get("effect", ""))
		# 元素伤害系数：武器系数 × 卡牌元素倍率（伤害卡 + 机制卡）
		var coef: float = float(cfg.get("coef", 0.0)) * float(player.element_damage_mult(effect_id))
		target.apply_effect(effect_id, positive, times, float(bullet.damage), coef)
		# 触发时元素伤害：命中敌方 debuff 时立即结算 武器伤害×元素系数
		if not self_target and not positive and coef > 0.0:
			var elem: int = int(round(float(bullet.damage) * coef))
			if elem > 0:
				var icon := String(EFFECTS.get_effect(effect_id).get("icon", "❔"))
				for k in range(int(player.trigger_times())):
					target.take_damage(elem)
					dmg_numbers.spawn_trigger(target.global_position, elem, icon)


func _aoe_damage(center: Vector2, bullet: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bullet.hit_targets.has(e):
			continue
		if e.global_position.distance_to(center) <= bullet.aoe_radius:
			bullet.hit_targets.append(e)
			_damage_enemy(e, bullet)
	_boom(center, bullet.aoe_radius)


# 范围伤害的扩散圆环特效
func _boom(center: Vector2, r: float) -> void:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in range(24):
		var a := i * TAU / 24.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	ring.points = pts
	ring.width = 3.0
	ring.default_color = Color(1.0, 0.55, 0.1, 0.9)
	ring.position = center
	ring.scale = Vector2(0.3, 0.3)
	fx.add_child(ring)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.28)
	tw.tween_property(ring, "modulate:a", 0.0, 0.28)
	tw.finished.connect(ring.queue_free)


# Effect 持续伤害事件 → 伤害飘字
func on_effect_damage(at: Vector2, amount: int, icon: String) -> void:
	dmg_numbers.spawn_dot(at, amount, icon)
