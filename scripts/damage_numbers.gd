extends Node

## 伤害飘字：基础伤害 / 持续伤害 / 触发元素伤害
## 作为 main 的子节点，坐标系与主场景一致；emoji 字体缓存也放在这里共用

var damage_numbers: Array = []   # 基础伤害飘字（最多 5 个）
var trigger_numbers: Array = []  # 触发元素伤害飘字（独立，最多 8 个）
var dot_numbers: Array = []      # 持续伤害飘字（独立，最多 5 个，飘得更慢）
var _emoji_font_cache: SystemFont


func emoji_font() -> SystemFont:
	if _emoji_font_cache == null:
		_emoji_font_cache = SystemFont.new()
		_emoji_font_cache.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"])
	return _emoji_font_cache


# 基础伤害飘字：在命中点周围 2m（60px）圆周上随机生成，再向外飘一点
func spawn_damage(from: Vector2, amount: int, crit_stacks: int) -> void:
	var crit := crit_stacks > 0
	var lbl := Label.new()
	lbl.text = str(amount) + "!".repeat(crit_stacks)
	lbl.add_theme_font_size_override("font_size", 20 + mini(crit_stacks * 8, 18))
	lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.1) if crit else Color(0.05, 0.05, 0.05))
	lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 4)

	var ang := randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var spawn := from + dir * 60.0
	lbl.size = lbl.get_combined_minimum_size()
	lbl.position = spawn - lbl.size * 0.5
	add_child(lbl)

	_trim(damage_numbers, 5, lbl)

	# 沿同一方向再向外飘一点
	var target := lbl.position + dir * 40.0
	var tw: Tween = create_tween().bind_node(lbl)
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", target, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(2.0)


# 持续伤害飘字：独立存在，最多 5 个，飘得更慢
func spawn_dot(from: Vector2, amount: int, icon: String) -> void:
	_spawn_element(from, amount, icon, dot_numbers, 5, 1.6, 3.2)


# 触发伤害飘字：独立存在，最多 8 个
func spawn_trigger(from: Vector2, amount: int, icon: String) -> void:
	_spawn_element(from, amount, icon, trigger_numbers, 8, 0.9, 2.0)


# 元素飘字通用：emoji + 伤害，各自独立列表与上限
func _spawn_element(from: Vector2, amount: int, icon: String, bucket: Array,
		limit: int, move_time: float, fade_delay: float) -> void:
	var lbl := Label.new()
	lbl.text = "%s%d" % [icon, amount]
	lbl.add_theme_font_override("font", emoji_font())
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.1))
	lbl.add_theme_color_override("font_outline_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 4)

	var ang := randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	lbl.size = lbl.get_combined_minimum_size()
	lbl.position = from + dir * 46.0 - lbl.size * 0.5
	add_child(lbl)

	_trim(bucket, limit, lbl)

	var target := lbl.position + dir * 26.0
	var tw: Tween = create_tween().bind_node(lbl)
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", target, move_time).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2).set_delay(fade_delay)
	tw.finished.connect(lbl.queue_free)


# 只保留最近 limit 个：最旧的立即消失
func _trim(bucket: Array, limit: int, lbl: Label) -> void:
	for i in range(bucket.size() - 1, -1, -1):
		if not is_instance_valid(bucket[i]):
			bucket.remove_at(i)
	if bucket.size() >= limit:
		var old: Node = bucket.pop_front()
		if is_instance_valid(old):
			(old as CanvasItem).visible = false
			old.queue_free()
	bucket.append(lbl)
