extends Node

## 设置按钮 / 设置弹窗 / 左下角帧率显示
## 由 main._ready 创建；暂停逻辑仍在 main（open_requested → _open_settings）

const UI_STYLE := preload("res://scripts/ui/ui_style.gd")

signal open_requested
signal close_requested
signal font_scale_changed(value: float)
signal combo_style_changed(enabled: bool, anchor_index: int)

var fps_label: Label
var popup: Control
var font_scale := 1.0
var combo_enabled := true
var combo_anchor := 0

var _resolution_opt: OptionButton
var _fullscreen_check: CheckButton
var _fps_opt: OptionButton
var _font_slider: HSlider
var _font_value_label: Label
var _combo_check: CheckButton
var _combo_pos_opt: OptionButton


func build(parent: Node, initial_font_scale: float) -> void:
	font_scale = initial_font_scale
	_build_fps_label(parent)
	_build_button(parent)
	_build_popup(parent)


func is_open() -> bool:
	return popup != null and popup.visible


func open() -> void:
	popup.move_to_front()
	popup.visible = true


func close() -> void:
	popup.visible = false


func _build_fps_label(parent: Node) -> void:
	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fps_label.offset_left = 10.0
	fps_label.offset_top = -30.0
	fps_label.offset_right = 120.0
	fps_label.offset_bottom = -6.0
	fps_label.add_theme_font_size_override("font_size", 14)
	fps_label.add_theme_color_override("font_color", Color(0.25, 0.25, 0.25))
	fps_label.text = "FPS: 0"
	parent.add_child(fps_label)


func _build_button(parent: Node) -> void:
	var btn := Button.new()
	btn.text = "⚙ 设置"
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -206.0
	btn.offset_top = 14.0
	btn.offset_right = -112.0
	btn.offset_bottom = 48.0
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func(): open_requested.emit())
	parent.add_child(btn)


func _build_popup(parent: Node) -> void:
	popup = Control.new()
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	parent.add_child(popup)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	popup.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI_STYLE.panel(Color(0.96, 0.98, 1.0), Color(0.35, 0.5, 0.7)))
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(380, 0)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25))
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	# 分辨率
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	res_row.add_child(_row_label("分辨率"))
	_resolution_opt = OptionButton.new()
	_resolution_opt.add_item("1280 x 720")
	_resolution_opt.add_item("1920 x 1080")
	_resolution_opt.selected = 1   # 默认 1920 x 1080（与 project.godot 一致）
	_resolution_opt.item_selected.connect(_on_resolution_selected)
	res_row.add_child(_resolution_opt)
	vb.add_child(res_row)

	# 全屏
	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 10)
	fs_row.add_child(_row_label("全屏"))
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_check)
	vb.add_child(fs_row)

	# 帧率上限
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 10)
	fps_row.add_child(_row_label("帧率"))
	_fps_opt = OptionButton.new()
	_fps_opt.add_item("30 帧")
	_fps_opt.add_item("60 帧")
	_fps_opt.add_item("120 帧")
	_fps_opt.selected = 1
	_fps_opt.item_selected.connect(_on_fps_selected)
	fps_row.add_child(_fps_opt)
	vb.add_child(fps_row)

	Engine.max_fps = 60

	# 界面字体大小（任务 / 属性 / 武器属性）
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 10)
	font_row.add_child(_row_label("字体大小"))
	_font_slider = HSlider.new()
	_font_slider.min_value = 0.8
	_font_slider.max_value = 1.6
	_font_slider.step = 0.05
	_font_slider.value = font_scale
	_font_slider.custom_minimum_size = Vector2(160, 0)
	_font_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_font_slider.value_changed.connect(_on_font_scale_changed)
	font_row.add_child(_font_slider)

	_font_value_label = Label.new()
	_font_value_label.text = "%d%%" % int(font_scale * 100.0)
	_font_value_label.add_theme_font_size_override("font_size", 14)
	_font_value_label.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25))
	_font_value_label.custom_minimum_size = Vector2(46, 0)
	font_row.add_child(_font_value_label)
	vb.add_child(font_row)

	# 连击显示：开关 + 位置
	var combo_row := HBoxContainer.new()
	combo_row.add_theme_constant_override("separation", 10)
	combo_row.add_child(_row_label("显示连击"))
	_combo_check = CheckButton.new()
	_combo_check.button_pressed = combo_enabled
	_combo_check.toggled.connect(_on_combo_toggled)
	combo_row.add_child(_combo_check)

	var combo_pos_opt := OptionButton.new()
	combo_pos_opt.add_item("顶部居中")
	combo_pos_opt.add_item("右上")
	combo_pos_opt.add_item("底部居中")
	combo_pos_opt.selected = combo_anchor
	combo_pos_opt.disabled = not combo_enabled
	combo_pos_opt.item_selected.connect(_on_combo_pos_selected)
	_combo_pos_opt = combo_pos_opt
	combo_row.add_child(combo_pos_opt)
	vb.add_child(combo_row)

	# 返回按钮
	var back := Button.new()
	back.text = "返回游戏"
	back.add_theme_font_size_override("font_size", 16)
	back.pressed.connect(func(): close_requested.emit())
	vb.add_child(back)


func _row_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25))
	lbl.custom_minimum_size = Vector2(90, 0)
	return lbl


func _on_resolution_selected(idx: int) -> void:
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = sizes[idx]
	if _fullscreen_check:
		_fullscreen_check.set_pressed_no_signal(false)


func _on_fullscreen_toggled(on: bool) -> void:
	var win := get_window()
	win.mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	if not on and _resolution_opt:
		_on_resolution_selected(_resolution_opt.selected)


func _on_fps_selected(idx: int) -> void:
	var caps: Array[int] = [30, 60, 120]
	Engine.max_fps = caps[idx]


func _on_font_scale_changed(value: float) -> void:
	font_scale = value
	if _font_value_label:
		_font_value_label.text = "%d%%" % int(round(font_scale * 100.0))
	font_scale_changed.emit(font_scale)


func _on_combo_toggled(on: bool) -> void:
	combo_enabled = on
	if _combo_pos_opt:
		_combo_pos_opt.disabled = not on
	combo_style_changed.emit(combo_enabled, combo_anchor)


func _on_combo_pos_selected(idx: int) -> void:
	combo_anchor = idx
	combo_style_changed.emit(combo_enabled, combo_anchor)
