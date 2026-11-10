extends RefCounted

## Boss 目录（纯数据）：新增 Boss = 这里加一条
## skills 里的 type 需在 boss.gd 的 SKILLS 注册；具体技能参数由组件自己解析
## 距离换算：2m = 60px，因此 20m = 600px

const CATALOG := {
	"demon": {
		"name": "地狱信使·小恶魔",
		"hp": 1000000,
		"shield": 3000000.0,
		"armor": 30.0,
		"speed": 55.0,
		"radius": 40.0,
		"visual": "demon",
		"warning": "⚠ 地狱信使·小恶魔 出现！",
		"skills": [
			{"type": "shoot", "interval": 2.6, "first_delay": 2.0,
				"count": 3, "spread": 0.36, "orb_speed": 300.0, "damage": 18},
			{"type": "summon", "interval": 8.0, "first_delay": 6.0, "count": 3},
		],
	},
	"minotaur": {
		"name": "牛头人·阿哞诺斯",
		"hp": 5000000,
		"shield": 3000000.0,
		"armor": 2000.0,
		"speed": 45.0,
		"radius": 50.0,
		"visual": "minotaur",
		"warning": "⚠ 牛头人·阿哞诺斯 出现！",
		"skills": [
			{"type": "ring", "interval": 10.0, "first_delay": 10.0,
				"charge": 5.0, "max_radius": 600.0, "damage_delay": 1.0, "damage": 40},
		],
	},
}


static func get_boss(id: String) -> Dictionary:
	return CATALOG.get(id, CATALOG["demon"])


## 随机取一个 Boss id；exclude 用于避免连续刷同一个
static func random_id(exclude: String = "") -> String:
	var pool := []
	for id in CATALOG.keys():
		if String(id) != exclude:
			pool.append(id)
	if pool.is_empty():
		return "demon"
	return String(pool[randi() % pool.size()])
