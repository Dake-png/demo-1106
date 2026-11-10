extends Node

## 任务运行时（从 main.gd 分离）：进度 / 完成判定 / 存档状态
## 只负责数据与信号，奖励落地和 UI 展示由 main.gd 处理
## 新增任务类型：在 quest_data.gd 加数据；新类型在这里补一个分支

const DATA := preload("res://scripts/quest_data.gd")

signal changed                                   ## 任务进度有任何变化
signal completed(title: String, gold: int, levels: int, is_main: bool)

var quests: Array = []


func _ready() -> void:
	reset()


## 重置为数据表初始状态（开局 / 新档）
func reset() -> void:
	quests.clear()
	for q in ([DATA.MAIN_TEMPLATE] + DATA.QUESTS):
		var st: Dictionary = q.duplicate(true)
		st["progress"] = 0
		st["round"] = 0
		st["done"] = false
		st["elapsed"] = 0.0
		quests.append(st)
	changed.emit()


func get_quest(id: String) -> Dictionary:
	for st in quests:
		if String(st["id"]) == id:
			return st
	return {}


# ---------- 事件推进 ----------

## 击杀敌人：推进 kill / kill_type 类任务
func notify_kill(enemy_type: int = -1) -> void:
	var touched := false
	for st in quests:
		if bool(st["done"]):
			continue
		match String(st["type"]):
			"kill":
				touched = true
				_advance(st, 1)
			"kill_type":
				if int(st.get("enemy_type", -1)) == enemy_type:
					touched = true
					_advance(st, 1)
	if touched:
		changed.emit()


## 收集金币：推进 coin 类任务
func notify_coin(amount: int = 1) -> void:
	var touched := false
	for st in quests:
		if bool(st["done"]) or String(st["type"]) != "coin":
			continue
		touched = true
		_advance(st, amount)
	if touched:
		changed.emit()


## 每帧推进 survive 类任务（暂停时 main 不会调用）
func tick(delta: float) -> void:
	var touched := false
	for st in quests:
		if bool(st["done"]) or String(st["type"]) != "survive":
			continue
		touched = true
		st["elapsed"] = float(st.get("elapsed", 0.0)) + delta
		st["progress"] = mini(int(st["elapsed"]), int(st["required"]))
		if int(st["progress"]) >= int(st["required"]):
			_complete(st)
		else:
			changed.emit()


## 击杀 Boss：结算主线
func notify_boss_killed(boss_id: String, kills: int) -> void:
	var touched := false
	for st in quests:
		if String(st["type"]) != "boss" or bool(st["done"]):
			continue
		if String(st.get("boss_id", "")) != boss_id:
			continue
		if kills < int(st.get("prereq_kills", 0)):
			continue
		st["done"] = true
		st["progress"] = int(st["required"])
		completed.emit(String(st["title"]), quest_gold(st), int(st["reward_levels"]), true)
		touched = true
	if touched:
		changed.emit()


## 首个 Boss 出现时确定主线目标与奖励（之后固定不变）
func set_main_boss(boss_id: String) -> void:
	var changed_main := false
	for st in quests:
		if String(st["type"]) != "boss" or bool(st["done"]):
			continue
		if String(st.get("boss_id", "")) != "":
			continue
		var cfg: Dictionary = DATA.BOSS_QUESTS.get(boss_id, {})
		if cfg.is_empty():
			continue
		st["boss_id"] = boss_id
		st["title"] = String(cfg.get("title", st["title"]))
		st["target"] = String(cfg.get("target", st["target"]))
		st["reward_levels"] = int(cfg.get("reward_levels", st["reward_levels"]))
		changed_main = true
	if changed_main:
		changed.emit()


# ---------- 奖励 / 存档 ----------

## 循环任务奖励：每轮金币按 reward_growth 递增
func quest_gold(st: Dictionary) -> int:
	return int(float(st["reward_gold"]) * pow(1.0 + float(st.get("reward_growth", 0.0)), int(st["round"])))


func save_state() -> Dictionary:
	var out := {}
	for st in quests:
		out[String(st["id"])] = {
			"progress": st["progress"], "round": st["round"],
			"required": st["required"], "done": st["done"],
			"elapsed": st.get("elapsed", 0.0),
			"boss_id": String(st.get("boss_id", "")),
			"title": String(st["title"]), "target": String(st.get("target", "")),
			"reward_levels": int(st["reward_levels"]),
		}
	return out


func load_state(state: Dictionary) -> void:
	for st in quests:
		var s: Dictionary = state.get(String(st["id"]), {})
		if s.is_empty():
			continue
		st["progress"] = int(s.get("progress", 0))
		st["round"] = int(s.get("round", 0))
		st["required"] = int(s.get("required", st["required"]))
		st["done"] = bool(s.get("done", false))
		st["elapsed"] = float(s.get("elapsed", 0.0))
		st["boss_id"] = String(s.get("boss_id", st.get("boss_id", "")))
		st["title"] = String(s.get("title", st["title"]))
		st["target"] = String(s.get("target", st.get("target", "")))
		st["reward_levels"] = int(s.get("reward_levels", st["reward_levels"]))
	changed.emit()


# ---------- 内部 ----------

func _advance(st: Dictionary, amount: int) -> void:
	st["progress"] = int(st["progress"]) + amount
	if int(st["progress"]) >= int(st["required"]):
		_complete(st)


func _complete(st: Dictionary) -> void:
	var is_main := String(st["type"]) == "boss"
	var gold := quest_gold(st)
	var title := String(st["title"])
	var lv := int(st["reward_levels"])
	if is_main:
		st["done"] = true
		st["progress"] = int(st["required"])
	else:
		st["round"] = int(st["round"]) + 1
		st["progress"] = 0
		st["elapsed"] = 0.0
		st["required"] = maxi(1, int(round(float(st["required"]) * float(st.get("growth", 1.0)))))
	completed.emit(title, gold, lv, is_main)
