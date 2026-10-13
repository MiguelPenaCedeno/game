class_name ContainerData
extends Resource
## Un tipo de mueble o lugar registrable. Archivos en res://data/containers/.

@export var id := ""
@export var name := ""
## segundos que se tarda en registrarlo
@export var time := 1.3
## Botín: cada entrada es [id del objeto, probabilidad 0-1, mínimo, máximo].
## Mínimo y máximo son opcionales (por defecto 1).
@export var loot: Array = []
