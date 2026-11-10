# 项目框架速读（给 AI / 新开发者）

> 一句话：Godot 4.6 + GDScript 的 2D 俯视角割草 Demo。
> **数值/目录为数据驱动**（武器 / Effect / Boss / 任务 / 卡牌 / 道具均为「表 + 通用逻辑」，新增内容只加数据条目）；但 UI 构建与输入处理仍有硬编码（如 E 键背包写在 `backpack_input.gd`）。
> **UI 全部用代码动态创建**（没有 .tscn UI 布局）：`scripts/ui/` 下按面板拆分（HUD / 武器栏 / 背包 / 商店 / 任务 / 升级 / 设置），`main.gd` 负责组装、暂停与业务。
> 当前版本：**v3.5**

---
# 回答尽量简短，只说结果，不说原因
# 开始执行前询问关键细节
## 1. 运行方式

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.6.2，GDScript，2D，`gl_compatibility` |
| 主场景 | `res://scenes/main.tscn` → `scripts/main.gd` |
| 窗口 | 1920x1080，`stretch/mode = canvas_items` |
| Autoload | `EventBus`（`scripts/event_bus.gd`，全局事件总线）；其余模块用 `preload` 静态表 + 实例 signal 通信 |
| 输入 | `project.godot` 中只注册了 `move_left/right/up/down`（WASD / 方向键）、`dash`（空格）、`shoot`（鼠标左键）；没有 `inventory` action，背包开关键 E 硬编码在 `backpack_input.gd` |
| 存档 | `user://save.cfg`（`_save_game` / `_load_game`，每 5 秒自动存：任务、Boss 进度、金币、等级、背包与物品栏） |

---

## 2. 目录结构

```
demo-1106/
├─ project.godot              # 主场景 / 输入映射 / 显示与渲染设置
├─ scenes/
│  ├─ main.tscn               # 唯一常驻场景（空 Node2D，逻辑全在脚本）
│  ├─ player.tscn  enemy.tscn  bullet.tscn  boss.tscn  boss_orb.tscn
│  └─ coin.tscn  exp_orb.tscn  item.tscn
├─ scripts/
│  ├─ main.gd                 # ★ 游戏主控：组装 UI、暂停协调、任务奖励、击杀/掉落计数
│  ├─ combat.gd               # 战斗结算：子弹生成 / 命中 / 范围伤害 / effect 施加
│  ├─ spawner.gd              # 生成器：金币 / 敌人 / Boss / 掉落物 + 生成循环 Timer
│  ├─ save_system.gd          # 存档：写盘 / 读盘恢复 / 自动存档计时
│  ├─ player.gd               # 玩家：移动/冲刺/射击/暴击/护盾护甲/经验升级/武器切换
│  ├─ enemy.gd                # 敌人：三角(快脆)/方形(均衡)/五边形(坦克)，血条颜色随血量
│  ├─ boss.gd                 # 通用 Boss 基类：数值/外观/技能全读 boss_data
│  ├─ boss_data.gd            # Boss 目录（纯数据）：小恶魔 / 牛头人
│  ├─ boss_skills/            # Boss 技能组件：shoot(扇形弹) / summon(召唤) / ring(红圈)
│  ├─ bullet.gd               # 玩家子弹：形状/大小/范围伤害/穿透/effect 施加
│  ├─ boss_orb.gd             # Boss 弹幕
│  ├─ coin.gd  exp_orb.gd  item.gd   # 掉落物（金币 / 经验球 / 通用道具，外观与效果读 item_data）
│  ├─ armor.gd                # 护甲减伤公式（纯函数）
│  ├─ rule_config.gd          # 读取 Gamerule/player.json（角色数值唯一来源）
│  ├─ weapon_data.gd          # 武器目录（纯数据）：手枪 / 榴弹炮 / AK47
│  ├─ effect_data.gd          # Effect 目录（纯数据）：燃烧 / 磁力 / 碎盾
│  ├─ effect_holder.gd        # Effect 运行时容器：层数/计时/伤害与护盾系数
│  ├─ event_bus.gd            # 全局事件总线（Autoload）：敌人/Boss/掉落物广播，main 订阅
│  ├─ sfx_player.gd           # 纯代码合成音效，main 只调 play(name)
│  ├─ damage_numbers.gd       # 伤害飘字（基础/持续/触发），main 只调 spawn_*
│  ├─ ui/
│  │  ├─ ui_style.gd          # 通用样式工厂（进度条 / 面板 / 卡片）
│  │  ├─ rich_text.gd         # RichTextLabel 文案拼装（数值差 / 百分比）
│  │  ├─ hud_ui.gd            # 顶部 HUD + Boss 血条 + 底部 Buff 栏
│  │  ├─ weapon_ui.gd         # 右侧武器切换栏 + 武器详情浮窗
│  │  ├─ inventory_ui.gd      # 物品栏 + 背包弹窗（拖拽 / 使用）
│  │  ├─ shop_ui.gd           # 商店弹窗（卡牌 / 武器 / 固定商品）
│  │  ├─ quest_ui.gd          # 左侧任务栏（拖动 / 收起 / 完成飘字）
│  │  ├─ upgrade_ui.gd        # 升级选卡弹窗
│  │  └─ settings_ui.gd       # 设置弹窗 + 左下角帧率（开关发信号给 main）
│  ├─ card_data.gd            # 卡牌系统（纯数据）：稀有度概率 + 卡牌目录 + 抽卡
│  ├─ item_data.gd            # 道具系统（纯数据）：增伤/磁铁/巨型化/回血 + 掉落权重
│  ├─ inventory.gd            # 物品存储：背包 20 格（堆叠 99）+ 物品栏 5 格
│  ├─ backpack_input.gd       # E 键开关背包（暂停时也能响应）
│  ├─ quest_data.gd           # 任务表：通用任务类型（杀敌/指定怪物/金币/存活）+ 各 Boss 主线文案奖励
│  └─ quest_manager.gd        # 任务运行时（Node）：进度 / 完成判定 / 存档状态，只发信号
├─ Gamerule/
│  ├─ GRule.md                # 策划规则文档（需求来源）
│  ├─ player.json             # 玩家数值（代码唯一读取的 JSON）
│  └─ rule.md                 # 早期规则草稿
└─ PROJECT.md                 # 本文件
```

---

## 3. 模块职责与扩展点

| 文件 | 职责 | 新增内容时怎么改 |
|---|---|---|
| `main.gd` | 主控：组装 UI、暂停协调、任务奖励、击杀计数与拾取处理 | UI 布局改 `scripts/ui/` 对应模块；业务改 main 的逻辑函数 |
| `combat.gd` | 战斗结算：子弹生成 / 命中判定 / 范围伤害 / effect 施加与触发伤害 | 一般不动；武器/effect 数值改对应数据表 |
| `spawner.gd` | 生成器：金币 / 敌人 / Boss / 掉落物与两个生成 Timer | 刷怪节奏改常量；新生成物加一个 `spawn_*` |
| `save_system.gd` | 存档写盘与读盘恢复、自动存档计时 | 新增持久化字段时改 `save_game` / `load_game` 与 main 的组装 |
| `player.gd` | 玩家属性与操作 | 属性默认值可被 `player.json` 覆盖 |
| `weapon_data.gd` | 武器表：倍率/暴击/范围/穿透/施加 effect | `CATALOG` 加一条，无需改逻辑 |
| `effect_data.gd` | Effect 表：buff/debuff 两套数值 | `CATALOG` 加一条 |
| `card_data.gd` | 卡牌表：稀有度概率 / 价格 / 卡牌修饰项 | `CATALOG` 加一条 |
| `item_data.gd` | 道具表：限时修饰（timed）/ 立即效果（instant）+ 掉落权重 | `CATALOG` / `DROP_WEIGHTS` 加一条 |
| `inventory.gd` | 背包与物品栏格子数据（堆叠、拖拽移动、消耗） | 一般不动 |
| `boss_data.gd` | Boss 表：血量/护盾/护甲/技能列表 | 加一条；新技能再加 `boss_skills/` 组件 |
| `quest_data.gd` | 任务表：type（kill / kill_type / coin / survive / boss）+ 奖励与成长 | `QUESTS` 加一条 |
| `quest_manager.gd` | 任务运行时：推进进度、完成判定、存档状态，`completed` 信号交给 main 发奖励 | 一般不动；新任务类型加一个分支 |
| `armor.gd` | `受到伤害 = 伤害 × (1 - ln(护甲+1)/(ln(护甲+1)+3.5355))` | 一般不动 |

---

## 4. 运行时数据流

```
main._ready()
  ├─ 建 UI（HUD/Boss 条/Buff 栏/任务栏/商店/设置/开始菜单）
  ├─ 读 player.json 覆盖玩家数值
  ├─ _pick_next_boss()  → 开局随机 Boss，同步主线任务
  └─ spawner.start_timers()：spawner.spawn_coin / spawner.spawn_enemy

射击：player 按射速与多重射击生成 bullet（combat.spawn_bullet：伤害 = 面板攻击 × 武器 atk_mult × effect 倍率）
命中：combat._bullet_hit → _damage_enemy
      伤害管线：基础×武器倍率 → 暴击段数(×2^段) → effect 承伤倍率 → 护甲减伤 → 护盾 → 生命
      同时 combat._apply_effects 按武器 apply 配置施加 buff/debuff，并结算触发伤害（武器伤害×元素系数）
死亡：敌人自身掉落经验球/金币/道具 → 上报击杀计数（推进任务、Boss 阈值）；Boss 自身掉落 12 金币 + 6 经验球 + 回血药
升级：_on_level_up → 暂停 + 3 张卡（白58%/蓝23%/紫12%/金6%/红1.2%）→ 点击卡牌 apply_upgrade
道具：拾取优先进物品栏（5 格），满则进背包（20 格）；点击物品栏使用，限时道具在 buff 栏显示倒计时
```

---

## 5. 关键系统定位

| 系统 | 入口 / 关键函数（UI 在 `scripts/ui/`，业务在 `scripts/main.gd`） |
|---|---|
| HUD / BUFF 栏 | `scripts/ui/hud_ui.gd`：`build` 建面板，main 只调 `set_hp/set_shield/set_exp/set_score/update_buffs` |
| Boss | 刷新 `spawner.spawn_boss`（每击杀 100 只、与上一只不同）、血条在 `hud_ui.gd`、死亡 `_on_boss_died` |
| 任务 | `scripts/ui/quest_ui.gd` 显示；进度与完成判定在 `quest_manager.gd`，奖励在 main `_on_quest_completed` |
| 商店 | `scripts/ui/shop_ui.gd`：`build_button` / `build_popup` / `open` / `_populate_shop`；金币扣减经 `spend_requested` 回 main |
| 升级选卡 | `scripts/ui/upgrade_ui.gd`：`show_cards` / `hide`；选卡发 `card_chosen`，main 负责加属性与连续升级排队 |
| 设置 | `scripts/ui/settings_ui.gd`：分辨率 / 全屏 / 帧率上限 / 字体缩放 + 左下角 FPS；开关发信号给 main 处理暂停 |
| 存档 | `scripts/save_system.gd`：`save_game` / `load_game` / `tick`；main 负责组装数据与读档后刷新 UI |
| 道具 / 背包 | `scripts/ui/inventory_ui.gd`：物品栏 + 背包弹窗；拾取在 main `_on_item_picked` |
| Effect 运行时 | `scripts/effect_holder.gd`：`damage_mult / taken_mult / shield_max_bonus / shield_drain_rate / shield_regen_delay_add / move_mult` |
| 武器切换 / 属性 UI | `scripts/ui/weapon_ui.gd`（切换 + 详情浮窗）、main `_refresh_attr_panel`（属性面板） |

---

## 6. 常见需求 → 改哪里

- 新增武器：`weapon_data.gd` 加目录条目（倍率/暴击/范围/穿透/apply）
- 新增 Effect：`effect_data.gd` 加条目；需要特殊结算时在 `effect_holder.gd` 加读取函数
- 新增 Boss：`boss_data.gd` 加数据；新技能在 `boss_skills/` 加组件并在 `boss.gd` 的 `SKILLS` 注册
- 新增任务：`quest_data.gd` 加条目；Boss 主线补 `BOSS_QUESTS`
- 新增卡牌 / 改卡池与概率：`card_data.gd` 的 `CATALOG` / `RARITIES`（价格也在 `RARITIES`）
- 新增道具 / 改掉落：`item_data.gd` 的 `CATALOG` / `DROP_WEIGHTS`
- 改背包与物品栏格数 / 堆叠上限：`inventory.gd` 的 `BAG_SLOTS` / `HOTBAR_SLOTS` / `STACK_MAX`
- 改 UI 布局：改 `scripts/ui/` 下对应模块的 `build*` 函数（全部代码构建，无场景文件）
- 改玩家基础数值：优先改 `Gamerule/player.json`（代码里的默认值只是兜底）

---

## 7. 约定与注意事项

1. **UI 用代码动态创建**：没有独立 UI 场景，控件用代码建、锚点用 `set_anchors_preset` + 相对 `position`；每个面板一个 `scripts/ui/*.gd`（`extends Node`，`build(parent, ...)` 挂到 hud_layer，对外发信号），main 只保留暂停协调与业务。
2. **数据驱动优先**：武器 / Effect / Boss / 任务都是「表 + 通用逻辑」，不要为单体写死分支。
3. **缩放与清晰度**：项目固定 1920x1080 + `canvas_items` 拉伸；相机按当前 zoom 对齐像素网格防抖。
4. **暂停语义**：升级/设置/开始菜单/背包用 `get_tree().paused = true`，HUD 层为 `PROCESS_MODE_ALWAYS`；背包开关靠 `backpack_input.gd` 在暂停时也能响应 E 键。
5. **headless 校验**：`--headless` 崩溃多为 `user://logs` 不可写；把 user 数据目录（`APPDATA`）指到可写位置后，可用 `--quit-after` 做冒烟校验。
6. **中文**：注释与 UI 文案均为简体中文，保持一致。
7. **无背景音乐**：BGM 已移除，仅保留 `_play_sfx` 合成音效。
