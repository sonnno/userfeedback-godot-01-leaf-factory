extends SceneTree
## 端到端目标测试：用直连、无绕线的稳健布局跑满两个阶段目标。
## 阶段一靠一条水平直连干叶线；阶段二靠两台烘干机直连包装机两侧。

var main: Node2D
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.hud.hide_all_overlays()
	main.paused = false
	main.reset_state()
	main.hud.hide_all_overlays()
	main.money = 100000

	# ---- 阶段一直连线：采收->切割->烘干->带->出货口（y=4，远离包装机）----
	var port: Vector2i = main.port_cell
	var y1: int = 4
	main.buildings[Vector2i(2, y1)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(3, y1)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(4, y1)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(5, y1)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(6, y1)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_RIGHT)
	for x in range(7, port.x):
		main.buildings[Vector2i(x, y1)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	# 出货口在 (port.x, port.y)，干叶线在 y1，需要一个转弯进入出货口正面
	main.buildings[Vector2i(port.x, y1)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_DOWN)
	for yy in range(y1 + 1, port.y):
		main.buildings[Vector2i(port.x, yy)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_DOWN)

	# ---- 阶段二：包装机 (10,12) 朝上，左右两侧各直连一台烘干机 ----
	var pc := Vector2i(10, 12)
	main.buildings[pc] = main._make_building(GameTypes.B.PACKAGER, GameTypes.DIR_UP)
	# 左烘干机 (8,12) 朝右，输出经 (9,12) 进包装机左口
	main.buildings[Vector2i(8, 12)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(9, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	# 右烘干机 (12,12) 朝左，输出经 (11,12) 进包装机右口
	main.buildings[Vector2i(12, 12)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_LEFT)
	main.buildings[Vector2i(11, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_LEFT)
	# 两台烘干机持续喂切叶：各放一台切割机直连其背面
	main.buildings[Vector2i(6, 12)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(7, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(14, 12)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_LEFT)
	main.buildings[Vector2i(13, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_LEFT)
	# 切割机喂原叶：各放一台采收机直连切割机背面
	main.buildings[Vector2i(4, 12)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(5, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	main.buildings[Vector2i(16, 12)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_LEFT)
	main.buildings[Vector2i(15, 12)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_LEFT)
	# 包装机输出朝上，独立专线：沿 x=10 一路向上到 y=2，右转到出货口列正上方，再下行进入出货口
	for yy in range(2, 12):
		if not main.buildings.has(Vector2i(10, yy)):
			main.buildings[Vector2i(10, yy)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_UP)
	# 顶行 y=2 右转（x 从 11 到出货口列）
	for xx in range(11, port.x + 1):
		if not main.buildings.has(Vector2i(xx, 2)):
			main.buildings[Vector2i(xx, 2)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	# 出货口列从 y=2 下行进入出货口（y=3..port.y-1）
	for yy in range(3, port.y):
		if not main.buildings.has(Vector2i(port.x, yy)):
			main.buildings[Vector2i(port.x, yy)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_DOWN)

	var guard: int = 0
	while not main.goal_done and guard < 8000:
		_tick_once()
		guard += 1
	check(main.goal_done, "两个阶段目标全部完成")
	check(main.sold.get(GameTypes.I.DRY, 0) >= 10, "阶段一：卖出至少 10 份干叶（实际 %d）" % main.sold.get(GameTypes.I.DRY, 0))
	check(main.sold.get(GameTypes.I.BOX, 0) >= 10, "阶段二：卖出至少 10 盒茶（实际 %d）" % main.sold.get(GameTypes.I.BOX, 0))
	check(main.total_income > 0, "累计收入为正（%d）" % main.total_income)
	print("")
	if failures == 0:
		print("端到端目标测试通过 ✅  sold=", main.sold, " income=", main.total_income, " 拍数=", guard)
		quit(0)
	else:
		print("%d 项失败 ❌" % failures)
		quit(1)

func check(cond: bool, name: String) -> void:
	checks += 1
	if cond:
		print("  ✓ ", name)
	else:
		failures += 1
		print("  ✗ ", name)

func _tick_once() -> void:
	main.world_time += GameTypes.TICK
	main.belt_accum = GameTypes.TICK
	main._process_machines(GameTypes.TICK)
	main._resolve_movement()
	main.belt_accum = 0.0
