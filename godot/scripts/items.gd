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
## id -> RecipeData, en el orden en que se muestran
static var RECIPES := {}


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
	var recipes := _load_dir("res://data/recipes/")
	var station_order := {"manos": 0, "banco": 1, "hoguera": 2}
	recipes.sort_custom(func(a, b): return [station_order[a.station], a.name] < [station_order[b.station], b.name])
	for r in recipes:
		RECIPES[r.id] = r


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


## Cuántas unidades tienes de algo (las armas cuentan como 1).
static func count_of(id: String, inv: Dictionary, owned: Dictionary) -> int:
	if owned.has(id) and id != "puños":
		return 1
	return int(inv.get(id, 0))


static func can_craft(r: RecipeData, inv: Dictionary, owned: Dictionary) -> bool:
	for k in r.ingredients:
		if count_of(k, inv, owned) < int(r.ingredients[k]):
			return false
	return true


## Texto de ingredientes: "2× Trapos, 1× Alcohol"
static func ingredients_text(r: RecipeData) -> String:
	var parts := PackedStringArray()
	for k in r.ingredients:
		parts.append("%d× %s" % [r.ingredients[k], ITEMS[k].short])
	return ", ".join(parts)


## Botín al desmontar un mueble.
static func roll_dismantle(type: String) -> Dictionary:
	var out := {}
	for entry in (CONTAINERS[type] as ContainerData).dismantle:
		if randf() < entry[1]:
			var lo: int = entry[2] if entry.size() > 2 else 1
			var hi: int = entry[3] if entry.size() > 3 else 1
			out[entry[0]] = out.get(entry[0], 0) + randi_range(lo, hi)
	return out
