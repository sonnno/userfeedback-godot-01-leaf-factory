class_name WorldRenderer
extends Node2D
## 工厂世界的全部自定义渲染：地板网格、出货口、设备、端口标记、
## 传送带货物插值移动、加工进度、堵塞动画、放置/拆除预览与选中框。

var main: Node2D
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	_draw_floor()
	_draw_port()
	for cell in main.buildings.keys():
		_draw_building(cell, main.buildings[cell])
	_draw_belt_items()
	_draw_buffer_items()
	_draw_overlays()

# ---- 地板与网格 -----------------------------------------------------------
func _draw_floor() -> void:
	var size := Vector2(GameTypes.GRID_W, GameTypes.GRID_H) * GameTypes.CELL
	IconDraw.fill_rounded(self, Rect2(-8, -8, size.x + 16, size.y + 16), 10, Color(0.10, 0.12, 0.14))
	var check_a := Color(0.145, 0.165, 0.185)
	var check_b := Color(0.125, 0.145, 0.165)
	for y in GameTypes.GRID_H:
		for x in GameTypes.GRID_W:
			var r := Rect2(Vector2(x, y) * GameTypes.CELL, Vector2.ONE * GameTypes.CELL)
			draw_rect(r, check_a if (x + y) % 2 == 0 else check_b)
	var line := Color(1, 1, 1, 0.07)
	for x in GameTypes.GRID_W + 1:
		draw_line(Vector2(x * GameTypes.CELL, 0), Vector2(x * GameTypes.CELL, size.y), line, 1.0)
	for y in GameTypes.GRID_H + 1:
		draw_line(Vector2(0, y * GameTypes.CELL), Vector2(size.x, y * GameTypes.CELL), line, 1.0)

# ---- 出货口 ---------------------------------------------------------------
func _draw_port() -> void:
	var p: Vector2i = main.port_cell
	var r := _cell_rect(p, 3)
	IconDraw.fill_rounded(self, r, 8, IconDraw.machine_color(GameTypes.B.PORT))
	IconDraw.stroke_rounded(self, r, 8, Color(1, 1, 1, 0.5), 2.5)
	var center: Vector2 = r.get_center()
	IconDraw.draw_machine_glyph(self, center + Vector2(0, -8), 16, GameTypes.B.PORT)
	_draw_label(center + Vector2(0, 20), "出货口", 15, Color.WHITE)

# ---- 设备 ---------------------------------------------------------------
func _draw_building(cell: Vector2i, b: Dictionary) -> void:
	var t: int = b["t"]
	var r := _cell_rect(cell, 5)
	match t:
		GameTypes.B.BELT:
			_draw_belt(cell, b, r)
		GameTypes.B.HARVESTER, GameTypes.B.CUTTER, GameTypes.B.DRYER:
			_draw_simple_machine(cell, b, r)
		GameTypes.B.PACKAGER:
			_draw_packager(cell, b, r)

func _draw_belt(cell: Vector2i, b: Dictionary, r: Rect2) -> void:
	IconDraw.fill_rounded(self, r, 7, IconDraw.machine_color(GameTypes.B.BELT))
	var dir: int = b["dir"]
	var angle: float = IconDraw.dir_to_angle(dir)
	var center: Vector2 = r.get_center()
	# 两条随时间滚动的 V 形纹，表现传送带运转
	var phase: float = fmod(_t, GameTypes.TICK) / GameTypes.TICK
	for k in [-1, 0]:
		var off: float = (k + phase) * 22.0
		var local := Vector2(off, 0)
		var p1: Vector2 = center + local.rotated(angle)
		var half := Vector2(0, 9).rotated(angle)
		var col := Color(1, 1, 1, 0.28)
		draw_line(p1 - half, p1 + half, col, 3.0, true)
	# 朝向小箭头
	IconDraw.draw_triangle(self, center + Vector2(18, 0).rotated(angle), 6, angle, Color(1, 1, 1, 0.55))
	# 堵塞描边
	if main.get_machine_state(cell) == "blocked":
		_pulse_border(r, 7)

func _draw_simple_machine(cell: Vector2i, b: Dictionary, r: Rect2) -> void:
	var t: int = b["t"]
	IconDraw.fill_rounded(self, r, 9, IconDraw.machine_color(t))
	IconDraw.stroke_rounded(self, r, 9, _border_for(cell), 2.5)
	var center: Vector2 = r.get_center()
	IconDraw.draw_machine_glyph(self, center + Vector2(0, -8), 15, t)
	var dir: int = b["dir"]
	# 普通加工机：输入口在背面（蓝），输出口在朝向面（黄）
	_port_marker(cell, (dir + 2) % 4, IconDraw.INPUT_PORT, 13)
	_port_marker(cell, dir, IconDraw.OUTPUT_PORT, 13)
	_draw_progress(cell, b, r)
	_draw_label(center + Vector2(0, 21), GameTypes.BUILDING_NAMES[t], 12, Color(1, 1, 1, 0.92))

func _draw_packager(cell: Vector2i, b: Dictionary, r: Rect2) -> void:
	IconDraw.fill_rounded(self, r, 9, IconDraw.machine_color(GameTypes.B.PACKAGER))
	IconDraw.stroke_rounded(self, r, 9, _border_for(cell), 2.5)
	var center: Vector2 = r.get_center()
	IconDraw.draw_machine_glyph(self, center + Vector2(0, -8), 15, GameTypes.B.PACKAGER)
	var dir: int = b["dir"]
	# 背面输出口
	_port_marker(cell, dir, IconDraw.OUTPUT_PORT, 12)
	# 两个独立输入口：朝向的左右两侧
	var left: int = (dir + 3) % 4
	var right: int = (dir + 1) % 4
	_port_marker(cell, left, IconDraw.INPUT_PORT, 12)
	_port_marker(cell, right, IconDraw.INPUT_PORT, 12)
	# 两侧缓存占用提示
	var slots: Array = b["in"]
	if slots[0] != null:
		_port_dot(cell, left, IconDraw.item_color(slots[0]))
	if slots[1] != null:
		_port_dot(cell, right, IconDraw.item_color(slots[1]))
	_draw_progress(cell, b, r)
	_draw_label(center + Vector2(0, 21), GameTypes.BUILDING_NAMES[GameTypes.B.PACKAGER], 12, Color(1, 1, 1, 0.92))

func _border_for(cell: Vector2i) -> Color:
	if main.get_machine_state(cell) == "blocked":
		var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
		return IconDraw.BLOCKED.lerp(Color(1, 0.75, 0.75), pulse * 0.6)
	return Color(1, 1, 1, 0.35)

func _pulse_border(r: Rect2, radius: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
	IconDraw.stroke_rounded(self, r, radius, IconDraw.BLOCKED.lerp(Color(1, 0.7, 0.7), pulse * 0.5), 3.0)

func _draw_progress(cell: Vector2i, b: Dictionary, r: Rect2) -> void:
	var prog: float = b.get("progress", 0.0)
	if prog <= 0.0:
		return
	var total: float = GameTypes.CYCLES[b["t"]]
	var bar_r := Rect2(r.position + Vector2(7, r.size.y - 9), Vector2(r.size.x - 14, 4))
	draw_rect(bar_r, Color(0, 0, 0, 0.55))
	var fill_r := Rect2(bar_r.position, Vector2(bar_r.size.x * clamp(prog / total, 0.0, 1.0), bar_r.size.y))
	draw_rect(fill_r, Color(0.45, 0.95, 0.5))

# ---- 端口标记 -------------------------------------------------------------
func _port_marker(cell: Vector2i, side: int, color: Color, s: float) -> void:
	var center: Vector2 = (_cell_center(cell) + Vector2(GameTypes.DIR_V[side]) * (GameTypes.CELL * 0.42))
	draw_circle(center, s + 2.5, Color(0, 0, 0, 0.6))
	draw_circle(center, s, color)

func _port_dot(cell: Vector2i, side: int, color: Color) -> void:
	var center: Vector2 = (_cell_center(cell) + Vector2(GameTypes.DIR_V[side]) * (GameTypes.CELL * 0.42))
	draw_circle(center, 5.0, color)

# ---- 传送带上的货物（插值移动 + 堵塞红框）----------------------------------
func _draw_belt_items() -> void:
	for item in main.belt_items:
		var from: Vector2i = item["from"]
		var to: Vector2i = item["to"]
		var t0: float = item["start_time"]
		var alpha: float = clamp((main.world_time - t0) / GameTypes.TICK, 0.0, 1.0)
		var pos: Vector2 = (_cell_center(from) * (1.0 - alpha) + _cell_center(to) * alpha)
		IconDraw.draw_item(self, pos, 13, item["t"])
		if item.get("stalled", false):
			var pulse: float = 0.5 + 0.5 * sin(_t * 8.0)
			var col: Color = IconDraw.BLOCKED.lerp(Color(1, 0.8, 0.8), pulse * 0.5)
			draw_arc(pos, 16, 0, TAU, 20, col, 2.5)

# ---- 机器缓存内的货物（输入侧 / 输出侧小图标）------------------------------
func _draw_buffer_items() -> void:
	for cell in main.buildings.keys():
		var b: Dictionary = main.buildings[cell]
		var t: int = b["t"]
		if t == GameTypes.B.BELT or t == GameTypes.B.PORT:
			continue
		if t == GameTypes.B.HARVESTER:
			if b["out"] != null:
				IconDraw.draw_item(self, _cell_center(cell) + Vector2(0, 6), 10, b["out"])
			continue
		if t == GameTypes.B.PACKAGER:
			var slots: Array = b["in"]
			var dir: int = b["dir"]
			if slots[0] != null:
				IconDraw.draw_item(self, _cell_center(cell) + Vector2(GameTypes.DIR_V[(dir + 3) % 4]) * 15.0, 9, slots[0])
			if slots[1] != null:
				IconDraw.draw_item(self, _cell_center(cell) + Vector2(GameTypes.DIR_V[(dir + 1) % 4]) * 15.0, 9, slots[1])
			if b["out"] != null:
				IconDraw.draw_item(self, _cell_center(cell) + Vector2(GameTypes.DIR_V[dir]) * 15.0, 10, b["out"])
			continue
		# 切割机 / 烘干机：输入在背面、输出在朝向面
		var dir2: int = b["dir"]
		if b["in"] != null:
			IconDraw.draw_item(self, _cell_center(cell) + Vector2(GameTypes.DIR_V[(dir2 + 2) % 4]) * 15.0, 9, b["in"])
		if b["out"] != null:
			IconDraw.draw_item(self, _cell_center(cell) + Vector2(GameTypes.DIR_V[dir2]) * 15.0, 10, b["out"])

# ---- 选中 / 幽灵 / 拆除预览 -----------------------------------------------
func _draw_overlays() -> void:
	if main.selected_cell != null and main.buildings.has(main.selected_cell):
		_draw_cell_frame(main.selected_cell, Color(1.0, 0.92, 0.35), 3.0, 6)
	if main.mode == main.MODE_BUILD and main.hover_cell != null:
		var ok: bool = main.can_place(main.hover_cell)
		var col: Color = Color(0.35, 0.95, 0.45, 0.85) if ok else Color(0.95, 0.3, 0.3, 0.85)
		var r := _cell_rect(main.hover_cell, 4)
		IconDraw.fill_rounded(self, r, 8, Color(col.r, col.g, col.b, 0.22))
		IconDraw.stroke_rounded(self, r, 8, col, 2.5)
		if ok:
			# 幽灵机器轮廓与朝向
			var ghost: Dictionary = {"t": main.ghost_type, "dir": main.ghost_dir}
			var gr := _cell_rect(main.hover_cell, 6)
			var gc: Color = IconDraw.machine_color(main.ghost_type)
			gc.a = 0.75
			IconDraw.fill_rounded(self, gr, 9, gc)
			var c2: Vector2 = gr.get_center()
			IconDraw.draw_triangle(self, c2 + Vector2(16, 0).rotated(IconDraw.dir_to_angle(main.ghost_dir)),
				7, IconDraw.dir_to_angle(main.ghost_dir), Color(1, 1, 1, 0.8))
	elif main.mode == main.MODE_DEMOLISH and main.hover_cell != null:
		var demolishable: bool = main.can_demolish(main.hover_cell)
		var col2: Color = Color(0.95, 0.35, 0.35) if demolishable else Color(0.5, 0.5, 0.5)
		_draw_cell_frame(main.hover_cell, col2, 3.0, 6)
		var c3: Vector2 = _cell_center(main.hover_cell)
		draw_line(c3 + Vector2(-10, -10), c3 + Vector2(10, 10), col2, 4.0)
		draw_line(c3 + Vector2(-10, 10), c3 + Vector2(10, -10), col2, 4.0)

func _draw_cell_frame(cell: Vector2i, color: Color, width: float, margin: float) -> void:
	var r := _cell_rect(cell, margin)
	IconDraw.stroke_rounded(self, r, 8, color, width)

# ---- 工具 -----------------------------------------------------------------
func _cell_rect(cell: Vector2i, margin: float) -> Rect2:
	return Rect2(Vector2(cell) * GameTypes.CELL + Vector2.ONE * margin,
		Vector2.ONE * (GameTypes.CELL - margin * 2))

func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2.ONE * 0.5) * GameTypes.CELL

func _draw_label(pos: Vector2, text: String, size: int, color: Color) -> void:
	var f: Font = IconDraw.font()
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(f, pos + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
