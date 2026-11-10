extends RefCounted

## 读取 Gamerule/player.json，作为游戏内角色数值的唯一来源

const PATH := "res://Gamerule/player.json"


static func load_player() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var p = data.get("player", {})
	return p if typeof(p) == TYPE_DICTIONARY else {}
