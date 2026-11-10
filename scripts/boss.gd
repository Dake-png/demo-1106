extends CharacterBody2D

## 通用 Boss：数值 / 外观 / 技能全部来自 scripts/boss_data.gd
## 特殊技能由 scripts/boss_skills/ 下的组件挂载，本脚本不写死任何 Boss 专属逻辑
## 新增 Boss：boss_data.gd 加一条数据（需要新技能时再加一个技能组件）

## 死亡 / 元素飘字走 EventBus（见 scripts/event_bus.gd）；stats_changed 只给 UI 用
signal stats_changed(hp: int, max_hp: int, shield: int, max_shield: int)
signal summon_requested(at: Vector2, count: int)

const BOSS_DATA := preload("res://scripts/boss_data.gd")
const ARMOR := preload("res://scripts/armor.gd")
const EFFECT_HOLDER := preload("res://scripts/effect_holder.gd")
const CoinScene := preload("res://scenes/coin.tscn")
const ExpOrbScene := preload("res://scenes/exp_orb.tscn")
const ItemScene := preload("res://scenes/item.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")

# 死亡掉落：12 金币、6 个经验球（每个 120 经验）、1 个补血道具
const COIN_DROPS := 12
const ORB_DROPS := 6
const ORB_EXP := 120

# 技能类型 → 组件脚本（新增技能类型在这里注册）
const SKILLS := {
	"shoot": preload("res://scripts/boss_skills/shoot_skill.gd"),
	"summon": preload("res://scripts/boss_skills/summon_skill.gd"),
	"ring": preload("res://scripts/boss_skills/ring_skill.gd"),
}

const SHIELD_REGEN_DELAY := 3.0
const SHIELD_REGEN_RATE := 10.0

# 接触伤害
const CONTACT_DAMAGE := 20
const CONTACT_COOLDOWN := 0.8

var boss_id := "demon"
var display_name := ""
var max_hp := 1000000
var max_shield := 0.0
var armor := 30.0
var speed := 55.0
var radius := 40.0
var visual := "demon"

var hp := max_hp
var shield := 0.0
var shield_delay := 0.0
var player: Node2D
var effects: Node
var movement_locked := false
var fx_host: Node = null      # 特效层（Fx）：弹幕等挂到实体之上，由 spawner 注入

var _dead := false
var _hit_flash := 0.0          # 受击闪白剩余时间
var _contact_timer := 0.0


## 由主场景在 add_child 之前调用
func configure(id: String) -> void:
	boss_id = id


func _ready() -> void:
	var d: Dictionary = BOSS_DATA.get_boss(boss_id)
	display_name = String(d.get("name", boss_id))
	max_hp = int(d.get("hp", 1000000))
	max_shield = float(d.get("shield", 0.0))
	armor = float(d.get("armor", 0.0))
	speed = float(d.get("speed", 55.0))
	radius = float(d.get("radius", 40.0))
	visual = String(d.get("visual", "demon"))
	hp = max_hp
	shield = max_shield

	var shape := CircleShape2D.new()
	shape.radius = radius
	$CollisionShape2D.shape = shape

	effects = EFFECT_HOLDER.new()
	effects.name = "Effects"
	add_child(effects)
	effects.dot_tick.connect(_on_dot_tick)   # 燃烧每秒伤害
	player = get_tree().get_first_node_in_group("player")

	_build_skills(d.get("skills", []))
	summon_requested.connect(_spawn_minions)
	stats_changed.emit(hp, max_hp, int(shield), int(max_shield))
	queue_redraw()


## 出场动画：2 秒从小放大 + 淡入（由主场景在 add_child 后调用）
func play_intro() -> void:
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.8)


## 召唤小怪（技能组件只发信号，生成与信号连接由 Boss 自己处理）
func _spawn_minions(at: Vector2, count: int) -> void:
	var host = get_parent()
	for i in range(count):
		var e := EnemyScene.instantiate()
		e.config(0)
		e.make_mini()
		e.position = at + Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))
		host.add_child(e)


## 死亡掉落：金币 / 经验球 / 补血道具，直接挂到主场景下
func _drop_loot() -> void:
	if get_tree().get_nodes_in_group("drop").size() >= 240:   # 掉落物上限
		return
	var host = get_parent()
	var at := global_position
	for i in range(COIN_DROPS):
		var coin := CoinScene.instantiate()
		coin.position = at
		host.add_child(coin)
	for i in range(ORB_DROPS):
		var orb := ExpOrbScene.instantiate()
		orb.position = at + Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))
		orb.exp_value = ORB_EXP
		host.add_child(orb)
	var item := ItemScene.instantiate()
	item.item_id = "heal_potion"
	item.position = at + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
	host.add_child(item)


func _build_skills(list: Array) -> void:
	for cfg in list:
		var type := String(cfg.get("type", ""))
		if not SKILLS.has(type):
			push_warning("Boss 技能未注册：%s" % type)
			continue
		var skill = SKILLS[type].new()
		skill.name = "Skill_" + type
		add_child(skill)
		skill.setup(self, cfg)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_tick_shield(delta)
	_tick_move(delta)
	_tick_contact(delta)


## 接触伤害：贴身站在 Boss 身上也会周期掉血
func _tick_contact(delta: float) -> void:
	_contact_timer = maxf(0.0, _contact_timer - delta)
	if player == null or _contact_timer > 0.0:
		return
	if global_position.distance_to(player.global_position) <= radius + 18.0:
		player.take_damage(CONTACT_DAMAGE)
		_contact_timer = CONTACT_COOLDOWN


func _tick_shield(delta: float) -> void:
	# 磁力 debuff 持续扣盾
	var drain: float = effects.shield_drain_rate()
	if drain > 0.0 and shield > 0.0:
		shield = maxf(0.0, shield - max_shield * drain * delta)
		shield_delay = SHIELD_REGEN_DELAY
		queue_redraw()
		stats_changed.emit(maxi(hp, 0), max_hp, int(shield), int(max_shield))

	# 护盾回复
	if shield_delay > 0.0:
		shield_delay = maxf(0.0, shield_delay - delta)
	elif shield < max_shield:
		shield = minf(max_shield, shield + SHIELD_REGEN_RATE * delta)
		queue_redraw()
		stats_changed.emit(maxi(hp, 0), max_hp, int(shield), int(max_shield))


func _tick_move(_delta: float) -> void:
	if movement_locked or effects.is_frozen() or not player:   # 冰冻满层同样无法移动
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var d: Vector2 = player.global_position - global_position
	var dist := d.length()
	var spd: float = speed * effects.slow_factor()
	if dist > 260.0:
		velocity = d.normalized() * spd
	elif dist < 170.0:
		velocity = -d.normalized() * spd
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func take_damage(amount: int, crit := false) -> void:
	if _dead:
		return
	shield_delay = SHIELD_REGEN_DELAY
	# 冰冻 debuff：受到暴击伤害增加
	var raw: float = float(amount) * (effects.crit_taken_mult() if crit else 1.0)
	var left := ARMOR.reduce(int(round(raw * effects.taken_mult())), armor)
	if shield > 0.0:
		var absorbed := minf(shield, float(left))
		shield -= absorbed
		left -= int(absorbed)
	hp -= left
	_hit_flash = 0.09
	queue_redraw()
	stats_changed.emit(maxi(hp, 0), max_hp, int(shield), int(max_shield))
	if hp <= 0:
		_dead = true
		EventBus.boss_died.emit(global_position)
		call_deferred("_finish_death")


## 死亡收尾：掉落与释放延迟到物理回调之外，避免 add_child 冲突
func _finish_death() -> void:
	_drop_loot()
	queue_free()


## 持续伤害：扣血 + 通知主场景飘字
func _on_dot_tick(amount: int, icon: String) -> void:
	take_damage(amount)
	EventBus.effect_damage.emit(global_position, amount, icon)


## 外部（武器命中）施加 effect
func apply_effect(effect_id: String, positive: bool, times := 1,
		src_damage := 0.0, element_coef := 0.0) -> void:
	effects.add(effect_id, positive, times, -1.0, src_damage, element_coef)


func is_dead() -> bool:
	return _dead


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()


func _draw() -> void:
	# 贴地阴影：Boss 更大更淡
	WorldView.draw_shadow(self, radius * 1.15, 0.2)

	# 护盾环：贴地椭圆（2.5D 下铺在地面，不悬空）
	if shield > 0.0 and max_shield > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, WorldView.SHADOW_FLAT))
		draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU * (shield / max_shield), 40,
			Color(0.3, 0.7, 1.0), 5.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 冰冻：地面霜圈
	if effects and effects.is_frozen():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, WorldView.SHADOW_FLAT))
		draw_circle(Vector2.ZERO, radius + 4.0, Color(0.62, 0.88, 1.0, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 本体抬升：底部厚度 + 外观（按 radius / 40 缩放）
	WorldView.body_begin_scaled(self, WorldView.LIFT_TALL, radius / 40.0)
	draw_circle(Vector2(0.0, 8.0), 40.0, Color(0.0, 0.0, 0.0, 0.22))
	if visual == "minotaur":
		_draw_minotaur()
	else:
		_draw_demon()

	# 受击闪白：短促白色覆盖，强化打击反馈
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, 40.0, Color(1.0, 1.0, 1.0, minf(0.7, _hit_flash * 8.0)))

	# 冰冻 debuff 满层：冰层覆盖 + 冰冻图标
	if effects and effects.is_frozen():
		draw_circle(Vector2.ZERO, 42.0, Color(0.6, 0.9, 1.0, 0.45))
		draw_arc(Vector2.ZERO, 47.0, 0.0, TAU, 40, Color(0.85, 0.97, 1.0, 0.9), 3.0)
		for i in range(6):
			var a := TAU * float(i) / 6.0
			var p1 := Vector2(cos(a), sin(a)) * 6.0
			var p2 := Vector2(cos(a), sin(a)) * 24.0
			draw_line(p1, p2, Color(0.9, 0.98, 1.0, 0.95), 3.0)
	WorldView.body_end(self)


func _draw_demon() -> void:
	# 犄角
	var lh := PackedVector2Array([Vector2(-26.0, -30.0), Vector2(-34.0, -54.0), Vector2(-10.0, -40.0)])
	var rh := PackedVector2Array([Vector2(26.0, -30.0), Vector2(34.0, -54.0), Vector2(10.0, -40.0)])
	draw_colored_polygon(lh, Color(0.4, 0.1, 0.12))
	draw_colored_polygon(rh, Color(0.4, 0.1, 0.12))

	# 圆滚滚的身体
	draw_circle(Vector2.ZERO, 40.0, Color(0.86, 0.26, 0.22))
	draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, Color(0.45, 0.08, 0.1), 3.0)
	# 顶部亮边：轻微渐变，让球体看起来有受光面
	draw_arc(Vector2(0.0, 2.0), 40.0, PI + 0.55, TAU - 0.55, 24, Color(0.96, 0.46, 0.42), 4.0)

	# 大眼睛
	draw_circle(Vector2(-14.0, -6.0), 11.0, Color.WHITE)
	draw_circle(Vector2(14.0, -6.0), 11.0, Color.WHITE)
	draw_circle(Vector2(-12.0, -4.0), 5.0, Color.BLACK)
	draw_circle(Vector2(16.0, -4.0), 5.0, Color.BLACK)
	draw_circle(Vector2(-14.0, -7.0), 2.0, Color.WHITE)
	draw_circle(Vector2(14.0, -7.0), 2.0, Color.WHITE)
	# 小嘴
	draw_arc(Vector2(0.0, 10.0), 9.0, 0.35, 2.79, 16, Color(0.3, 0.05, 0.05), 2.5)

	# 三叉戟
	var staff_a := Vector2(30.0, 20.0)
	var staff_b := Vector2(58.0, -32.0)
	draw_line(staff_a, staff_b, Color(0.42, 0.3, 0.12), 5.0)
	var gold := Color(1.0, 0.85, 0.3)
	draw_line(staff_b, staff_b + Vector2(-7.0, -16.0), gold, 3.0)
	draw_line(staff_b, staff_b + Vector2(7.0, -16.0), gold, 3.0)
	draw_line(staff_b, staff_b + Vector2(0.0, -20.0), gold, 3.0)
	draw_circle(staff_b + Vector2(0.0, -20.0), 3.0, gold)


func _draw_minotaur() -> void:
	var body := Color(0.42, 0.27, 0.16)
	var outline := Color(0.22, 0.13, 0.07)

	# 犄角
	draw_line(Vector2(-26.0, -22.0), Vector2(-40.0, -56.0), Color(0.85, 0.8, 0.68), 10.0)
	draw_line(Vector2(26.0, -22.0), Vector2(40.0, -56.0), Color(0.85, 0.8, 0.68), 10.0)
	draw_circle(Vector2(-41.0, -58.0), 5.0, Color(0.9, 0.86, 0.76))
	draw_circle(Vector2(41.0, -58.0), 5.0, Color(0.9, 0.86, 0.76))

	# 身体
	draw_circle(Vector2.ZERO, 40.0, body)
	draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, outline, 3.0)
	draw_arc(Vector2(0.0, 2.0), 40.0, PI + 0.55, TAU - 0.55, 24, Color(0.56, 0.38, 0.24), 4.0)

	# 口鼻
	draw_circle(Vector2(0.0, 18.0), 19.0, Color(0.58, 0.4, 0.26))
	draw_circle(Vector2(-7.0, 20.0), 3.0, outline)
	draw_circle(Vector2(7.0, 20.0), 3.0, outline)

	# 怒眼
	draw_line(Vector2(-19.0, -8.0), Vector2(-6.0, -3.0), Color(0.95, 0.15, 0.1), 4.0)
	draw_line(Vector2(19.0, -8.0), Vector2(6.0, -3.0), Color(0.95, 0.15, 0.1), 4.0)

	# 鼻环
	draw_arc(Vector2(0.0, 30.0), 9.0, 0.15, PI - 0.15, 16, Color(0.95, 0.8, 0.3), 3.0)
