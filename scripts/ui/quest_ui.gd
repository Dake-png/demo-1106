extends Node

## 左侧任务栏：可拖动、点击标题收起；显示每条任务的进度文案
## 任务数据 / 完成奖励在 quest_manager.gd 与 main，本模块只负责显示

const QUESTS := preload("res://scripts/quest_data.gd")

const BASE_TITLE_FONT := 30.0    # 标题基准字号（设置里的字体比例在此之上缩放）
const BASE_BODY_FONT := 28.0     # 任务条目基准字号

var host: Node              # hud_layer：面板挂载点 + toast tween
var quest_mgr
var quest_list: Array = []
var font_scale := 1.0
var kills := 0

var quest_panel
var quest_tab                    # 收起后贴左侧的竖直窄条
var quest_content
var quest_title                  # 可拖拽的标题栏
var quest_title_label
var quest_open := true
var quest_labels := {}           # id -> Label
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_moved := false


func build(parent: Node, mgr, list: Array, initial_font_scale: float) -> void:
	host = parent
	quest_mgr = mgr
	quest_list = list
	font_scale = initial_font_scale

	# 收起后贴左侧的竖直窄条（与任务栏平行），字号与展开时的标题一致
	quest_tab = Button.new()
	quest_tab.text = "任\n务"
	quest_tab.focus_mode = Control.FOCUS_NONE
	quest_tab.position = Vector2(0.0, 176.0)
	quest_tab.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	for state in ["normal", "hover", "pressed", "focus"]:
		quest_tab.add_theme_stylebox_override(state, _make_style())
	quest_tab.pressed.connect(_open)
	quest_tab.visible = false
	host.add_child(quest_tab)
	_apply_tab_style()

	# 深灰半透明面板：可拖动，点击标题栏收起；大小随文字自适应
	quest_panel = PanelContainer.new()
	quest_panel.position = Vector2(8.0, 128.0)
	quest_panel.add_theme_stylebox_override("panel", _make_style())
	host.add_child(quest_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	quest_panel.add_child(vb)

	# 标题栏：按住可拖动整块面板，单击收起
	quest_title = Control.new()
	quest_title.custom_minimum_size = Vector2(0, _title_font_size() + 6)
	quest_title.mouse_filter = Control.MOUSE_FILTER_STOP
	quest_title.mouse_default_cursor_shape = Control.CURSOR_DRAG
	quest_title.gui_input.connect(_on_title_input)
	vb.add_child(quest_title)

	quest_title_label = Label.new()
	quest_title_label.text = "◀ 任务📜  "
	quest_title_label.add_theme_font_size_override("font_size", _title_font_size())
	quest_title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	quest_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	quest_title_label.offset_bottom = _title_font_size()
	quest_title.add_child(quest_title_label)

	quest_content = VBoxContainer.new()
	quest_content.add_theme_constant_override("separation", 4)
	vb.add_child(quest_content)

	for st in quest_list:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", _body_font_size())
		lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF   # 不换行，面板宽度随最长一行自适应
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		quest_content.add_child(lbl)
		quest_labels[st["id"]] = lbl

	refresh(kills)
	quest_panel.reset_size()


func refresh(kill_count: int) -> void:
	kills = kill_count
	if quest_labels.is_empty():
		return
	for st in quest_list:
		var lbl: Label = quest_labels.get(st["id"])
		if lbl:
			lbl.text = _quest_text(st)
	if quest_panel:
		quest_panel.reset_size()


## 当前标题 / 正文字号（基准字号 × 设置里的字体比例）
func _title_font_size() -> int:
	return int(round(BASE_TITLE_FONT * font_scale))


func _body_font_size() -> int:
	return int(round(BASE_BODY_FONT * font_scale))


## 收起窄条：字号与展开时标题一致，尺寸随字号自适应（竖排两字）
func _apply_tab_style() -> void:
	if quest_tab == null:
		return
	var fs := _title_font_size()
	quest_tab.add_theme_font_size_override("font_size", fs)
	quest_tab.size = Vector2(fs + 16.0, fs * 2.2 + 16.0)


func apply_font_scale(scale: float) -> void:
	font_scale = scale
	if quest_title_label:
		quest_title_label.add_theme_font_size_override("font_size", _title_font_size())
		quest_title_label.offset_bottom = _title_font_size()
	if quest_title:
		quest_title.custom_minimum_size.y = _title_font_size() + 6
	for id in quest_labels:
		var ql: Label = quest_labels[id]
		if ql:
			ql.add_theme_font_size_override("font_size", _body_font_size())
	# 面板尺寸随新字号重新自适应，并保证不被挤出屏幕
	if quest_panel:
		quest_panel.reset_size()
		_move_panel(quest_panel.position)
	# 收起窄条同步字号与尺寸，并夹回屏幕内
	_apply_tab_style()
	if quest_tab:
		var vs := get_viewport().get_visible_rect().size
		quest_tab.position.y = clampf(quest_tab.position.y, 0.0, maxf(vs.y - quest_tab.size.y, 0.0))


# 顶部飘字：任务完成提示
func toast(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl.offset_left = -260.0
	lbl.offset_right = 260.0
	lbl.offset_top = 116.0
	lbl.offset_bottom = 148.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.45, 0.15))
	lbl.modulate.a = 0.0
	host.add_child(lbl)
	var tw: Tween = host.create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)


func _make_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.16, 0.16, 0.80)
	sb.border_color = Color(0.5, 0.5, 0.5, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_drag_moved = false
		_drag_offset = event.global_position - quest_panel.position


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var target: Vector2 = event.position - _drag_offset
		if target.distance_to(quest_panel.position) > 3.0:
			_drag_moved = true
		_move_panel(target)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		if not _drag_moved:
			_collapse()


func _move_panel(pos: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var ps: Vector2 = quest_panel.get_combined_minimum_size()
	quest_panel.position = Vector2(
		clampf(pos.x, 0.0, maxf(vs.x - ps.x, 0.0)),
		clampf(pos.y, 0.0, maxf(vs.y - ps.y, 0.0)))


func _open() -> void:
	quest_open = true
	quest_tab.visible = false
	var vs := get_viewport().get_visible_rect().size
	quest_panel.position.y = clampf(quest_tab.position.y, 0.0, maxf(vs.y - 120.0, 0.0))
	quest_panel.visible = true


func _collapse() -> void:
	quest_open = false
	quest_panel.visible = false
	var vs := get_viewport().get_visible_rect().size
	quest_tab.position.y = clampf(quest_panel.position.y, 0.0, maxf(vs.y - quest_tab.size.y, 0.0))
	quest_tab.visible = true


func _quest_text(st: Dictionary) -> String:
	var tag := "主线" if String(st["type"]) == "boss" else "任务"
	var head := "【%s】%s" % [tag, st["title"]]
	if bool(st["done"]):
		return head + "\n已完成"
	if String(st["type"]) == "boss" and kills < int(st.get("prereq_kills", 0)):
		return head + "\n前置：击杀敌人 %d/%d" % [kills, int(st["prereq_kills"])]
	return head + "\n%s\n奖励：%d 金币 · 等级+%d" % [
		_quest_objective(st), quest_mgr.quest_gold(st), int(st["reward_levels"]),
	]


## 各任务类型的进度文案
func _quest_objective(st: Dictionary) -> String:
	var p := int(st["progress"])
	var r := int(st["required"])
	match String(st["type"]):
		"kill":
			return "击杀敌人 %d/%d" % [p, r]
		"kill_type":
			var nm := String(QUESTS.ENEMY_TYPE_NAMES.get(int(st.get("enemy_type", -1)), "敌人"))
			return "击杀%s %d/%d" % [nm, p, r]
		"coin":
			return "收集金币 %d/%d" % [p, r]
		"survive":
			return "存活 %d/%d 秒" % [p, r]
		"boss":
			return "击杀%s %d/%d" % [String(st.get("target", "Boss")), p, r]
	return "进度 %d/%d" % [p, r]
