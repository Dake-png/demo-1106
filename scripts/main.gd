extends Node2D

## 游戏主控：生成玩家/金币/敌人，HUD，碰撞处理

@onready var hud: CanvasLayer = $HUD
@onready var hp_bar: ProgressBar = $HUD/Root/HPBar
@onready var score_label: Label = $HUD/Root/ScoreLabel

# prefab 加载
const PlayerScene := preload("res://scenes/player.tscn")
const BulletScene := preload("res://scenes/bullet.tscn")
const CoinScene   := preload("res://scenes/coin.tscn")
const EnemyScene  := preload("res://scenes/enemy.tscn")

# 参数
const COIN_SPAWN_INTERVAL := 2.2
const ENEMY_SPAWN_INTERVAL := 3.0
const WORLD_HALF := 800.0

var player
var score := 0


func _ready() -> void:
	randomize()
	_spawn_player()
	hp_bar.max_value = player.MAX_HP
	hp_bar.value = player.hp
	# 定时生成
	get_tree().create_timer(COIN_SPAWN_INTERVAL, true).timeout.connect(_spawn_coin)
	get_tree().create_timer(ENEMY_SPAWN_INTERVAL, true).timeout.connect(_spawn_enemy)
	for i in range(5):
		_spawn_coin()


# --- 生成 ---

func _spawn_player() -> void:
	var p := PlayerScene.instantiate()
	p.position = Vector2.ZERO
	add_child(p)
	p.health_changed.connect(_on_health_changed)
	p.bullet_spawned.connect(_on_bullet_spawned)
	player = p


func _spawn_coin() -> void:
	var coin := CoinScene.instantiate()
	coin.position = _random_pos()
	coin.picked_up.connect(func(): score += 1; score_label.text = "金币: %d" % score)
	add_child(coin)


func _spawn_enemy() -> void:
	var enemy := EnemyScene.instantiate()
	var angle := randf_range(0, TAU)
	var dist := randf_range(400, 600)
	enemy.position = player.position + Vector2.RIGHT.rotated(angle) * dist
	add_child(enemy)


func _random_pos() -> Vector2:
	var pad := 100.0
	return Vector2(randf_range(-WORLD_HALF + pad, WORLD_HALF - pad),
	               randf_range(-WORLD_HALF + pad, WORLD_HALF - pad))


# --- 碰撞处理 ---

func _on_bullet_spawned(origin: Vector2, direction: Vector2) -> void:
	var bullet := BulletScene.instantiate()
	bullet.position = origin
	bullet.velocity = direction * bullet.SPEED
	add_child(bullet)
	# 子弹可撞 CharacterBody2D（敌人本体）和 Area2D（敌人攻击区）
	bullet.body_entered.connect(_on_bullet_hit_body.bind(bullet))
	bullet.area_entered.connect(_on_bullet_hit_area.bind(bullet))


func _on_bullet_hit_body(body: Node, bullet: Node) -> void:
	if body.is_in_group("enemy"):
		body.take_damage(25)
		bullet.queue_free()


func _on_bullet_hit_area(area: Area2D, bullet: Node) -> void:
	var parent := area.get_parent()
	if parent and parent.is_in_group("enemy"):
		parent.take_damage(25)
		bullet.queue_free()


# --- HUD ---

func _on_health_changed(cur: int, max_v: int) -> void:
	hp_bar.max_value = max_v
	hp_bar.value = cur
