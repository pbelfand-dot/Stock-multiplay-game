extends RefCounted
## The twin "kidney" grille on the nose, built in code: two tall rounded
## openings side by side, each a chrome rim standing proud round black vertical
## slats. Two surfaces: 0 = chrome, 1 = black. It faces -x (the body model's
## front) from the origin (the grille band's face); `height` in model units.
## Built once per size and kept.

const SEGMENTS := 48           # round each kidney's outline
const SQUARE := 3.2            # the outline's squareness (2 = an ellipse; higher = a rounded box)
const SLATS := 5               # per kidney

static var _cache := {}


static func build(height: float) -> ArrayMesh:
	var key := "%.4f" % height
	if _cache.has(key):
		return _cache[key]
	var chrome := SurfaceTool.new()
	chrome.begin(Mesh.PRIMITIVE_TRIANGLES)
	var black := SurfaceTool.new()
	black.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b := height * 0.5                  # half height
	var a := height * 0.34                 # half width: taller than wide
	var t := height * 0.075                # the rim's width
	var d := height * 0.13                 # how far the rim stands out
	var gap := height * 0.07               # between the two kidneys
	for side in [1.0, -1.0]:
		var zc: float = side * (a + gap * 0.5)
		var outer := _outline(a, b, zc)
		var inner := _outline(a - t, b - t, zc)
		for i in SEGMENTS:
			var j := (i + 1) % SEGMENTS
			# the rim's face, its outside wall back to the grille, its inside wall a little way in
			_quad(chrome, _at(outer[i], -d), _at(outer[j], -d), _at(inner[j], -d), _at(inner[i], -d))
			_quad(chrome, _at(outer[i], 0.0), _at(outer[j], 0.0), _at(outer[j], -d), _at(outer[i], -d))
			_quad(chrome, _at(inner[i], -d), _at(inner[j], -d), _at(inner[j], -d * 0.3), _at(inner[i], -d * 0.3))
			# the black behind the slats
			_tri(black, _at(Vector2(zc, 0.0), -d * 0.3), _at(inner[i], -d * 0.3), _at(inner[j], -d * 0.3))
		# the slats: thin upright bars, as tall as the opening is at each
		for k in SLATS:
			var z := zc + (a - t) * (2.0 * (k + 0.5) / SLATS - 1.0) * 0.86
			var u := absf(z - zc) / (a - t)
			var h := (b - t) * pow(1.0 - pow(u, SQUARE), 1.0 / SQUARE) * 0.97
			_box(black, Vector3(-d * 0.55, 0.0, z), Vector3(d * 0.5, h * 2.0, t * 0.45))
	var mesh := ArrayMesh.new()
	chrome.generate_normals()
	black.generate_normals()
	chrome.commit(mesh)
	black.commit(mesh)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.86, 0.87, 0.9)
	cm.metallic = 0.9
	cm.roughness = 0.18
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, cm)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.05, 0.05, 0.055)
	bm.roughness = 0.7
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, bm)
	_cache[key] = mesh
	return mesh


## A rounded-box outline (a superellipse), half width a and half height b,
## centred at z = zc: Vector2(z, y) points.
static func _outline(a: float, b: float, zc: float) -> Array:
	var pts := []
	for i in SEGMENTS:
		var th := TAU * i / SEGMENTS
		var c := cos(th)
		var s := sin(th)
		pts.append(Vector2(zc + a * signf(c) * pow(absf(c), 2.0 / SQUARE), b * signf(s) * pow(absf(s), 2.0 / SQUARE)))
	return pts


static func _at(p: Vector2, x: float) -> Vector3:
	return Vector3(x, p.y, p.x)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## A box: centre, size (x deep, y tall, z wide).
static func _box(st: SurfaceTool, c: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var p := []
	for i in 8:
		p.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]])
