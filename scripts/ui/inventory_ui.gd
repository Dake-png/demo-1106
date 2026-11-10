extends Node

## 物品栏（屏幕底部）+ 背包弹窗：格子显示、拖拽交换、点击使用
## 数据仍在 scripts/inventory.gd；开关键与暂停由 main 负责

signal toggle_requested     # 按下 E（由 main 做弹窗互斥判断与暂停）
signal item_used            # 用掉一个道具（main 播放音效、刷新属性）
signal attr_changed         # 道具效果改变了属性

const BackpackInput := preload("res://scripts/backpack_input.gd")
const ITEM_DATA := preload("res://scripts/item_data.gd")
const INVENTORY := preload("res://scripts/inventory.gd")
const UI_STYLE := preload("res://scripts/ui/ui_style.gd")

var inventory
var player
var emoji_font: Font

var backpack_popup: Control
var bag_buttons: Array = []
var hot_buttons: Array = []
var inv_drag_bag := -1   # 正在拖拽的背包格（-1 无）
var inv_drag_hot := -1   # 正在拖拽的物品栏格（-1 无）


func build(parent: Node, inv, emoji: Font) -> void:
	inventory = inv
	emoji_font = emoji

	# E 键开关背包（暂停时也要能响应）
	var key_probe := BackpackInput.new()
	key_probe.toggle_pressed.connect(func(): toggle_requested.emit())
	parent.add_child(key_probe)

	# 物品栏：画面最下面，buff 栏下方
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -150.0
	bar.offset_right = 150.0
	bar.offset_top = -62.0
	bar.offset_bottom = -12.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	parent.add_child(bar)
	for i in INVENTORY.HOTBAR_SLOTS:
		var b := _make_slot(50.0, true)
		b.button_down.connect(_on_hot_down.bind(i))
		b.button_up.connect(_on_release)
		# 左上角快捷键提示：1~5
		var key_hint := Label.new()
		key_hint.name = "KeyHint"
		key_hint.text = str(i + 1)
		key_hint.position = Vector2(5.0, 2.0)
		key_hint.add_theme_font_size_override("font_size", 11)
		key_hint.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key_hint)
		bar.add_child(b)
		hot_buttons.append(b)

	# 背包弹窗
	backpack_popup = Control.new()
	backpack_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	backpack_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	backpack_popup.visible = false
	parent.add_child(backpack_popup)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	backpack_popup.add_child(dim)

	# 居中容器：面板大小跟随格子内容，无多余空白边框
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backpack_popup.add_child(center)

	var panel := PanelContainer.new()
	var sb := UI_STYLE.card(Color(0.24, 0.26, 0.31, 0.72), Color(0.6, 0.65, 0.75, 0.85))
	sb.set_content_margin_all(16.0)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	var title := Label.new()
	title.text = "背包（E 关闭）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "拖拽道具到下方物品栏 · 点击物品栏格子使用"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	vb.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(grid)
	for i in INVENTORY.BAG_SLOTS:
		var b := _make_slot(58.0)
		b.button_down.connect(_on_bag_down.bind(i))
		b.button_up.connect(_on_release)
		grid.add_child(b)
		bag_buttons.append(b)

	refresh()


func set_player(p) -> void:
	player = p


func is_open() -> bool:
	return backpack_popup != null and backpack_popup.visible


func toggle() -> void:
	if backpack_popup:
		backpack_popup.visible = not backpack_popup.visible


func refresh() -> void:
	for i in hot_buttons.size():
		_set_slot_view(hot_buttons[i], inventory.hot_slot(i))
	for i in bag_buttons.size():
		_set_slot_view(bag_buttons[i], inventory.bag_slot(i))


func _make_slot(size: float, white_bg := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	if white_bg:
		b.add_theme_stylebox_override("normal", UI_STYLE.card(Color(0.95, 0.96, 0.98), Color(0.78, 0.82, 0.9)))
		b.add_theme_stylebox_override("hover", UI_STYLE.card(Color(1.0, 1.0, 1.0), Color(0.55, 0.7, 0.95)))
		b.add_theme_stylebox_override("pressed", UI_STYLE.card(Color(0.88, 0.91, 0.96), Color(0.45, 0.6, 0.9)))
	else:
		b.add_theme_stylebox_override("normal", UI_STYLE.card(Color(0.16, 0.18, 0.23), Color(0.35, 0.4, 0.5)))
		b.add_theme_stylebox_override("hover", UI_STYLE.card(Color(0.22, 0.25, 0.32), Color(0.55, 0.65, 0.85)))
		b.add_theme_stylebox_override("pressed", UI_STYLE.card(Color(0.26, 0.3, 0.38), Color(0.7, 0.8, 1.0)))
	var icon := Label.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_override("font", emoji_font)
	icon.add_theme_font_size_override("font_size", int(size * 0.45))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var cnt := Label.new()
	cnt.name = "Count"
	cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cnt.offset_left = -size
	cnt.offset_top = -18.0
	cnt.offset_right = -4.0
	cnt.offset_bottom = -2.0
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.add_theme_font_size_override("font_size", 12)
	cnt.add_theme_color_override("font_color",
		Color(0.15, 0.18, 0.25) if white_bg else Color(0.85, 0.9, 1.0))
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cnt)
	return b


func _set_slot_view(button: Button, slot: Dictionary) -> void:
	var icon := button.get_node("Icon") as Label
	var cnt := button.get_node("Count") as Label
	if slot.is_empty():
		icon.text = ""
		cnt.text = ""
		button.tooltip_text = ""
	else:
		var id := String(slot["id"])
		var cfg: Dictionary = ITEM_DATA.get_item(id)
		icon.text = ITEM_DATA.icon_of(id)
		cnt.text = "×%d" % int(slot["count"])
		button.tooltip_text = "%s%s\n%s" % [
			String(cfg.get("icon", "")), String(cfg.get("name", id)),
			String(cfg.get("desc", "")),
		]


func _on_bag_down(index: int) -> void:
	inv_drag_bag = index
	inv_drag_hot = -1


func _on_hot_down(index: int) -> void:
	inv_drag_hot = index
	inv_drag_bag = -1


func _on_release() -> void:
	# 用 Control 取鼠标坐标，坐标系与 get_global_rect 一致（不受相机影响）
	var mp: Vector2 = hot_buttons[0].get_global_mouse_position()
	var hot_target := _slot_at(hot_buttons, mp)
	var bag_target := _slot_at(bag_buttons, mp) if is_open() else -1

	if inv_drag_bag >= 0:
		if hot_target >= 0:
			inventory.bag_to_hot(inv_drag_bag, hot_target)
	elif inv_drag_hot >= 0:
		if hot_target == inv_drag_hot:
			_use_hotbar_item(inv_drag_hot)          # 单击使用
		elif hot_target >= 0:
			inventory.swap_hot(inv_drag_hot, hot_target)
		elif bag_target >= 0:
			inventory.hot_to_bag(inv_drag_hot, bag_target)

	inv_drag_bag = -1
	inv_drag_hot = -1
	refresh()


func _slot_at(buttons: Array, pos: Vector2) -> int:
	for i in buttons.size():
		var b: Button = buttons[i]
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return i
	return -1


## 快捷键使用物品栏格：1~5 键对应从左到右五格
func use_hotbar_slot(index: int) -> void:
	if index < 0 or index >= INVENTORY.HOTBAR_SLOTS:
		return
	_use_hotbar_item(index)


func _use_hotbar_item(index: int) -> void:
	var slot: Dictionary = inventory.hot_slot(index)
	if slot.is_empty() or player == null:
		return
	var data: Dictionary = ITEM_DATA.get_item(String(slot["id"]))
	match String(data.get("use", "")):
		"instant":
			if data.has("heal"):
				player.heal(int(data["heal"]))
		"timed":
			var duration := float(data.get("duration", 0.0))
			for m in data.get("modifiers", []):
				player.apply_timed_modifier(String(m.get("attr", "")), String(m.get("op", "add")),
					float(m.get("value", 0.0)), duration)
			player.apply_item_timer(String(slot["id"]), duration)
		_:
			return
	inventory.consume_hot(index)
	refresh()
	item_used.emit()
	attr_changed.emit()
