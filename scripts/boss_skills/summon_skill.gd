extends Node

## 召唤技能组件：每隔 interval 请求主场景生成 count 个小怪

var boss: Node
var cfg := {}
var _timer := 0.0


func setup(owner_boss: Node, config: Dictionary) -> void:
	boss = owner_boss
	cfg = config
	_timer = float(cfg.get("first_delay", 6.0))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(boss) or boss.is_dead():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(cfg.get("interval", 8.0))
	boss.summon_requested.emit(boss.global_position, int(cfg.get("count", 3)))
