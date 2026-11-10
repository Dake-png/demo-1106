extends Area2D

## 道具掉落物：外观读 item_data.gd，拾取事件走 EventBus（效果在 main 使用道具时结算）

const ITEM_DATA := preload("res://scripts/item_data.gd")

var item_id := "magnet"
var pickup_delay := 0.0   # >0 时延迟开启拾取（防止背包满掉落时立刻被捡回）
var _t := 0.0
var _icon_label: Label


func _ready() -> void:
	add_to_group("drop")
	monitoring = false
	body_entered.connect(_on_body_entered)

	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"])
	_icon_label = Label.new()
	_icon_label.add_theme_font_override("font", f)
	_icon_label.add_theme_font_size_override("font_size", 22)
	_icon_label.text = ITEM_DATA.icon_of(item_id)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.position = Vector2(-14, -18)
	_icon_label.size = Vector2(28, 32)
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_label)
	queue_redraw()

	if pickup_delay <= 0.0:
		monitoring = true


func _process(delta: float) -> void:
	_t += delta
	scale = Vector2.ONE * (1.0 + 0.1 * sin(_t * 4.0))

	if not monitoring and pickup_delay > 0.0:
		pickup_delay -= delta
		if pickup_delay <= 0.0:
			monitoring = true


func _draw() -> void:
	var c: Color = ITEM_DATA.color_of(item_id)
	c.a = 0.95
	draw_circle(Vector2.ZERO, 14.0, c)
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 24, Color.WHITE, 2.0)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		EventBus.item_picked.emit(item_id)
		queue_free()
