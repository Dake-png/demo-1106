extends RefCounted

## Effect 目录（纯数据）：新增一个 Effect = 在 CATALOG 里加一条
## buff / debuff 两套数值，由施加方决定走哪一套；UI 与逻辑自动读取

const CATALOG := {
	"burn": {
		"name": "燃烧", "icon": "🔥", "duration": 10.0,
		"max_stacks": {"buff": 10, "debuff": -1},          # -1 = 无上限
		"stack_rule": {"buff": "refresh", "debuff": "refresh"},
		"buff": {"damage_mult": 0.03},                     # 每层 +3% 造成伤害
		"debuff": {
			"taken_mult": 0.03,                            # 每层 +3% 受到伤害
			"dot_ratio_per_stack_sec": 1.0,                # 每秒造成 武器伤害×火伤害系数×层数×该倍率
		},
	},
	"magnet": {
		"name": "磁力", "icon": "🧲", "duration": 5.0,
		"max_stacks": {"buff": 10, "debuff": 10},
		"stack_rule": {"buff": "extend", "debuff": "extend"},
		"buff": {
			"extend_step": 5.0,                      # 新层 +5 秒
			"shield_max_ratio_per_stack_sec": 0.02,  # 每秒 +2%×层数 护盾上限（结束消失）
		},
		"debuff": {
			"extend_step": 1.0,                      # 首层 5 秒，新层 +1 秒
			"slow_per_stack": 0.07,                  # 每层 -7% 移速
			"shield_drain_ratio_per_stack_sec": 0.02, # 每秒 -2%×层数 护盾
			"mutual_attract": true,                  # 携带者相互吸引，1m 内停止
			"root_at_full": true,                    # 满层束缚：携带者无法移动
			"pull_radius": 360.0,                    # 满层时吸引「未满层敌人」的半径（12 米）
			"pull_speed": 300.0,                     # 吸引速度（大幅）
		},
	},
	"freeze": {
		"name": "冰冻", "icon": "❄️", "duration": 10.0,
		"max_stacks": {"buff": 10, "debuff": 10},
		"stack_rule": {"buff": "extend", "debuff": "extend"},
		"buff": {
			"shield_max_ratio_per_stack": 0.05,      # 每层 +5% 护盾上限
		},
		"debuff": {
			"slow_per_stack": 0.09,                  # 每层 -9% 移速
			"attack_speed_per_stack": 0.09,          # 每层 -9% 攻速
			"crit_taken_per_stack": 0.10,            # 每层 +10% 受到暴击伤害
			"freeze_at_full": true,                  # 满层冻结：无法移动（冰层覆盖表现）（boos不会被冰冻）
		},
	},
	"shatter": {
		"name": "碎盾", "icon": "💥", "duration": 10.0,
		"max_stacks": {"buff": 1, "debuff": 1},
		"stack_rule": {"buff": "refresh", "debuff": "refresh"},
		"buff": {},
		"debuff": {"shield_regen_delay_add": 10.0},   # 护盾回复延迟 +10 秒
	},
}


static func get_effect(id: String) -> Dictionary:
	return CATALOG.get(id, {})


## 施加概率 → 实际施加次数：每满 100% 多施加一次，余数按概率再 +1
static func roll_count(chance: float) -> int:
	if chance <= 0.0:
		return 0
	var c := int(floor(chance))
	if randf() < chance - float(c):
		c += 1
	return c
