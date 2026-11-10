extends Node

## 升级选卡弹窗：抽 3 张卡展示 + 弹出动画
## 点卡后只发信号，加属性与暂停/连续升级排队由 main 处理

signal card_chosen(card_id: String)

const CARD_DATA := preload("res://scripts/card_data.gd")
const UI_STYLE := preload("res://scripts/ui/ui_style.gd")

var host: Node              # hud_layer：弹窗挂载点，也用于暂停时创建 tween
var emoji_font: Font
var popup: Control
var card_row: HBoxContainer


func build(parent: Node, emoji: Font) -> void:
	host = parent
	emoji_font = emoji
	popup = Control.new()
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	parent.add_child(popup)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	popup.add_child(dim)

	var title := Label.new()
	title.text = "升级！选择一项增强"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-100, 60)
	title.size = Vector2(200, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	popup.add_child(title)

	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 16)
	card_row.set_anchors_preset(Control.PRESET_CENTER)
	card_row.position = Vector2(-246, -90)
	card_row.size = Vector2(492, 180)
	popup.add_child(card_row)


func is_open() -> bool:
	return popup != null and popup.visible


func show_cards() -> void:
	_populate()
	popup.visible = true


func hide() -> void:
	popup.visible = false


# 按稀有度概率抽 3 张不重复的卡
func _populate() -> void:
	for c in card_row.get_children():
		card_row.remove_child(c)
		c.queue_free()
	var used := []
	for i in range(3):
		var card: Dictionary = CARD_DATA.roll_card(used)
		used.append(card["id"])
		_make_card(card)
	_animate_cards(card_row.get_children())


# 卡牌弹出特效：依次放大 + 淡入（用 hud_layer 建 tween，暂停时也能播放）
func _animate_cards(items: Array) -> void:
	var i := 0
	for node in items:
		if not is_instance_valid(node):
			continue
		var c: Control = node
		c.modulate.a = 0.0
		c.scale = Vector2(0.6, 0.6)
		var tw: Tween = host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "scale", Vector2.ONE, 0.30).set_delay(i * 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(i * 0.06)
		i += 1


func _make_card(card: Dictionary) -> void:
	var rarity: String = card["rarity"] if card.has("rarity") else "white"
	var col := CARD_DATA.color_of(rarity)
	var bg: Color = col["bg"]
	var fg: Color = col["fg"]
	var border: Color = col["border"]

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 180)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pivot_offset = Vector2(75, 90)
	btn.add_theme_stylebox_override("normal", UI_STYLE.card(bg, border))
	btn.add_theme_stylebox_override("hover", UI_STYLE.card(bg.lightened(0.12), border))
	btn.add_theme_stylebox_override("pressed", UI_STYLE.card(bg.darkened(0.12), border))
	btn.add_theme_stylebox_override("focus", UI_STYLE.card(bg, border))
	card_row.add_child(btn)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cc)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(vb)

	var ic := Label.new()
	ic.text = String(card["icon"])
	ic.add_theme_font_override("font", emoji_font)
	ic.add_theme_font_size_override("font_size", 38)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ic)

	var t := Label.new()
	t.text = String(card["title"])
	t.add_theme_color_override("font_color", fg)
	t.add_theme_font_size_override("font_size", 16)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	var d := Label.new()
	d.text = String(card["desc"])
	d.add_theme_color_override("font_color", fg)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(d)

	var id := String(card["id"])
	btn.pressed.connect(func(): card_chosen.emit(id))
