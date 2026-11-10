extends RefCounted

## 任务数据表：新增任务只需在 QUESTS 加一条，不用改逻辑
##
## 通用字段：
##   id / title / type / required / reward_gold / reward_levels
##   growth        —— 每轮完成后需求量倍率（默认 1.0 不增长）
##   reward_growth —— 每轮完成后金币增幅（默认 0）
##
## type 取值：
##   kill      击杀任意敌人
##   kill_type 击杀指定类型敌人（enemy_type：0 三角 / 1 方形 / 2 五边形）
##   coin      收集金币
##   survive   存活时间（秒）
##   boss      主线：击杀指定 Boss（需先完成 prereq_kills 前置击杀）

## 主线任务模板：首个 Boss 出现时，按 BOSS_QUESTS 填入标题 / 目标 / 奖励
const MAIN_TEMPLATE := {
	"id": "main", "type": "boss", "title": "调查 Boss 的踪迹",
	"target": "Boss", "boss_id": "",
	"prereq_kills": 100, "required": 1,
	"reward_gold": 100, "reward_levels": 2,
}

## 各 Boss 对应的主线文案与奖励（新增 Boss 时在这里补一条）
const BOSS_QUESTS := {
	"demon": {
		"title": "消灭地狱的信使 - 小恶魔",
		"target": "地狱信使·小恶魔",
		"reward_levels": 2,
	},
	"minotaur": {
		"title": "消灭牛头人 - 阿哞诺斯",
		"target": "牛头人·阿哞诺斯",
		"reward_levels": 5,
	},
}

## 敌人类型显示名（kill_type 任务用）
const ENEMY_TYPE_NAMES := {
	0: "三角敌",
	1: "方形敌",
	2: "五边形敌",
}

const QUESTS := [
	{
		"id": "normal", "type": "kill", "title": "消灭敌人",
		"required": 10, "growth": 1.5,
		"reward_gold": 30, "reward_levels": 1, "reward_growth": 0.1,
	},
	# —— 示例：取消注释即可启用 ——
	# {"id": "hunter", "type": "kill_type", "title": "清剿三角敌", "enemy_type": 0,
	#	"required": 15, "growth": 1.5, "reward_gold": 40, "reward_levels": 1, "reward_growth": 0.1},
	# {"id": "collector", "type": "coin", "title": "收集金币",
	#	"required": 50, "growth": 1.4, "reward_gold": 60, "reward_levels": 1, "reward_growth": 0.1},
	# {"id": "survivor", "type": "survive", "title": "存活 60 秒",
	#	"required": 60, "growth": 1.3, "reward_gold": 50, "reward_levels": 1, "reward_growth": 0.1},
]
