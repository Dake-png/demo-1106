extends RefCounted

## 富文本工具：属性行着色 / 差异文本 / RichTextLabel 行工厂
## 纯静态函数，main 与各 UI 模块共用


## 文本未变化时不重排（RichTextLabel 每次赋值都会触发布局）
static func set_rich(lbl, text: String) -> void:
	if lbl == null or lbl.text == text:
		return
	lbl.text = text


## 属性行：基础值白色 + 修饰值蓝色
static func stat_text(base: String, extra: String) -> String:
	if extra == "":
		return "[color=#ffffff]%s[/color]" % base
	return "[color=#ffffff]%s[/color] [color=#4da6ff]%s[/color]" % [base, extra]


static func diff_text(diff: float, fmt: String) -> String:
	if absf(diff) < 0.005:
		return ""
	return ("+" if diff > 0.0 else "") + (fmt % diff)


static func pct_diff(mult_diff: float) -> String:
	if absf(mult_diff) < 0.001:
		return ""
	return "%+.0f%%" % (mult_diff * 100.0)


## 可着色的文本行（用于属性 / 武器面板）；base_font 供字体缩放时重设
static func make_rich_row(font_size: int, wrap: bool, font_scale: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_meta("base_font", font_size)
	r.add_theme_font_size_override("normal_font_size", int(round(font_size * font_scale)))
	return r
