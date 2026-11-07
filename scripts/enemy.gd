extends CharacterBody2D

## 敌人：朝玩家移动 + 接触伤害

const SPEED := 140.0
const DAMAGE := 10.0
const ATTACK_COOLDOWN := 0.8
const HP := 50

var hp := HP
var player: Node2D
var _attack_timer := 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	var attack_area: Area2D = $AttackArea
	if attack_area:
		attack_area.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	if player:
		velocity = (player.global_position - global_position).normalized() * SPEED
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 16.0, Color.RED)
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 20, Color.DARK_RED, 2.0)
	draw_circle(Vector2(-5.0, -3.0), 3.0, Color.WHITE)
	draw_circle(Vector2( 5.0, -3.0), 3.0, Color.WHITE)
	draw_circle(Vector2(-5.0, -3.0), 1.5, Color.BLACK)
	draw_circle(Vector2( 5.0, -3.0), 1.5, Color.BLACK)


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and _attack_timer <= 0.0:
		body.take_damage(DAMAGE)
		_attack_timer = ATTACK_COOLDOWN
