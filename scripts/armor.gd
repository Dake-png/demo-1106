extends RefCounted

## 护甲减伤（物理伤害）：
## 受到伤害 = 子弹伤害 × (1 - ln(护甲 + 1) / (ln(护甲 + 1) + 3.5355))

const K := 3.5355

static func reduction(armor: float) -> float:
	if armor <= 0.0:
		return 0.0
	var l := log(armor + 1.0)
	return l / (l + K)

static func reduce(dmg: int, armor: float) -> int:
	if armor <= 0.0 or dmg <= 0:
		return dmg
	return maxi(1, int(round(float(dmg) * (1.0 - reduction(armor)))))
