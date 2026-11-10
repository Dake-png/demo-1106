extends Node

## 商店：右上角入口按钮 + 弹窗（卡牌 / 武器 / 固定商品）
## 金币扣减与属性/武器栏刷新都通过信号交回 main，保持暂停逻辑集中在主控

signal open_requested                # 点了右上角「商店」
signal spend_requested(cost: int)    # 请 main 扣金币并刷新金币显示
signal closed                        # 弹窗已关闭
signal attr_changed                  # 需要刷新角色属性面板
signal weapons_changed               # 买到新武器，刷新右侧武器栏

const UI_STYLE := preload("res://scripts/ui/ui_style.gd")
const CARD_DATA := preload("res://scripts/card_data.gd")
const WEAPONS := preload("res://scripts/weapon_data.gd")

var player
var emoji_font: Font
var host: Node                  # hud_layer：弹窗挂载点，也用于暂停时创建 tween
var popup: Control
var cards_row: HBoxContainer
var weapon_row: HBoxContainer
var gold_label: Label
var status_label: Label
var gold := 0


# ========== 构建 ==========

func build_button(parent: Node) -> void:
	var btn := Button.new()
	btn.text = "商店"
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -104
	btn.offset_top = 14
	btn.offset_right = -16
	btn.offset_bottom = 48
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func(): open_requested.emit())
	parent.add_child(btn)


func build_popup(parent: Node, emoji: Font) -> void:
	host = parent
	emoji_font = emoji
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
	panel.add_theme_stylebox_override("panel", UI_STYLE.panel(Color(1.0, 0.98, 0.92), Color(0.75, 0.58, 0.15)))
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "商店"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.15, 0.1, 0.0))
	vb.add_child(title)

	gold_label = Label.new()
	gold_label.text = "金币: 0"
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", Color(0.15, 0.1, 0.0))
	vb.add_child(gold_label)

	cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 12)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(cards_row)

	# 武器售卖区：只列出尚未拥有的武器
	weapon_row = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 10)
	weapon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(weapon_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(bottom)

	_add_action(bottom, "回血药 +30", 5, _buy_heal)
	_add_action(bottom, "攻击 +12", 12, _buy_atk)
	_add_action(bottom, "攻速 +10%", 12, _buy_rate)
	_add_action(bottom, "关闭", -1, close)

	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.6, 0.1, 0.1))
	vb.add_child(status_label)


# ========== 开关（暂停由 main 负责） ==========

func is_open() -> bool:
	return popup != null and popup.visible


func open(p) -> void:
	player = p
	_populate_shop()
	set_gold(gold)
	set_notice("")
	popup.visible = true


func close() -> void:
	popup.visible = false
	closed.emit()


func set_gold(value: int) -> void:
	gold = value
	if gold_label:
		gold_label.text = "金币: %d" % value


func set_notice(text: String) -> void:
	if status_label:
		status_label.text = text


# ========== 固定商品 ==========

# price < 0 表示免费（关闭）
func _add_action(parent: Node, text: String, price: int, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text if price < 0 else "%s（%d金）" % [text, price]
	btn.custom_minimum_size = Vector2(124, 40)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func():
		if price >= 0 and gold < price:
			set_notice("金币不足！")
			return
		if not action.call():
			return
		if price >= 0:
			spend_requested.emit(price)
		attr_changed.emit()
	)
	parent.add_child(btn)


func _buy_heal() -> bool:
	if player.hp >= player.MAX_HP:
		set_notice("生命值已满")
		return false
	player.heal(30)
	set_notice("恢复 30 点生命")
	return true


func _buy_atk() -> bool:
	player.atk_power += 12.0
	set_notice("攻击力 +12")
	return true


func _buy_rate() -> bool:
	player.fire_cooldown = maxf(0.05, player.fire_cooldown * 0.9)
	set_notice("射击间隔 -10%")
	return true


# ========== 商品列表 ==========

func _populate_shop() -> void:
	for c in cards_row.get_children():
		cards_row.remove_child(c)
		c.queue_free()
	var used := []
	for i in range(3):
		var card: Dictionary = CARD_DATA.roll_card(used)
		used.append(card["id"])
		_make_shop_card(card)
	_animate_cards(cards_row.get_children())
	_populate_weapon_shop()


func _populate_weapon_shop() -> void:
	for c in weapon_row.get_children():
		weapon_row.remove_child(c)
		c.queue_free()
	for id in WEAPONS.CATALOG:
		if player.owned_weapons.has(id):
			continue
		var w: Dictionary = WEAPONS.get_weapon(id)
		var btn := Button.new()
		btn.text = "%s（%d金）" % [String(w["name"]), int(w["price"])]
		btn.custom_minimum_size = Vector2(150, 40)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_buy_weapon.bind(id, btn))
		weapon_row.add_child(btn)
	if weapon_row.get_child_count() == 0:
		var lbl := Label.new()
		lbl.text = "已拥有全部武器"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
		weapon_row.add_child(lbl)


func _buy_weapon(id: String, btn: Button) -> void:
	var w: Dictionary = WEAPONS.get_weapon(id)
	var price := int(w.get("price", 0))
	if gold < price:
		set_notice("金币不足！")
		return
	if not player.add_weapon(id):
		return
	spend_requested.emit(price)
	set_notice("已获得 %s，按数字键或右侧 UI 切换" % String(w["name"]))
	btn.queue_free()
	weapons_changed.emit()


func _make_shop_card(card: Dictionary) -> void:
	var rarity: String = String(card.get("rarity", "white"))
	var price: int = CARD_DATA.price_of(rarity)
	var col := CARD_DATA.color_of(rarity)
	var bg: Color = col["bg"]
	var fg: Color = col["fg"]
	var border: Color = col["border"]

	# 卡面只做展示，购买必须点击卡片底部的「购买」按钮
	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(140, 196)
	card_panel.pivot_offset = Vector2(70, 98)
	card_panel.add_theme_stylebox_override("panel", UI_STYLE.card(bg, border))
	cards_row.add_child(card_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card_panel.add_child(vb)

	var ic := Label.new()
	ic.text = String(card["icon"])
	ic.add_theme_font_override("font", emoji_font)
	ic.add_theme_font_size_override("font_size", 34)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ic)

	var t := Label.new()
	t.text = String(card["title"])
	t.add_theme_color_override("font_color", fg)
	t.add_theme_font_size_override("font_size", 15)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)

	var d := Label.new()
	d.text = String(card["desc"])
	d.add_theme_color_override("font_color", fg)
	d.add_theme_font_size_override("font_size", 13)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(d)

	var buy := Button.new()
	buy.text = "购买（%d 金）" % price
	buy.custom_minimum_size = Vector2(0, 34)
	buy.add_theme_font_size_override("font_size", 14)
	vb.add_child(buy)

	var card_id: String = String(card["id"])
	buy.pressed.connect(func():
		if buy.disabled:
			return
		if gold < price:
			set_notice("金币不足！")
			return
		spend_requested.emit(price)
		player.apply_upgrade(card_id)
		attr_changed.emit()
		buy.disabled = true
		buy.text = "已购买"
	)


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
