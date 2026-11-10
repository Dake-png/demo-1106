# v4.0 升级规划：2.5D 视觉化改造

> 选型结论（已确认）：**2D 伪 2.5D + 继续纯代码绘制 + 高度仅做视觉 + 分阶段推进**
>
> 本版本只改「看起来怎么样」，不改数值、碰撞、命中判定与存档结构。所有实体在世界坐标上仍是平面 `(x, y)`，其中 `y` 视为脚下着地点；「高度」只影响绘制偏移，不参与任何玩法计算。

---

## 1. 目标与边界

### 1.1 目标
1. 画面从「俯视平面色块」升级为「有厚度、有阴影、有前后遮挡的俯视立体」。
2. 保持 1920x1080、相机跟随手感、UI 布局与所有现有系统不变。
3. 每个阶段结束都能正常游玩、可回滚。

### 1.2 明确不做（4.0 范围外）
- 不做等距（isometric）坐标换算，不改移动方向与地图坐标系。
- 不做 3D 网格、不引入 glTF / 贴图资源。
- 不做跳跃、抛射弹道、高低差命中（留给 4.1）。
- 不调整数值、卡牌、Boss 技能逻辑。

### 1.3 完成标准
- 角色绕敌人走动时，前后遮挡关系正确且随 Y 变化。
- 角色、敌人、Boss、掉落物都有贴地椭圆阴影 + 抬升本体，静止截图能看出「立起来了」。
- 范围技能 / 触发圈画在地面（椭圆），不是悬空正圆。
- 1920x1080 下 300 只敌人规模仍稳定 60fps。

---

## 2. 现状盘点（改造阻力点）

| 现状 | 位置 | 对 2.5D 的影响 |
|---|---|---|
| 主场景是单个 `Node2D`，所有实体直接挂在 Main 下，按入树顺序叠放 | `scenes/main.tscn`、`main.gd:131` `spawner.setup(self, WORLD_HALF)` | 没有 Y 轴排序，无法做前后遮挡 |
| 玩家 / 敌人 / Boss / 掉落物 / 子弹各自在同一层自绘 | `player.gd:429`、`enemy.gd:248`、`boss.gd:248/275/307`、`bullet.gd:52`、`coin.gd:27`、`exp_orb.gd:30`、`item.gd:46`、`boss_orb.gd:24` | 全部是平面图形，无阴影、无厚度 |
| 背景由 Main 自己绘制 | `main.gd:615` `_draw` | 地面与实体同层，无法做视差与分层 |
| 相机固定 zoom 1.2、无平滑、无前视 | `scenes/player.tscn`（Camera2D） | 3D 感不足，移动时生硬 |
| 子弹 / 范围圈与角色同层 | `combat.gd:39` `host.add_child(bullet)`、`combat.gd:148` 范围圈 | 会被 Y 排序干扰，必须独立到 Fx 层 |
| 伤害飘字是 world 坐标 `Label` | `damage_numbers.gd:19-43` | 抬升后要与「脚点」对齐，否则飘字偏上 |
| UI 全在 `hud_layer`（CanvasLayer） | `main.gd:166` | 不受影响，无需改动 |

---

## 3. 技术方案

### 3.1 核心约定
- **脚点即节点坐标**：`position` 永远是物体与地面接触点，碰撞体、命中判定、距离计算全部不变。
- **本体绘制抬升**：`_draw` 里用 `draw_set_transform(Vector2(0, -lift))` 把本体画高，排序仍按脚点 `position.y`。
- **阴影贴脚**：椭圆按 `(1, 0.42)` 压扁画在脚点，透明度 0.25~0.3。
- **排序靠容器**：`World` 容器开启 `y_sort_enabled`，不手写 `z_index` 排序。
- **Fx 独立层**：子弹、弹幕、范围圈、飘字、粒子放独立容器，整体压在实体之上，避免被 Y 排序拆散。

### 3.2 三层结构

```
Main (Node2D)
├─ Ground     (Node2D, z_index = -100)   地面 / 视差背景 / 静态装饰
├─ World      (Node2D, y_sort_enabled)   玩家 / 敌人 / Boss / 掉落物
└─ Fx         (Node2D, z_index = 100)    子弹 / 弹幕 / 范围圈 / 飘字 / 特效
```

- `spawner.setup(world, WORLD_HALF)`：敌人、Boss、金币、经验球、道具落到 `World`
- `_spawn_player()` 把玩家挂到 `World`
- `combat.setup(..., fx_host)`：`spawn_bullet`、范围圈文字改用 `Fx`
- `damage_numbers` 挂到 `Fx`，坐标仍用脚点

### 3.3 新增工具：`scripts/world_view.gd`

```gdscript
# 纯工具函数，所有实体共用，避免每个 _draw 各写一套变换
class_name WorldView

const SHADOW_FLAT := 0.42     # 阴影椭圆纵向压扁
const LIFT_DEFAULT := 10.0    # 角色/敌人本体抬升
const LIFT_TALL := 18.0       # Boss
const LIFT_BULLET := 26.0     # 子弹悬浮高度

static func draw_shadow(c: CanvasItem, radius: float, alpha := 0.28) -> void:
    c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_FLAT))
    c.draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, alpha))
    c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func body_begin(c: CanvasItem, lift := LIFT_DEFAULT) -> void:
    c.draw_set_transform(Vector2(0.0, -lift))

static func body_end(c: CanvasItem) -> void:
    c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

约束：`draw_set_transform` 会覆盖当前绘制变换，`_draw` 内必须成对调用，且所有 `queue_redraw()` 周期内不跨帧保留。

---

## 4. 阶段拆分与验收

### 阶段 A：世界分层 + Y 轴排序（基础，必须先做）

**改动**
- `main.gd`：`_ready` 中创建 `Ground / World / Fx` 三个 `Node2D`，`World.y_sort_enabled = true`；`spawner.setup(world, ...)`；`_spawn_player` 挂到 `World`；`damage_numbers` 挂到 `Fx`。
- `combat.gd`：`setup()` 增加 `fx_host` 参数，`spawn_bullet`（`combat.gd:39`）与范围圈（`combat.gd:148`）改挂 `Fx`。
- `spawner.gd`：`host` 语义不变，仅传入对象换成 `World`。
- `main.gd:615` 的背景绘制先原样迁到 `Ground` 的绘制脚本里（本阶段不做美化）。

**验收**
- 玩家走到敌人上方时被遮挡、走到下方时遮挡敌人，穿怪时遮挡关系随 Y 实时翻转。
- 子弹始终显示在最上层，不出现被敌人盖住的情况。
- headless 冒烟 300 帧无报错。

**风险**：`World` 的子树结构变化影响 `get_parent()` 相关代码 → 全局搜索一次 `get_parent()`（已知 `boss_skills/shoot_skill.gd:45` 用 `boss.get_parent().add_child(orb)`，弹幕会落到 `World`，需改为 `Fx`）。

---

### 阶段 B：立体绘制规范（视觉主体）

**改动**（逐个重写 `_draw`，统一「阴影 → 抬升 → 本体 → 复位」四步）
- `player.gd:429`：本体抬升 10，脚下一层椭圆阴影；身体加一圈深色侧壁 + 顶部亮面（用同一多边形偏移 3~4px 画暗色，再画原色形成厚度）。
- `enemy.gd:248`：按形状（三角 / 方形 / 五边形）保留轮廓，加侧壁与阴影；血量条保持现有位置（画在本体上方，跟随抬升）。
- `boss.gd:248/275/307`：Boss 抬升 18，阴影更大更淡；护盾圈保持贴地椭圆。
- `coin.gd:27` / `exp_orb.gd:30` / `item.gd:46`：小尺寸，抬升 6~8，阴影半径 0.4 倍；金币用椭圆环表现倾倒角度。
- `bullet.gd:52` / `boss_orb.gd:24`：抬升 26，阴影很小且偏移半格，形成「飞在空中」。
- 状态表现（冰冻覆盖、燃烧、磁力环绕）同步改为贴地椭圆/抬升本体两种层次。

**验收**
- 暂停截图对比改造前后：每个实体都能看出厚度与投影。
- 敌人放大后（巨型化道具）阴影与本体比例仍协调。
- 攻击判定范围与视觉脚点一致（打脚下而不是打贴图上沿）。

**风险**：绘制调用翻倍（阴影 + 本体）→ 用视口裁剪：只绘制屏幕外延 200px 内的阴影。

---

### 阶段 C：相机与镜头语言

**改动**
- `scenes/player.tscn`：`Camera2D` 开启 `position_smoothing_enabled`、设置 `position_smoothing_speed ≈ 8`；`offset = Vector2(0, -36)` 形成轻微俯视前视。
- `player.gd`：现有 `shake()` 保留，震屏方向改为以纵向为主（2.5D 下纵向位移观感更强）。
- 可选（体感加分）：连击 ≥10 时相机 `zoom` 从 1.2 微推到 1.26 再回落。

**验收**：快速 8 字走位不晕、不漂移；撞墙时相机不抖动。

---

### 阶段 D：地面与环境（纯代码）

**改动**
- 新增 `scripts/ground.gd`：程序化地面纹理（草地噪点 / 冰雪斑块，按 `WORLD_HALF` 平铺），一次生成到 `ImageTexture` 后复用，避免每帧 `draw_*`。
- 三层视差：远景雾层（随相机 0.2 倍速）、地面（1 倍）、前景草/雪粒（1.2 倍，半透明，压在实体之上但低于 Fx）。
- 静态装饰：岩石、冰柱等，放在 `Ground` 下、`y_sort` 之外；仅视觉、不参与碰撞（对应 `GRule.md` 中冰雪地图设想，可先做 1 个「雪地」主题）。
- 地图边界：渐隐雾圈替代硬边。

**验收**：地面无接缝、无闪烁；相机移动时三层视差方向正确；内存占用不随时间增长。

---

### 阶段 E：战斗视觉适配

**改动**
- `combat.gd`：范围伤害圈、触发环改为 `draw_set_transform` 压扁的椭圆（贴地）；`_spawn_ring` 的 tween 缩放保持。
- `damage_numbers.gd`：生成点从命中点 y 再减 18，使飘字出现在本体中部而非脚下；暴击字号放大保持。
- 元素表现：冰层覆盖、燃烧地面、磁力吸引轨迹都按「贴地」绘制。
- 连击 / 任务 toast 等 UI 文案不受影响（CanvasLayer）。

**验收**：AOE 看起来铺在地面上；飘字不飘进敌人身体里；冰冻结界视觉不穿帮。

---

### 阶段 F：性能与回归

**改动**
- 统计每帧 `draw_*` 调用数与节点数（临时 debug 输出），阴影按视距裁剪。
- 粒子上限、伤害飘字上限沿用现有实现。
- 更新 `PROJECT.md`：目录结构补充 `world_view.gd` / `ground.gd`，运行时数据流补充三层结构。
- 更新 `版本简要.txt` 与 `PROJECT.md` 版本号至 v4.0。

**验收**
- 1920x1080、300 敌人 + 1 Boss：稳定 60fps（允许短时 45+）。
- 存档读档、升级选卡、商店、背包、任务、Boss 主线全流程回归 1 次。
- headless 冒烟通过。

---

## 5. 文件改动清单

| 文件 | 阶段 | 改动 | 风险 |
|---|---|---|---|
| `main.gd` | A/F | 建 `Ground/World/Fx` 三层、玩家与 spawner 挂载点、背景迁出、版本号 | 中（结构改动面广） |
| `spawner.gd` | A | `host` 改为 `World` | 低 |
| `combat.gd` | A/E | `fx_host` 参数、子弹与范围圈挂 `Fx`、椭圆范围圈 | 中 |
| `boss_skills/shoot_skill.gd` | A | 弹幕挂 `Fx` | 低 |
| `player.gd` / `scenes/player.tscn` | B/C | 立体绘制、相机平滑与前视、纵向震屏 | 低 |
| `enemy.gd` / `boss.gd` | B | 阴影 + 抬升 + 侧壁 + 状态贴地 | 中（绘制重写） |
| `bullet.gd` / `boss_orb.gd` | B | 悬浮高度与阴影 | 低 |
| `coin.gd` / `exp_orb.gd` / `item.gd` | B | 小物件立体化 | 低 |
| `damage_numbers.gd` | E | 飘字纵向偏移 | 低 |
| `scripts/world_view.gd`（新增） | A | 阴影 / 抬升工具函数 | 低 |
| `scripts/ground.gd`（新增） | D | 程序化地面 + 视差 | 中 |
| `PROJECT.md` / `版本简要.txt` | F | 结构与版本更新 | 低 |

---

## 6. 回滚与开关

- 每阶段独立提交，阶段 A 单独一个 commit，便于 `git revert`。
- 阶段 A 可在 `main.gd` 保留一个 `const USE_WORLD_LAYERS := true`：为 false 时 `World/Fx` 直接指向 `self`，等价于旧结构，用于快速对比与排障。

---

## 7. 4.1 场景化改造（本版不做，已确认纳入路线）

目标：让项目从「纯代码构建」转为「编辑器可视化编辑」，你能自己在 Godot 里拖 UI、拼地图、换图与配动画。两条路线已确认：**先完成 4.0 视觉，再做 4.1；4.1 从 UI 场景化开刀。**

### 7.1 第一步：UI 迁到 .tscn（优先级最高）

- 新建 `scenes/ui/`，每个面板一个场景：`hud.tscn`、`weapon.tscn`、`inventory.tscn`、`shop.tscn`、`quest.tscn`、`upgrade.tscn`、`settings.tscn`。
- `scripts/ui/*.gd` 里删除 `build()` 中的控件创建代码，改为：
  - `@onready var hp_bar: ProgressBar = $Root/HpBar` 这类节点引用
  - 保留数据填充函数（`set_hp` / `update_buffs` / `refresh`）与信号
- `main.gd` 改为 `preload(...).instantiate()` 后 `hud_layer.add_child()`，对外接口不变，业务代码零改动。
- 样式抽成 `Theme` 资源（`ui_theme.tres`），替换 `ui_style.gd` 的工厂函数；字号缩放改用 Theme 的 font_size 批量覆盖。
- 拖拽类交互（背包拖放、任务栏拖动）保留脚本逻辑，节点只做布局。

**验收**：在编辑器里移动任意按钮、改字号、加图标后直接运行生效；暂停语义、E 键背包、商店扣款、升级选卡全流程不回归。

**风险**：现有 UI 代码量大（每个面板 200~600 行），拆分需逐面板验收；`inventory_ui` 的格子是动态创建的，仍需运行时生成。

### 7.2 第二步：实体改精灵 + 动画

- 每个实体根节点下加 `SpriteRoot`，约定「脚点锚点」在精灵底部中央（与 4.0 的 `position` 语义一致）。
- 状态机：`idle / move / hit / freeze / die`，8 向朝向（可先 4 向）。
- 无美术资源时回退到 4.0 的 `_draw`，保证可渐进替换。
- 新增 `scripts/sprite_config.gd` 登记每个实体的帧表与动画名。

### 7.3 第三步：地图模块化

- `TileMapLayer` 做地面与障碍，障碍挂 `StaticBody2D` 参与碰撞。
- 新增 `scripts/map_data.gd`：主题、tile 资源、出生点区域、障碍权重、刷怪权重、环境特效。
- `spawner.gd` 从「固定 `WORLD_HALF` 随机」改为「读地图配置的区域与权重」。
- 地图场景放 `scenes/maps/`，可在编辑器直接拼接；首个落地主题为雪地（对应 `GRule.md` 冰雪地图设想）。

**顺序建议**：UI 场景化 → 实体精灵动画 → 地图模块。每步单独可交付、可回滚。

---

## 8. 里程碑清单

- [ ] A 三层结构与 Y 轴排序，遮挡关系正确
- [ ] B 全部实体阴影 + 抬升 + 侧壁
- [ ] C 相机平滑 / 前视 / 震屏方向
- [ ] D 程序化地面 + 三层视差 + 边界雾化
- [ ] E 范围圈椭圆化、飘字与元素表现贴地
- [ ] F 性能回归 + 文档与版本号更新

### 4.1（已确认纳入路线，4.0 之后推进）

- [ ] UI 全部面板迁到 `scenes/ui/*.tscn`，可在编辑器直接拖拽
- [ ] 实体精灵化 + `idle/move/hit/freeze/die` 动画，无资源时回退绘制
- [ ] `TileMapLayer` 地图模块 + `map_data.gd`，spawner 读取地图配置
- [ ] 首个雪地主题地图可拼接运行
