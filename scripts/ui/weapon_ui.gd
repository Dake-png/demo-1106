extends Node

## 右侧武器切换栏 + 武器详情浮窗
## 由 main._ready 创建；点击切换仍调 player.equip_weapon，main 的 _on_weapon_switched 负责刷新属性

const UI_STYLE := preload("res://scripts/ui/ui_style.gd")
const RICH_TEXT := preload("res://scripts/ui/rich_text.gd")
const WEAPONS := preload("res://scripts/weapon_data.gd")
const EFFECTS := preload("res://scripts/effect_data.gd")

var player
var box: VBoxContainer
var info_panel
var info_label
var info_id := ""
var font_scale := 1.0
var emoji_font: Font


func build(parent: Node, p, emoji: Font, initial_font_scale: float) -> void:
	player = p
	emoji_font = emoji
	font_scale = initial_font_scale
	box = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	box.offset_left = -140.0
	box.offset_top = -70.0
	box.offset_right = -12.0
	box.offset_bottom = 70.0
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(box)
	refresh()


func refresh() -> void:
	if not box or not player:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for id in player.owned_weapons:
		var w: Dictionary = WEAPONS.get_weapon(id)
		var active: bool = id == player.weapon_id
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(128, 40)
		btn.focus_mode = Control.FOCUS_NONE
		# 未选中：灰底白字；已选中：蓝底白字
		var bg: Color = Color(0.25, 0.52, 0.90) if active else Color(0.55, 0.55, 0.55)
		var bd: Color = bg.darkened(0.28)
		btn.add_theme_stylebox_override("normal", UI_STYLE.card(bg, bd))
		btn.add_theme_stylebox_override("hover", UI_STYLE.card(bg.lightened(0.12), bd))
		btn.add_theme_stylebox_override("pressed", UI_STYLE.card(bg.darkened(0.12), bd))
		btn.add_theme_stylebox_override("focus", UI_STYLE.card(bg, bd))
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.text = "      " + String(w["name"])   # 给左侧 emoji 留位
		btn.pressed.connect(_on_weapon_click.bind(id))
		box.add_child(btn)

		# 武器 emoji 用系统 emoji 字体单独贴左侧
		var icon := Label.new()
		icon.text = String(w.get("icon", "🔫"))
		icon.add_theme_font_override("font", emoji_font)
		icon.add_theme_font_size_override("font_size", 19)
		icon.position = Vector2(10, 9)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)


func _on_weapon_click(id: String) -> void:
	if id == player.weapon_id:
		_show_info(id)   # 再次点击已装备武器 → 查看属性
	else:
		player.equip_weapon(id)
		close_info()


# 武器详情浮窗（点击已装备武器时显示倍率等属性）
func _show_info(id: String) -> void:
	if info_id == id and info_panel:
		close_info()   # 再点一次收起
		return
	close_info()
	var w: Dictionary = WEAPONS.get_weapon(id)
	var rarity_names := {"common": "白色", "rare": "蓝色", "gold": "金色"}
	var shape_names := {"circle": "圆形", "hex": "六边形"}
	var aoe := "无" if float(w.get("aoe_meter", 0.0)) <= 0.0 else "%.0f 米" % float(w["aoe_meter"])

	# 施加的 Effect：种类 / 触发概率 / 伤害系数 / 触发伤害（基础白 + 修饰蓝）
	var apply_lines := ""
	for a in w.get("apply", []):
		var eid := String(a.get("effect", ""))
		var ed: Dictionary = EFFECTS.get_effect(eid)
		var coef: float = float(a.get("coef", 0.0))
		var chance: float = float(a.get("chance", 0.0))
		var elem_mult: float = float(player.element_damage_mult(eid))
		var trig_base: int = int(round(float(player.atk_power) * float(w.get("atk_mult", 1.0)) * coef))
		var trig_eff: int = int(round(float(player.eff_atk()) * coef * elem_mult))
		var extra := ""
		if absf(elem_mult - 1.0) > 0.001 or trig_eff != trig_base:
			extra = "实 ×%.2f · 触发伤害 %d" % [elem_mult, trig_eff]
		apply_lines += "\n  " + RICH_TEXT.stat_text("%s%s 概率 %d%% · 系数 ×%.2f · 触发伤害 %d" % [
			String(ed.get("icon", "❔")), String(ed.get("name", eid)),
			int(round(chance * 100.0)), coef, trig_base,
		], extra)
	if apply_lines == "":
		apply_lines = "\n  [color=#ffffff]无[/color]"

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -480.0
	panel.offset_top = -150.0
	panel.offset_right = -150.0
	panel.offset_bottom = 160.0
	panel.add_theme_stylebox_override("panel", UI_STYLE.panel(Color(0.10, 0.12, 0.16), Color(0.25, 0.55, 0.95)))
	box.get_parent().add_child(panel)

	var rate_mul: float = float(player.mod_mul("attack_speed"))
	var atk_mul: float = float(player.mod_mul("phys_damage")) * float(player.mod_mul("phys_coef"))
	var multi_added: float = float(player.mod_add("multishot"))
	var crit_mul: float = float(player.mod_mul("crit_rate"))
	var lines: Array = [
		"[color=#ffffff]%s（%s）[/color]" % [String(w["name"]), rarity_names.get(String(w["rarity"]), "白色")],
		RICH_TEXT.stat_text("攻速倍率 ×%.2f" % float(w["rate_mult"]), RICH_TEXT.pct_diff(rate_mul - 1.0)),
		RICH_TEXT.stat_text("攻击倍率 ×%.2f" % float(w["atk_mult"]), RICH_TEXT.pct_diff(atk_mul - 1.0)),
		RICH_TEXT.stat_text("多重射击 ×%.2f" % float(w["multi_mult"]),
			("+%.1f" % multi_added) if absf(multi_added) > 0.001 else ""),
		RICH_TEXT.stat_text("基础暴击 +%d%%" % int(float(w["crit_add"]) * 100.0), RICH_TEXT.pct_diff(crit_mul - 1.0)),
		"[color=#ffffff]范围伤害 %s[/color]" % aoe,
		"[color=#ffffff]子弹 %s %dmm[/color]" % [
			shape_names.get(String(w["bullet_shape"]), "圆形"), int(WEAPONS.bullet_mm(w))],
		"[color=#ffffff]穿透 %d[/color]" % int(w["pierce"]),
		"[color=#ffffff]元素效果[/color]" + apply_lines,
	]

	var lbl := RICH_TEXT.make_rich_row(14, true, font_scale)
	lbl.text = "\n".join(PackedStringArray(lines))
	panel.add_child(lbl)

	info_panel = panel
	info_label = lbl
	info_id = id


func close_info() -> void:
	if info_panel:
		info_panel.queue_free()
		info_panel = null
		info_label = null
	info_id = ""


func apply_font_scale(scale: float) -> void:
	font_scale = scale
	if info_label:
		info_label.add_theme_font_size_override("normal_font_size", int(round(14 * scale)))
		info_panel.custom_minimum_size = Vector2(230.0 * scale, 0)
