extends Node

## 存档：写盘、读盘数据恢复、自动存档计时。
## 读档后的 UI 刷新与 Boss 进度处理由 main.gd 负责。

const SAVE_PATH := "user://save.cfg"
const INVENTORY := preload("res://scripts/inventory.gd")
const AUTOSAVE_INTERVAL := 5.0

var autosave_timer := 0.0


## 自动存档计时：满 5 秒返回 true，由 main 触发实际写盘
func tick(delta: float) -> bool:
	autosave_timer += delta
	if autosave_timer >= AUTOSAVE_INTERVAL:
		autosave_timer = 0.0
		return true
	return false


## 写盘：state 由 main 组装（分数、玩家、任务、背包等）
func save_game(state: Dictionary) -> void:
	var player = state["player"]
	var quest_mgr = state["quest_mgr"]
	var inventory = state["inventory"]
	var cfg := ConfigFile.new()
	cfg.set_value("game", "score", int(state["score"]))
	cfg.set_value("game", "kills", int(state["kills"]))
	cfg.set_value("game", "elapsed", float(state["elapsed"]))
	cfg.set_value("player", "pos", player.position)
	cfg.set_value("player", "hp", player.hp)
	cfg.set_value("player", "shield", player.shield)
	cfg.set_value("player", "level", player.level)
	cfg.set_value("player", "exp", player.exp)
	cfg.set_value("player", "atk", player.atk_power)
	cfg.set_value("player", "fire_cd", player.fire_cooldown)
	cfg.set_value("player", "multishot", player.multishot)
	cfg.set_value("player", "crit", player.base_crit)
	cfg.set_value("player", "crit_bonus", player.crit_bonus)
	cfg.set_value("player", "weapon", player.weapon_id)
	cfg.set_value("player", "weapons", player.owned_weapons)
	cfg.set_value("player", "modifiers", player.perm_modifiers)
	cfg.set_value("quests", "state", quest_mgr.save_state())
	cfg.set_value("game", "boss_kills_mark", int(state["boss_kills_mark"]))
	cfg.set_value("game", "last_boss_id", String(state["last_boss_id"]))
	cfg.set_value("inventory", "bag", inventory.bag)
	cfg.set_value("inventory", "hotbar", inventory.hotbar)
	cfg.save(SAVE_PATH)


## 读盘：把数据恢复到 player / quest / inventory
## 返回 {ok, score, kills, elapsed, boss_kills_mark, last_boss_id}
func load_game(player, quest_mgr, inventory, last_boss_id: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("player"):
		return {"ok": false}

	var p: Dictionary = {}
	for key in ["pos", "hp", "shield", "level", "exp", "atk", "fire_cd",
			"multishot", "crit", "crit_bonus", "weapon", "weapons"]:
		p[key] = cfg.get_value("player", key, null)

	player.owned_weapons = Array(p["weapons"]) if p["weapons"] != null else ["pistol"]
	player.weapon_id = String(p["weapon"]) if p["weapon"] != null else "pistol"
	player.level = int(p["level"]) if p["level"] != null else 1
	player.exp = int(p["exp"]) if p["exp"] != null else 0
	player.exp_to_next = player._calc_exp_needed(player.level)
	player.atk_power = float(p["atk"]) if p["atk"] != null else player.atk_power
	player.fire_cooldown = float(p["fire_cd"]) if p["fire_cd"] != null else player.fire_cooldown
	player.multishot = float(p["multishot"]) if p["multishot"] != null else player.multishot
	player.base_crit = float(p["crit"]) if p["crit"] != null else player.base_crit
	player.crit_bonus = float(p["crit_bonus"]) if p["crit_bonus"] != null else 0.0
	# 卡牌永久修饰：必须恢复后再重算，否则伤害/暴击/护盾/护甲等全部归零
	var mod_raw = cfg.get_value("player", "modifiers", [])
	player.restore_modifiers(Array(mod_raw) if mod_raw is Array else [])
	player._recalc_crit()
	player.hp = int(p["hp"]) if p["hp"] != null else player.MAX_HP
	player.shield = float(p["shield"]) if p["shield"] != null else player.SHIELD_MAX
	if p["pos"] != null:
		player.position = p["pos"]
		player.cam_pos = player.position

	var qstate: Dictionary = cfg.get_value("quests", "state", {})
	quest_mgr.load_state(qstate)

	# 背包 / 物品栏
	var bag_data: Array = cfg.get_value("inventory", "bag", [])
	var hot_data: Array = cfg.get_value("inventory", "hotbar", [])
	for i in mini(bag_data.size(), INVENTORY.BAG_SLOTS):
		inventory.bag[i] = _restore_slot(bag_data[i])
	for i in mini(hot_data.size(), INVENTORY.HOTBAR_SLOTS):
		inventory.hotbar[i] = _restore_slot(hot_data[i])

	return {
		"ok": true,
		"score": int(cfg.get_value("game", "score", 0)),
		"kills": int(cfg.get_value("game", "kills", 0)),
		"elapsed": float(cfg.get_value("game", "elapsed", 0.0)),
		"boss_kills_mark": int(cfg.get_value("game", "boss_kills_mark", 0)),
		"last_boss_id": String(cfg.get_value("game", "last_boss_id", last_boss_id)),
	}


## 读档恢复单个格子：空 / null 返回 null，其余规整为 {"id", "count"}
func _restore_slot(raw) -> Variant:
	if raw == null:
		return null
	if raw is Dictionary and raw.has("id"):
		return {"id": String(raw["id"]), "count": maxi(1, int(raw.get("count", 1)))}
	return null
