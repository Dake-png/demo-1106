extends Node

## 全局事件总线（Autoload 名称：EventBus）
## 敌人 / Boss / 掉落物不再 get_parent()._on_xxx 直接调主控，
## 统一广播事件，由订阅方（main.gd）处理；新增系统只需订阅信号。

signal enemy_died(at: Vector2, enemy_type: int)
signal boss_died(at: Vector2)
signal effect_damage(at: Vector2, amount: int, icon: String)
signal coin_picked
signal exp_orb_picked
signal item_picked(item_id: String)
