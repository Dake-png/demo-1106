extends RefCounted

## 物品存储系统：背包（固定格子，每格堆叠 99）+ 物品栏（5 格）
## 格子内容为空时是 {}，否则 {"id": 道具 id, "count": 数量}

const BAG_SLOTS := 20
const HOTBAR_SLOTS := 5
const STACK_MAX := 99

var bag: Array = []
var hotbar: Array = []


func _init() -> void:
	bag.resize(BAG_SLOTS)
	hotbar.resize(HOTBAR_SLOTS)


## 背包格：返回 {} 或 {"id", "count"}（副本，改内容请用其它方法）
func bag_slot(index: int) -> Dictionary:
	if index < 0 or index >= BAG_SLOTS:
		return {}
	var s = bag[index]
	return {} if s == null else s


## 物品栏格
func hot_slot(index: int) -> Dictionary:
	if index < 0 or index >= HOTBAR_SLOTS:
		return {}
	var s = hotbar[index]
	return {} if s == null else s


## 拾取放入：优先物品栏（堆叠 / 空格），物品栏满后再进背包。返回未放入的数量
func add_item(id: String, count := 1) -> int:
	if id == "" or count <= 0:
		return count
	count = _fill(hotbar, HOTBAR_SLOTS, id, count)
	if count > 0:
		count = _fill(bag, BAG_SLOTS, id, count)
	return count


## 向指定槽位数组填充：先堆叠已有同种，再占用空格
func _fill(slots: Array, size: int, id: String, count: int) -> int:
	for i in size:
		var s = slots[i]
		if s != null and String(s["id"]) == id and int(s["count"]) < STACK_MAX:
			var put := mini(STACK_MAX - int(s["count"]), count)
			s["count"] = int(s["count"]) + put
			count -= put
			if count <= 0:
				return 0
	for i in size:
		if slots[i] == null:
			var put2 := mini(STACK_MAX, count)
			slots[i] = {"id": id, "count": put2}
			count -= put2
			if count <= 0:
				return 0
	return count


## 背包格 → 物品栏格：空格放入 / 同种堆叠 / 不同种交换
func bag_to_hot(bag_index: int, hot_index: int) -> bool:
	if bag_index < 0 or bag_index >= BAG_SLOTS or hot_index < 0 or hot_index >= HOTBAR_SLOTS:
		return false
	var src = bag[bag_index]
	if src == null:
		return false
	var dst = hotbar[hot_index]
	if dst == null:
		hotbar[hot_index] = src
		bag[bag_index] = null
		return true
	if String(dst["id"]) == String(src["id"]):
		var put := mini(STACK_MAX - int(dst["count"]), int(src["count"]))
		if put <= 0:
			return false
		dst["count"] = int(dst["count"]) + put
		src["count"] = int(src["count"]) - put
		if int(src["count"]) <= 0:
			bag[bag_index] = null
		return true
	bag[bag_index] = dst
	hotbar[hot_index] = src
	return true


## 物品栏 → 背包格（同上规则）
func hot_to_bag(hot_index: int, bag_index: int) -> bool:
	if bag_index < 0 or bag_index >= BAG_SLOTS or hot_index < 0 or hot_index >= HOTBAR_SLOTS:
		return false
	var src = hotbar[hot_index]
	if src == null:
		return false
	var dst = bag[bag_index]
	if dst == null:
		bag[bag_index] = src
		hotbar[hot_index] = null
		return true
	if String(dst["id"]) == String(src["id"]):
		var put := mini(STACK_MAX - int(dst["count"]), int(src["count"]))
		if put <= 0:
			return false
		dst["count"] = int(dst["count"]) + put
		src["count"] = int(src["count"]) - put
		if int(src["count"]) <= 0:
			hotbar[hot_index] = null
		return true
	hotbar[hot_index] = dst
	bag[bag_index] = src
	return true


## 交换两个物品栏格
func swap_hot(a: int, b: int) -> bool:
	if a < 0 or a >= HOTBAR_SLOTS or b < 0 or b >= HOTBAR_SLOTS or a == b:
		return false
	var tmp = hotbar[a]
	hotbar[a] = hotbar[b]
	hotbar[b] = tmp
	return true


## 使用物品栏格：数量 -1，耗尽后清空；返回使用的道具 id
func consume_hot(index: int) -> String:
	var s = hot_slot(index)
	if s.is_empty():
		return ""
	var id := String(s["id"])
	s["count"] = int(s["count"]) - 1
	if int(s["count"]) <= 0:
		hotbar[index] = null
	return id
