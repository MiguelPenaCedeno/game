class_name MeshBatcher
extends RefCounted
## Junta muchas mallas pequeñas en pocas mallas grandes: una por grupo.
## El color de cada pieza se guarda en sus vértices, así todas las piezas de
## un grupo comparten material y la tarjeta gráfica las dibuja de una vez.


class Group:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var material: Material
	var shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON


var groups := {}


## Añade una malla con su transformación (en el espacio del nodo donde irá el resultado).
func add(mesh: Mesh, xform: Transform3D, key: Variant, material: Material, color: Color,
		shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> void:
	var g: Group = groups.get(key)
	if g == null:
		g = Group.new()
		g.material = material
		g.shadows = shadows
		groups[key] = g
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var base := g.verts.size()
		g.verts.append_array(xform * verts)
		var normal_xform := Transform3D(xform.basis.inverse().transposed(), Vector3.ZERO)
		g.normals.append_array(normal_xform * normals)
		var cols := PackedColorArray()
		cols.resize(verts.size())
		# el shader trabaja en lineal; los colores del juego están en sRGB
		cols.fill(color.srgb_to_linear())
		g.colors.append_array(cols)
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			for i in verts.size():
				g.indices.append(base + i)
		else:
			for i in (idx as PackedInt32Array):
				g.indices.append(base + i)


## Crea un MeshInstance3D por grupo dentro de `parent`. Devuelve los creados.
func build(parent: Node3D, prefix := "Lote") -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var n := 0
	for key in groups:
		var g: Group = groups[key]
		if g.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_INDEX] = g.indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, g.material)
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [prefix, n]
		mi.mesh = mesh
		mi.cast_shadow = g.shadows
		parent.add_child(mi)
		out.append(mi)
		n += 1
	groups.clear()
	return out
