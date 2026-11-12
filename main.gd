extends Node2D
## 《青叶加工厂》主控：
## 固定 0.25 秒逻辑节拍，加工计时与传送带运输共用同一时间轴；
## 所有移动意图先收集、再按“每个目标每拍只接收一件 + 轮转交替”统一裁决，
## 保证货物数量/类型守恒、多路汇流公平、下游堵塞时整体停机。

# ---- 交互模式 ----
const MODE_NONE := 0
const MODE_BUILD := 1
const MODE_DEMOLISH := 2

# ---- 状态 ----
var buildings: Dictionary = {}          # Vector2i -> 设备字典
var belt_items: Array = []              # 传送带上在途货物
var money: int = GameTypes.START_MONEY
var total_income: int = 0
var sold: Dictionary = {}               # 货物类型 -> 已售数量
var phase: int = 1
var goal_done: bool = false

var world_time: float = 0.0
var belt_accum: float = 0.0
var merge_counter: Dictionary = {}      # 目标格 -> 上次放行的源序号
var paused: bool = false

var mode: int = MODE_NONE
var ghost_type: int = GameTypes.B.BELT
var ghost_dir: int = GameTypes.DIR_RIGHT
var hover_cell: Variant = null
var selected_cell: Variant = null
var pending_demolish: Variant = null

var port_cell := Vector2i(GameTypes.GRID_W - 1, GameTypes.GRID_H / 2)

var camera: Camera2D
var renderer: WorldRenderer
var hud: HUD

var _panning: bool = false

# ===========================================================================
# 初始化
# ===========================================================================
func _ready() -> void:
	camera = Camera2D.new()
	camera.enabled = true
	camera.zoom = Vector2(1.15, 1.15)
	add_child(camera)
	renderer = WorldRenderer.new()
	renderer.main = self
	add_child(renderer)
	hud = HUD.new()
	hud.main = self
	add_child(hud)
	set_process_unhandled_input(true)
	reset_state()
	hud.show_main_menu()
	hud.refresh()

func reset_state() -> void:
	buildings.clear()
	belt_items.clear()
	money = GameTypes.START_MONEY
	total_income = 0
	sold = {GameTypes.I.CUT: 0, GameTypes.I.DRY: 0, GameTypes.I.BOX: 0}
	phase = 1
	goal_done = false
	world_time = 0.0
	belt_accum = 0.0
	merge_counter.clear()
	paused = false
	mode = MODE_NONE
	hover_cell = null
	selected_cell = null
	pending_demolish = null
	# 固定出货口
	port_cell = Vector2i(GameTypes.GRID_W - 1, GameTypes.GRID_H / 2)
	buildings[port_cell] = {"t": GameTypes.B.PORT, "dir": GameTypes.DIR_LEFT}
	camera.position = Vector2(GameTypes.GRID_W, GameTypes.GRID_H) * GameTypes.CELL * 0.5
	camera.zoom = Vector2(1.15, 1.15)
	_panning = false

func _make_building(t: int, dir: int) -> Dictionary:
	var b := {"t": t, "dir": dir}
	match t:
		GameTypes.B.BELT:
			pass
		GameTypes.B.HARVESTER:
			b["out"] = null
			b["progress"] = 0.0
		GameTypes.B.CUTTER, GameTypes.B.DRYER:
			b["in"] = null
			b["out"] = null
			b["progress"] = 0.0
		GameTypes.B.PACKAGER:
			b["in"] = [null, null]
			b["out"] = null
			b["progress"] = 0.0
	return b

# ===========================================================================
# 主循环
# ===========================================================================
func _process(delta: float) -> void:
	if not _frozen():
		world_time += delta
		belt_accum += delta
		# 机器加工计时（连续时间）
		_process_machines(delta)
		# 传送带固定节拍（追赶式补拍）
		var guard: int = 0
		while belt_accum >= GameTypes.TICK and guard < 8:
			belt_accum -= GameTypes.TICK
			_resolve_movement()
			guard += 1
		if guard >= 8:
			belt_accum = 0.0
	_update_hover()
	_update_camera(delta)
	hud.refresh()

func _frozen() -> bool:
	return paused or hud != null and hud.any_overlay_open()

# ===========================================================================
# 机器加工
# ===========================================================================
func _process_machines(delta: float) -> void:
	for cell in buildings.keys():
		var b: Dictionary = buildings[cell]
		var t: int = b["t"]
		if t == GameTypes.B.BELT or t == GameTypes.B.PORT:
			continue
		var running: bool
		match t:
			GameTypes.B.HARVESTER:
				running = b["out"] == null
			GameTypes.B.CUTTER:
				running = b["in"] == GameTypes.I.RAW and b["out"] == null
			GameTypes.B.DRYER:
				running = b["in"] == GameTypes.I.CUT and b["out"] == null
			GameTypes.B.PACKAGER:
				running = b["in"][0] == GameTypes.I.DRY and b["in"][1] == GameTypes.I.DRY and b["out"] == null
			_:
				running = false
		if not running:
			continue
		b["progress"] = float(b["progress"]) + delta
		if float(b["progress"]) >= GameTypes.CYCLES[t]:
			b["progress"] = 0.0
			match t:
				GameTypes.B.HARVESTER:
					b["out"] = GameTypes.I.RAW
				GameTypes.B.CUTTER:
					b["in"] = null
					b["out"] = GameTypes.I.CUT
				GameTypes.B.DRYER:
					b["in"] = null
					b["out"] = GameTypes.I.DRY
				GameTypes.B.PACKAGER:
					b["in"] = [null, null]
					b["out"] = GameTypes.I.BOX

# ===========================================================================
# 运输裁决：意图收集 -> 目标分组 -> 轮转放行 -> 同时生效
# ===========================================================================
func _resolve_movement() -> void:
	# 1) 传送带上已有的货物尝试前进一格。
	# 目标是另一条传送带 -> 保留在 belt_items 中逐格移动；
	# 目标是机器/出货口 -> 立即送达（进缓存或出售）。
	# 因此 belt_items 中每件货物所在格（"to"）永远是传送带。
	var delivered: Array = []
	for item in belt_items:
		var origin: Vector2i = item["to"]
		var belt: Dictionary = buildings[origin]
		var target: Vector2i = origin + GameTypes.DIR_V[belt["dir"]]
		if _can_receive(target, item["t"], origin):
			if _is_belt(target):
				item["from"] = origin
				item["to"] = target
				item["start_time"] = world_time
				item["stalled"] = false
			else:
				# 机器或出货口：本拍立即送达（记录真正的目标格）
				item["delivery_target"] = target
				delivered.append(item)
		else:
			item["stalled"] = true
	for item in delivered:
		var target2: Vector2i = item["delivery_target"]
		belt_items.erase(item)
		if _target_is_port(target2):
			_sell_item(item["t"])
		else:
			_put_into_machine(target2, item["t"], item["to"])

	# 2) 设备输出缓存（采收机/切割机/烘干机/包装机）尝试推到相邻格
	# 约定：dir 为机器朝向（输出口方向），输出目标 = 朝向相邻格
	var intents: Array = []
	for cell in buildings.keys():
		var b: Dictionary = buildings[cell]
		var t: int = b["t"]
		if t == GameTypes.B.BELT or t == GameTypes.B.PORT or b["out"] == null:
			continue
		var target: Vector2i = cell + GameTypes.DIR_V[b["dir"]]
		if _can_receive(target, b["out"], cell):
			intents.append({"src": cell, "target": target, "item": b["out"]})

	# 3) 按目标分组，轮转交替（每目标每拍最多一件）
	# 轮转计数器每拍都前进，即使某一路暂时堵塞，恢复后也能按序获得放行，避免饿死
	var groups: Dictionary = {}
	for intent in intents:
		var key: Vector2i = intent["target"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(intent)
	var accepted: Array = []
	for key in groups.keys():
		var list: Array = groups[key]
		var start: int = (int(merge_counter.get(key, -1)) + 1) % list.size()
		var pick: int = start
		for offset in list.size():
			var idx: int = (start + offset) % list.size()
			var cand: Dictionary = list[idx]
			if _can_receive(cand["target"], cand["item"], cand["src"]):
				pick = idx
				break
		merge_counter[key] = pick
		accepted.append(list[pick])

	# 4) 统一执行
	for intent in accepted:
		var src: Vector2i = intent["src"]
		var target: Vector2i = intent["target"]
		var item_type: int = intent["item"]
		buildings[src]["out"] = null
		if _target_is_port(target):
			_sell_item(item_type)
		elif _is_belt(target):
			belt_items.append({
				"t": item_type, "from": src, "to": target,
				"start_time": world_time, "stalled": false,
			})
		else:
			_put_into_machine(target, item_type, src)

func _can_receive(target: Vector2i, item_type: int, source: Vector2i) -> bool:
	if not _in_bounds(target):
		return false
	if not buildings.has(target):
		return false
	var b: Dictionary = buildings[target]
	var t: int = b["t"]
	if t == GameTypes.B.PORT:
		# 出货口：任何相邻格送达的可售货物都接收（只校验货物类型）
		return GameTypes.SELL_PRICE.has(item_type)
	if t == GameTypes.B.BELT:
		# 传送带可从任意相邻格接货（支持 Y 形多路汇流），但每格同时最多一件
		for item in belt_items:
			if item["to"] == target:
				return false
		return true
	# 加工设备：只能从输入端口方向进料，且缓存有空位
	if not _is_input_face(target, b, source):
		return false
	match t:
		GameTypes.B.HARVESTER:
			return false
		GameTypes.B.CUTTER:
			return item_type == GameTypes.I.RAW and b["in"] == null
		GameTypes.B.DRYER:
			return item_type == GameTypes.I.CUT and b["in"] == null
		GameTypes.B.PACKAGER:
			if item_type != GameTypes.I.DRY:
				return false
			var slot: int = _packager_slot(b["dir"], source - target)
			if slot < 0:
				return false
			return b["in"][slot] == null
	return false

func _is_input_face(cell: Vector2i, b: Dictionary, source: Vector2i) -> bool:
	# 约定：dir 是输出方向；普通加工机输入面在背面 (dir+2)，包装机两个输入口在左右两侧
	var rel: Vector2i = source - cell
	var dir: int = b["dir"]
	match b["t"]:
		GameTypes.B.CUTTER, GameTypes.B.DRYER:
			return rel == GameTypes.DIR_V[(dir + 2) % 4]
		GameTypes.B.PACKAGER:
			return rel == GameTypes.DIR_V[(dir + 1) % 4] or rel == GameTypes.DIR_V[(dir + 3) % 4]
	return false

func _packager_slot(dir: int, rel: Vector2i) -> int:
	if rel == GameTypes.DIR_V[(dir + 3) % 4]:
		return 0   # 左侧输入
	if rel == GameTypes.DIR_V[(dir + 1) % 4]:
		return 1   # 右侧输入
	return -1

func _put_into_machine(cell: Vector2i, item_type: int, source: Vector2i) -> void:
	var b: Dictionary = buildings[cell]
	if b["t"] == GameTypes.B.PACKAGER:
		var slot: int = _packager_slot(b["dir"], source - cell)
		if slot >= 0:
			b["in"][slot] = item_type
	else:
		b["in"] = item_type

func _sell_item(item_type: int) -> void:
	if not GameTypes.SELL_PRICE.has(item_type):
		return
	var price: int = GameTypes.SELL_PRICE[item_type]
	money += price
	total_income += price
	sold[item_type] = int(sold.get(item_type, 0)) + 1
	_check_goals()

func _check_goals() -> void:
	if phase == 1 and int(sold.get(GameTypes.I.DRY, 0)) >= GameTypes.GOAL_DRY_COUNT:
		phase = 2
		hud.show_toast("阶段一完成：已卖出 %d 份干叶！新目标：卖出 %d 盒茶" % [
			GameTypes.GOAL_DRY_COUNT, GameTypes.GOAL_BOX_COUNT])
	elif phase == 2 and not goal_done and int(sold.get(GameTypes.I.BOX, 0)) >= GameTypes.GOAL_BOX_COUNT:
		goal_done = true
		hud.show_result({
			"income": total_income,
			"money": money,
			"sold_cut": sold.get(GameTypes.I.CUT, 0),
			"sold_dry": sold.get(GameTypes.I.DRY, 0),
			"sold_box": sold.get(GameTypes.I.BOX, 0),
		})

func goal_text() -> String:
	if goal_done:
		return "目标：全部完成，可继续自由建设"
	if phase == 1:
		return "目标一：卖出干叶 %d / %d" % [sold.get(GameTypes.I.DRY, 0), GameTypes.GOAL_DRY_COUNT]
	return "目标二：卖出盒茶 %d / %d" % [sold.get(GameTypes.I.BOX, 0), GameTypes.GOAL_BOX_COUNT]

# ===========================================================================
# 设备状态（供渲染与检查器使用）
# ===========================================================================
func get_machine_state(cell: Vector2i) -> String:
	if not buildings.has(cell):
		return "idle"
	var b: Dictionary = buildings[cell]
	var t: int = b["t"]
	if t == GameTypes.B.BELT:
		for item in belt_items:
			if (item["to"] == cell or item["from"] == cell) and item.get("stalled", false):
				return "blocked"
		return "working"
	if t == GameTypes.B.PORT:
		return "working"
	var has_output: bool = b["out"] != null
	if has_output:
		# 输出缓存被占：检查朝向的下游能否接收
		var target: Vector2i = cell + GameTypes.DIR_V[b["dir"]]
		return "blocked" if not _can_receive(target, b["out"], cell) else "working"
	match t:
		GameTypes.B.HARVESTER:
			return "working"
		GameTypes.B.CUTTER, GameTypes.B.DRYER:
			return "working" if b["in"] != null else "idle"
		GameTypes.B.PACKAGER:
			return "working" if b["in"][0] != null or b["in"][1] != null else "idle"
	return "idle"

# ===========================================================================
# 建造 / 旋转 / 拆除
# ===========================================================================
func set_build_mode(t: int) -> void:
	mode = MODE_BUILD
	ghost_type = t
	selected_cell = null

func set_demolish_mode() -> void:
	mode = MODE_DEMOLISH
	selected_cell = null

func cancel_mode() -> void:
	mode = MODE_NONE
	pending_demolish = null

func can_place(cell: Variant) -> bool:
	if cell == null or not _in_bounds(cell):
		return false
	if buildings.has(cell):
		return false
	return money >= GameTypes.PRICES[ghost_type]

func place_building(cell: Vector2i) -> void:
	if not can_place(cell):
		hud.show_toast("无法建造：余额不足或格子已占用")
		return
	var price: int = GameTypes.PRICES[ghost_type]
	money -= price
	buildings[cell] = _make_building(ghost_type, ghost_dir)

func can_demolish(cell: Variant) -> bool:
	if cell == null or not buildings.has(cell):
		return false
	return buildings[cell]["t"] != GameTypes.B.PORT

func request_demolish(cell: Vector2i) -> void:
	if not can_demolish(cell):
		return
	var b: Dictionary = buildings[cell]
	# 传送带：检查是否有在途货物占用
	var on_belt: bool = false
	for item in belt_items:
		if item["to"] == cell or item["from"] == cell:
			on_belt = true
			break
	var holds: bool
	match b["t"]:
		GameTypes.B.BELT:
			holds = on_belt
		GameTypes.B.HARVESTER:
			holds = b["out"] != null
		GameTypes.B.CUTTER, GameTypes.B.DRYER:
			holds = b["in"] != null or b["out"] != null
		GameTypes.B.PACKAGER:
			holds = b["in"][0] != null or b["in"][1] != null or b["out"] != null
		_:
			holds = false
	if holds:
		pending_demolish = cell
		var refund: int = int(floor(GameTypes.PRICES[b["t"]] * 0.8))
		hud.show_demolish_dialog("该 %s 内部仍有货物，拆除将丢弃这些货物。\n拆除返还 %d 金币（原价的 80%%，向下取整）。" % [
			GameTypes.BUILDING_NAMES[b["t"]], refund])
	else:
		_do_demolish(cell)

func confirm_demolish() -> void:
	if pending_demolish != null:
		_do_demolish(pending_demolish)
	pending_demolish = null
	hud.demolish_dialog.visible = false

func cancel_demolish() -> void:
	pending_demolish = null
	hud.demolish_dialog.visible = false

func _do_demolish(cell: Vector2i) -> void:
	var b: Dictionary = buildings[cell]
	var price: int = GameTypes.PRICES[b["t"]]
	money += int(floor(price * 0.8))
	# 丢弃在途货物（仅计数意义上的消失——规格要求确认后丢弃）
	var removed: Array = []
	for item in belt_items:
		if item["to"] == cell or item["from"] == cell:
			removed.append(item)
	for item in removed:
		belt_items.erase(item)
	buildings.erase(cell)
	if selected_cell == cell:
		selected_cell = null
	merge_counter.erase(cell)

func rotate_at(cell: Vector2i) -> void:
	if buildings.has(cell) and buildings[cell]["t"] != GameTypes.B.PORT:
		var b: Dictionary = buildings[cell]
		b["dir"] = (int(b["dir"]) + 1) % 4

# ===========================================================================
# 菜单 / 存档
# ===========================================================================
func new_game() -> void:
	reset_state()
	hud.hide_all_overlays()
	hud.show_toast("新游戏开始：初始资金 %d 金币" % GameTypes.START_MONEY)
	hud.refresh()

func toggle_pause() -> void:
	if hud.main_menu.visible or hud.demolish_dialog.visible or hud.result_menu.visible:
		return
	paused = not paused
	hud.show_pause_menu(paused)

func quit_to_menu() -> void:
	paused = false
	hud.hide_all_overlays()
	hud.show_main_menu()

func save_game() -> void:
	if SaveSystem.save(self):
		hud.show_toast("游戏已保存")
	else:
		hud.show_toast("保存失败")

func load_game() -> void:
	if SaveSystem.load(self):
		hud.hide_all_overlays()
		paused = false
		mode = MODE_NONE
		hud.show_toast("存档已恢复，从原状态继续")
		hud.refresh()
	else:
		hud.show_toast("没有可用存档或存档已损坏")

# ===========================================================================
# 输入
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if hud.any_overlay_open():
		if event.is_action_pressed("ui_cancel") and hud.demolish_dialog.visible:
			cancel_demolish()
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _panning:
			camera.position -= event.relative / camera.zoom.x
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(event.position, 1.12)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(event.position, 1.0 / 1.12)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	var cell: Variant = _cell_at_mouse(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if mode != MODE_NONE:
			cancel_mode()
		else:
			selected_cell = null
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if cell == null:
		return
	match mode:
		MODE_BUILD:
			place_building(cell)
		MODE_DEMOLISH:
			request_demolish(cell)
		MODE_NONE:
			if buildings.has(cell):
				selected_cell = cell
			else:
				selected_cell = null

func _handle_key(event: InputEventKey) -> void:
	var k: int = event.keycode
	match k:
		KEY_R:
			if mode == MODE_BUILD:
				ghost_dir = (ghost_dir + 1) % 4
			elif selected_cell != null:
				rotate_at(selected_cell)
		KEY_ESCAPE:
			if mode != MODE_NONE:
				cancel_mode()
			else:
				toggle_pause()
		KEY_1: set_build_mode(GameTypes.B.BELT)
		KEY_2: set_build_mode(GameTypes.B.HARVESTER)
		KEY_3: set_build_mode(GameTypes.B.CUTTER)
		KEY_4: set_build_mode(GameTypes.B.DRYER)
		KEY_5: set_build_mode(GameTypes.B.PACKAGER)
		KEY_6: set_demolish_mode()
		KEY_P: toggle_pause()

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before: Vector2 = camera.get_global_mouse_position()
	camera.zoom = (camera.zoom * factor).clamp(Vector2(0.5, 0.5), Vector2(2.6, 2.6))
	var after: Vector2 = camera.get_global_mouse_position()
	camera.position += before - after

# ===========================================================================
# 镜头与悬停
# ===========================================================================
func _update_camera(delta: float) -> void:
	var speed: float = 560.0 / camera.zoom.x
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if move != Vector2.ZERO:
		camera.position += move.normalized() * speed * delta
	var half: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom.x
	var world_size: Vector2 = Vector2(GameTypes.GRID_W, GameTypes.GRID_H) * GameTypes.CELL
	camera.position.x = clamp(camera.position.x, half.x * 0.6, world_size.x - half.x * 0.6)
	camera.position.y = clamp(camera.position.y, half.y * 0.6, world_size.y - half.y * 0.6)

func _update_hover() -> void:
	hover_cell = _cell_at_mouse(get_viewport().get_mouse_position())

func _cell_at_mouse(screen_pos: Vector2) -> Variant:
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var cell := Vector2i(floor(world_pos / float(GameTypes.CELL)))
	if not _in_bounds(cell):
		return null
	return cell

func _safe_hover() -> Vector2i:
	if hover_cell != null:
		return hover_cell
	return Vector2i.ZERO

# ===========================================================================
# 小工具
# ===========================================================================
func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GameTypes.GRID_W and cell.y < GameTypes.GRID_H

func _is_belt(cell: Vector2i) -> bool:
	return buildings.has(cell) and buildings[cell]["t"] == GameTypes.B.BELT

func _target_is_port(cell: Vector2i) -> bool:
	return buildings.has(cell) and buildings[cell]["t"] == GameTypes.B.PORT
