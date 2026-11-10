extends Node

## 可挂载到任意角色的 Effect 容器（buff / debuff 通用，数据见 effect_data.gd）
## 用法：var fx := EFFECT_HOLDER.new(); add_child(fx)
## 角色只需读 damage_mult() / taken_mult() / active()，不关心具体 Effect

const EFFECTS := preload("res://scripts/effect_data.gd")

signal changed
signal dot_tick(amount: int, icon: String)   # 持续伤害（燃烧每秒结算）→ 由宿主扣血并飘字

# key = "effect_id:buff|debuff" -> { "id", "positive", "stacks", "time", "src", "coef" }
var _entries := {}


## 施加 effect：times 为施加次数（层数），duration < 0 时用目录默认时长
## src_damage / element_coef：触发该 effect 的武器伤害与元素伤害系数（燃烧每秒伤害用）
func add(effect_id: String, positive: bool, times := 1, duration := -1.0,
		src_damage := 0.0, element_coef := 0.0) -> void:
	if not EFFECTS.CATALOG.has(effect_id) or times <= 0:
		return
	var key := _key(effect_id, positive)
	var cfg: Dictionary = EFFECTS.get_effect(effect_id)
	var side := "buff" if positive else "debuff"
	var cap := int(cfg.get("max_stacks", {}).get(side, -1))
	var rule := String(cfg.get("stack_rule", {}).get(side, "refresh"))
	var e: Dictionary = _entries.get(key, {
		"id": effect_id, "positive": positive, "stacks": 0, "time": 0.0,
		"src": 0.0, "coef": 0.0,
	})
	# 记住最近一次命中的武器伤害与元素系数
	if src_damage > 0.0:
		e["src"] = src_damage
		e["coef"] = element_coef
	var base_time := float(cfg.get("duration", 5.0)) if duration < 0.0 else duration
	var step := float(cfg.get(side, {}).get("extend_step", base_time))
	for i in range(times):
		if cap >= 0 and int(e["stacks"]) >= cap:
			break
		var first := int(e["stacks"]) == 0
		e["stacks"] = int(e["stacks"]) + 1
		if first:
			e["time"] = base_time
		elif rule == "extend":
			e["time"] = float(e["time"]) + step
		elif rule == "refresh":
			e["time"] = base_time
		else:
			e["time"] = maxf(float(e["time"]), base_time)
	_entries[key] = e
	changed.emit()


func has(effect_id: String, positive := true) -> bool:
	return _entries.has(_key(effect_id, positive))


func stacks(effect_id: String, positive := true) -> int:
	var e: Dictionary = _entries.get(_key(effect_id, positive), {})
	return int(e.get("stacks", 0))


func time_left(effect_id: String, positive := true) -> float:
	var e: Dictionary = _entries.get(_key(effect_id, positive), {})
	return float(e.get("time", 0.0))


## 当前全部生效条目（供 UI 遍历）
func active() -> Array:
	return _entries.values()


## 造成伤害倍率：1 + Σ(buff 每层加成 × 层数)
func damage_mult() -> float:
	var m := 1.0
	for e in _entries.values():
		if not bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		m += float(cfg.get("buff", {}).get("damage_mult", 0.0)) * float(e["stacks"])
	return m


## 受到伤害倍率：1 + Σ(debuff 每层加成 × 层数)
func taken_mult() -> float:
	var m := 1.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		m += float(cfg.get("debuff", {}).get("taken_mult", 0.0)) * float(e["stacks"])
	return m


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var expired := []
	for key in _entries.keys():
		var e: Dictionary = _entries[key]
		var side := "buff" if bool(e["positive"]) else "debuff"
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {}).get(side, {})
		var rate := float(cfg.get("shield_max_ratio_per_stack_sec", 0.0))
		if rate != 0.0:
			e["acc"] = float(e.get("acc", 0.0)) + rate * float(e["stacks"]) * delta
		# 持续伤害：每秒造成 武器伤害×元素系数×层数
		var dot_scale := float(cfg.get("dot_ratio_per_stack_sec", 0.0))
		var src := float(e.get("src", 0.0)) * float(e.get("coef", 0.0))
		if dot_scale > 0.0 and src > 0.0:
			e["dot_acc"] = float(e.get("dot_acc", 0.0)) + src * dot_scale * float(e["stacks"]) * delta
			var dmg := int(floor(float(e["dot_acc"])))
			if dmg > 0:
				e["dot_acc"] = float(e["dot_acc"]) - float(dmg)
				var icon := String(EFFECTS.get_effect(String(e["id"])).get("icon", "❔"))
				dot_tick.emit(dmg, icon)
		e["time"] = float(e["time"]) - delta
		if float(e["time"]) <= 0.0:
			expired.append(key)
	for key in expired:
		_entries.erase(key)
	if not expired.is_empty():
		changed.emit()


## 护盾上限加成比例（磁力 buff 按存活时间累计；冰冻 buff 按层数固定加成）
func shield_max_bonus() -> float:
	var total := 0.0
	for e in _entries.values():
		if bool(e["positive"]):
			var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
			total += float(e.get("acc", 0.0))
			total += float(cfg.get("buff", {}).get("shield_max_ratio_per_stack", 0.0)) * float(e["stacks"])
	return total


## 护盾扣除速率（每层每秒占上限的比例之和）
func shield_drain_rate() -> float:
	var total := 0.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		total += float(cfg.get("debuff", {}).get("shield_drain_ratio_per_stack_sec", 0.0)) * float(e["stacks"])
	return total


## 护盾回复延迟加成（秒）
func shield_regen_delay_add() -> float:
	var total := 0.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		total += float(cfg.get("debuff", {}).get("shield_regen_delay_add", 0.0))
	return total


## 移速倍率（debuff 减速，最低保留 20%）
func slow_factor() -> float:
	var slow := 0.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		slow += float(cfg.get("debuff", {}).get("slow_per_stack", 0.0)) * float(e["stacks"])
	return maxf(0.2, 1.0 - slow)


## 攻速倍率（debuff 降攻速 → 攻击间隔按 1/倍率 拉长，最低保留 20%）
func attack_speed_factor() -> float:
	var slow := 0.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		slow += float(cfg.get("debuff", {}).get("attack_speed_per_stack", 0.0)) * float(e["stacks"])
	return maxf(0.2, 1.0 - slow)


## 受到暴击伤害倍率：1 + Σ(每层加成 × 层数)
func crit_taken_mult() -> float:
	var m := 1.0
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		m += float(cfg.get("debuff", {}).get("crit_taken_per_stack", 0.0)) * float(e["stacks"])
	return m


## 是否携带「未满层」的磁力 debuff（1 ~ 上限-1 层）：只有这种敌人会被满层者吸引
func is_magnet_pullable() -> bool:
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		var d: Dictionary = cfg.get("debuff", {})
		if not bool(d.get("root_at_full", false)):
			continue
		var cap := int(cfg.get("max_stacks", {}).get("debuff", -1))
		var s := int(e["stacks"])
		if s >= 1 and (cap < 0 or s < cap):
			return true
	return false


## 是否被冻结（带 freeze_at_full 的 debuff 达到层数上限）
func is_frozen() -> bool:
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		if not bool(cfg.get("debuff", {}).get("freeze_at_full", false)):
			continue
		var cap := int(cfg.get("max_stacks", {}).get("debuff", -1))
		if cap >= 0 and int(e["stacks"]) >= cap:
			return true
	return false


## 是否有「携带者相互吸引」的 debuff
func has_mutual_attract() -> bool:
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		if bool(cfg.get("debuff", {}).get("mutual_attract", false)):
			return true
	return false


## 满层「束缚 + 吸引」参数：返回 { radius, speed }，未满层返回空字典
func magnet_pull() -> Dictionary:
	for e in _entries.values():
		if bool(e["positive"]):
			continue
		var cfg: Dictionary = EFFECTS.CATALOG.get(String(e["id"]), {})
		var d: Dictionary = cfg.get("debuff", {})
		if not bool(d.get("root_at_full", false)):
			continue
		var cap := int(cfg.get("max_stacks", {}).get("debuff", -1))
		if cap >= 0 and int(e["stacks"]) >= cap:
			return {
				"radius": float(d.get("pull_radius", 0.0)),
				"speed": float(d.get("pull_speed", 0.0)),
			}
	return {}


func _key(effect_id: String, positive: bool) -> String:
	return "%s:%s" % [effect_id, "buff" if positive else "debuff"]
