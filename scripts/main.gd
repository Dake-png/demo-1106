extends Node2D

## 游戏主控：所有 UI 代码动态创建

const ARMOR := preload("res://scripts/armor.gd")

var player
var score := 0
var kills := 0
var combo := 0                          # 连杀计数（5 秒内持续击杀累积）
var combo_timer := 0.0
const COMBO_WINDOW := 5.0
const COMBO_COIN_STEP := 10             # 每 10 连杀多掉 1 金币，最多 3 个
const COMBO_COIN_MAX := 3

# UI 引用
var hud: Node                 # HUD/Boss 条/Buff 栏（scripts/ui/hud_ui.gd）
var atk_label
var rate_label
var multi_label
var crit_label
var crit_dmg_label
var armor_label
var weapon_label
var attr_hp_label
var hud_layer

# 升级选卡（实现在 scripts/ui/upgrade_ui.gd）
var upgrade_ui: Node

# 商店（实现在 scripts/ui/shop_ui.gd）
var shop_ui: Node

# 武器切换 UI（右侧边，实现在 scripts/ui/weapon_ui.gd）
var weapon_ui: Node

# 任务系统（左侧边，逻辑在 quest_manager.gd，显示在 scripts/ui/quest_ui.gd）
var quest_mgr: Node
var quest_ui: Node
var pending_level_cards := 0      # 连续升级时排队的选卡次数
var dmg_numbers: Node            # 伤害飘字（实现在 scripts/damage_numbers.gd）
var start_menu                 # 开始菜单遮罩
var save_btn                   # 存档（继续游戏）按钮

# 拆分出的子系统（scripts/combat.gd / spawner.gd / save_system.gd）
var combat: Node
var spawner: Node
var save_system: Node

# Boss 逻辑（血条控件在 hud_ui.gd）
var boss_node
var boss_spawned := false
var boss_kills_mark := 0      # 下一个 Boss 的击杀数门槛基准
var last_boss_id := ""        # 上一次刷出的 Boss，避免连续重复

# --- 物品存储系统 ---
var inventory = INVENTORY.new()
var inventory_ui: Node       # 物品栏 + 背包弹窗（scripts/ui/inventory_ui.gd）

var attr_panel
var attr_content
var attr_toggle
var attr_open := true

# 设置 / 帧率（实现在 scripts/ui/settings_ui.gd）
var settings_ui: Node
var ui_font_scale := 1.0
var _fps_timer := 0.0
var _ui_timer := 0.0     # HUD 文本刷新节流（每 0.1s 一次）

var elapsed := 0.0
var sfx_player: Node

const RULE_CONFIG := preload("res://scripts/rule_config.gd")
const INVENTORY := preload("res://scripts/inventory.gd")
const QUEST_MANAGER := preload("res://scripts/quest_manager.gd")
const SFX_PLAYER := preload("res://scripts/sfx_player.gd")
const DAMAGE_NUMBERS := preload("res://scripts/damage_numbers.gd")
const UI_STYLE := preload("res://scripts/ui/ui_style.gd")
const UI_SETTINGS := preload("res://scripts/ui/settings_ui.gd")
const UI_WEAPON := preload("res://scripts/ui/weapon_ui.gd")
const UI_HUD := preload("res://scripts/ui/hud_ui.gd")
const UI_SHOP := preload("res://scripts/ui/shop_ui.gd")
const UI_INVENTORY := preload("res://scripts/ui/inventory_ui.gd")
const UI_QUEST := preload("res://scripts/ui/quest_ui.gd")
const UI_UPGRADE := preload("res://scripts/ui/upgrade_ui.gd")
const RICH_TEXT := preload("res://scripts/ui/rich_text.gd")

const PlayerScene := preload("res://scenes/player.tscn")
const BOSS_DATA   := preload("res://scripts/boss_data.gd")
const COMBAT      := preload("res://scripts/combat.gd")
const SPAWNER     := preload("res://scripts/spawner.gd")
const SAVE_SYSTEM := preload("res://scripts/save_system.gd")
const GROUND      := preload("res://scripts/ground.gd")

const WORLD_HALF := 800.0

## 2.5D 三层结构开关：false 时 World/Fx 直接指向 self，等价于旧版单层结构（排障用）
const USE_WORLD_LAYERS := true

# 三层结构：Ground（地面，最底）/ World（实体，按脚点 Y 排序）/ Fx（子弹与特效，最上）
var ground_layer: Node2D
var world_layer: Node2D
var fx_layer: Node2D


func _ready() -> void:
	randomize()
	# 全局事件：敌人 / Boss / 掉落物通过 EventBus 广播，不再直接调父节点 _on_*
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.boss_died.connect(_on_boss_died)
	EventBus.effect_damage.connect(_on_effect_damage)
	EventBus.coin_picked.connect(_on_coin_picked)
	EventBus.exp_orb_picked.connect(_on_exp_orb_picked)
	EventBus.item_picked.connect(_on_item_picked)
	_build_world_layers()
	sfx_player = SFX_PLAYER.new()
	add_child(sfx_player)
	dmg_numbers = DAMAGE_NUMBERS.new()
	fx_layer.add_child(dmg_numbers)
	_build_hud()
	_build_inventory_ui()
	_build_shop_btn()
	settings_ui = UI_SETTINGS.new()
	add_child(settings_ui)
	settings_ui.build(hud_layer, ui_font_scale)
	settings_ui.open_requested.connect(_open_settings)
	settings_ui.close_requested.connect(_close_settings)
	settings_ui.font_scale_changed.connect(_on_font_scale_changed)
	settings_ui.combo_style_changed.connect(_on_combo_style_changed)
	_build_attr_panel()
	_build_upgrade_popup()
	_build_shop_popup()
	_init_quests()
	_build_quest_ui()
	_pick_next_boss()   # 开局就决定首个 Boss，任务栏直接显示目标

	# 生成 / 存档子系统
	spawner = SPAWNER.new()
	add_child(spawner)
	spawner.setup(world_layer, WORLD_HALF, fx_layer)
	save_system = SAVE_SYSTEM.new()
	add_child(save_system)

	_spawn_player()
	combat = COMBAT.new()
	add_child(combat)
	combat.setup(fx_layer, player, dmg_numbers, _play_sfx)

	inventory_ui.set_player(player)
	_build_weapon_ui()
	hud.set_hp(player.hp, player.MAX_HP)
	_on_shield_changed(int(player.shield), int(player.SHIELD_MAX))
	hud.set_exp(0, player.exp_to_next)

	# 生成循环在 spawner 内
	spawner.start_timers()
	for i in range(5): spawner.spawn_coin()
	for i in range(3): spawner.spawn_enemy()

	_refresh_attr_panel()
	_build_start_menu()   # 最后构建，盖在所有 HUD 之上


# ========== 音效（实现在 scripts/sfx_player.gd） ==========

func _play_sfx(name: String) -> void:
	sfx_player.play(name)


# ========== 世界分层（2.5D 脚点 Y 排序） ==========

## 建立 Ground / World / Fx 三层：地面最底、实体按脚点 Y 排序、子弹与特效最上
func _build_world_layers() -> void:
	if not USE_WORLD_LAYERS:
		world_layer = self
		fx_layer = self
		return

	ground_layer = GROUND.new()
	ground_layer.name = "Ground"
	ground_layer.z_index = -100
	add_child(ground_layer)
	ground_layer.setup(WORLD_HALF)

	world_layer = Node2D.new()
	world_layer.name = "World"
	world_layer.y_sort_enabled = true
	add_child(world_layer)

	fx_layer = Node2D.new()
	fx_layer.name = "Fx"
	fx_layer.z_index = 100
	add_child(fx_layer)


# ========== 动态构建 UI ==========

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)
	hud = UI_HUD.new()
	add_child(hud)
	hud.build(hud_layer, _emoji_font())


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	return UI_STYLE.panel(bg, border)


# ========== 武器切换 UI（实现在 scripts/ui/weapon_ui.gd） ==========

func _build_weapon_ui() -> void:
	weapon_ui = UI_WEAPON.new()
	add_child(weapon_ui)
	weapon_ui.build(hud_layer, player, _emoji_font(), ui_font_scale)


func _refresh_weapon_ui() -> void:
	if weapon_ui:
		weapon_ui.refresh()


func _close_weapon_info() -> void:
	if weapon_ui:
		weapon_ui.close_info()


func _on_weapon_switched(_id: String) -> void:
	_close_weapon_info()
	_refresh_weapon_ui()
	_refresh_attr_panel()


# ========== 任务系统（左侧边） ==========

func _init_quests() -> void:
	quest_mgr = QUEST_MANAGER.new()
	add_child(quest_mgr)            # _ready 内自动 reset 出任务列表
	quest_mgr.changed.connect(_refresh_quest_ui)
	quest_mgr.completed.connect(_on_quest_completed)


func _build_quest_ui() -> void:
	quest_ui = UI_QUEST.new()
	add_child(quest_ui)
	quest_ui.build(hud_layer, quest_mgr, quest_mgr.quests, ui_font_scale)


func _refresh_quest_ui() -> void:
	if quest_ui:
		quest_ui.refresh(kills)


## QuestManager 完成任务 → 发奖励 + 提示
func _on_quest_completed(title: String, gold: int, levels: int, is_main: bool) -> void:
	score += gold
	_update_shop_gold()
	player.gain_levels(levels)
	_play_sfx("coin")
	if is_main:
		quest_ui.toast("主线完成：%s（+%d 金币，等级+%d）" % [title, gold, levels])
	else:
		quest_ui.toast("任务完成：%s（+%d 金币，等级+%d）" % [title, gold, levels])
	_refresh_quest_ui()


## 决定下一个出场的 Boss（与上一个不同），并同步主线任务显示
func _pick_next_boss() -> void:
	last_boss_id = BOSS_DATA.random_id(last_boss_id)
	quest_mgr.set_main_boss(last_boss_id)


# ========== 商店 ==========

func _build_shop_btn() -> void:
	shop_ui = UI_SHOP.new()
	add_child(shop_ui)
	shop_ui.open_requested.connect(_open_shop)
	shop_ui.spend_requested.connect(_on_shop_spend)
	shop_ui.closed.connect(_on_shop_closed)
	shop_ui.attr_changed.connect(_refresh_attr_panel)
	shop_ui.weapons_changed.connect(_on_shop_weapons_changed)
	shop_ui.build_button(hud_layer)


func _open_settings() -> void:
	if upgrade_ui.is_open() or (shop_ui and shop_ui.is_open()) or settings_ui.is_open():
		return
	if inventory_ui and inventory_ui.is_open():
		return
	settings_ui.open()
	_sync_pause()


func _close_settings() -> void:
	settings_ui.close()
	_sync_pause()


## 统一的暂停状态：任一弹窗/菜单可见即暂停，避免互相覆盖
func _sync_pause() -> void:
	var should_pause := false
	if start_menu and start_menu.visible: should_pause = true
	if upgrade_ui and upgrade_ui.is_open(): should_pause = true
	if settings_ui and settings_ui.is_open(): should_pause = true
	if shop_ui and shop_ui.is_open(): should_pause = true
	if inventory_ui and inventory_ui.is_open(): should_pause = true
	get_tree().paused = should_pause


# ========== 开始菜单 / 存档 ==========

func _build_start_menu() -> void:
	start_menu = Control.new()
	start_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(start_menu)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_menu.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -160.0
	panel.offset_top = -175.0
	panel.offset_right = 160.0
	panel.offset_bottom = 175.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(1.0, 0.98, 0.90), Color(1.0, 0.80, 0.30)))
	start_menu.add_child(panel)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "开始菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.15, 0.1, 0.05))
	vb.add_child(title)

	_add_menu_button(vb, "开始游戏", _start_new_game)
	save_btn = _add_menu_button(vb, "存档", _continue_game)
	var has_save := FileAccess.file_exists(save_system.SAVE_PATH)
	save_btn.text = "继续游戏（存档）" if has_save else "存档（无记录）"
	save_btn.disabled = not has_save
	_add_menu_button(vb, "设置", _open_settings)
	_add_menu_button(vb, "退出游戏", _quit_game)

	get_tree().paused = true


func _add_menu_button(parent: VBoxContainer, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(240, 46)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


func _start_new_game() -> void:
	start_menu.visible = false
	_sync_pause()


func _continue_game() -> void:
	if not _load_game():
		return
	start_menu.visible = false
	_sync_pause()


func _quit_game() -> void:
	get_tree().quit()


# ========== 存档（写盘 / 读盘实现在 scripts/save_system.gd） ==========

## 自动存档（每 5 秒一次）：数据组装在 main，写盘在 save_system
func _save_game() -> void:
	if player == null or player.dead:
		return
	save_system.save_game({
		"player": player,
		"quest_mgr": quest_mgr,
		"inventory": inventory,
		"score": score,
		"kills": kills,
		"elapsed": elapsed,
		"boss_kills_mark": boss_kills_mark,
		"last_boss_id": last_boss_id,
	})


func _load_game() -> bool:
	var data: Dictionary = save_system.load_game(player, quest_mgr, inventory, last_boss_id)
	if not data.get("ok", false):
		return false

	score = int(data["score"])
	kills = int(data["kills"])
	elapsed = float(data["elapsed"])

	# Boss 进度：换算阈值不能再按“当前击杀数”重置，否则读档后永远差 100 杀
	boss_spawned = false
	boss_kills_mark = int(data["boss_kills_mark"])
	last_boss_id = String(data["last_boss_id"])
	if last_boss_id == "":
		_pick_next_boss()
	else:
		quest_mgr.set_main_boss(last_boss_id)

	_refresh_inventory_ui()
	_update_shop_gold()
	hud.set_kills(kills)
	hud.set_level(player.level)
	hud.set_hp(player.hp, player.MAX_HP)
	player.health_changed.emit(player.hp, player.MAX_HP)
	player.shield_changed.emit(int(player.shield), int(player.SHIELD_MAX))
	_on_shield_changed(int(player.shield), int(player.SHIELD_MAX))
	player.exp_changed.emit(player.exp, player.exp_to_next)
	player.weapon_switched.emit(player.weapon_id)
	_refresh_quest_ui()
	_refresh_attr_panel()
	_refresh_weapon_ui()
	return true


func _on_font_scale_changed(value: float) -> void:
	ui_font_scale = value
	_apply_ui_fonts()


## 设置里的连击显示：开关 + 位置，立刻刷新 HUD 上的连击提示
func _on_combo_style_changed(enabled: bool, anchor_index: int) -> void:
	hud.set_combo_style(enabled, anchor_index)
	hud.set_combo(combo)


## 把字号比例应用到任务栏 / 属性面板 / 武器属性浮窗
func _apply_ui_fonts() -> void:
	if quest_ui:
		quest_ui.apply_font_scale(ui_font_scale)
	if attr_content:
		for c in attr_content.get_children():
			if c is RichTextLabel and c.has_meta("base_font"):
				c.add_theme_font_size_override("normal_font_size",
					int(round(int(c.get_meta("base_font")) * ui_font_scale)))
	if weapon_ui:
		weapon_ui.apply_font_scale(ui_font_scale)


func _build_shop_popup() -> void:
	shop_ui.build_popup(hud_layer, _emoji_font())


func _open_shop() -> void:
	if upgrade_ui.is_open() or (shop_ui and shop_ui.is_open()) or settings_ui.is_open():
		return
	if inventory_ui and inventory_ui.is_open():
		return
	shop_ui.set_gold(score)
	shop_ui.open(player)
	_sync_pause()


func _on_shop_spend(cost: int) -> void:
	score -= cost
	_update_shop_gold()
	_play_sfx("coin")


func _on_shop_closed() -> void:
	_sync_pause()
	_refresh_attr_panel()


func _on_shop_weapons_changed() -> void:
	_refresh_weapon_ui()
	_refresh_attr_panel()


func _update_shop_gold() -> void:
	if shop_ui:
		shop_ui.set_gold(score)
	hud.set_score(score)


func _build_attr_panel() -> void:
	attr_panel = PanelContainer.new()
	attr_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	attr_panel.offset_left = -190.0
	attr_panel.offset_top = -260.0
	attr_panel.offset_right = -10.0
	attr_panel.offset_bottom = -10.0
	hud_layer.add_child(attr_panel)

	var vb := VBoxContainer.new()
	attr_panel.add_child(vb)

	# 折叠按钮：展开时是标题栏，收起时是右下角小方块
	attr_toggle = Button.new()
	attr_toggle.text = "📊属性⇲"
	attr_toggle.focus_mode = Control.FOCUS_NONE
	attr_toggle.add_theme_font_size_override("font_size", 16)
	attr_toggle.add_theme_color_override("font_color", Color.WHITE)
	attr_toggle.add_theme_color_override("font_hover_color", Color.WHITE)
	attr_toggle.add_theme_stylebox_override("normal", UI_STYLE.card(Color(0.30, 0.30, 0.30), Color(0.55, 0.55, 0.55)))
	attr_toggle.add_theme_stylebox_override("hover", UI_STYLE.card(Color(0.38, 0.38, 0.38), Color(0.65, 0.65, 0.65)))
	attr_toggle.add_theme_stylebox_override("pressed", UI_STYLE.card(Color(0.25, 0.25, 0.25), Color(0.65, 0.65, 0.65)))
	attr_toggle.pressed.connect(_toggle_attr_panel)
	vb.add_child(attr_toggle)

	attr_content = VBoxContainer.new()
	vb.add_child(attr_content)

	attr_content.add_child(HSeparator.new())

	weapon_label = _make_rich_row(16); attr_content.add_child(weapon_label)
	atk_label = _make_rich_row(16); attr_content.add_child(atk_label)
	rate_label = _make_rich_row(16); attr_content.add_child(rate_label)
	multi_label = _make_rich_row(16); attr_content.add_child(multi_label)
	crit_label = _make_rich_row(16); attr_content.add_child(crit_label)
	crit_dmg_label = _make_rich_row(16); attr_content.add_child(crit_dmg_label)
	armor_label = _make_rich_row(16); attr_content.add_child(armor_label)
	attr_hp_label = _make_rich_row(16); attr_content.add_child(attr_hp_label)


func _toggle_attr_panel() -> void:
	attr_open = not attr_open
	attr_content.visible = attr_open
	attr_toggle.text = "📊 属性 ▼" if attr_open else "📊"
	if attr_open:
		attr_toggle.custom_minimum_size = Vector2(0, 0)
		attr_panel.offset_left = -190.0
		attr_panel.offset_top = -290.0
		attr_panel.offset_right = -10.0
		attr_panel.offset_bottom = -10.0
	else:
		attr_toggle.custom_minimum_size = Vector2(56, 56)
		attr_panel.offset_left = -70.0
		attr_panel.offset_top = -70.0
		attr_panel.offset_right = -10.0
		attr_panel.offset_bottom = -10.0


func _build_upgrade_popup() -> void:
	upgrade_ui = UI_UPGRADE.new()
	add_child(upgrade_ui)
	upgrade_ui.card_chosen.connect(_on_upgrade_card_chosen)
	upgrade_ui.build(hud_layer, _emoji_font())


func _on_upgrade_card_chosen(id: String) -> void:
	player.apply_upgrade(id)
	_hide_upgrade_popup()


func _emoji_font() -> SystemFont:
	return dmg_numbers.emoji_font()


# ========== 主循环 ==========

func _process(delta: float) -> void:
	elapsed += delta
	hud.set_time(elapsed)
	# 连杀窗口倒计时：超时清零并隐藏提示
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			hud.set_combo(0)
	_ui_timer -= delta
	var refresh_ui: bool = _ui_timer <= 0.0
	if refresh_ui:
		_ui_timer = 0.1
		if player and not upgrade_ui.is_open():
			_refresh_attr_panel()
		if player:
			hud.update_buffs(player)
		hud.update_boss_effects(boss_node)
	if player:
		quest_mgr.tick(delta)   # survive 类任务计时

	# 左下角帧率
	_fps_timer -= delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.5
		if settings_ui and settings_ui.fps_label:
			settings_ui.fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	# 每 5 秒自动存档（计时在 save_system）
	if player and not player.dead and not get_tree().paused:
		if save_system.tick(delta):
			_save_game()


func _refresh_attr_panel() -> void:
	var w: Dictionary = player.current_weapon()
	_set_rich(weapon_label, "[color=#ffffff]武器: %s[/color]" % String(w["name"]))

	var base_atk: float = player.atk_power * float(w.get("atk_mult", 1.0))
	_set_rich(atk_label, _stat_text("攻击力: %.0f" % base_atk, _diff_text(player.eff_atk() - base_atk, "%.0f")))

	var base_cd: float = player.fire_cooldown / maxf(float(w.get("rate_mult", 1.0)), 0.01)
	_set_rich(rate_label, _stat_text("射击间隔: %.2fs" % base_cd, _diff_text(player.eff_cooldown() - base_cd, "%.2fs")))

	var base_multi: float = player.multishot * float(w.get("multi_mult", 1.0))
	_set_rich(multi_label, _stat_text("多重射击: %.1f" % base_multi, _diff_text(player.eff_multishot() - base_multi, "%.1f")))

	var base_crit: float = (player.base_crit + player.weapon_crit_add()) * (1.0 + player.crit_bonus) * 100.0
	_set_rich(crit_label, _stat_text("暴击率: %.0f%%" % base_crit,
		_diff_text(player.crit_chance * 100.0 - base_crit, "%.0f%%")))
	_set_rich(crit_dmg_label, "[color=#ffffff]爆伤 x2.0 · 段数 %d[/color]" % int(floor(player.crit_chance)))
	_set_rich(armor_label, _stat_text("护甲: %.0f" % player.armor,
		_diff_text(player.eff_armor() - player.armor, "%.0f")) \
		+ " [color=#ffffff]· 减伤 %.0f%%[/color]" % [ARMOR.reduction(player.eff_armor()) * 100.0])
	_set_rich(attr_hp_label, "[color=#ffffff]生命: %d/%d[/color]" % [player.hp, player.MAX_HP])


## 富文本工具见 scripts/ui/rich_text.gd
func _set_rich(lbl, text: String) -> void:
	RICH_TEXT.set_rich(lbl, text)


func _stat_text(base: String, extra: String) -> String:
	return RICH_TEXT.stat_text(base, extra)


func _diff_text(diff: float, fmt: String) -> String:
	return RICH_TEXT.diff_text(diff, fmt)


func _pct_diff(mult_diff: float) -> String:
	return RICH_TEXT.pct_diff(mult_diff)


func _make_rich_row(font_size: int, wrap := false) -> RichTextLabel:
	return RICH_TEXT.make_rich_row(font_size, wrap, ui_font_scale)


# ========== 地图 ==========

# 地面绘制已迁到 scripts/ground.gd（挂在 Ground 层）


# ========== 生成 ==========

func _spawn_player() -> void:
	var p := PlayerScene.instantiate()
	p.position = Vector2.ZERO
	world_layer.add_child(p)
	p.health_changed.connect(_on_health_changed)
	p.shield_changed.connect(_on_shield_changed)
	p.bullet_spawned.connect(_on_bullet_spawned)
	p.exp_changed.connect(_on_exp_changed)
	p.level_up.connect(_on_level_up)
	p.weapon_switched.connect(_on_weapon_switched)
	player = p


func _on_coin_picked() -> void:
	score += 1
	hud.set_score(score)
	quest_mgr.notify_coin(1)
	_play_sfx("coin")


func _on_exp_orb_picked() -> void:
	_play_sfx("orb")


func _on_item_picked(item_id: String) -> void:
	_play_sfx("item")
	var left: int = inventory.add_item(item_id, 1)
	if left > 0:
		# 背包满：掉回地面（带拾取延迟，避免立刻被捡回）
		spawner.spawn_item_drop(item_id, player.global_position
			+ Vector2(randf_range(-120.0, 120.0), randf_range(-120.0, 120.0)))
	_refresh_inventory_ui()


# ========== 物品存储系统（背包 + 物品栏） ==========

func _build_inventory_ui() -> void:
	inventory_ui = UI_INVENTORY.new()
	add_child(inventory_ui)
	inventory_ui.toggle_requested.connect(_toggle_backpack)
	inventory_ui.item_used.connect(func(): _play_sfx("item"))
	inventory_ui.attr_changed.connect(_refresh_attr_panel)
	inventory_ui.build(hud_layer, inventory, _emoji_font())


func _refresh_inventory_ui() -> void:
	if inventory_ui:
		inventory_ui.refresh()


func _toggle_backpack() -> void:
	if not inventory_ui:
		return
	if not inventory_ui.is_open():
		# 其它弹窗占用时不开背包
		if upgrade_ui and upgrade_ui.is_open():
			return
		if settings_ui and settings_ui.is_open():
			return
		if shop_ui and shop_ui.is_open():
			return
		if start_menu and start_menu.visible:
			return
	inventory_ui.toggle()
	_sync_pause()


## 快捷栏快捷键：1~5（含小键盘）使用从左到右对应格的物品
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var slot := -1
	match event.keycode:
		KEY_1, KEY_KP_1:
			slot = 0
		KEY_2, KEY_KP_2:
			slot = 1
		KEY_3, KEY_KP_3:
			slot = 2
		KEY_4, KEY_KP_4:
			slot = 3
		KEY_5, KEY_KP_5:
			slot = 4
	if slot < 0:
		return
	get_viewport().set_input_as_handled()
	inventory_ui.use_hotbar_slot(slot)


func _on_enemy_died(at: Vector2, enemy_type: int) -> void:
	kills += 1
	hud.set_kills(kills)
	quest_mgr.notify_kill(enemy_type)
	# 连杀：5 秒内持续击杀累积，HUD 提示 + 追加金币掉落
	combo += 1
	combo_timer = COMBO_WINDOW
	hud.set_combo(combo)
	var bonus: int = mini(combo / COMBO_COIN_STEP, COMBO_COIN_MAX)
	for i in range(bonus):
		var pos := at + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		spawner.call_deferred("spawn_coin_at", pos)   # 可能在物理回调中，延迟入树
	# 击败 100 名敌人后出现 Boss（之后每 100 杀再刷，Boss 交替）
	if not boss_spawned and kills >= boss_kills_mark + 100:
		boss_spawned = true
		call_deferred("_spawn_boss")
	# 掉落物由敌人自己在死亡时生成（见 enemy.gd 的 _drop_loot）


# ========== Boss ==========

func _spawn_boss() -> void:
	if last_boss_id == "":
		_pick_next_boss()
	var data: Dictionary = BOSS_DATA.get_boss(last_boss_id)

	var boss: Node = spawner.spawn_boss(last_boss_id)
	boss.stats_changed.connect(_on_boss_stats)
	boss.play_intro()
	boss_node = boss
	hud.boss_name_label.text = String(data.get("name", ""))
	_play_sfx("levelup")
	_show_boss_warning(String(data.get("warning", "⚠ Boss 出现！")))


func _show_boss_warning(text: String) -> void:
	# 红色闪光
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.8, 0.0, 0.0, 0.38)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(flash)
	var ftw: Tween = hud_layer.create_tween()
	ftw.tween_property(flash, "color:a", 0.0, 0.55)
	ftw.tween_callback(flash.queue_free)

	# 警告文字
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -260.0
	lbl.offset_top = -180.0
	lbl.offset_right = 260.0
	lbl.offset_bottom = -130.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.05, 0.05))
	lbl.modulate.a = 0.0
	hud_layer.add_child(lbl)
	var tw: Tween = hud_layer.create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_interval(0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(lbl.queue_free)


func _on_boss_stats(hp: int, max_hp: int, shield: int, max_shield: int) -> void:
	hud.set_boss_stats(hp, max_hp, shield, max_shield)


func _on_boss_died(_at: Vector2) -> void:
	hud.boss_panel.visible = false
	boss_node = null
	boss_spawned = false
	boss_kills_mark = kills   # 下一个 Boss 需要再击杀 100 个敌人
	_play_sfx("levelup")
	quest_mgr.notify_boss_killed(last_boss_id, kills)   # 主线跟随首个 Boss，击杀对应目标才结算
	# 掉落物由 Boss 自己在死亡时生成（见 boss.gd 的 _drop_loot）
	_pick_next_boss()   # 提前抽下一只 Boss


# ========== 子弹（结算在 scripts/combat.gd） ==========

func _on_bullet_spawned(origin: Vector2, direction: Vector2, damage: float, crit_stacks: int) -> void:
	combat.spawn_bullet(origin, direction, damage, crit_stacks)


# Effect 持续伤害事件 → 伤害飘字
func _on_effect_damage(at: Vector2, amount: int, icon: String) -> void:
	combat.on_effect_damage(at, amount, icon)


# ========== 经验 / 升级 ==========

func _on_exp_changed(cur: int, next: int) -> void:
	hud.set_exp(cur, next)


func _on_level_up(new_level: int) -> void:
	hud.set_level(new_level)
	_play_sfx("levelup")
	if upgrade_ui.is_open():
		pending_level_cards += 1   # 连续升级：排队，选完再弹
		return
	_show_upgrade_cards()


func _show_upgrade_cards() -> void:
	upgrade_ui.show_cards()
	_sync_pause()


func _hide_upgrade_popup() -> void:
	upgrade_ui.hide()
	if player: player.upgrading = false
	_refresh_attr_panel()
	if pending_level_cards > 0:
		pending_level_cards -= 1
		if player: player.upgrading = true
		_show_upgrade_cards()
	else:
		_sync_pause()


func _on_health_changed(cur: int, max_v: int) -> void:
	hud.set_hp(cur, max_v)
	_refresh_attr_panel()


func _on_shield_changed(cur: int, max_v: int) -> void:
	hud.set_shield(cur, max_v)
