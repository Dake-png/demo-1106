extends Node

## 顶部 HUD（血量/护盾/经验/金币/击杀/等级/时间）+ Boss 血条 + 底部 Buff 栏
## 由 main._ready 创建；main 只调用 set_* / update_* 更新显示

const UI_STYLE := preload("res://scripts/ui/ui_style.gd")
const EFFECTS := preload("res://scripts/effect_data.gd")
const ITEM_DATA := preload("res://scripts/item_data.gd")

var hp_bar: ProgressBar
var shield_bar: ProgressBar
var exp_bar: ProgressBar
var score_label: Label
var kill_label: Label
var combo_label: Label
var combo_enabled := true
var combo_anchor := 0       # 0 顶部居中 / 1 右上 / 2 底部居中
var level_label: Label
var time_label: Label

var boss_panel: VBoxContainer
var boss_hp_bar: ProgressBar
var boss_shield_bar: ProgressBar
var boss_effect_label: Label
var boss_name_label: Label

var buff_box: HBoxContainer
var dash_chip: PanelContainer
var dash_label: Label
var buff_chips := {}     # "effect:buff|debuff" -> [panel, label]
var item_chips := {}     # 道具 buff：item_id -> [panel, label]

var emoji_font: Font


func build(parent: Node, emoji: Font) -> void:
	emoji_font = emoji
	_build_top(parent)
	_build_boss(parent)
	_build_buffs(parent)


# ========== 顶部：血条 / 数值 ==========

func _build_top(parent: Node) -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(16, 16)
	parent.add_child(root)

	var toprow := HBoxContainer.new()
	toprow.add_theme_constant_override("separation", 16)
	root.add_child(toprow)

	# 左侧：护盾条（蓝）+ 血条（红）+ 下方细经验条（黄）
	var barbox := VBoxContainer.new()
	barbox.add_theme_constant_override("separation", 2)
	toprow.add_child(barbox)

	shield_bar = ProgressBar.new()
	shield_bar.custom_minimum_size = Vector2(220, 8)
	shield_bar.show_percentage = false
	# 透明底：只显示蓝色填充，护盾越多蓝线越长
	shield_bar.add_theme_stylebox_override("background", UI_STYLE.bar(Color(0, 0, 0, 0)))
	shield_bar.add_theme_stylebox_override("fill", UI_STYLE.bar(Color(0.3, 0.65, 1.0)))
	barbox.add_child(shield_bar)

	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(220, 18)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", UI_STYLE.bar(Color(0.9, 0.9, 0.9)))
	hp_bar.add_theme_stylebox_override("fill", UI_STYLE.bar(Color(0.85, 0.2, 0.2)))
	barbox.add_child(hp_bar)

	exp_bar = ProgressBar.new()
	exp_bar.custom_minimum_size = Vector2(220, 5)   # 细黄线
	exp_bar.show_percentage = false
	exp_bar.add_theme_stylebox_override("background", UI_STYLE.bar(Color(0.9, 0.9, 0.9)))
	exp_bar.add_theme_stylebox_override("fill", UI_STYLE.bar(Color(0.95, 0.8, 0.1)))
	barbox.add_child(exp_bar)

	score_label = _make_value_label("金币: 0")
	toprow.add_child(score_label)

	kill_label = _make_value_label("击杀: 0")
	toprow.add_child(kill_label)

	level_label = _make_value_label("Lv.1")
	toprow.add_child(level_label)

	time_label = _make_value_label("⏱ 00:00")
	toprow.add_child(time_label)

	# 连杀 Combo：位置与开关由设置控制，击杀时放大回弹
	combo_label = Label.new()
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_label.add_theme_font_size_override("font_size", 34)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.15))
	combo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	combo_label.add_theme_constant_override("outline_size", 6)
	combo_label.text = ""
	parent.add_child(combo_label)
	_apply_combo_layout()


func _make_value_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", Color.BLACK)
	lbl.text = text
	return lbl


# ========== Boss 血条（画面上侧居中） ==========

func _build_boss(parent: Node) -> void:
	boss_panel = VBoxContainer.new()
	boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_left = -200
	boss_panel.offset_right = 200
	boss_panel.offset_top = 52
	boss_panel.offset_bottom = 108
	boss_panel.add_theme_constant_override("separation", 2)
	boss_panel.visible = false
	parent.add_child(boss_panel)

	boss_name_label = Label.new()
	boss_name_label.text = ""
	boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name_label.add_theme_font_size_override("font_size", 18)
	boss_name_label.add_theme_color_override("font_color", Color(0.6, 0.05, 0.05))
	boss_panel.add_child(boss_name_label)

	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.custom_minimum_size = Vector2(400, 14)
	boss_hp_bar.show_percentage = false
	boss_hp_bar.add_theme_stylebox_override("background", UI_STYLE.bar(Color(0.9, 0.9, 0.9)))
	boss_hp_bar.add_theme_stylebox_override("fill", UI_STYLE.bar(Color(0.85, 0.15, 0.15)))
	boss_panel.add_child(boss_hp_bar)

	boss_shield_bar = ProgressBar.new()
	boss_shield_bar.custom_minimum_size = Vector2(400, 6)
	boss_shield_bar.show_percentage = false
	boss_shield_bar.add_theme_stylebox_override("background", UI_STYLE.bar(Color(0.9, 0.9, 0.9)))
	boss_shield_bar.add_theme_stylebox_override("fill", UI_STYLE.bar(Color(0.3, 0.65, 1.0)))
	boss_panel.add_child(boss_shield_bar)

	# 血条下方：debuff 图标 + 层数
	boss_effect_label = Label.new()
	boss_effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_effect_label.add_theme_font_override("font", emoji_font)
	boss_effect_label.add_theme_font_size_override("font_size", 15)
	boss_effect_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.1))
	boss_panel.add_child(boss_effect_label)


# ========== 底部 Buff 栏 ==========

func _build_buffs(parent: Node) -> void:
	buff_box = HBoxContainer.new()
	buff_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	buff_box.offset_left = -240
	buff_box.offset_right = 240
	buff_box.offset_top = -110
	buff_box.offset_bottom = -70
	buff_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buff_box.add_theme_constant_override("separation", 10)
	parent.add_child(buff_box)

	# 冲刺只是冷却指示，不属于 Effect，固定放在最右侧
	var pair := _make_buff_chip(Color(0.2, 0.45, 0.8))
	dash_chip = pair[0]
	dash_label = pair[1]
	dash_chip.visible = false
	buff_box.add_child(dash_chip)


func _make_buff_chip(c: Color) -> Array:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(lbl)
	return [panel, lbl]


func update_buffs(player) -> void:
	if not player:
		return
	_sync_effect_chips(player)
	_sync_item_chips(player)
	var show_dash: bool = player.dash_cooldown > 0.0
	dash_chip.visible = show_dash
	if show_dash:
		dash_label.text = "冲刺 %.1fs" % player.dash_cooldown


# 底部 Buff 栏：按玩家 Effect 容器实时生成 / 回收图标块
func _sync_effect_chips(player) -> void:
	if not player.effects:
		return
	var seen := {}
	for e in player.effects.active():
		var positive := bool(e["positive"])
		var key := "%s:%s" % [String(e["id"]), "buff" if positive else "debuff"]
		seen[key] = true
		if not buff_chips.has(key):
			var chip := _make_buff_chip(Color(0.22, 0.45, 0.85) if positive else Color(0.78, 0.2, 0.2))
			buff_chips[key] = chip
			buff_box.add_child(chip[0])
			buff_box.move_child(dash_chip, buff_box.get_child_count() - 1)
		var cfg: Dictionary = EFFECTS.get_effect(String(e["id"]))
		var lbl: Label = buff_chips[key][1]
		lbl.text = "%s%s x%d %.1fs" % [
			String(cfg.get("icon", "")), String(cfg.get("name", e["id"])),
			int(e["stacks"]), float(e["time"])
		]
	for key in buff_chips.keys():
		if not seen.has(key):
			buff_chips[key][0].queue_free()
			buff_chips.erase(key)


# 道具 buff：使用后按剩余时间显示在底部 buff 栏
func _sync_item_chips(player) -> void:
	var seen := {}
	for id in player.item_timers.keys():
		var key := String(id)
		seen[key] = true
		if not item_chips.has(key):
			var chip := _make_buff_chip(Color(0.2, 0.6, 0.56))
			item_chips[key] = chip
			buff_box.add_child(chip[0])
			buff_box.move_child(dash_chip, buff_box.get_child_count() - 1)
		var cfg: Dictionary = ITEM_DATA.get_item(key)
		var lbl: Label = item_chips[key][1]
		lbl.text = "%s%s %.1fs" % [
			String(cfg.get("icon", "")), String(cfg.get("name", key)),
			float(player.item_timers[id]),
		]
	for key in item_chips.keys():
		if not seen.has(key):
			item_chips[key][0].queue_free()
			item_chips.erase(key)


# Boss 血条下方：全部 effect 图标 + 层数（含磁力等 buff）
func update_boss_effects(boss_node) -> void:
	if boss_effect_label == null:
		return
	if not is_instance_valid(boss_node) or not boss_node.effects:
		boss_effect_label.text = ""
		return
	var text := ""
	for e in boss_node.effects.active():
		var cfg: Dictionary = EFFECTS.get_effect(String(e["id"]))
		text += "%sx%d " % [String(cfg.get("icon", "❔")), int(e["stacks"])]
	boss_effect_label.text = text.strip_edges()


# ========== 数值更新（main 调用） ==========

func set_hp(cur: int, max_v: int) -> void:
	hp_bar.max_value = max_v
	hp_bar.value = cur


func set_shield(cur: int, max_v: int) -> void:
	# 没有护盾上限时不显示蓝条
	if max_v <= 0:
		shield_bar.visible = false
		return
	shield_bar.visible = true
	shield_bar.max_value = max_v
	shield_bar.value = clampi(cur, 0, max_v)


func set_exp(cur: int, next: int) -> void:
	exp_bar.max_value = next
	exp_bar.value = cur


func set_score(value: int) -> void:
	score_label.text = "金币: %d" % value


func set_kills(value: int) -> void:
	kill_label.text = "击杀: %d" % value


## 连杀提示：2 连以上显示，每次击杀放大回弹
func set_combo(count: int) -> void:
	if combo_label == null:
		return
	if not combo_enabled or count < 2:
		combo_label.text = ""
		return
	combo_label.text = "COMBO ×%d" % count
	combo_label.pivot_offset = combo_label.size * 0.5
	combo_label.scale = Vector2.ONE * 1.25
	var tw: Tween = combo_label.create_tween()
	tw.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 设置项：是否显示连击 + 显示位置（0 顶部居中 / 1 右上 / 2 底部居中）
func set_combo_style(enabled: bool, anchor_index: int) -> void:
	combo_enabled = enabled
	combo_anchor = clampi(anchor_index, 0, 2)
	_apply_combo_layout()


func _apply_combo_layout() -> void:
	if combo_label == null:
		return
	match combo_anchor:
		1:  # 右上（避开顶部数值区，放在其下方）
			combo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			combo_label.offset_left = -280.0
			combo_label.offset_right = -20.0
			combo_label.offset_top = 56.0
			combo_label.offset_bottom = 100.0
		2:  # 底部居中
			combo_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			combo_label.offset_left = 0.0
			combo_label.offset_right = 0.0
			combo_label.offset_top = -130.0
			combo_label.offset_bottom = -86.0
		_:  # 顶部居中
			combo_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
			combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			combo_label.offset_left = 0.0
			combo_label.offset_right = 0.0
			combo_label.offset_top = 78.0
			combo_label.offset_bottom = 122.0
	if not combo_enabled:
		combo_label.text = ""


func set_level(value: int) -> void:
	level_label.text = "Lv.%d" % value


func set_time(seconds: float) -> void:
	var time_text := "⏱ %02d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	if time_label.text != time_text:
		time_label.text = time_text


func set_boss_stats(hp: int, max_hp: int, shield: int, max_shield: int) -> void:
	boss_panel.visible = true
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = hp
	boss_shield_bar.max_value = max_shield
	boss_shield_bar.value = shield
