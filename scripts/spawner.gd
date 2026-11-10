extends Node

## 生成器：金币 / 敌人 / Boss / 掉落物，以及两个生成循环 Timer。
## 击杀、Boss 血条与警告等业务逻辑仍由 main.gd 处理。

const CoinScene := preload("res://scenes/coin.tscn")
const ItemScene := preload("res://scenes/item.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const BossScene := preload("res://scenes/boss.tscn")

const MAX_ENEMIES := 200   # 场上敌人上限
const COIN_SPAWN_INTERVAL := 2.2
const ENEMY_SPAWN_INTERVAL := 2.5

var host: Node       # 主场景：生成物仍挂在它下面，保持渲染层级不变
var world_half := 800.0


func setup(host_node: Node, world_half_value: float) -> void:
	host = host_node
	world_half = world_half_value


# 金币 / 敌人生成循环（create_timer 只触发一次，所以用 Timer 节点）
func start_timers() -> void:
	var coin_timer := Timer.new()
	coin_timer.wait_time = COIN_SPAWN_INTERVAL
	coin_timer.autostart = true
	coin_timer.timeout.connect(spawn_coin)
	add_child(coin_timer)

	var enemy_timer := Timer.new()
	enemy_timer.wait_time = ENEMY_SPAWN_INTERVAL
	enemy_timer.autostart = true
	enemy_timer.timeout.connect(spawn_enemy)
	add_child(enemy_timer)


func spawn_coin() -> void:
	spawn_coin_at(random_pos())


func spawn_coin_at(pos: Vector2) -> void:
	var coin := CoinScene.instantiate()
	coin.position = pos
	host.add_child(coin)


func spawn_item_drop(item_id: String, pos: Vector2) -> void:
	var item := ItemScene.instantiate()
	item.item_id = item_id
	item.pickup_delay = 0.6
	item.position = pos
	host.add_child.call_deferred(item)   # 可能在物理回调里调用，延迟入树


func spawn_enemy() -> void:
	var alive := get_tree().get_nodes_in_group("enemy").size()
	if alive >= MAX_ENEMIES:
		return
	for i in range(3):   # 一次刷 3 只
		if alive + i >= MAX_ENEMIES:
			break
		var enemy := EnemyScene.instantiate()
		enemy.config(pick_enemy_type())
		enemy.position = edge_spawn_pos()
		host.add_child(enemy)


# 三角 50% / 方 35% / 五边形 15%
func pick_enemy_type() -> int:
	var r := randf()
	if r < 0.5:
		return 0
	elif r < 0.85:
		return 1
	return 2


## 生成 Boss 并返回；血条 / 音效 / 警告由 main 处理
func spawn_boss(boss_id: String) -> Node:
	var boss := BossScene.instantiate()
	boss.configure(boss_id)
	boss.position = edge_spawn_pos()
	host.add_child(boss)
	return boss


func edge_spawn_pos() -> Vector2:
	var side := randi() % 4
	var m := 20.0
	match side:
		0: return Vector2(randf_range(-world_half + m, world_half - m), -world_half + m)
		1: return Vector2(randf_range(-world_half + m, world_half - m), world_half - m)
		2: return Vector2(-world_half + m, randf_range(-world_half + m, world_half - m))
		3: return Vector2(world_half - m, randf_range(-world_half + m, world_half - m))
	return Vector2.ZERO


func random_pos() -> Vector2:
	var pad := 100.0
	return Vector2(randf_range(-world_half + pad, world_half - pad),
				   randf_range(-world_half + pad, world_half - pad))
