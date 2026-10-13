class_name Items
extends RefCounted
## Datos de objetos, armas y botín. Los valores salen de la versión web,
## más el peso de cada cosa.

## nombre visible y peso en kg por unidad
const ITEMS := {
	"comida": {"name": "Comida enlatada", "short": "Comida", "kg": 0.4},
	"agua": {"name": "Botella de agua", "short": "Agua", "kg": 0.5},
	"vendas": {"name": "Vendas", "short": "Vendas", "kg": 0.05},
	"balas": {"name": "Balas", "short": "Balas", "kg": 0.02},
	"bate": {"name": "Bate de béisbol", "short": "Bate", "kg": 1.0},
	"hacha": {"name": "Hacha", "short": "Hacha", "kg": 2.2},
	"pistola": {"name": "Pistola", "short": "Pistola", "kg": 0.9},
}

## Armas: daño, alcance, enfriamiento, energía, ruido, durabilidad (golpes), objetivos por golpe
const WEAPONS := {
	"puños": {"name": "Puños", "dmg": 1.1, "range": 1.5, "cd": 0.45, "stam": 4.0, "noise": 6.0, "dur": -1, "hits": 1},
	"bate": {"name": "Bate", "dmg": 2.6, "range": 2.1, "cd": 0.65, "stam": 7.0, "noise": 9.0, "dur": 35, "hits": 2},
	"hacha": {"name": "Hacha", "dmg": 4.6, "range": 2.0, "cd": 0.85, "stam": 10.0, "noise": 9.0, "dur": 50, "hits": 1},
	"pistola": {"name": "Pistola", "dmg": 4.2, "range": 60.0, "cd": 0.32, "stam": 0.0, "noise": 48.0, "dur": -1, "hits": 1, "gun": true},
}
const WEAPON_ORDER: Array[String] = ["puños", "bate", "hacha", "pistola"]

## Contenedores: nombre visible y tabla de botín [objeto, probabilidad, mín, máx]
const CONTAINERS := {
	"nevera": {"name": "Nevera", "time": 1.3, "loot": [["comida", .85, 1, 3], ["agua", .75, 1, 2]]},
	"armario": {"name": "Armario", "time": 1.3, "loot": [["vendas", .5, 1, 2], ["balas", .14, 3, 7], ["bate", .16], ["hacha", .08], ["pistola", .035], ["comida", .15, 1, 1]]},
	"cajonera": {"name": "Cajonera", "time": 1.3, "loot": [["vendas", .45, 1, 1], ["comida", .25, 1, 1], ["balas", .1, 2, 5], ["agua", .2, 1, 1]]},
	"estanteria": {"name": "Estantería", "time": 1.3, "loot": [["comida", .5, 1, 2], ["agua", .45, 1, 2], ["vendas", .2, 1, 1]]},
	"coche": {"name": "Maletero", "time": 1.8, "loot": [["agua", .35, 1, 1], ["comida", .3, 1, 1], ["vendas", .2, 1, 1], ["bate", .06], ["balas", .07, 2, 4]]},
}

## Carga: hasta CARRY_LIGHT vas normal; a partir de ahí cada vez más lento.
## Por encima de CARRY_MAX ya no puedes recoger más.
const CARRY_LIGHT := 8.0
const CARRY_HEAVY := 14.0
const CARRY_MAX := 20.0


static func roll_loot(type: String) -> Dictionary:
	var out := {}
	for entry in CONTAINERS[type].loot:
		if randf() < entry[1]:
			var lo: int = entry[2] if entry.size() > 2 else 1
			var hi: int = entry[3] if entry.size() > 3 else 1
			out[entry[0]] = out.get(entry[0], 0) + randi_range(lo, hi)
	return out


static func kg(item: String) -> float:
	return ITEMS[item].kg


## Multiplicador de velocidad según el peso que llevas.
static func speed_factor(weight: float) -> float:
	if weight <= CARRY_LIGHT:
		return 1.0
	if weight <= CARRY_HEAVY:
		return lerpf(1.0, 0.78, (weight - CARRY_LIGHT) / (CARRY_HEAVY - CARRY_LIGHT))
	return lerpf(0.78, 0.45, clampf((weight - CARRY_HEAVY) / (CARRY_MAX - CARRY_HEAVY), 0.0, 1.0))


static func describe(loot: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in loot:
		var n: int = loot[k]
		parts.append("%d× %s" % [n, ITEMS[k].name] if n > 1 else ITEMS[k].name)
	return ", ".join(parts)
