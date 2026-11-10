extends RefCounted

## 道具系统（纯数据 + 可插拔）：新增道具 = 在 CATALOG 加一条，不改逻辑与 UI
## use = timed：限时修饰（duration 秒，modifiers 走玩家修饰体系）
## use = instant：立即生效（heal 等字段）
## 掉落权重见 DROP_WEIGHTS

const CATALOG := {
	"damage_potion": {
		"name": "增伤药水", "icon": "🧪", "color": Color(0.95, 0.45, 0.35),
		"desc": "30 秒内总伤害 +100%",
		"use": "timed", "duration": 30.0,
		"modifiers": [{"attr": "damage", "op": "mul", "value": 1.0}],
	},
	"magnet": {
		"name": "磁铁", "icon": "🧲", "color": Color(0.75, 0.45, 1.0),
		"desc": "30 秒内吸取范围 +5 米",
		"use": "timed", "duration": 30.0,
		"modifiers": [{"attr": "pickup_range", "op": "add", "value": 5.0}],
	},
	"giant_potion": {
		"name": "巨型化药水", "icon": "🔵", "color": Color(0.35, 0.7, 1.0),
		"desc": "30 秒内子弹大小 +100%、穿透 +2",
		"use": "timed", "duration": 30.0,
		"modifiers": [
			{"attr": "bullet_scale", "op": "mul", "value": 1.0},
			{"attr": "pierce", "op": "add", "value": 2.0},
		],
	},
	"heal_potion": {
		"name": "回血药水", "icon": "❤️", "color": Color(0.35, 0.9, 0.4),
		"desc": "立即恢复 50 点生命",
		"use": "instant", "heal": 50,
	},
}

const DROP_WEIGHTS := {
	"damage_potion": 3,
	"magnet": 3,
	"giant_potion": 2,
	"heal_potion": 4,
}


static func get_item(id: String) -> Dictionary:
	return CATALOG.get(id, {})


static func icon_of(id: String) -> String:
	return String(get_item(id).get("icon", "❔"))


static func color_of(id: String) -> Color:
	return get_item(id).get("color", Color(0.8, 0.8, 0.8))


## 随机掉落一个道具 id（按 DROP_WEIGHTS 权重）
static func random_drop_id() -> String:
	var total := 0
	for key in DROP_WEIGHTS:
		total += int(DROP_WEIGHTS[key])
	if total <= 0:
		return CATALOG.keys()[0]
	var r := randi() % total
	var acc := 0
	for key in DROP_WEIGHTS:
		acc += int(DROP_WEIGHTS[key])
		if r < acc:
			return key
	return CATALOG.keys()[0]
