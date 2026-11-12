class_name SaveSystem
extends RefCounted
## 存档读写：JSON，保留布局、朝向、在途货物（含插值起点与计时）、
## 机器缓存、加工进度、金币、目标与镜头位置。

const SAVE_VERSION := 1

static func save(main: Node2D, path: String = GameTypes.SAVE_PATH) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"money": main.money,
		"total_income": main.total_income,
		"phase": main.phase,
		"goal_done": main.goal_done,
		"sold": main.sold.duplicate(),
		"world_time": main.world_time,
		"belt_accum": main.belt_accum,
		"merge_counter": _vec2i_dict_to_json(main.merge_counter),
		"port": _cell(main.port_cell),
		"camera_pos": [main.camera.position.x, main.camera.position.y],
		"camera_zoom": main.camera.zoom.x,
		"buildings": [],
		"belt_items": [],
	}
	for cell in main.buildings.keys():
		var b: Dictionary = main.buildings[cell]
		var rec := {
			"cell": _cell(cell),
			"t": b["t"],
			"dir": b["dir"],
		}
		match b["t"]:
			GameTypes.B.HARVESTER:
				rec["out"] = b["out"]
				rec["progress"] = b["progress"]
			GameTypes.B.CUTTER, GameTypes.B.DRYER:
				rec["in"] = b["in"]
				rec["out"] = b["out"]
				rec["progress"] = b["progress"]
			GameTypes.B.PACKAGER:
				rec["in_left"] = b["in"][0]
				rec["in_right"] = b["in"][1]
				rec["out"] = b["out"]
				rec["progress"] = b["progress"]
		data["buildings"].append(rec)
	for item in main.belt_items:
		data["belt_items"].append({
			"t": item["t"],
			"from": _cell(item["from"]),
			"to": _cell(item["to"]),
			"start_time": item["start_time"],
		})
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("存档失败：%s" % str(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

static func load(main: Node2D, path: String = GameTypes.SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		push_error("存档版本不兼容或已损坏")
		return false

	main.reset_state()
	main.money = int(parsed["money"])
	main.total_income = int(parsed["total_income"])
	main.phase = int(parsed["phase"])
	main.goal_done = bool(parsed["goal_done"])
	main.sold = {}
	for k in parsed["sold"].keys():
		main.sold[int(k)] = int(parsed["sold"][k])
	main.world_time = float(parsed["world_time"])
	main.belt_accum = float(parsed["belt_accum"])
	main.merge_counter = _vec2i_dict_from_json(parsed.get("merge_counter", {}))
	main.port_cell = _from_cell(parsed["port"])
	main.camera.position = Vector2(parsed["camera_pos"][0], parsed["camera_pos"][1])
	main.camera.zoom = Vector2.ONE * float(parsed["camera_zoom"])

	for rec in parsed["buildings"]:
		var t: int = int(rec["t"])
		var b: Dictionary = main._make_building(t, int(rec["dir"]))
		match t:
			GameTypes.B.HARVESTER:
				b["out"] = _nullable_int(rec.get("out"))
				b["progress"] = float(rec.get("progress", 0.0))
			GameTypes.B.CUTTER, GameTypes.B.DRYER:
				b["in"] = _nullable_int(rec.get("in"))
				b["out"] = _nullable_int(rec.get("out"))
				b["progress"] = float(rec.get("progress", 0.0))
			GameTypes.B.PACKAGER:
				b["in"] = [_nullable_int(rec.get("in_left")), _nullable_int(rec.get("in_right"))]
				b["out"] = _nullable_int(rec.get("out"))
				b["progress"] = float(rec.get("progress", 0.0))
		main.buildings[_from_cell(rec["cell"])] = b

	for rec in parsed["belt_items"]:
		main.belt_items.append({
			"t": int(rec["t"]),
			"from": _from_cell(rec["from"]),
			"to": _from_cell(rec["to"]),
			"start_time": float(rec["start_time"]),
		})
	return true

# ---- 键/值工具 -------------------------------------------------------------
static func _cell(c: Vector2i) -> Array:
	return [c.x, c.y]

static func _from_cell(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

static func _nullable_int(v: Variant):
	if v == null:
		return null
	return int(v)

static func _vec2i_dict_to_json(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out["%d,%d" % [k.x, k.y]] = d[k]
	return out

static func _vec2i_dict_from_json(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		var parts: PackedStringArray = String(k).split(",")
		out[Vector2i(int(parts[0]), int(parts[1]))] = int(d[k])
	return out
