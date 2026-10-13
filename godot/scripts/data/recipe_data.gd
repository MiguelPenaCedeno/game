class_name RecipeData
extends Resource
## Una receta de fabricación. Archivos en res://data/recipes/.
##
## `result` puede ser el id de un objeto, "estructura:<tipo>" para algo que se
## coloca en el mundo (banco, hoguera, caja…) o "reparar" para arreglar el arma
## que llevas en la mano.

@export var id := ""
@export var name := ""
@export_multiline var description := ""
## dónde se puede fabricar
@export_enum("manos", "banco", "hoguera") var station := "manos"
## {id_objeto: cantidad}. Las armas cuentan como 1 y se gastan.
@export var ingredients := {}
@export var result := ""
@export var result_count := 1
## segundos que se tarda (quieto)
@export var time := 2.0
