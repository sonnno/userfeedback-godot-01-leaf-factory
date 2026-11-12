extends SceneTree
## 可视化烟雾测试 2：包装机双输入 + 主菜单 / 工具条界面截图

var main: Node2D

func _initialize() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.hud.hide_all_overlays()
	main.paused = false
	# 包装机放在 (10,9) 朝上，两台烘干机分别从左右两侧供干叶
	var pc := Vector2i(10, 9)
	main.buildings[pc] = main._make_building(GameTypes.B.PACKAGER, GameTypes.DIR_UP)
	main.buildings[Vector2i(10, 7)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_DOWN)
	main.buildings[Vector2i(10, 11)] = main._make_building(GameTypes.B.DRYER, GameTypes.DIR_UP)
	main.buildings[Vector2i(10, 8)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_DOWN)
	main.buildings[Vector2i(10, 10)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_UP)
	# 输出朝上接一条传送带
	main.buildings[Vector2i(10, 6)] = main._make_building(GameTypes.B.BELT, GameTypes.DIR_UP)
	# 给烘干机直接塞原料，让包装机有料可加工
	main.buildings[Vector2i(10, 7)]["in"] = GameTypes.I.CUT
	main.buildings[Vector2i(10, 11)]["in"] = GameTypes.I.CUT
	# 进入建造模式显示幽灵预览与底部工具条
	main.set_build_mode(GameTypes.B.HARVESTER)
	main.ghost_dir = GameTypes.DIR_RIGHT
	main.hover_cell = Vector2i(13, 9)
	# 选中包装机显示检查器
	main.selected_cell = pc
	main.camera.position = Vector2(10, 9) * GameTypes.CELL
	main.camera.zoom = Vector2(1.3, 1.3)
	for i in 300:
		await process_frame
	var img: Image = root.get_texture().get_image()
	var path := "user://smoke_packager.png"
	img.save_png(path)
	print("已保存：", ProjectSettings.globalize_path(path), " packager=", main.buildings[pc])
	quit(0)
