class_name GameTypes
## 全局常量与枚举：货物 / 设备 / 方向 / 价格 / 加工周期

enum B { BELT, HARVESTER, CUTTER, DRYER, PACKAGER, PORT }
enum I { RAW, CUT, DRY, BOX }

const GRID_W := 24
const GRID_H := 18
const CELL := 64

const TICK := 0.25                  # 传送带每步耗时（秒）
const START_MONEY := 600

const DIR_UP := 0
const DIR_RIGHT := 1
const DIR_DOWN := 2
const DIR_LEFT := 3
const DIR_V: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

const PRICES := {
	B.BELT: 5,
	B.HARVESTER: 60,
	B.CUTTER: 80,
	B.DRYER: 100,
	B.PACKAGER: 140,
}

const CYCLES := {
	B.HARVESTER: 2.0,
	B.CUTTER: 1.0,
	B.DRYER: 2.0,
	B.PACKAGER: 3.0,
}

# 出货口收购价（原叶不收购）
const SELL_PRICE := {
	I.CUT: 5,
	I.DRY: 12,
	I.BOX: 30,
}

const BUILDING_NAMES := {
	B.BELT: "传送带",
	B.HARVESTER: "采收机",
	B.CUTTER: "切割机",
	B.DRYER: "烘干机",
	B.PACKAGER: "包装机",
	B.PORT: "出货口",
}

const ITEM_NAMES := {
	I.RAW: "原叶",
	I.CUT: "切叶",
	I.DRY: "干叶",
	I.BOX: "盒茶",
}

const SAVE_PATH := "user://leaf_factory_save.json"

const GOAL_DRY_COUNT := 10
const GOAL_BOX_COUNT := 10
