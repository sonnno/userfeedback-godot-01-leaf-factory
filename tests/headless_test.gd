extends SceneTree
## 无头自动化测试（不依赖渲染窗口）：
##   Godot_v4.7.2-stable_win64.exe --headless --script res://tests/headless_test.gd
## 直接实例化 Main 并驱动内部模拟，验证规格中的守恒、节拍、汇流、
## 堵塞停机、出售、拆除返还与存档恢复等关键行为。

var main: Node2D
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	print("=== 青叶加工厂 无头逻辑测试 ===")
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	# 等待 _ready 完成（HUD/相机在 _ready 中创建）
	await process_frame
	# 关闭菜单覆盖，让模拟处于可运行状态
	main.hud.hide_all_overlays()
	main.paused = false

	_test_belt_movement_and_tick()
	_test_harvester_and_cutter_chain()
	_test_dryer_sale_and_goal()
	_test_packager()
	_test_merge_alternation()
	_test_blocking()
	_test_economy_and_demolish()
	_test_save_load()
	_test_rotation_and_placement_rules()
	_test_pause_freezes()

	print("")
	if failures == 0:
		print("全部 %d 项断言通过 ✅" % checks)
		quit(0)
	else:
		print("%d / %d 项断言失败 ❌" % [failures, checks])
		quit(1)

# ---- 断言与驱动工具 -------------------------------------------------------
func check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("  ✓ ", name)
	else:
		failures += 1
		print("  ✗ 失败：", name)

func tick(n: int = 1) -> void:
	# 精确推进 n 个逻辑拍（同时让机器加工计时推进相同时间）
	for i in n:
		main.world_time += GameTypes.TICK
		main.belt_accum = GameTypes.TICK
		main._process_machines(GameTypes.TICK)
		main._resolve_movement()
	main.belt_accum = 0.0

func belt(item_t: int, x: int, y: int, dir: int = GameTypes.DIR_RIGHT) -> void:
	main.buildings[Vector2i(x, y)] = main._make_building(GameTypes.B.BELT, dir)

func count_items(t: int) -> int:
	var n: int = 0
	for item in main.belt_items:
		if item["t"] == t:
			n += 1
	return n

# ---- 1. 传送带节拍：每 0.25 秒一格 -----------------------------------------
func _test_belt_movement_and_tick() -> void:
	print("[1] 传送带节拍与逐格移动")
	main.reset_state()
	main.hud.hide_all_overlays()
	belt(GameTypes.I.RAW, 1, 1)
	belt(GameTypes.I.RAW, 2, 1)
	belt(GameTypes.I.RAW, 3, 1)
	main.belt_items.append({
		"t": GameTypes.I.RAW, "from": Vector2i(1, 1), "to": Vector2i(1, 1),
		"start_time": main.world_time, "stalled": false,
	})
	tick()
	check(count_items(GameTypes.I.RAW) == 1 and main.belt_items[0]["to"] == Vector2i(2, 1), "货物前进一格 (1,1)->(2,1)")
	tick()
	check(main.belt_items[0]["to"] == Vector2i(3, 1), "再前进一格到 (3,1)")
	# 每格最多一件：在 (4,1) 前加一件 (5,1) 来的货，第一件进 (4,1) 后第二件必须等待
	belt(0, 4, 1)
	belt(0, 5, 1, GameTypes.DIR_LEFT)
	main.belt_items.append({
		"t": GameTypes.I.RAW, "from": Vector2i(5, 1), "to": Vector2i(5, 1),
		"start_time": main.world_time, "stalled": false,
	})
	tick()
	check(main.belt_items[0]["to"] == Vector2i(4, 1), "第一件进入 (4,1)")
	check(main.belt_items[1]["to"] == Vector2i(5, 1) and main.belt_items[1].get("stalled", false), "第二件留在原地并标记堵塞")
	tick()
	check(main.belt_items[1].get("stalled", false), "下游持续堵塞时货物持续停留")

# ---- 2. 采收机 -> 切割机 加工链 -------------------------------------------
func _test_harvester_and_cutter_chain() -> void:
	print("[2] 采收机 2 秒产原叶，切割机 1 秒产切叶")
	main.reset_state()
	main.hud.hide_all_overlays()
	main.money = 10000
	# 采收机 (2,2) 朝右（输出到 (3,2)），传送带 (3,2) 朝右，切割机 (4,2) 朝右（输入在背面左侧 (3,2)）
	main.buildings[Vector2i(2, 2)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_RIGHT)
	belt(0, 3, 2, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(4, 2)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_RIGHT)
	# 8 拍 = 2 秒：采收机产出并经传送带送入切割机输入缓存
	tick(12)
	var c: Dictionary = main.buildings[Vector2i(4, 2)]
	check(c["in"] == GameTypes.I.RAW, "切割机收到原叶")
	tick(4)
	check(c["out"] == GameTypes.I.CUT and c["in"] == null, "1 秒后原叶加工为切叶")

# ---- 3. 烘干机周期与出货口出售 --------------------------------------------
func _test_dryer_sale_and_goal() -> void:
	print("[3] 烘干机 2 秒产干叶，出货口实际到达才结算")
	main.reset_state()
	main.hud.hide_all_overlays()
	var port: Vector2i = main.port_cell
	main.money = 10000
	# 烘干机 (21,9) 朝右：输入在背面左侧、输出到右侧 (22,9)，传送带 (22,9) 朝右通向出货口
	var dryer_cell := port + Vector2i(-2, 0)
	main.buildings[dryer_cell] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_RIGHT)
	belt(0, port.x - 1, port.y, GameTypes.DIR_RIGHT)
	var d: Dictionary = main.buildings[dryer_cell]
	d["in"] = GameTypes.I.CUT
	var money_before: int = main.money
	var income_before: int = main.total_income
	tick(9)  # 略多于 2 秒，确保烘干完成并尝试输出
	check(d["out"] == GameTypes.I.DRY or main.sold.get(GameTypes.I.DRY, 0) >= 1, "烘干机产出干叶")
	tick(4)
	check(d["out"] == null, "干叶离开烘干机")
	check(main.sold.get(GameTypes.I.DRY, 0) == 1, "恰好 1 份干叶被出货口收购")
	check(main.total_income == income_before + 12 and main.money == money_before + 12, "收入与金币各增加 12")
	# 原叶不收购：把原叶送到出货口正面的传送带，下一拍到达时被拒收，货物原地停留
	var feed: Vector2i = port + Vector2i(-1, 0)
	if not main.buildings.has(feed):
		belt(0, feed.x, feed.y, GameTypes.DIR_RIGHT)
	main.belt_items.append({
		"t": GameTypes.I.RAW, "from": feed, "to": feed,
		"start_time": main.world_time, "stalled": false,
	})
	tick(2)
	check(main.sold.get(GameTypes.I.RAW, 0) == 0, "原叶不被结算")
	check(main.belt_items.size() == 1 and main.belt_items[0]["t"] == GameTypes.I.RAW, "原叶被出货口拒收后留在传送带上")

# ---- 4. 包装机：两侧各一份干叶，3 秒一盒 ----------------------------------
func _test_packager() -> void:
	print("[4] 包装机双输入与 3 秒产出")
	main.reset_state()
	main.hud.hide_all_overlays()
	var pcell := Vector2i(5, 5)
	main.buildings[pcell] = main._make_building(GameTypes.B.PACKAGER, GameTypes.DIR_UP)
	var p: Dictionary = main.buildings[pcell]
	# 只有一侧有料：不能开工
	p["in"] = [GameTypes.I.DRY, null]
	tick(12)
	check(p["out"] == null and p["progress"] == 0.0, "单侧干叶不启动包装")
	# 两侧齐料
	p["in"] = [GameTypes.I.DRY, GameTypes.I.DRY]
	tick(12)  # 3 秒
	check(p["out"] == GameTypes.I.BOX and p["in"] == [null, null], "3 秒后两侧干叶 -> 1 盒茶，输入清空")
	# 侧口方向判定：朝上时左右两侧可进，正面（上）不能进
	check(main._is_input_face(pcell, p, Vector2i(4, 5)), "左侧为输入面")
	check(main._is_input_face(pcell, p, Vector2i(6, 5)), "右侧为输入面")
	check(not main._is_input_face(pcell, p, Vector2i(5, 4)), "正面不是输入面")
	check(main._packager_slot(GameTypes.DIR_UP, Vector2i(-1, 0)) == 0, "左槽位编号 0")
	check(main._packager_slot(GameTypes.DIR_UP, Vector2i(1, 0)) == 1, "右槽位编号 1")

# ---- 5. 多路汇流交替放行 ---------------------------------------------------
func _test_merge_alternation() -> void:
	print("[5] 两路汇流轮转交替，每拍目标只收一件")
	main.reset_state()
	main.hud.hide_all_overlays()
	# Y 形汇流：上路 (4,2) 朝下、下路 (4,4) 朝上，共同汇入 (4,3)，再进汇流格 (5,3)（后接长直道）
	belt(0, 4, 3, GameTypes.DIR_RIGHT)
	belt(0, 5, 3, GameTypes.DIR_RIGHT)
	for x in range(6, 14):
		belt(0, x, 3, GameTypes.DIR_RIGHT)
	belt(0, 4, 2, GameTypes.DIR_DOWN)
	belt(0, 4, 4, GameTypes.DIR_UP)
	belt(0, 3, 2, GameTypes.DIR_RIGHT)
	belt(0, 3, 4, GameTypes.DIR_RIGHT)
	main.belt_items.append({
		"t": GameTypes.I.RAW, "from": Vector2i(3, 2), "to": Vector2i(4, 2),
		"start_time": main.world_time, "stalled": false,
	})
	main.belt_items.append({
		"t": GameTypes.I.CUT, "from": Vector2i(3, 4), "to": Vector2i(4, 4),
		"start_time": main.world_time, "stalled": false,
	})
	var seen_raw: bool = false
	var seen_cut: bool = false
	for i in 14:
		tick()
		# 每拍后汇流格 (4,3) 上至多一件（只统计以它为目标的在途货物）
		var n: int = 0
		var wtype: int = -1
		for item in main.belt_items:
			if item["to"] == Vector2i(4, 3):
				n += 1
				wtype = item["t"]
		check(n <= 1, "第 %d 拍汇流格至多一件" % (i + 1))
		if n == 1:
			if wtype == GameTypes.I.RAW:
				seen_raw = true
			elif wtype == GameTypes.I.CUT:
				seen_cut = true
	check(seen_raw and seen_cut, "两条来路都被交替放行过")

# ---- 6. 堵塞：下游满 -> 设备停机，腾出空间后续工 ---------------------------
func _test_blocking() -> void:
	print("[6] 下游堵塞时设备停机，腾出空间后继续")
	main.reset_state()
	main.hud.hide_all_overlays()
	main.money = 10000
	# 采收机 (5,5) 朝左（输出到 (4,5)）；两格传送带 (4,5)->(3,5) 朝左，
	# (3,5) 的下一格 (2,5) 为空，货物到达 (3,5) 后无路可走，形成死路
	main.buildings[Vector2i(5, 5)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_LEFT)
	belt(0, 4, 5, GameTypes.DIR_LEFT)
	belt(0, 3, 5, GameTypes.DIR_LEFT)
	tick(8)   # 第一件产出：进入传送带 (4,5)
	var h: Dictionary = main.buildings[Vector2i(5, 5)]
	check(count_items(GameTypes.I.RAW) == 1, "首份原叶进入传送带")
	# 再等 4 秒：两件货填满 (4,5)/(3,5)，采收机第二件堵在输出缓存，机器停机
	tick(16)
	check(h["out"] == GameTypes.I.RAW and h["progress"] == 0.0, "下游堵塞后采收机停机，不超产")
	# 拆除堵死的传送带，换一条向上再向右的通路（(4,5) 是机器输出格，必须重新铺带）
	main._do_demolish(Vector2i(4, 5))
	main._do_demolish(Vector2i(3, 5))
	belt(0, 4, 5, GameTypes.DIR_UP)
	belt(0, 4, 4, GameTypes.DIR_UP)
	belt(0, 4, 3, GameTypes.DIR_RIGHT)
	belt(0, 5, 3, GameTypes.DIR_RIGHT)
	var steps: int = 0
	while h["out"] != null and steps < 12:
		tick()
		steps += 1
	check(h["out"] == null, "腾出通路后缓存货物被推出")
	# 缓存排空后采收机重新计时，给足 2 秒以上等待新一份原叶产出
	var produced: bool = false
	for i in 12:
		tick()
		if h["out"] == GameTypes.I.RAW or count_items(GameTypes.I.RAW) > 0:
			produced = true
			break
	check(produced, "采收机恢复生产")
	check(main.get_machine_state(Vector2i(5, 5)) != "idle", "设备状态可查询")

# ---- 7. 金币、建造限制与拆除 80% 返还 --------------------------------------
func _test_economy_and_demolish() -> void:
	print("[7] 经济规则：价格、余额不足禁建、拆除返还 80% 向下取整")
	main.reset_state()
	main.hud.hide_all_overlays()
	check(main.money == 600, "初始资金 600")
	main.ghost_type = GameTypes.B.PACKAGER
	main.ghost_dir = GameTypes.DIR_UP
	check(main.can_place(Vector2i(3, 3)), "资金充足且空地可建")
	main.place_building(Vector2i(3, 3))
	check(main.money == 600 - 140, "包装机扣款 140")
	check(not main.can_place(Vector2i(3, 3)), "已占用格不可建")
	# 余额不足
	main.money = 4
	main.ghost_type = GameTypes.B.BELT
	check(not main.can_place(Vector2i(4, 4)), "余额 4 不能买 5 金币传送带")
	main.money = 100
	main.place_building(Vector2i(4, 4))
	check(main.money == 95, "传送带扣款 5")
	var refund: int = int(floor(140 * 0.8))
	main.request_demolish(Vector2i(3, 3))
	check(main.hud.demolish_dialog.visible == false, "空设备拆除无需确认")
	check(main.money == 95 + refund and not main.buildings.has(Vector2i(3, 3)), "拆除返还 %d（80%% 向下取整）" % refund)
	# 含货物设备需确认，确认后丢弃货物
	main.buildings[Vector2i(6, 6)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_UP)
	main.buildings[Vector2i(6, 6)]["out"] = GameTypes.I.RAW
	main.request_demolish(Vector2i(6, 6))
	check(main.hud.demolish_dialog.visible and main.pending_demolish == Vector2i(6, 6), "含货物设备弹出确认框")
	var money_before: int = main.money
	main.confirm_demolish()
	check(not main.buildings.has(Vector2i(6, 6)) and main.money == money_before + int(floor(60 * 0.8)), "确认后拆除并丢弃货物、返还 48")

# ---- 8. 存档：恢复布局/缓存/在途货物/金币/目标 -----------------------------
func _test_save_load() -> void:
	print("[8] 保存与恢复")
	main.reset_state()
	main.hud.hide_all_overlays()
	main.money = 333
	main.total_income = 210
	main.sold[GameTypes.I.DRY] = 4
	main.phase = 2
	main.buildings[Vector2i(7, 7)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_DOWN)
	main.buildings[Vector2i(7, 7)]["in"] = GameTypes.I.RAW
	main.buildings[Vector2i(7, 7)]["progress"] = 0.37
	belt(0, 8, 7, GameTypes.DIR_RIGHT)
	main.belt_items.append({
		"t": GameTypes.I.CUT, "from": Vector2i(8, 7), "to": Vector2i(9, 7),
		"start_time": 12.5, "stalled": true,
	})
	var path := "user://test_save.json"
	check(SaveSystem.save(main, path), "存档写入成功")
	# 打乱现场
	main.money = 0
	main.buildings.clear()
	main.belt_items.clear()
	main.phase = 1
	check(SaveSystem.load(main, path), "存档读取成功")
	check(main.money == 333 and main.total_income == 210 and main.phase == 2, "金币/收入/阶段恢复")
	check(main.sold[GameTypes.I.DRY] == 4, "目标进度恢复")
	var b: Dictionary = main.buildings[Vector2i(7, 7)]
	check(b["t"] == GameTypes.B.CUTTER and b["dir"] == GameTypes.DIR_DOWN, "布局与朝向恢复")
	check(b["in"] == GameTypes.I.RAW and abs(float(b["progress"]) - 0.37) < 0.001, "缓存与加工进度恢复")
	check(main.belt_items.size() == 1 and main.belt_items[0]["t"] == GameTypes.I.CUT, "在途货物恢复")
	check(main.belt_items[0]["from"] == Vector2i(8, 7) and main.belt_items[0]["to"] == Vector2i(9, 7), "在途货物位置恢复")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---- 9. 旋转与放置规则 -----------------------------------------------------
func _test_rotation_and_placement_rules() -> void:
	print("[9] 旋转与边界/占用规则")
	main.reset_state()
	main.hud.hide_all_overlays()
	main.money = 10000
	main.buildings[Vector2i(9, 9)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_UP)
	main.rotate_at(Vector2i(9, 9))
	check(main.buildings[Vector2i(9, 9)]["dir"] == GameTypes.DIR_RIGHT, "R 旋转设备朝向")
	check(not main.can_place(Vector2i(9, 9)), "占用格禁止建造")
	check(not main.can_place(Vector2i(-1, 0)) and not main.can_place(Vector2i(24, 0)), "越界格禁止建造")
	check(not main.can_demolish(main.port_cell), "固定出货口不可拆除")
	# 传送带可从任意相邻格接货，但每格最多一件
	belt(0, 10, 9, GameTypes.DIR_RIGHT)
	check(main._can_receive(Vector2i(10, 9), GameTypes.I.RAW, Vector2i(11, 9)), "传送带可从相邻格接货")
	check(main._can_receive(Vector2i(10, 9), GameTypes.I.RAW, Vector2i(9, 9)), "传送带背面同样可接货")

# ---- 10. 暂停冻结一切计时 --------------------------------------------------
func _test_pause_freezes() -> void:
	print("[10] 暂停时生产与运输同时停止")
	main.reset_state()
	main.hud.hide_all_overlays()
	main.buildings[Vector2i(2, 2)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_UP)
	var h: Dictionary = main.buildings[Vector2i(2, 2)]
	main.paused = true
	for i in 40:
		main._process(GameTypes.TICK)
	check(h["out"] == null and main.world_time == 0.0, "暂停期间无产出、世界时间不走")
	main.paused = false
	for i in 40:
		main._process(GameTypes.TICK)
	check(h["out"] == GameTypes.I.RAW, "恢复后加工继续")
