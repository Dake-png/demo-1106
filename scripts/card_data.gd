extends RefCounted

## 卡牌系统（纯数据 + 抽卡）：归属「伤害修饰体系」
## 一张卡 = 一条数据：modifiers 列出 { attr, op, value }
##   op = add：加算区，面板值 = 基础值 + Σ(add)
##   op = mul：乘算区，最终值 = 面板值 × Π(1 + value)
## 新增卡牌 = 在 CATALOG 追加一条，不改逻辑与 UI

# 稀有度权重：白 0.50 / 蓝 0.20 / 紫 0.10 / 金 0.05 / 红 0.01
# 权重总和 0.86，抽卡按总和归一化 → 实际约 白 58% / 蓝 23% / 紫 12% / 金 6% / 红 1.2%
const RARITY_ORDER := ["white", "blue", "purple", "gold", "red"]

const RARITIES := {
	"white":  {"name": "白", "weight": 0.50, "price": 8},
	"blue":   {"name": "蓝", "weight": 0.20, "price": 18},
	"purple": {"name": "紫", "weight": 0.10, "price": 32},
	"gold":   {"name": "金", "weight": 0.05, "price": 50},
	"red":    {"name": "红", "weight": 0.01, "price": 80},
}

# attr 约定：
#   phys_damage     物理伤害（mul）
#   phys_coef       物理伤害系数（mul，机制卡）
#   element_coef    元素伤害系数（mul，机制卡）
#   burn_damage     燃烧元素伤害（mul）
#   magnet_damage   磁力元素伤害（mul）
#   attack_speed    攻速（mul，射击间隔 ÷(1+value)）
#   multishot       多重射击（add）
#   crit_rate       暴击率（mul）
#   shield_max      护盾上限（add / mul）
#   armor           护甲（add / mul）
#   trigger_times   触发伤害次数（add）
#   move_speed      移速（mul）

const CATALOG := [
	# ===== 伤害卡：物理 =====
	{"id": "phys_w", "type": "物理卡牌", "rarity": "white", "icon": "⚔️", "title": "物理伤害+", "desc": "物理伤害 +8%",
		"modifiers": [{"attr": "phys_damage", "op": "mul", "value": 0.08}]},
	{"id": "phys_b", "type": "物理卡牌", "rarity": "blue", "icon": "⚔️", "title": "物理伤害++", "desc": "物理伤害 +15%",
		"modifiers": [{"attr": "phys_damage", "op": "mul", "value": 0.15}]},
	{"id": "phys_p", "type": "物理卡牌", "rarity": "purple", "icon": "⚔️", "title": "物理伤害+++", "desc": "物理伤害 +25%",
		"modifiers": [{"attr": "phys_damage", "op": "mul", "value": 0.25}]},
	{"id": "phys_g", "type": "物理卡牌", "rarity": "gold", "icon": "⚔️", "title": "物理伤害·极", "desc": "物理伤害 +40%",
		"modifiers": [{"attr": "phys_damage", "op": "mul", "value": 0.40}]},

	# ===== 伤害卡：元素（燃烧） =====
	{"id": "burn_w", "type": "元素卡牌", "rarity": "white", "icon": "🔥", "title": "燃烧伤害+", "desc": "燃烧伤害 +10%",
		"modifiers": [{"attr": "burn_damage", "op": "mul", "value": 0.10}]},
	{"id": "burn_b", "type": "元素卡牌", "rarity": "blue", "icon": "🔥", "title": "燃烧伤害++", "desc": "燃烧伤害 +20%",
		"modifiers": [{"attr": "burn_damage", "op": "mul", "value": 0.20}]},
	{"id": "burn_p", "type": "元素卡牌", "rarity": "purple", "icon": "🔥", "title": "燃烧伤害+++", "desc": "燃烧伤害 +35%",
		"modifiers": [{"attr": "burn_damage", "op": "mul", "value": 0.35}]},
	{"id": "burn_g", "type": "元素卡牌", "rarity": "gold", "icon": "🔥", "title": "燃烧伤害·极", "desc": "燃烧伤害 +55%",
		"modifiers": [{"attr": "burn_damage", "op": "mul", "value": 0.55}]},

	# ===== 伤害卡：元素（磁力） =====
	{"id": "magnet_w", "type": "元素卡牌", "rarity": "white", "icon": "🧲", "title": "磁力伤害+", "desc": "磁力伤害 +10%",
		"modifiers": [{"attr": "magnet_damage", "op": "mul", "value": 0.10}]},
	{"id": "magnet_b", "type": "元素卡牌", "rarity": "blue", "icon": "🧲", "title": "磁力伤害++", "desc": "磁力伤害 +20%",
		"modifiers": [{"attr": "magnet_damage", "op": "mul", "value": 0.20}]},
	{"id": "magnet_p", "type": "元素卡牌", "rarity": "purple", "icon": "🧲", "title": "磁力伤害+++", "desc": "磁力伤害 +35%",
		"modifiers": [{"attr": "magnet_damage", "op": "mul", "value": 0.35}]},
	{"id": "magnet_g", "type": "元素卡牌", "rarity": "gold", "icon": "🧲", "title": "磁力伤害·极", "desc": "磁力伤害 +55%",
		"modifiers": [{"attr": "magnet_damage", "op": "mul", "value": 0.55}]},

	# ===== 效果卡：暴击率 =====
	{"id": "crit_w", "type": "效果卡", "rarity": "white", "icon": "🎯", "title": "暴击率+", "desc": "暴击率 +10%",
		"modifiers": [{"attr": "crit_rate", "op": "mul", "value": 0.10}]},
	{"id": "crit_b", "type": "效果卡", "rarity": "blue", "icon": "🎯", "title": "暴击率++", "desc": "暴击率 +20%",
		"modifiers": [{"attr": "crit_rate", "op": "mul", "value": 0.20}]},
	{"id": "crit_p", "type": "效果卡", "rarity": "purple", "icon": "🎯", "title": "暴击率+++", "desc": "暴击率 +35%",
		"modifiers": [{"attr": "crit_rate", "op": "mul", "value": 0.35}]},
	{"id": "crit_g", "type": "效果卡", "rarity": "gold", "icon": "🎯", "title": "暴击率·极", "desc": "暴击率 +50%",
		"modifiers": [{"attr": "crit_rate", "op": "mul", "value": 0.50}]},

	# ===== 效果卡：护盾值 =====
	{"id": "shield_w", "type": "效果卡", "rarity": "white", "icon": "🛡️", "title": "护盾值+", "desc": "护盾上限 +10%",
		"modifiers": [{"attr": "shield_max", "op": "mul", "value": 0.10}]},
	{"id": "shield_b", "type": "效果卡", "rarity": "blue", "icon": "🛡️", "title": "护盾值++", "desc": "护盾上限 +20%",
		"modifiers": [{"attr": "shield_max", "op": "mul", "value": 0.20}]},
	{"id": "shield_p", "type": "效果卡", "rarity": "purple", "icon": "🛡️", "title": "护盾值+++", "desc": "护盾上限 +35%",
		"modifiers": [{"attr": "shield_max", "op": "mul", "value": 0.35}]},

	# ===== 效果卡：护甲值 =====
	{"id": "armor_w", "type": "效果卡", "rarity": "white", "icon": "🧱", "title": "护甲值+", "desc": "护甲 +2",
		"modifiers": [{"attr": "armor", "op": "add", "value": 2.0}]},
	{"id": "armor_b", "type": "效果卡", "rarity": "blue", "icon": "🧱", "title": "护甲值++", "desc": "护甲 +4",
		"modifiers": [{"attr": "armor", "op": "add", "value": 4.0}]},
	{"id": "armor_p", "type": "效果卡", "rarity": "purple", "icon": "🧱", "title": "护甲值+++", "desc": "护甲 +7",
		"modifiers": [{"attr": "armor", "op": "add", "value": 7.0}]},
	{"id": "armor_g", "type": "效果卡", "rarity": "gold", "icon": "🧱", "title": "护甲值·极", "desc": "护甲 +12",
		"modifiers": [{"attr": "armor", "op": "add", "value": 12.0}]},

	# ===== 效果卡：多重射击 =====
	{"id": "multi_w", "type": "效果卡", "rarity": "white", "icon": "✨", "title": "多重射击+", "desc": "多重射击 +0.2",
		"modifiers": [{"attr": "multishot", "op": "add", "value": 0.2}]},
	{"id": "multi_b", "type": "效果卡", "rarity": "blue", "icon": "✨", "title": "多重射击++", "desc": "多重射击 +0.4",
		"modifiers": [{"attr": "multishot", "op": "add", "value": 0.4}]},
	{"id": "multi_p", "type": "效果卡", "rarity": "purple", "icon": "✨", "title": "多重射击+++", "desc": "多重射击 +0.7",
		"modifiers": [{"attr": "multishot", "op": "add", "value": 0.7}]},
	{"id": "multi_g", "type": "效果卡", "rarity": "gold", "icon": "✨", "title": "多重射击·极", "desc": "多重射击 +1",
		"modifiers": [{"attr": "multishot", "op": "add", "value": 1.0}]},

	# ===== 机制卡：元素伤害系数 =====
	{"id": "ecoef_w", "type": "机制卡", "rarity": "white", "icon": "🧪", "title": "元素伤害系数+", "desc": "元素伤害系数 +10%",
		"modifiers": [{"attr": "element_coef", "op": "mul", "value": 0.10}]},
	{"id": "ecoef_b", "type": "机制卡", "rarity": "blue", "icon": "🧪", "title": "元素伤害系数++", "desc": "元素伤害系数 +20%",
		"modifiers": [{"attr": "element_coef", "op": "mul", "value": 0.20}]},
	{"id": "ecoef_p", "type": "机制卡", "rarity": "purple", "icon": "🧪", "title": "元素伤害系数+++", "desc": "元素伤害系数 +35%",
		"modifiers": [{"attr": "element_coef", "op": "mul", "value": 0.35}]},
	{"id": "ecoef_g", "type": "机制卡", "rarity": "gold", "icon": "🧪", "title": "元素伤害系数·极", "desc": "元素伤害系数 +50%",
		"modifiers": [{"attr": "element_coef", "op": "mul", "value": 0.50}]},

	# ===== 机制卡：物理伤害系数 =====
	{"id": "pcoef_w", "type": "机制卡", "rarity": "white", "icon": "⚙️", "title": "物理伤害系数+", "desc": "物理伤害系数 +8%",
		"modifiers": [{"attr": "phys_coef", "op": "mul", "value": 0.08}]},
	{"id": "pcoef_b", "type": "机制卡", "rarity": "blue", "icon": "⚙️", "title": "物理伤害系数++", "desc": "物理伤害系数 +15%",
		"modifiers": [{"attr": "phys_coef", "op": "mul", "value": 0.15}]},
	{"id": "pcoef_p", "type": "机制卡", "rarity": "purple", "icon": "⚙️", "title": "物理伤害系数+++", "desc": "物理伤害系数 +25%",
		"modifiers": [{"attr": "phys_coef", "op": "mul", "value": 0.25}]},

	# ===== 机制卡：护盾值 / 护甲值 =====
	{"id": "mshield", "type": "机制卡", "rarity": "purple", "icon": "🔰", "title": "护盾机制", "desc": "护盾上限 +40%",
		"modifiers": [{"attr": "shield_max", "op": "mul", "value": 0.40}]},
	{"id": "marmor", "type": "机制卡", "rarity": "purple", "icon": "🔰", "title": "护甲机制", "desc": "护甲 +15%",
		"modifiers": [{"attr": "armor", "op": "mul", "value": 0.15}]},

	# ===== 其他卡牌（红卡）：增加其他 / 减少其他属性 =====
	{"id": "red_trigger", "type": "红卡", "rarity": "red", "icon": "💥", "title": "焰心", "desc": "触发伤害次数 +1，攻速 -15%",
		"modifiers": [{"attr": "trigger_times", "op": "add", "value": 1.0},
			{"attr": "attack_speed", "op": "mul", "value": -0.15}]},
	{"id": "red_glass", "type": "红卡", "rarity": "red", "icon": "💥", "title": "孤注一掷", "desc": "物理伤害 +100%，移速 -20%",
		"modifiers": [{"attr": "phys_damage", "op": "mul", "value": 1.0},
			{"attr": "move_speed", "op": "mul", "value": -0.20}]},
	{"id": "red_crit", "type": "红卡", "rarity": "red", "icon": "💥", "title": "暴击狂潮", "desc": "暴击率 +100%，护盾上限 -30%",
		"modifiers": [{"attr": "crit_rate", "op": "mul", "value": 1.0},
			{"attr": "shield_max", "op": "mul", "value": -0.30}]},
	{"id": "red_elem", "type": "红卡", "rarity": "red", "icon": "💥", "title": "元素共鸣", "desc": "元素伤害系数 +80%，物理伤害 -20%",
		"modifiers": [{"attr": "element_coef", "op": "mul", "value": 0.80},
			{"attr": "phys_damage", "op": "mul", "value": -0.20}]},
	{"id": "red_multi", "type": "红卡", "rarity": "red", "icon": "💥", "title": "弹幕洪流", "desc": "多重射击 +1，攻速 -20%",
		"modifiers": [{"attr": "multishot", "op": "add", "value": 1.0},
			{"attr": "attack_speed", "op": "mul", "value": -0.20}]},
]


static func get_card(id: String) -> Dictionary:
	for c in CATALOG:
		if String(c["id"]) == id:
			return c
	return {}


static func cards_of_rarity(rarity: String) -> Array:
	var out: Array = []
	for c in CATALOG:
		if String(c["rarity"]) == rarity:
			out.append(c)
	return out


static func price_of(rarity: String) -> int:
	return int(RARITIES.get(rarity, {}).get("price", 8))


static func rarity_name(rarity: String) -> String:
	return String(RARITIES.get(rarity, {}).get("name", "白"))


static func color_of(rarity: String) -> Dictionary:
	match rarity:
		"blue":
			return {"bg": Color(0.30, 0.58, 0.95), "fg": Color.WHITE, "border": Color(0.12, 0.30, 0.60)}
		"purple":
			return {"bg": Color(0.66, 0.42, 0.92), "fg": Color.WHITE, "border": Color(0.38, 0.18, 0.58)}
		"gold":
			return {"bg": Color(0.97, 0.80, 0.25), "fg": Color(0.25, 0.15, 0.0), "border": Color(0.70, 0.50, 0.05)}
		"red":
			return {"bg": Color(0.92, 0.30, 0.30), "fg": Color.WHITE, "border": Color(0.55, 0.10, 0.10)}
	return {"bg": Color(1, 1, 1), "fg": Color(0.1, 0.1, 0.1), "border": Color(0.55, 0.55, 0.55)}


## 按稀有度概率抽一张卡；exclude 为本轮已出现的卡 id
static func roll_card(exclude: Array = []) -> Dictionary:
	var rarity := _roll_rarity()
	var pool := cards_of_rarity(rarity)
	var filtered: Array = []
	for c in pool:
		if not (String(c["id"]) in exclude):
			filtered.append(c)
	if filtered.is_empty():
		for c in CATALOG:
			if not (String(c["id"]) in exclude):
				filtered.append(c)
	if filtered.is_empty():
		filtered = CATALOG
	return filtered[randi() % filtered.size()]


static func _roll_rarity() -> String:
	var total := 0.0
	for key in RARITY_ORDER:
		total += float(RARITIES[key]["weight"])
	var r := randf() * total
	var acc := 0.0
	for key in RARITY_ORDER:
		acc += float(RARITIES[key]["weight"])
		if r < acc:
			return key
	return RARITY_ORDER[RARITY_ORDER.size() - 1]
