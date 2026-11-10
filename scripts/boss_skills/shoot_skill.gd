extends Node

## 远程弹幕技能组件：每隔 interval 向玩家发射 count 发扇形弹
## 参数：interval / first_delay / count / spread（弧度）/ orb_speed / damage

const BossOrbScene := preload("res://scenes/boss_orb.tscn")

var boss: Node
var cfg := {}
var _timer := 0.0


func setup(owner_boss: Node, config: Dictionary) -> void:
	boss = owner_boss
	cfg = config
	_timer = float(cfg.get("first_delay", 2.0))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(boss) or boss.is_dead():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(cfg.get("interval", 2.6))
	_fire()


func _fire() -> void:
	var player: Node2D = boss.player
	if not player:
		return
	var aim: Vector2 = (player.global_position - boss.global_position).normalized()
	var count := maxi(1, int(cfg.get("count", 1)))
	var spread := float(cfg.get("spread", 0.0))
	for i in range(count):
		var off := 0.0
		if count > 1:
			off = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		var dir := aim.rotated(off)
		var orb := BossOrbScene.instantiate()
		orb.position = boss.global_position + dir * (float(boss.radius) + 10.0)
		orb.velocity = dir * float(cfg.get("orb_speed", 300.0))
		orb.damage = int(cfg.get("damage", 18))
		boss.get_parent().add_child(orb)
