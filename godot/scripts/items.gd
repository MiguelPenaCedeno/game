class_name Items
extends RefCounted
## Objetos, armas, botín y reglas de carga.
## Los objetos, armas y muebles se cargan de res://data/ (archivos .tres que
## se editan desde Godot). Aquí solo quedan las reglas.

## id -> ItemData (todo lo que puede ir en la mochila, más los puños)
static var ITEMS := {}
## id -> ItemData, solo las armas
static var WEAPONS := {}
## ids de las armas en el orden en que se cambian con Q
static var WEAPON_ORDER: Array[String] = []
## id -> ContainerData
static var CONTAINERS := {}


static func _static_init() -> void:
	for res in _load_dir("res://data/items/"):
		var it := res as ItemData
		ITEMS[it.id] = it
		if it.is_weapon:
			WEAPONS[it.id] = it
	var weapons := WEAPONS.values()
	weapons.sort_custom(func(a, b): return a.weapon_order < b.weapon_order)
	for w in weapons:
		WEAPON_ORDER.append(w.id)
	for res in _load_dir("res://data/containers/"):
		CONTAINERS[res.id] = res


static func _load_dir(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with(".tres") or f.ends_with(".res"):
			out.append(load(dir + f))
	return out


## Carga: hasta CARRY_LIGHT vas normal; a partir de ahí cada vez más lento.
## Por encima de CARRY_MAX ya no puedes recoger más.
const CARRY_LIGHT := 8.0
const CARRY_HEAVY := 14.0
const CARRY_MAX := 20.0


static func roll_loot(type: String) -> Dictionary:
	var out := {}
	for entry in (CONTAINERS[type] as ContainerData).loot:
		if randf() < entry[1]:
			var lo: int = entry[2] if entry.size() > 2 else 1
			var hi: int = entry[3] if entry.size() > 3 else 1
			out[entry[0]] = out.get(entry[0], 0) + randi_range(lo, hi)
	# la pistola viene con su cargador
	if out.has("pistola"):
		out["balas"] = out.get("balas", 0) + 6
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
