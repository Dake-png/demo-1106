extends RefCounted

## 武器目录（纯数据）：新增武器只需在 CATALOG 里加一条，玩家/子弹/UI 逻辑无需改动
## 实际伤害 = 属性面板攻击 × atk_mult
## 实际间隔 = 面板射击间隔 ÷ rate_mult（rate_mult 即攻速倍率）

const PX_PER_METER := 30.0
# 子弹口径：mm → 像素半径；每比 10mm 多 1mm，伤害 +1%、飞行速度 -1%
const MM_TO_PX := 0.4
const BASE_MM := 10.0
const MM_DAMAGE_PER := 0.01
const MM_SPEED_PER := 0.01

const CATALOG := {
	"pistol": {
		"name": "小手枪", "icon": "🔫", "rarity": "common", "price": 0,
		"rate_mult": 10.0, "atk_mult": 1.0, "multi_mult": 1.2, "crit_add": 0.05,
		"aoe_meter": 0.0, "pierce": 2, "bullet_shape": "circle", "bullet_mm": 10.0,
		# 施加 effect：effect=效果 id，positive=true 为 buff，chance=施加概率（每满 100% 多施加一次）
		# coef=元素伤害系数：触发时造成 武器伤害×coef 的元素伤害
		"apply": [
			{"effect": "magnet", "positive": false, "chance": 0.5, "coef": 0.5, "targets": ["enemy"]},
		],
	},
	"grenade": {
		"name": "榴弹炮", "icon": "💣", "rarity": "gold", "price": 200,
		"rate_mult": 0.3, "atk_mult": 3.0, "multi_mult": 1.0, "crit_add": 0.20,
		"aoe_meter": 5.0, "pierce": 0, "bullet_shape": "hex", "bullet_mm": 20.0,
		"apply": [
			{"effect": "burn", "positive": false, "chance": 1.5, "coef": 1.0, "targets": ["enemy"]},
		],
	},
	"Ak47": {
		"name": "Ak47", "icon": "🅰️", "rarity": "gold", "price": 200,
		"rate_mult": 1.1, "atk_mult": 1.5, "multi_mult": 1.0, "crit_add": 0.15,
		"aoe_meter": 2.0, "pierce": 2, "bullet_shape": "hex", "bullet_mm": 20.0,
		"apply": [
			{"effect": "burn", "positive": false, "chance": 1.5, "coef": 0.5, "targets": ["enemy"]},
			{"effect": "magnet", "positive": false, "chance": 1.5, "coef": 0.3, "targets": ["enemy"]},
		],
	},
	"Sanhua": {
		"name": "散华", "icon": "🌸", "rarity": "red", "price": 400,
		"rate_mult": 0.9, "atk_mult": 2.0, "multi_mult": 10.0, "crit_add": 0.5,
		"aoe_meter": 2.0, "pierce": 2, "bullet_shape": "hex", "bullet_mm": 20.0,
		"apply": [
			{"effect": "freeze", "positive": false, "chance": 2.0, "coef": 0.5, "targets": ["enemy"]},
			{"effect": "magnet", "positive": false, "chance": 1.5, "coef": 0.3, "targets": ["enemy"]},
			]
		}
	}


static func get_weapon(id: String):
	return CATALOG[id] if CATALOG.has(id) else CATALOG["pistol"]


static func aoe_radius(w: Dictionary) -> float:
	return float(w.get("aoe_meter", 0.0)) * PX_PER_METER


static func bullet_mm(w: Dictionary) -> float:
	return float(w.get("bullet_mm", BASE_MM))


## 碰撞体与绘制共用的像素半径
static func bullet_radius_px(w: Dictionary) -> float:
	return maxf(1.5, bullet_mm(w) * MM_TO_PX)


## 口径伤害加成：10mm 为基准，每多 1mm +1%
static func bullet_damage_mult(w: Dictionary) -> float:
	return maxf(0.1, 1.0 + (bullet_mm(w) - BASE_MM) * MM_DAMAGE_PER)


## 口径速度惩罚：10mm 为基准，每多 1mm -1%
static func bullet_speed_mult(w: Dictionary) -> float:
	return maxf(0.1, 1.0 - (bullet_mm(w) - BASE_MM) * MM_SPEED_PER)
