extends SceneTree
## 可视化烟雾测试：自动建一条完整生产线，运行若干秒后截图，验证渲染与全链路。
## 运行：Godot --script res://tests/smoke_screenshot.gd（非 headless 才能渲染）

var main: Node2D
var _frames: int = 0

func _initialize() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.hud.hide_all_overlays()
	main.paused = false
	_build_line()
	# 运行 25 秒模拟（约 100 拍），让货物走完加工链并到达出货口
	for i in 1000:
		await process_frame
	_capture()
	print("截图完成，sold=", main.sold, " money=", main.money)
	quit(0)

func _build_line() -> void:
	# 采收机 -> 传送带 -> 切割机 -> 烘干机 -> 长传送带 -> 出货口
	var port: Vector2i = main.port_cell
	var row: int = port.y
	# 采收机 (4,row) 朝右
	main.buildings[Vector2i(4, row)] = main._make_building(GameTypes.B.HARVESTER, GameTypes.DIR_RIGHT)
	# 切割机 (6,row) 朝右（输入在背面左）
	main.buildings[Vector2i(6, row)] = main._make_building(GameTypes.B.CUTTER, GameTypes.DIR_RIGHT)
	# 烘干机 (8,row) 朝右
	main.buildings[Vector2i(8, row)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_RIGHT)
	# 传送带连接 (5,row),(7,row) 以及 (9..port.x-1, row)
	for x in [5, 7]:
		main.buildings[Vector2i(x, row)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	for x in range(9, port.x):
		main.buildings[Vector2i(x, row)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_RIGHT)
	# 镜头对准生产线中部
	main.camera.position = Vector2(11, row) * GameTypes.CELL
	main.camera.zoom = Vector2(1.0, 1.0)

func _capture() -> void:
	var img: Image = root.get_texture().get_image()
	var path := "user://smoke_line.png"
	img.save_png(path)
	print("已保存截图：", ProjectSettings.globalize_path(path))
