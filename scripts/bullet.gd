extends Area2D

## 子弹：直线飞行，撞墙或超时销毁
## 外观（形状/大小）、范围伤害、穿透由武器配置决定

var SPEED := 650.0
const LIFETIME := 1.5

var velocity := Vector2.ZERO
var damage := 25.0
var crit_stacks := 0

# --- 武器参数（由 main.gd 按当前武器赋值） ---
var bullet_shape := "circle"   # circle / hex
var bullet_size := 4.0
var aoe_radius := 0.0          # >0 时命中造成范围伤害
var pierce := 0                # 剩余可额外穿透的敌人数
var hit_targets: Array = []    # 已命中的敌人，避免重复结算
var effects: Array = []        # 武器配置的施加效果（命中时结算）

var _life := 0.0

const PIERCE_SPEED_MULT := 0.5   # 每穿透一个敌人，飞行速度 ×50%


func _ready() -> void:
	_sync_collision()


## 碰撞体半径与绘制大小保持一致
func _sync_collision() -> void:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		return
	var circle := CircleShape2D.new()
	circle.radius = bullet_size
	cs.shape = circle


## 穿透减速（GRule 穿透规则）
func on_pierced() -> void:
	velocity *= PIERCE_SPEED_MULT


func _physics_process(delta: float) -> void:
	position += velocity * delta
	_life += delta
	if _life > LIFETIME:
		queue_free()


func _draw() -> void:
	var c := Color.ORANGE
	if crit_stacks >= 2:
		c = Color(1.0, 0.1, 0.1)
	elif crit_stacks == 1:
		c = Color(1.0, 0.45, 0.1)
	var r := bullet_size + float(mini(crit_stacks, 3)) * 0.8
	if bullet_shape == "hex":
		var pts := PackedVector2Array()
		for i in range(6):
			var a := i * TAU / 6.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, c)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.YELLOW, 1.5)
	else:
		draw_circle(Vector2.ZERO, r, c)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, Color.YELLOW, 1.5)
