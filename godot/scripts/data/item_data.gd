class_name ItemData
extends Resource
## Un objeto del juego. Cada uno es un archivo .tres en res://data/items/
## que se puede editar desde el Inspector de Godot sin tocar código.
## Para añadir un objeto nuevo: duplica uno parecido y cambia el id.

@export var id := ""
@export var name := ""
## nombre corto para la barra inferior
@export var short := ""
@export_range(0.0, 50.0, 0.01, "suffix:kg") var kg := 0.1
@export_enum("comida", "medicina", "municion", "arma", "material", "herramienta", "ropa", "nota") var category := "material"
@export_multiline var description := ""
## icono para el inventario (opcional por ahora)
@export var icon: Texture2D
## modelo 3D para cuando se vea en el mundo o en la mano (opcional)
@export var model: PackedScene

@export_group("Consumible")
## lo que recupera al usarlo (comer, beber, curarse)
@export var hunger := 0.0
@export var thirst := 0.0
@export var heal := 0.0
@export var stops_bleeding := false
## cura la infección de una mordida
@export var cures_infection := false
## objeto que queda al usarlo (p. ej. la botella vacía al beber)
@export var leaves := ""
## probabilidad de que siente mal (carne cruda): quita salud y sed
@export_range(0.0, 1.0) var sick_chance := 0.0

@export_group("Ropa")
## dónde se lleva: cabeza, torso, piernas o espalda (mochilas)
@export var slot := ""
## parte del daño de mordidas y arañazos que para (0-0.8); también evita heridas
@export_range(0.0, 0.8, 0.01) var armor := 0.0
## kilos de más que puedes cargar (mochilas)
@export var capacity := 0.0
## color con el que se ve puesta
@export var color := Color(0.5, 0.5, 0.5)
## forma: gorra, casco, casco_militar, chaleco, mochila, mochila_grande, bolsa
@export var look := ""

@export_group("Nota")
## texto que se lee (notas y diarios de la historia)
@export_multiline var text := ""

@export_group("Herramienta")
## sirve para desmontar muebles y coches
@export var is_tool := false

@export_group("Arma")
@export var is_weapon := false
## posición en el ciclo de armas (Q)
@export var weapon_order := 0
@export var dmg := 1.0
@export_range(0.5, 100.0, 0.1, "suffix:m") var reach := 1.5
## segundos entre golpes
@export var cd := 0.5
## energía que gasta cada golpe
@export var stam := 4.0
## metros a los que se oye
@export var noise := 6.0
## golpes que aguanta (-1 = no se gasta)
@export var dur := -1
## zombis a los que alcanza de un golpe
@export var hits := 1
@export var gun := false
## además de ser arma, ¿se guarda en la mochila? (los puños no)
@export var in_backpack := true
