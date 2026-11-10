extends CharacterBody2D

## 敌人三种类型：三角形（快脆） / 正方形（均衡） / 五边形（坦克）
## 颜色：满血绿 → 中血黄 → 残血红

enum Type { TRIANGLE, SQUARE, PENTAGON }

const ARMOR := preload("res://scripts/armor.gd")
const EFFECTS := preload("res://scripts/effect_data.gd")
const EFFECT_HOLDER := preload("res://scripts/effect_holder.gd")
const ITEM_DATA := preload("res://scripts/item_data.gd")
const CoinScene := preload("res://scenes/coin.tscn")
const ExpOrbScene := preload("res://scenes/exp_orb.tscn")
const ItemScene := preload("res://scenes/item.tscn")

# 掉落配置：金币 0~3 个，经验球 0~2 个，道具 10%
const COIN_DROP_MAX := 3
const ORB_DROP_MAX := 2
const ITEM_DROP_CHANCE := 0.1

var effects: Node
var effect_label: Label

var enemy_type: int = Type.PENTAGON
var max_hp := 50
var hp := 50
var speed := 140.0
var damage := 10.0
var exp_reward := 15
var radius := 18.0
var armor := 0.0

const ATTACK_COOLDOWN := 0.8

# 护盾：3 秒未受伤后每秒回复 10 点，最多 50 点
const SHIELD_MAX := 50.0
const SHIELD_REGEN_DELAY := 3.0
const SHIELD_REGEN_RATE := 10.0
var shield := SHIELD_MAX
var shield_delay := 0.0

var player: Node2D
var _attack_timer := 0.0
var _attract_timer := 0.0      # 磁力互吸目标的重算计时
var _attract_mate: Node2D = null
var _pull_timer := 0.0         # 被满层磁力敌人吸引的目标重算计时
var _pull_anchor: Node2D = null
var _hit_flash := 0.0          # 受击闪白剩余时间
var _dead := false

## 死亡 / 元素飘字等事件统一走 EventBus（见 scripts/event_bus.gd）


## 生成前调用，设定类型与属性
func config(t: int) -> void:
	enemy_type = t
	match t:
		Type.TRIANGLE:
			max_hp = 150
			speed = 200.0
			damage = 6.0
			exp_reward = 9
			radius = 14.0
			armor = 2.0
		Type.SQUARE:
			max_hp = 300
			speed = 130.0
			damage = 10.0
			exp_reward = 15
			radius = 18.0
			armor = 5.0
		Type.PENTAGON:
			max_hp = 600
			speed = 90.0
			damage = 16.0
			exp_reward = 24
			radius = 24.0
			armor = 10.0
	hp = max_hp
	queue_redraw()


## Boss 召唤的小型分身
func make_mini() -> void:
	max_hp = 20000
	speed = 200.0
	damage = 4.0
	exp_reward = 6
	radius = 11.0
	shield = 10.0
	armor = 0.0
	hp = max_hp
	queue_redraw()


func _ready() -> void:
	_sync_collision_shapes()
	effects = EFFECT_HOLDER.new()
	effects.name = "Effects"
	add_child(effects)
	effects.changed.connect(_refresh_effect_label)
	effects.dot_tick.connect(_on_dot_tick)   # 燃烧每秒伤害

	# 血条下方的 buff / debuff 图标（emoji + 层数）
	effect_label = Label.new()
	effect_label.add_theme_font_override("font", shared_emoji_font())
	effect_label.add_theme_font_size_override("font_size", 13)
	effect_label.add_theme_color_override("font_outline_color", Color.BLACK)
	effect_label.add_theme_constant_override("outline_size", 3)
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.position = Vector2(-40.0, radius + 2.0)
	effect_label.size = Vector2(80.0, 20.0)
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect_label)

	player = get_tree().get_first_node_in_group("player")
	var attack_area: Area2D = $AttackArea
	if attack_area:
		attack_area.body_entered.connect(_on_body_entered)


## 全局共享的 emoji 字体，避免每只怪新建 SystemFont
static var _emoji_font: SystemFont = null

static func shared_emoji_font() -> SystemFont:
	if _emoji_font == null:
		_emoji_font = SystemFont.new()
		_emoji_font.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"])
	return _emoji_font


## 碰撞体半径跟随外观大小（config / make_mini 设置的 radius）
func _sync_collision_shapes() -> void:
	var body_cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_cs:
		var body_circle := CircleShape2D.new()
		body_circle.radius = radius
		body_cs.shape = body_circle
	var hit_cs := get_node_or_null("AttackArea/CollisionShape2D") as CollisionShape2D
	if hit_cs:
		var hit_circle := CircleShape2D.new()
		hit_circle.radius = radius
		hit_cs.shape = hit_circle


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	# 站在怪堆里也持续掉血：每个冷却周期检测一次重叠
	var attack_area: Area2D = $AttackArea
	if attack_area and _attack_timer <= 0.0:
		for body in attack_area.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage(int(damage))
				_attack_timer = _attack_interval()
				break

	# 护盾：磁力 debuff 持续扣盾，磁力 buff 提升上限
	var smax := shield_max()
	var drain: float = effects.shield_drain_rate()
	if drain > 0.0 and shield > 0.0:
		shield = maxf(0.0, shield - smax * drain * delta)
		shield_delay = SHIELD_REGEN_DELAY
		queue_redraw()
	if shield_delay > 0.0:
		shield_delay = maxf(0.0, shield_delay - delta)
	elif shield < smax:
		shield = minf(smax, shield + SHIELD_REGEN_RATE * delta)
		queue_redraw()
	shield = minf(shield, smax)

	if player:
		var pull: Dictionary = effects.magnet_pull()
		if effects.is_frozen() or not pull.is_empty():
			# 冰冻满层 / 磁力 debuff 满层：无法移动（磁力吸引未满层敌人由对方结算）
			velocity = Vector2.ZERO
		else:
			var v: float = speed * effects.slow_factor()   # 磁力 debuff 减速
			velocity = (player.global_position - global_position).normalized() * v
			# 磁力 debuff：携带者之间相互吸引，距离小于 1 米（30px）停止
			# 目标每 0.2s 重算一次，避免每帧 O(n) 扫全场敌人
			if effects.has_mutual_attract():
				_attract_timer -= delta
				if _attract_timer <= 0.0:
					_attract_timer = 0.2
					_attract_mate = _nearest_magnet_mate()
				var mate: Node2D = _attract_mate
				if mate and is_instance_valid(mate):
					var to_mate: Vector2 = mate.global_position - global_position
					if to_mate.length() > 30.0:
						velocity += to_mate.normalized() * 120.0
			# 磁力 debuff 满层者大幅吸引周围 1~9 层的敌人，目标每 0.2s 重算一次
			if effects.is_magnet_pullable():
				_pull_timer -= delta
				if _pull_timer <= 0.0:
					_pull_timer = 0.2
					_pull_anchor = _nearest_magnet_anchor()
				if _pull_anchor and is_instance_valid(_pull_anchor):
					var cfg: Dictionary = _pull_anchor.effects.magnet_pull()
					var to_anchor: Vector2 = _pull_anchor.global_position - global_position
					var d := to_anchor.length()
					if not cfg.is_empty() and d > 30.0 and d <= float(cfg["radius"]):
						velocity += to_anchor.normalized() * float(cfg["speed"])
	move_and_slide()


func _nearest_magnet_mate() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		if not other.effects or not other.effects.has_mutual_attract():
			continue
		var d := global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## 最近的「磁力满层」敌人：满层者会大幅吸引周围未满层的敌人
func _nearest_magnet_anchor() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other) or other.effects == null:
			continue
		if other.effects.magnet_pull().is_empty():
			continue
		var d := global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## 护盾上限：基础值 × (1 + 磁力 buff 累计加成)
func shield_max() -> float:
	return SHIELD_MAX * (1.0 + effects.shield_max_bonus())


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()


func _draw() -> void:
	var ratio := float(hp) / float(max_hp)
	var sides := 5
	match enemy_type:
		Type.TRIANGLE:
			sides = 3
		Type.SQUARE:
			sides = 4
	var body_color := Color(0.0, 0.8, 0.2)
	if ratio <= 0.34:
		body_color = Color(0.9, 0.2, 0.1)
	elif ratio <= 0.67:
		body_color = Color(1.0, 0.85, 0.0)

	var poly := PackedVector2Array()
	for i in range(sides):
		var a := i * TAU / sides - PI / 2.0
		poly.append(Vector2(cos(a), sin(a)) * radius)

	# 贴地椭圆阴影 + 冰冻时的地面霜圈（画在脚点，不参与抬升）
	WorldView.draw_shadow(self, radius * 0.95, 0.26)
	if effects and effects.is_frozen():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, WorldView.SHADOW_FLAT))
		draw_circle(Vector2.ZERO, radius + 5.0, Color(0.62, 0.88, 1.0, 0.32))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 本体抬升：侧壁厚度 + 顶面
	WorldView.body_begin(self, WorldView.LIFT_DEFAULT)
	WorldView.draw_prism(self, poly, body_color, 7.0, Color.BLACK, 2.0)

	# 受击闪白：短促白色覆盖，强化打击反馈
	if _hit_flash > 0.0:
		draw_colored_polygon(poly, Color(1.0, 1.0, 1.0, minf(0.85, _hit_flash * 9.0)))

	# 护盾：蓝色圆弧，按剩余比例显示
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU * (shield / shield_max()), 24, Color(0.3, 0.7, 1.0), 3.0)

	# 磁力 debuff 满层：磁铁图标环绕，表现被束缚
	if effects and not effects.magnet_pull().is_empty():
		var font := shared_emoji_font()
		draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 32, Color(0.35, 0.85, 1.0, 0.6), 2.0)
		for i in range(4):
			var a := TAU * float(i) / 4.0 - PI / 2.0
			var p := Vector2(cos(a), sin(a)) * (radius + 18.0)
			draw_circle(p, 10.0, Color(0.35, 0.85, 1.0, 0.25))
			draw_string(font, p + Vector2(-7.0, 6.0), "🧲", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# 冰冻 debuff 满层：冰层覆盖 + 冰冻图标
	if effects and effects.is_frozen():
		var ice_font := shared_emoji_font()
		draw_circle(Vector2.ZERO, radius + 2.0, Color(0.6, 0.9, 1.0, 0.45))
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Color(0.85, 0.97, 1.0, 0.9), 2.0)
		draw_string(ice_font, Vector2(-10.0, 8.0), "❄️", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	# 眼睛
	var eye_y := -radius * 0.25
	var eye_dx := radius * 0.28
	draw_circle(Vector2(-eye_dx, eye_y), 3.0, Color.WHITE)
	draw_circle(Vector2( eye_dx, eye_y), 3.0, Color.WHITE)
	draw_circle(Vector2(-eye_dx, eye_y), 1.5, Color.BLACK)
	draw_circle(Vector2( eye_dx, eye_y), 1.5, Color.BLACK)
	WorldView.body_end(self)


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
	if hp <= 0:
		_dead = true
		EventBus.enemy_died.emit(global_position, enemy_type)
		call_deferred("_finish_death")


## 死亡收尾：掉落与释放延迟到物理回调之外，避免 add_child 冲突
func _finish_death() -> void:
	_drop_loot()
	queue_free()


## 死亡掉落：金币 / 经验球 / 道具，直接挂到主场景下
const MAX_DROPS := 240   # 场上掉落物上限，超出后不再生成

func _drop_loot() -> void:
	if get_tree().get_nodes_in_group("drop").size() >= MAX_DROPS:
		return
	var host = get_parent()
	var at := global_position
	for i in range(randi() % (COIN_DROP_MAX + 1)):
		var coin := CoinScene.instantiate()
		coin.position = at
		host.add_child(coin)
	for i in range(randi() % (ORB_DROP_MAX + 1)):
		var orb := ExpOrbScene.instantiate()
		orb.position = at + Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))
		orb.exp_value = exp_reward
		host.add_child(orb)
	if randf() < ITEM_DROP_CHANCE:
		var item := ItemScene.instantiate()
		item.item_id = ITEM_DATA.random_drop_id()
		item.position = at + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
		host.add_child(item)


## 持续伤害：扣血 + 通知主场景飘字
func _on_dot_tick(amount: int, icon: String) -> void:
	take_damage(amount)
	EventBus.effect_damage.emit(global_position, amount, icon)


## 外部（武器命中）施加 effect
func apply_effect(effect_id: String, positive: bool, times := 1,
		src_damage := 0.0, element_coef := 0.0) -> void:
	effects.add(effect_id, positive, times, -1.0, src_damage, element_coef)


func _refresh_effect_label() -> void:
	if effect_label == null:
		return
	var text := ""
	for e in effects.active():
		var icon := String(EFFECTS.get_effect(String(e["id"])).get("icon", "❔"))
		text += "%sx%d " % [icon, int(e["stacks"])]
	effect_label.text = text.strip_edges()
	queue_redraw()   # 磁力满层的环绕表现随层数变化


## 攻击间隔：攻速 debuff（冰冻）会拉长冷却
func _attack_interval() -> float:
	return ATTACK_COOLDOWN / effects.attack_speed_factor()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and _attack_timer <= 0.0:
		body.take_damage(int(damage))
		_attack_timer = _attack_interval()
