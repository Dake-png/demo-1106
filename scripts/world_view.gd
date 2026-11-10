class_name WorldView

## 2.5D 绘制工具：贴地椭圆阴影 + 本体抬升 + 侧壁厚度
## 约定：节点 position 永远是「脚点」，本体在 _draw 里抬升绘制，排序仍按脚点 Y


const SHADOW_FLAT := 0.42      # 阴影椭圆纵向压扁比例
const LIFT_DEFAULT := 10.0     # 玩家 / 敌人本体抬升
const LIFT_TALL := 18.0        # Boss
const LIFT_BULLET := 26.0      # 子弹 / 弹幕悬浮高度
const LIFT_DROP := 7.0         # 金币 / 经验球 / 道具


## 贴地椭圆阴影：绘制在脚点，自动抵消节点自身旋转（金币旋转时阴影不跟着转）
static func draw_shadow(c: CanvasItem, radius: float, alpha := 0.26) -> void:
	c.draw_set_transform(Vector2.ZERO, -c.rotation, Vector2(1.0, SHADOW_FLAT))
	c.draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 进入「本体绘制」：后续绘制整体上移 lift 像素
static func body_begin(c: CanvasItem, lift := LIFT_DEFAULT) -> void:
	c.draw_set_transform(Vector2(0.0, -lift))


## 进入「本体绘制」并整体缩放（Boss 外观按 radius / 40 缩放）
static func body_begin_scaled(c: CanvasItem, lift: float, s: float) -> void:
	c.draw_set_transform(Vector2(0.0, -lift), 0.0, Vector2.ONE * s)


## 退出本体绘制，恢复默认变换（必须与 body_begin 成对调用）
static func body_end(c: CanvasItem) -> void:
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 多边形棱柱：侧壁分上下两段明暗（轻微渐变）+ 顶面 + 描边
static func draw_prism(c: CanvasItem, poly: PackedVector2Array, color: Color,
		depth := 7.0, edge := Color.BLACK, edge_width := 2.0) -> void:
	var n := poly.size()
	if n < 3:
		return
	var mid := depth * 0.5
	var side_top := color.darkened(0.38)
	var side_low := color.darkened(0.62)
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var m_a := a + Vector2(0.0, mid)
		var m_b := b + Vector2(0.0, mid)
		c.draw_colored_polygon(PackedVector2Array([a, b, m_b, m_a]), side_top)
		c.draw_colored_polygon(PackedVector2Array([
			m_a, m_b, b + Vector2(0.0, depth), a + Vector2(0.0, depth)]), side_low)
	c.draw_colored_polygon(poly, color)
	if edge_width > 0.0:
		c.draw_polyline(poly + PackedVector2Array([poly[0]]), edge, edge_width)


## 圆形棱柱：底缘一圈深色侧壁 + 顶部亮边（Boss / 玩家底座用）
static func draw_disc(c: CanvasItem, radius: float, color: Color, depth := 8.0) -> void:
	c.draw_circle(Vector2(0.0, depth), radius, color.darkened(0.55))
	c.draw_circle(Vector2.ZERO, radius, color)
	c.draw_arc(Vector2(0.0, 1.0), radius, PI + 0.45, TAU - 0.45, 28, color.lightened(0.18), 4.0)
