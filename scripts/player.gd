extends CharacterBody2D

## 玩家：WASD / 空格冲刺 / 鼠标瞄准 / 左键射击 / 滚轮缩放 / 经验升级

# --- 基础属性（默认值，实际数值由 Gamerule/player.json 覆盖） ---
const RULE_CONFIG := preload("res://scripts/rule_config.gd")
const ARMOR := preload("res://scripts/armor.gd")
const EFFECT_HOLDER := preload("res://scripts/effect_holder.gd")
const CARD_DATA := preload("res://scripts/card_data.gd")

var effects: Node               # buff / debuff 容器（见 scripts/effect_holder.gd）

var armor := 5.0                 # 护甲：按公式减少受到的物理伤害

var SPEED := 260.0
var DASH_SPEED := 700.0
var DASH_DURATION := 0.18
var DASH_COOLDOWN := 0.8
var BULLET_SPEED := 650.0
var BASE_FIRE_COOLDOWN := 0.20   # 基础射击间隔
var MAX_HP := 100

var WORLD_HALF := 800.0
var WORLD_PADDING := 16.0
var ZOOM_MIN := 0.5
var ZOOM_MAX := 2.5
var ZOOM_STEP := 0.15

# --- 摄像机缓动 ---
var CAM_FOLLOW_SPEED := 9.0   # 越大跟得越紧；越小越"拖尾"
var CAM_FORWARD := Vector2(0, -36)   # 2.5D 前视：镜头略偏上方，露出更多前方地面
var cam_pos := Vector2.ZERO

# --- 动态属性（可被升级卡修改） ---
var atk_power := 25.0           # 子弹基础伤害
var fire_cooldown := 0.20
var multishot := 1.0            # 每次射击的期望子弹数：1.5 = 50% 射 2 发

# 暴击率 = 基础暴击率 × (1 + 暴击率加成)
# 基础暴击率只随等级成长；卡牌只累加「加成」，不会在当前暴击率上连乘
var BASE_CRIT_START := 0.01
var base_crit := 0.01
var crit_growth := 0.01          # 每级基础暴击成长（player.json 可覆盖）
var crit_bonus := 0.0
var crit_chance := 0.01

var CRIT_DAMAGE := 2.0          # 暴击伤害固定 x2：伤害 = 攻击力 × 2^暴击段数

# --- 卡牌 / 道具修饰（加算 / 乘算，数据见 scripts/card_data.gd、scripts/item_data.gd） ---
var mods := {}   # attr -> {"add": float, "mul": float}，mul 为 Π(1 + value)
var perm_modifiers: Array = []    # 永久修饰（卡牌）：{attr, op, value}
var timed_modifiers: Array = []   # 限时修饰（道具）：{attr, op, value, remain}
var item_timers := {}             # 道具 buff 计时：item_id -> 剩余秒数（用于 buff 栏显示）

func apply_modifier(attr: String, op: String, value: float) -> void:
	if attr.is_empty():
		return
	perm_modifiers.append({"attr": attr, "op": op, "value": value})
	_rebuild_mods()

## 限时修饰：duration 秒后自动移除
func apply_timed_modifier(attr: String, op: String, value: float, duration: float) -> void:
	if attr.is_empty() or duration <= 0.0:
		return
	timed_modifiers.append({"attr": attr, "op": op, "value": value, "remain": duration})
	_rebuild_mods()

## 读档恢复卡牌修饰（永久修饰）并重算所有派生属性
func restore_modifiers(list: Array) -> void:
	perm_modifiers = list.duplicate(true)
	_rebuild_mods()


func _rebuild_mods() -> void:
	mods = {}
	for m in perm_modifiers:
		_accum_mod(m)
	for m in timed_modifiers:
		_accum_mod(m)
	_recalc_crit()

func _accum_mod(entry: Dictionary) -> void:
	var attr := String(entry["attr"])
	var m: Dictionary = mods.get(attr, {"add": 0.0, "mul": 1.0})
	if String(entry["op"]) == "add":
		m["add"] = float(m["add"]) + float(entry["value"])
	else:
		m["mul"] = float(m["mul"]) * (1.0 + float(entry["value"]))
	mods[attr] = m

func _tick_timed_modifiers(delta: float) -> void:
	if timed_modifiers.is_empty():
		return
	var changed := false
	var alive: Array = []
	for m in timed_modifiers:
		m["remain"] = float(m["remain"]) - delta
		if float(m["remain"]) > 0.0:
			alive.append(m)
		else:
			changed = true
	if changed:
		timed_modifiers = alive
		_rebuild_mods()


## 道具 buff 计时（buff 栏显示用），重复使用取较长剩余时间
func apply_item_timer(item_id: String, duration: float) -> void:
	if item_id == "" or duration <= 0.0:
		return
	item_timers[item_id] = maxf(float(item_timers.get(item_id, 0.0)), duration)


func _tick_item_timers(delta: float) -> void:
	if item_timers.is_empty():
		return
	for id in item_timers.keys():
		item_timers[id] = float(item_timers[id]) - delta
		if float(item_timers[id]) <= 0.0:
			item_timers.erase(id)

func mod_add(attr: String) -> float:
	return float(mods.get(attr, {}).get("add", 0.0))

func mod_mul(attr: String) -> float:
	return float(mods.get(attr, {}).get("mul", 1.0))

## 施加一张卡牌
func apply_card(card: Dictionary) -> void:
	for m in card.get("modifiers", []):
		apply_modifier(String(m.get("attr", "")), String(m.get("op", "add")), float(m.get("value", 0.0)))

## 元素伤害倍率（伤害卡 + 机制卡）
func element_damage_mult(effect_id: String) -> float:
	return mod_mul("element_coef") * mod_mul(effect_id + "_damage")

## 触发伤害次数（红卡可增加）
func trigger_times() -> int:
	return maxi(1, 1 + int(round(mod_add("trigger_times"))))

func _recalc_crit() -> void:
	# 武器基础暴击率加成先加在基础上，再乘卡牌加成
	crit_chance = (base_crit + weapon_crit_add()) * (1.0 + crit_bonus) * mod_mul("crit_rate")


# --- 武器：所有面板数值都经武器倍率换算，换武器即可复用同一套升级 ---

func current_weapon():
	return WEAPONS.get_weapon(weapon_id)

func weapon_crit_add() -> float:
	return float(current_weapon().get("crit_add", 0.0))

func eff_atk() -> float:
	return (atk_power + mod_add("atk_power")) * mod_mul("phys_damage") * mod_mul("phys_coef") \
		* float(current_weapon().get("atk_mult", 1.0)) * effects.damage_mult() * mod_mul("damage")

func eff_cooldown() -> float:
	return maxf(0.05, fire_cooldown / maxf(float(current_weapon().get("rate_mult", 1.0)), 0.01) \
		/ maxf(mod_mul("attack_speed"), 0.01))

func eff_multishot() -> float:
	return (multishot + mod_add("multishot")) * float(current_weapon().get("multi_mult", 1.0))

func add_weapon(id: String) -> bool:
	if not WEAPONS.CATALOG.has(id) or owned_weapons.has(id):
		return false
	owned_weapons.append(id)
	equip_weapon(id)
	return true

func equip_weapon(id: String) -> bool:
	if not owned_weapons.has(id) or id == weapon_id:
		return false
	weapon_id = id
	_recalc_crit()
	weapon_switched.emit(id)
	return true

# 每 100% 暴击率稳定 1 段暴击，余数按概率多 1 段
func roll_crit_stacks() -> int:
	var stacks := int(floor(crit_chance))
	var frac := crit_chance - float(stacks)
	if frac > 0.0 and randf() < frac:
		stacks += 1
	return stacks

# --- 磁吸 / 拾取范围 ---
var magnet_time := 0.0
const BASE_PICKUP_RADIUS := 480.0

## 是否处于自动吸取状态（磁力 buff 或磁铁道具）
func pickup_active() -> bool:
	return magnet_time > 0.0 or mod_add("pickup_range") > 0.0

## 自动吸取半径（像素）：基础 + 道具加成（米 → 像素）
func pickup_radius() -> float:
	return BASE_PICKUP_RADIUS + mod_add("pickup_range") * WEAPONS.PX_PER_METER

# --- 护盾 ---
var SHIELD_MAX := 50.0
var SHIELD_REGEN_DELAY := 3.0
var SHIELD_REGEN_RATE := 10.0
var shield := 50.0
var shield_delay := 0.0

# --- 内部状态 ---
var HIT_INVULN := 0.5      # 受伤后的无敌时间
var hp := 100
# UI 信号节流：只在数值真正变化时发出
var _last_hp := -1
var _last_max_hp := -1
var _last_shield_i := -1
var _last_smax_i := -1
var dead := false
var dash_remaining := 0.0
var dash_cooldown := 0.0
var fire_timer := 0.0
var invuln_timer := 0.0

# --- 经验系统 ---
var EXP_BASE := 10.0
var EXP_GROWTH := 1.35
var level := 1
var exp := 0
var exp_to_next := 10

# 升级中（冻结输入）
var upgrading := false

# --- 武器（数据驱动，见 scripts/weapon_data.gd） ---
const WEAPONS := preload("res://scripts/weapon_data.gd")
var owned_weapons: Array = ["pistol"]
var weapon_id := "pistol"

@onready var cam: Camera2D = $Camera2D
var _shake := 0.0   # 震屏强度（像素），指数衰减

## 震屏：取较大值，避免连续命中时叠加过猛
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

# --- emoji 表情 ---
const EMOJI_IDLE := "🙂"
const EMOJI_ATTACK := "😡"
const EMOJI_CRIT := "🤬"
var DEATH_EMOJI := "💀"
var DEATH_PAUSE := 1.0
var emoji_label: Label
var emoji_timer := 0.0

# --- 信号 ---
signal health_changed(current: int, maximum: int)
signal shield_changed(current: int, maximum: int)
signal bullet_spawned(origin: Vector2, direction: Vector2, damage: float, crit_stacks: int)
signal exp_changed(cur: int, next: int)
signal level_up(new_level: int)
signal weapon_switched(id: String)


func _ready() -> void:
	effects = EFFECT_HOLDER.new()
	effects.name = "Effects"
	add_child(effects)
	_apply_rule()

	# 用系统 emoji 字体显示表情
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"])
	emoji_label = Label.new()
	emoji_label.add_theme_font_override("font", f)
	emoji_label.add_theme_font_size_override("font_size", 28)
	emoji_label.text = EMOJI_IDLE
	emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emoji_label.size = Vector2(32, 32)
	emoji_label.position = Vector2(-16, -28)   # 2.5D：表情本体抬升，站在脚下底座上
	emoji_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(emoji_label)

	# 摄像机脱离玩家节点独立缓动跟随（top_level 避免被玩家位移直接带动）
	cam.top_level = true
	cam.position_smoothing_enabled = false
	cam_pos = global_position + CAM_FORWARD
	cam.global_position = cam_pos


# 摄像机缓动：指数平滑跟随 + 按当前缩放对齐像素网格，保证画面不糊
func _process(delta: float) -> void:
	if not cam:
		return
	cam_pos = cam_pos.lerp(global_position + CAM_FORWARD, 1.0 - exp(-CAM_FOLLOW_SPEED * delta))
	var z: float = maxf(cam.zoom.x, 0.001)
	var step := 1.0 / z          # 屏幕 1 像素对应的世界距离
	cam.global_position = Vector2(
		round(cam_pos.x / step) * step,
		round(cam_pos.y / step) * step
	)

	# 震屏：2.5D 下纵向位移观感更强，纵向幅度更大
	if _shake > 0.05:
		_shake = maxf(0.0, _shake - delta * 40.0)
		cam.offset = Vector2(randf_range(-_shake * 0.35, _shake * 0.35), randf_range(-_shake, _shake))
	else:
		_shake = 0.0
		cam.offset = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if upgrading:
		return   # 升级中冻结

	_tick_timed_modifiers(delta)
	_tick_item_timers(delta)

	# 表情：按住射击时持续 😡，松开后才恢复 🙂
	if emoji_timer > 0.0:
		emoji_timer -= delta
	if emoji_label and emoji_timer <= 0.0 and not Input.is_action_pressed("shoot"):
		emoji_label.text = EMOJI_IDLE

	dash_remaining = max(0.0, dash_remaining - delta)
	dash_cooldown  = max(0.0, dash_cooldown  - delta)
	fire_timer     = max(0.0, fire_timer     - delta)
	invuln_timer   = max(0.0, invuln_timer   - delta)
	magnet_time    = effects.time_left("magnet")   # 磁力 buff 由 Effect 系统统一计时

	# 护盾：磁力 buff 提升上限，磁力 debuff 持续扣盾
	var smax := shield_max()
	var drain: float = effects.shield_drain_rate()
	var regen_hold: float = effects.shield_regen_delay_add()
	if regen_hold > 0.0:
		shield_delay = maxf(shield_delay, regen_hold)   # 碎盾 debuff：护盾回复延迟
	if drain > 0.0:
		shield = maxf(0.0, shield - smax * drain * delta)
		_emit_shield_changed()
	if shield_delay > 0.0:
		shield_delay = max(0.0, shield_delay - delta)
	elif shield < smax:
		shield = minf(smax, shield + SHIELD_REGEN_RATE * delta)
		_emit_shield_changed()
	shield = minf(shield, smax)   # buff 结束时上限回落

	# 移动
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	).normalized()

	if dash_remaining > 0.0:
		pass
	else:
		velocity = input_dir * SPEED * mod_mul("move_speed")

	# 冲刺
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0 and dash_remaining <= 0.0:
		var dash_dir := input_dir if input_dir != Vector2.ZERO else -transform.x
		velocity = dash_dir * DASH_SPEED
		dash_remaining = DASH_DURATION
		dash_cooldown = DASH_COOLDOWN
		invuln_timer = max(invuln_timer, DASH_DURATION)

	move_and_slide()

	# 地图边界
	position.x = clamp(position.x, -WORLD_HALF + WORLD_PADDING, WORLD_HALF - WORLD_PADDING)
	position.y = clamp(position.y, -WORLD_HALF + WORLD_PADDING, WORLD_HALF - WORLD_PADDING)

	# 射击（数值 = 面板 × 武器倍率；多重射击：1.5 → 1 发 + 50% 概率多 1 发）
	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		var aim := (get_global_mouse_position() - global_position).normalized()
		var shots := eff_multishot()
		var count := int(floor(shots))
		if randf() < (shots - floor(shots)):
			count += 1
		var any_crit := false
		for i in range(count):
			var offset := 0.0
			if count > 1:
				offset = lerp(-0.10, 0.10, float(i) / float(count - 1))
			var stacks := roll_crit_stacks()
			if stacks > 0:
				any_crit = true
			var dmg := eff_atk() * pow(CRIT_DAMAGE, float(stacks))
			bullet_spawned.emit(global_position, aim.rotated(offset), dmg, stacks)
		fire_timer = eff_cooldown()

		# 攻击 / 暴击表情
		if emoji_label:
			emoji_label.text = EMOJI_CRIT if any_crit else EMOJI_ATTACK
		emoji_timer = 0.30 if any_crit else 0.15

	_emit_health_changed()
	queue_redraw()   # 每帧刷新瞄准方向 / 无敌圈


func _emit_health_changed() -> void:
	if hp == _last_hp and MAX_HP == _last_max_hp:
		return
	_last_hp = hp
	_last_max_hp = MAX_HP
	health_changed.emit(hp, MAX_HP)


func _emit_shield_changed() -> void:
	var s := int(shield)
	var m := int(shield_max())
	if s == _last_shield_i and m == _last_smax_i:
		return
	_last_shield_i = s
	_last_smax_i = m
	shield_changed.emit(s, m)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 数字键快速切武器：1=第一把，2=第二把……
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < owned_weapons.size():
			equip_weapon(owned_weapons[idx])
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var z := cam.zoom.x + ZOOM_STEP   # 上滚放大
			cam.zoom = Vector2.ONE * clamp(z, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var z := cam.zoom.x - ZOOM_STEP   # 下滚缩小
			cam.zoom = Vector2.ONE * clamp(z, ZOOM_MIN, ZOOM_MAX)


func _draw() -> void:
	# 身体由 emoji Label 显示（已抬升），这里画贴地阴影、脚下底座与地面光环
	WorldView.draw_shadow(self, 20.0, 0.28)

	# 脚下底座：压扁的深色圆盘，表情站在上面才有落地感
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2(0.0, 3.0), 15.0, Color(0.30, 0.36, 0.46, 0.9))
	draw_arc(Vector2(0.0, 3.0), 15.0, 0.0, TAU, 24, Color(0.58, 0.68, 0.82, 0.95), 2.0)

	# 护盾 / 磁吸 / 无敌：贴地扁环（2.5D 下光环铺在地面上）
	if shield > 0.0:
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU * (shield / shield_max()), 24, Color(0.35, 0.75, 1.0), 2.5)
	if magnet_time > 0.0:
		var pulse := 30.0 + sin(float(Time.get_ticks_msec()) * 0.006) * 4.0
		draw_arc(Vector2.ZERO, pulse, 0.0, TAU, 32, Color(0.75, 0.35, 1.0, 0.85), 2.0)
	if invuln_timer > 0.0:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color.YELLOW, 2.0)

	# 瞄准指示：贴地扇形，方向仍跟随鼠标
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	var tri := PackedVector2Array([aim_dir * 20.0, aim_dir.rotated(0.45) * 10.0, aim_dir.rotated(-0.45) * 10.0])
	draw_colored_polygon(tri, Color(0.1, 0.1, 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- 经验相关 ---

func gain_exp(amount: int) -> void:
	exp += amount
	while exp >= exp_to_next:
		exp -= exp_to_next
		level += 1
		exp_to_next = _calc_exp_needed(level)
		base_crit += crit_growth   # 每级基础暴击率成长（无上限）
		_recalc_crit()
		upgrading = true
		level_up.emit(level)   # 让 main.gd 弹出卡
	exp_changed.emit(exp, exp_to_next)


func _calc_exp_needed(lv: int) -> int:
	return int(EXP_BASE * pow(EXP_GROWTH, lv - 1))


# 任务奖励直接加等级（每级弹一次选卡）
func gain_levels(n: int) -> void:
	if n <= 0:
		return
	level += n
	exp_to_next = _calc_exp_needed(level)
	base_crit += crit_growth * float(n)
	_recalc_crit()
	exp_changed.emit(exp, exp_to_next)
	for i in range(n):
		upgrading = true
		level_up.emit(level - n + i + 1)


## 应用一张卡牌（卡牌数据见 scripts/card_data.gd）
func apply_upgrade(kind: String) -> void:
	var card: Dictionary = CARD_DATA.get_card(kind)
	if card.is_empty():
		return
	apply_card(card)


func heal(amount: int) -> void:
	hp = mini(hp + amount, MAX_HP)
	health_changed.emit(hp, MAX_HP)


## 护盾上限：(基础值 + 卡牌加算) × 卡牌乘算 × (1 + 磁力 buff 累计加成)
func shield_max() -> float:
	return (SHIELD_MAX + mod_add("shield_max")) * mod_mul("shield_max") \
		* (1.0 + effects.shield_max_bonus())

## 护甲：(基础值 + 卡牌加算) × 卡牌乘算
func eff_armor() -> float:
	return (armor + mod_add("armor")) * mod_mul("armor")


## 击碎护盾：清空护盾 + 上「碎盾」debuff（护盾回复延迟 +10s）
func break_shield() -> void:
	shield = 0.0
	shield_changed.emit(0, int(shield_max()))
	effects.add("shatter", false, 1)


## 外部（武器命中 / 道具）施加 effect
func apply_effect(effect_id: String, positive: bool, times := 1,
		src_damage := 0.0, element_coef := 0.0) -> void:
	effects.add(effect_id, positive, times, -1.0, src_damage, element_coef)


func take_damage(amount: int) -> void:
	if dead or invuln_timer > 0.0 or upgrading:
		return
	invuln_timer = HIT_INVULN
	shield_delay = SHIELD_REGEN_DELAY
	var left := ARMOR.reduce(int(round(float(amount) * effects.taken_mult())), eff_armor())
	if shield > 0.0:
		var absorbed := minf(shield, float(left))
		shield = maxf(0.0, shield - absorbed)
		left -= int(absorbed)
		shield_changed.emit(int(shield), int(shield_max()))
	if left > 0:
		hp = maxi(0, hp - left)
	health_changed.emit(hp, MAX_HP)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	upgrading = true   # 冻结输入
	hp = 0
	if emoji_label:
		emoji_label.text = DEATH_EMOJI
		emoji_label.add_theme_font_size_override("font_size", 32)
	health_changed.emit(hp, MAX_HP)
	queue_redraw()
	await get_tree().create_timer(DEATH_PAUSE).timeout
	get_tree().reload_current_scene()


func _apply_rule() -> void:
	var cfg: Dictionary = RULE_CONFIG.load_player()
	if cfg.is_empty():
		return

	var b: Dictionary = cfg.get("base_stats", {})
	MAX_HP = int(b.get("hp", MAX_HP))
	SPEED = float(b.get("speed", SPEED))
	atk_power = float(b.get("attack_power", atk_power))
	fire_cooldown = float(b.get("fire_cooldown_second", fire_cooldown))
	BASE_FIRE_COOLDOWN = fire_cooldown
	multishot = float(b.get("multishot", multishot))
	BULLET_SPEED = float(b.get("bullet_speed", BULLET_SPEED))
	BASE_CRIT_START = float(b.get("base_crit_rate", BASE_CRIT_START))
	base_crit = BASE_CRIT_START
	crit_growth = float(b.get("crit_rate_growth_per_level", crit_growth))
	armor = float(b.get("armor", armor))
	CRIT_DAMAGE = float(b.get("crit_damage_multiplier", CRIT_DAMAGE))
	_recalc_crit()

	var dash_cfg: Dictionary = cfg.get("dash", {})
	DASH_SPEED = float(dash_cfg.get("speed", DASH_SPEED))
	DASH_DURATION = float(dash_cfg.get("duration_second", DASH_DURATION))
	DASH_COOLDOWN = float(dash_cfg.get("cooldown_second", DASH_COOLDOWN))

	var sh: Dictionary = cfg.get("shield_rule", {})
	SHIELD_MAX = float(sh.get("max", SHIELD_MAX))
	SHIELD_REGEN_DELAY = float(sh.get("regen_delay_second", SHIELD_REGEN_DELAY))
	SHIELD_REGEN_RATE = float(sh.get("regen_rate_per_second", SHIELD_REGEN_RATE))
	shield = float(sh.get("initial_shield", SHIELD_MAX))

	var dmg: Dictionary = cfg.get("damage_rule", {})
	HIT_INVULN = float(dmg.get("invulnerable_after_hit_second", HIT_INVULN))

	var exp_cfg: Dictionary = cfg.get("exp_level_rule", {})
	EXP_BASE = float(exp_cfg.get("base_exp", EXP_BASE))
	EXP_GROWTH = float(exp_cfg.get("growth_multiplier", EXP_GROWTH))
	exp_to_next = int(exp_cfg.get("first_level_exp", EXP_BASE))

	var cam_cfg: Dictionary = cfg.get("camera", {})
	CAM_FOLLOW_SPEED = float(cam_cfg.get("follow_speed", CAM_FOLLOW_SPEED))
	ZOOM_MIN = float(cam_cfg.get("zoom_min", ZOOM_MIN))
	ZOOM_MAX = float(cam_cfg.get("zoom_max", ZOOM_MAX))
	ZOOM_STEP = float(cam_cfg.get("zoom_step", ZOOM_STEP))

	var mb: Dictionary = cfg.get("map_bound", {})
	WORLD_HALF = float(mb.get("world_half_size", WORLD_HALF))
	WORLD_PADDING = float(mb.get("clamp_padding", WORLD_PADDING))

	var appearance: Dictionary = cfg.get("appearance", {})
	DEATH_EMOJI = String(appearance.get("death_emoji", DEATH_EMOJI))
	DEATH_PAUSE = float(appearance.get("death_pause_second", DEATH_PAUSE))

	hp = MAX_HP
