class_name HUD
extends CanvasLayer
## 全部界面：顶栏（金币 / 累计收入 / 目标 / 暂停 / 保存）、底部建造工具条、
## 右侧设备检查器、提示气泡、主菜单、暂停菜单、阶段结算、拆除确认框。

var main: Node2D
var _ui_theme: Theme

var money_lbl: Label
var income_lbl: Label
var goal_lbl: Label
var tool_buttons: Dictionary = {}      # type(int) 或 "demolish" -> ToolButton
var inspector: PanelContainer
var inspector_vbox: VBoxContainer
var toast_lbl: Label
var toast_time: float = 0.0

var main_menu: Control
var pause_menu: Control
var result_menu: Control
var demolish_dialog: Control
var continue_btn: Button

const HOTKEYS := [
	[GameTypes.B.BELT, "1"], [GameTypes.B.HARVESTER, "2"], [GameTypes.B.CUTTER, "3"],
	[GameTypes.B.DRYER, "4"], [GameTypes.B.PACKAGER, "5"],
]

func _ready() -> void:
	layer = 10
	_ui_theme = _theme()
	set("theme", _ui_theme)
	_build_top_bar()
	_build_bottom_bar()
	_build_inspector()
	_build_toast()
	_build_main_menu()
	_build_pause_menu()
	_build_result_menu()
	_build_demolish_dialog()
	hide_all_overlays()

# ===========================================================================
# 主题与小控件
# ===========================================================================
func _theme() -> Theme:
	var th := Theme.new()
	th.default_font = IconDraw.font()
	th.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.13, 0.94)
	panel.border_color = Color(1, 1, 1, 0.14)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	th.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.18, 0.22, 0.27)
	btn.border_color = Color(1, 1, 1, 0.18)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	var hover: StyleBoxFlat = btn.duplicate()
	hover.bg_color = Color(0.26, 0.32, 0.39)
	var press: StyleBoxFlat = btn.duplicate()
	press.bg_color = Color(0.12, 0.15, 0.19)
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", press)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.93, 0.95, 0.97))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	return th

func _lbl(text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", IconDraw.font())
	l.add_theme_font_size_override("font_size", size)
	return l

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 0)
	return b

# ===========================================================================
# 顶栏
# ===========================================================================
func _build_top_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 22)

	money_lbl = _lbl("")
	money_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	income_lbl = _lbl("")
	income_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	goal_lbl = _lbl("")
	goal_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pause_btn := Button.new()
	pause_btn.text = "暂停 (Esc)"
	pause_btn.pressed.connect(func(): main.toggle_pause())
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(func(): main.save_game())
	var menu_btn := Button.new()
	menu_btn.text = "主菜单"
	menu_btn.pressed.connect(func(): main.quit_to_menu())
	for c in [money_lbl, income_lbl, goal_lbl, pause_btn, save_btn, menu_btn]:
		hbox.add_child(c)
	panel.add_child(hbox)
	margin.add_child(panel)
	add_child(margin)

# ===========================================================================
# 底部工具条
# ===========================================================================
class ToolGlyph extends Control:
	var machine_type: int = -1
	var is_demolish: bool = false
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var s: float = min(size.x, size.y) * 0.36
		if is_demolish:
			draw_line(c + Vector2(-s, -s), c + Vector2(s, s), Color(0.95, 0.4, 0.4), 5.0)
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), Color(0.95, 0.4, 0.4), 5.0)
		else:
			var r := Rect2(c - Vector2(s * 1.3, s), Vector2(s * 2.6, s * 2))
			IconDraw.fill_rounded(self, r, 5, IconDraw.machine_color(machine_type))
			IconDraw.draw_machine_glyph(self, c, s * 0.8, machine_type)

class ToolButton extends PanelContainer:
	signal activated
	var selected: bool = false
	var base: StyleBoxFlat
	var sel: StyleBoxFlat
	func _init() -> void:
		base = StyleBoxFlat.new()
		base.bg_color = Color(0.15, 0.18, 0.22, 0.95)
		base.border_color = Color(1, 1, 1, 0.15)
		base.set_border_width_all(2)
		base.set_corner_radius_all(8)
		base.content_margin_left = 10
		base.content_margin_right = 10
		base.content_margin_top = 6
		base.content_margin_bottom = 6
		sel = base.duplicate()
		sel.bg_color = Color(0.30, 0.38, 0.28, 0.98)
		sel.border_color = Color(0.55, 0.95, 0.45)
		add_theme_stylebox_override("panel", base)
		custom_minimum_size = Vector2(118, 86)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			activated.emit()
	func set_selected(v: bool) -> void:
		selected = v
		add_theme_stylebox_override("panel", sel if v else base)

func _build_bottom_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 4)
	var hint := _lbl("左键 建造/选择　R 旋转　右键/Esc 取消　WASD/方向键 移动镜头　滚轮 缩放　中键拖拽平移", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	for entry in HOTKEYS:
		var t: int = entry[0]
		var key: String = entry[1]
		var tb := ToolButton.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		var glyph := ToolGlyph.new()
		glyph.machine_type = t
		glyph.custom_minimum_size = Vector2(0, 34)
		glyph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := _lbl("%s  [%s]" % [GameTypes.BUILDING_NAMES[t], key], 14)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var price_lbl := _lbl("%d 金币" % GameTypes.PRICES[t], 13)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
		vbox.add_child(glyph)
		vbox.add_child(name_lbl)
		vbox.add_child(price_lbl)
		tb.add_child(vbox)
		tb.activated.connect(_on_tool.bind(t))
		hbox.add_child(tb)
		tool_buttons[t] = tb
	# 拆除工具
	var demo := ToolButton.new()
	var dvbox := VBoxContainer.new()
	var dglyph := ToolGlyph.new()
	dglyph.is_demolish = true
	dglyph.custom_minimum_size = Vector2(0, 34)
	var dname := _lbl("拆除  [6]", 14)
	dname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dnote := _lbl("返还 80%", 13)
	dnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dnote.add_theme_color_override("font_color", Color(0.95, 0.55, 0.5))
	dvbox.add_theme_constant_override("separation", 2)
	dvbox.add_child(dglyph)
	dvbox.add_child(dname)
	dvbox.add_child(dnote)
	demo.add_child(dvbox)
	demo.activated.connect(_on_demolish_tool)
	hbox.add_child(demo)
	tool_buttons["demolish"] = demo
	panel.add_child(hbox)
	outer.add_child(hint)
	outer.add_child(panel)
	margin.add_child(outer)
	add_child(margin)

func _on_tool(t: int) -> void:
	main.set_build_mode(t)

func _on_demolish_tool() -> void:
	main.set_demolish_mode()

# ===========================================================================
# 右侧设备检查器
# ===========================================================================
class ItemGlyph extends Control:
	var item_type: int
	func _draw() -> void:
		IconDraw.draw_item(self, size * 0.5, min(size.x, size.y) * 0.36, item_type)

func _build_inspector() -> void:
	inspector = PanelContainer.new()
	inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inspector.offset_left = -250
	inspector.offset_top = 64
	inspector.offset_bottom = -128
	inspector.offset_right = -10
	inspector.visible = false
	inspector_vbox = VBoxContainer.new()
	inspector_vbox.add_theme_constant_override("separation", 8)
	inspector.add_child(inspector_vbox)
	add_child(inspector)

func _item_row(label_text: String, item_type) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if item_type == null:
		var empty := _lbl("—", 15)
		empty.custom_minimum_size = Vector2(30, 30)
		row.add_child(empty)
	else:
		var g := ItemGlyph.new()
		g.item_type = item_type
		g.custom_minimum_size = Vector2(30, 30)
		row.add_child(g)
	row.add_child(_lbl("%s%s" % [label_text, "" if item_type == null else "：" + GameTypes.ITEM_NAMES[item_type]], 15))
	inspector_vbox.add_child(row)

func refresh_inspector() -> void:
	for c in inspector_vbox.get_children():
		c.queue_free()
	var cell = main.selected_cell
	if cell == null or not main.buildings.has(cell):
		inspector.visible = false
		return
	inspector.visible = true
	var b: Dictionary = main.buildings[cell]
	var t: int = b["t"]
	var title := _lbl(GameTypes.BUILDING_NAMES[t], 20)
	inspector_vbox.add_child(title)
	inspector_vbox.add_child(_lbl("位置：%d, %d　朝向：%s" % [cell.x, cell.y, _dir_name(b["dir"])], 14))
	if t == GameTypes.B.PORT:
		inspector_vbox.add_child(_lbl("收购价格：", 15))
		for it in [GameTypes.I.CUT, GameTypes.I.DRY, GameTypes.I.BOX]:
			_item_row("　", it)
		inspector_vbox.add_child(_lbl("原叶不收购", 13))
		return
	inspector_vbox.add_child(_lbl("状态：%s" % _state_name(main.get_machine_state(cell)), 15))
	if t == GameTypes.B.BELT:
		inspector_vbox.add_child(_lbl("每 0.25 秒输送一格，每格最多一件货物", 13))
		return
	# 缓存
	if t == GameTypes.B.HARVESTER:
		_item_row("输出缓存", b["out"])
	else:
		if t == GameTypes.B.PACKAGER:
			var slots: Array = b["in"]
			_item_row("左输入缓存", slots[0])
			_item_row("右输入缓存", slots[1])
		else:
			_item_row("输入缓存", b["in"])
		_item_row("输出缓存", b["out"])
	# 加工进度
	var prog: float = b.get("progress", 0.0)
	var total: float = GameTypes.CYCLES[t]
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = total
	bar.value = prog
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	var pct := _lbl("加工进度：%d%%（%.2f / %.1f 秒）" % [int(prog / total * 100.0), prog, total], 13)
	inspector_vbox.add_child(pct)
	inspector_vbox.add_child(bar)
	# 配方说明
	var recipe: String = ""
	match t:
		GameTypes.B.CUTTER: recipe = "每秒消耗 1 原叶 → 1 切叶"
		GameTypes.B.DRYER: recipe = "每 2 秒消耗 1 切叶 → 1 干叶"
		GameTypes.B.HARVESTER: recipe = "每 2 秒产出 1 原叶"
		GameTypes.B.PACKAGER: recipe = "每 3 秒两侧各消耗 1 干叶 → 1 盒茶"
	if recipe != "":
		inspector_vbox.add_child(_lbl(recipe, 13))
	inspector_vbox.add_child(_lbl("拆除返还：%d 金币" % int(floor(GameTypes.PRICES[t] * 0.8)), 13))

func _dir_name(d: int) -> String:
	return ["上", "右", "下", "左"][d]

func _state_name(s: String) -> String:
	match s:
		"working": return "加工中"
		"idle": return "待机（缺原料）"
		"blocked": return "堵塞（下游已满）"
		_: return s

# ===========================================================================
# 提示气泡
# ===========================================================================
func _build_toast() -> void:
	toast_lbl = _lbl("", 18)
	toast_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_lbl.offset_top = 56
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	add_child(toast_lbl)

func show_toast(text: String) -> void:
	toast_lbl.text = text
	toast_time = 2.5

# ===========================================================================
# 通用全屏弹层
# ===========================================================================
func _overlay(alpha: float = 0.72) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, alpha)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	root.add_child(panel)
	root.set_meta("vbox", vbox)
	add_child(root)
	return root

func _overlay_title(ov: Control, text: String, size: int = 28) -> void:
	var l := _lbl(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov.get_meta("vbox").add_child(l)

func _overlay_button(ov: Control, text: String, callable: Callable) -> Button:
	var b := _button(text)
	b.pressed.connect(callable)
	ov.get_meta("vbox").add_child(b)
	return b

# ===========================================================================
# 主菜单
# ===========================================================================
func _build_main_menu() -> void:
	main_menu = _overlay(0.8)
	_overlay_title(main_menu, "青叶加工厂", 36)
	var sub := _lbl("俯视 2D 自动化茶叶生产经营", 15)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	main_menu.get_meta("vbox").add_child(sub)
	_overlay_button(main_menu, "新游戏", func(): main.new_game())
	continue_btn = _overlay_button(main_menu, "继续游戏", func(): main.load_game())
	_overlay_button(main_menu, "退出", func(): get_tree().quit())
	var help := PanelContainer.new()
	var help_v := VBoxContainer.new()
	help_v.add_theme_constant_override("separation", 4)
	for line in [
		"操作：左键建造/选择，R 旋转，右键或 Esc 取消，6 进入拆除模式",
		"镜头：WASD/方向键移动，滚轮缩放，按住中键拖拽平移",
		"目标一：卖出 10 份干叶　目标二：卖出 10 盒茶",
		"传送带每 0.25 秒前进一格，堵塞时货物停留、设备停机",
	]:
		var l := _lbl(line, 13)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		help_v.add_child(l)
	help.add_child(help_v)
	main_menu.get_meta("vbox").add_child(help)

# ===========================================================================
# 暂停菜单
# ===========================================================================
func _build_pause_menu() -> void:
	pause_menu = _overlay()
	_overlay_title(pause_menu, "已暂停", 30)
	_overlay_button(pause_menu, "继续游戏", func(): main.toggle_pause())
	_overlay_button(pause_menu, "保存游戏", func(): main.save_game())
	_overlay_button(pause_menu, "保存并回到主菜单", func(): main.save_game(); main.quit_to_menu())
	_overlay_button(pause_menu, "不保存回到主菜单", func(): main.quit_to_menu())

# ===========================================================================
# 阶段结算
# ===========================================================================
func _build_result_menu() -> void:
	result_menu = _overlay(0.78)
	_overlay_title(result_menu, "经营结果", 30)
	result_menu.set_meta("body", _lbl("", 16))
	result_menu.get_meta("vbox").add_child(result_menu.get_meta("body"))
	_overlay_button(result_menu, "继续建设", func(): result_menu.visible = false)
	_overlay_button(result_menu, "保存并回到主菜单", func(): main.save_game(); main.quit_to_menu())

func show_result(stats: Dictionary) -> void:
	var l: Label = result_menu.get_meta("body")
	l.text = "全部经营目标已完成！\n\n累计收入：%d 金币\n当前资金：%d 金币\n卖出切叶：%d　干叶：%d　盒茶：%d\n\n可以继续扩建你的茶叶工厂。" % [
		stats["income"], stats["money"], stats["sold_cut"], stats["sold_dry"], stats["sold_box"],
	]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_menu.visible = true

# ===========================================================================
# 拆除确认
# ===========================================================================
func _build_demolish_dialog() -> void:
	demolish_dialog = _overlay(0.55)
	_overlay_title(demolish_dialog, "确认拆除？", 24)
	demolish_dialog.set_meta("body", _lbl("", 15))
	demolish_dialog.get_meta("vbox").add_child(demolish_dialog.get_meta("body"))
	_overlay_button(demolish_dialog, "确认拆除（丢弃内部货物）", func(): main.confirm_demolish())
	_overlay_button(demolish_dialog, "取消", func(): main.cancel_demolish())

func show_demolish_dialog(info: String) -> void:
	(demolish_dialog.get_meta("body") as Label).text = info
	demolish_dialog.visible = true

# ===========================================================================
# 状态刷新
# ===========================================================================
func hide_all_overlays() -> void:
	main_menu.visible = false
	pause_menu.visible = false
	result_menu.visible = false
	demolish_dialog.visible = false

func show_main_menu() -> void:
	hide_all_overlays()
	continue_btn.disabled = not FileAccess.file_exists(GameTypes.SAVE_PATH)
	main_menu.visible = true

func show_pause_menu(v: bool) -> void:
	pause_menu.visible = v

func any_overlay_open() -> bool:
	return main_menu.visible or pause_menu.visible or result_menu.visible or demolish_dialog.visible

func refresh() -> void:
	money_lbl.text = "金币：%d" % main.money
	income_lbl.text = "累计收入：%d" % main.total_income
	goal_lbl.text = main.goal_text()
	# 工具条选中态（键可能是设备 int 或字符串 "demolish"）
	for t in tool_buttons.keys():
		var tb: ToolButton = tool_buttons[t]
		var sel: bool
		if typeof(t) == TYPE_STRING:
			sel = main.mode == main.MODE_DEMOLISH
		else:
			sel = main.mode == main.MODE_BUILD and main.ghost_type == int(t)
		tb.set_selected(sel)
	refresh_inspector()

func _process(delta: float) -> void:
	if toast_time > 0.0:
		toast_time -= delta
		if toast_time <= 0.0:
			toast_lbl.text = ""
