extends Node2D

## 地面层：当前只是网格地面（v4.0 阶段 D 再替换为程序化贴图与视差）
## 由 main 挂到 Ground 节点（z_index = -100），永远压在实体之下

var world_half := 800.0


func setup(world_half_value: float) -> void:
	world_half = world_half_value
	queue_redraw()


func _draw() -> void:
	var size := world_half * 2.0
	var tl := Vector2(-world_half, -world_half)
	draw_rect(Rect2(tl, Vector2(size, size)), Color.WHITE)
	draw_rect(Rect2(tl, Vector2(size, size)), Color.BLACK, false, 3.0)
	var step := 100.0
	for x in range(-int(world_half), int(world_half) + 1, int(step)):
		draw_line(Vector2(x, -world_half), Vector2(x, world_half), Color(0.85, 0.85, 0.85), 1.0)
	for y in range(-int(world_half), int(world_half) + 1, int(step)):
		draw_line(Vector2(-world_half, y), Vector2(world_half, y), Color(0.85, 0.85, 0.85), 1.0)
