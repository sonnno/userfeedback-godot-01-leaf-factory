class_name IconDraw
## 自定义绘图辅助：统一的颜色、中文字体、货物形状、机器图标，
## 世界渲染与界面图标共用同一套视觉语言。

static var _font: SystemFont

static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray([
			"Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
			"PingFang SC", "Arial Unicode MS", "sans-serif",
		])
	return _font

# ---- 调色板 ---------------------------------------------------------------
static func item_color(t: int) -> Color:
	match t:
		GameTypes.I.RAW: return Color(0.30, 0.69, 0.31)   # 绿
		GameTypes.I.CUT: return Color(1.00, 0.60, 0.00)   # 橙
		GameTypes.I.DRY: return Color(0.82, 0.64, 0.16)   # 琥珀
		GameTypes.I.BOX: return Color(0.55, 0.36, 0.78)   # 紫
	return Color.WHITE

static func machine_color(t: int) -> Color:
	match t:
		GameTypes.B.BELT: return Color(0.21, 0.27, 0.31)
		GameTypes.B.HARVESTER: return Color(0.18, 0.49, 0.20)
		GameTypes.B.CUTTER: return Color(0.90, 0.32, 0.00)
		GameTypes.B.DRYER: return Color(0.95, 0.66, 0.15)
		GameTypes.B.PACKAGER: return Color(0.42, 0.18, 0.62)
		GameTypes.B.PORT: return Color(0.00, 0.52, 0.56)
	return Color.GRAY

const INPUT_PORT := Color(0.36, 0.72, 0.98)
const OUTPUT_PORT := Color(1.00, 0.80, 0.30)
const BLOCKED := Color(0.95, 0.30, 0.30)

# ---- 基础图形 -------------------------------------------------------------
static func fill_rounded(ci: CanvasItem, r: Rect2, radius: float, color: Color) -> void:
	var rr: float = min(radius, min(r.size.x, r.size.y) * 0.5)
	ci.draw_rect(Rect2(r.position + Vector2(rr, 0), Vector2(r.size.x - 2 * rr, r.size.y)), color)
	ci.draw_rect(Rect2(r.position + Vector2(0, rr), Vector2(r.size.x, r.size.y - 2 * rr)), color)
	for cx in [r.position.x + rr, r.position.x + r.size.x - rr]:
		for cy in [r.position.y + rr, r.position.y + r.size.y - rr]:
			ci.draw_circle(Vector2(cx, cy), rr, color)

static func stroke_rounded(ci: CanvasItem, r: Rect2, radius: float, color: Color, width: float = 2.0) -> void:
	var rr: float = min(radius, min(r.size.x, r.size.y) * 0.5)
	var pts: PackedVector2Array = [
		r.position + Vector2(rr, 0),
		r.position + Vector2(r.size.x - rr, 0),
		r.position + Vector2(r.size.x, rr),
		r.position + Vector2(r.size.x, r.size.y - rr),
		r.position + Vector2(r.size.x - rr, r.size.y),
		r.position + Vector2(rr, r.size.y),
		r.position + Vector2(0, r.size.y - rr),
		r.position + Vector2(0, rr),
	]
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), color, width, true)

# ---- 货物（形状互不相同）--------------------------------------------------
static func draw_item(ci: CanvasItem, center: Vector2, s: float, t: int) -> void:
	var dark := Color(0.08, 0.10, 0.12)
	match t:
		GameTypes.I.RAW:
			# 圆形原叶
			ci.draw_circle(center, s, dark)
			ci.draw_circle(center, s - 2.0, item_color(t))
			ci.draw_circle(center - Vector2(s * 0.3, s * 0.3), s * 0.28, Color(1, 1, 1, 0.35))
		GameTypes.I.CUT:
			# 三角形切叶
			var tri: PackedVector2Array = [
				center + Vector2(0, -s), center + Vector2(s * 0.9, s * 0.75),
				center + Vector2(-s * 0.9, s * 0.75),
			]
			ci.draw_colored_polygon(_grow(tri, 2.0, center), dark)
			ci.draw_colored_polygon(tri, item_color(t))
		GameTypes.I.DRY:
			# 菱形干叶
			var dia: PackedVector2Array = [
				center + Vector2(0, -s), center + Vector2(s, 0),
				center + Vector2(0, s), center + Vector2(-s, 0),
			]
			ci.draw_colored_polygon(_grow(dia, 2.0, center), dark)
			ci.draw_colored_polygon(dia, item_color(t))
		GameTypes.I.BOX:
			# 方形盒茶（带盒盖与封条）
			var r := Rect2(center - Vector2(s, s * 0.85), Vector2(s * 2, s * 1.7))
			fill_rounded(ci, r.grow(2.0), 4, dark)
			fill_rounded(ci, r, 4, item_color(t))
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.32)), Color(1, 1, 1, 0.22))
			ci.draw_line(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.32),
				r.position + Vector2(r.size.x * 0.5, r.size.y), Color(1, 1, 1, 0.55), 2.0)

static func _grow(pts: PackedVector2Array, amount: float, center: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p in pts:
		out.append(center + (p - center).normalized() * ((p - center).length() + amount))
	return out

# ---- 机器面板小图标 --------------------------------------------------------
static func draw_machine_glyph(ci: CanvasItem, center: Vector2, s: float, t: int) -> void:
	var white := Color(1, 1, 1, 0.92)
	match t:
		GameTypes.B.HARVESTER:
			ci.draw_circle(center, s, white)
			ci.draw_circle(center, s - 2.5, machine_color(GameTypes.B.HARVESTER))
			ci.draw_circle(center - Vector2(s * 0.3, s * 0.3), s * 0.3, Color(1, 1, 1, 0.4))
		GameTypes.B.CUTTER:
			# 刀片：两条交叉刀刃
			ci.draw_line(center + Vector2(-s, -s), center + Vector2(s, s), white, 4.0)
			ci.draw_line(center + Vector2(-s, s), center + Vector2(s, -s), white, 4.0)
			ci.draw_circle(center, s * 0.28, Color(1, 1, 1, 0.95))
		GameTypes.B.DRYER:
			# 三条热浪
			for i in 3:
				var x: float = center.x + (i - 1) * s * 0.7
				var pts: PackedVector2Array = [
					Vector2(x, center.y + s * 0.7), Vector2(x - s * 0.25, center.y + s * 0.2),
					Vector2(x + s * 0.25, center.y - s * 0.2), Vector2(x, center.y - s * 0.7),
				]
				ci.draw_polyline(pts, white, 3.0, true)
		GameTypes.B.PACKAGER:
			var r := Rect2(center - Vector2(s * 0.8, s * 0.7), Vector2(s * 1.6, s * 1.4))
			fill_rounded(ci, r, 3, white)
			ci.draw_line(r.position + Vector2(0, r.size.y * 0.35),
				r.position + Vector2(r.size.x, r.size.y * 0.35), machine_color(GameTypes.B.PACKAGER), 2.5)
		GameTypes.B.PORT:
			# 向上的货箱箭头
			var r := Rect2(center - Vector2(s * 0.75, s * 0.55), Vector2(s * 1.5, s * 1.1))
			fill_rounded(ci, r, 3, white)
			ci.draw_line(center + Vector2(0, -s * 0.2), center + Vector2(0, s * 0.75), machine_color(GameTypes.B.PORT), 3.0)
			var tri: PackedVector2Array = [
				center + Vector2(0, -s * 0.55), center + Vector2(-s * 0.4, -s * 0.1),
				center + Vector2(s * 0.4, -s * 0.1),
			]
			ci.draw_colored_polygon(tri, machine_color(GameTypes.B.PORT))

# ---- 朝向三角 -------------------------------------------------------------
static func dir_to_angle(dir: int) -> float:
	# Godot 坐标 y 向下：上=0、右=-90°、下=180°、左=90°
	return [0.0, -PI * 0.5, PI, PI * 0.5][dir]

static func draw_triangle(ci: CanvasItem, center: Vector2, s: float, angle: float, color: Color) -> void:
	var local: PackedVector2Array = [
		Vector2(s, 0), Vector2(-s * 0.7, -s * 0.7), Vector2(-s * 0.7, s * 0.7),
	]
	var rotated: PackedVector2Array = []
	for p in local:
		rotated.append(center + p.rotated(angle))
	ci.draw_colored_polygon(rotated, color)
