class_name Arena
extends Node3D
## Construit la grande salle fermée (sol, plafond, 4 murs) et ses obstacles.
## Tout est généré de façon déterministe pour être identique chez tous les joueurs.

const W := 60.0   # largeur (x)
const H := 32.0   # hauteur (y)
const D := 60.0   # profondeur (z)
const CENTER := Vector3(0, H / 2.0, 0)

## Points d'apparition : tableau de { "pos": Vector3, "up": Vector3 }
var spawn_points: Array = []

const GRID_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.3);
uniform vec3 line_color : source_color = vec3(0.8);
uniform float cell = 2.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = abs(wnrm);
	vec2 uv = n.x > 0.5 ? wpos.zy : (n.y > 0.5 ? wpos.xz : wpos.xy);
	vec2 g = uv / cell;
	vec2 w = max(fwidth(g), vec2(0.0001));
	vec2 a = abs(fract(g - 0.5) - 0.5) / (w * 1.5);
	float line = 1.0 - min(min(a.x, a.y), 1.0);
	ALBEDO = mix(base_color, line_color, line * 0.9);
	ROUGHNESS = 0.85;
}
"""

var _shader: Shader


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = GRID_SHADER
	_build()


func _faces() -> Array:
	# Chaque face : centre, normale vers l'intérieur (= "haut" pour qui y marche),
	# deux tangentes, demi-étendues, couleur. Une couleur par face pour s'orienter.
	return [
		{"c": Vector3(0, 0, 0), "n": Vector3.UP, "t1": Vector3.RIGHT, "t2": Vector3.BACK, "e1": W / 2, "e2": D / 2, "col": Color("#3b4a6b")},
		{"c": Vector3(0, H, 0), "n": Vector3.DOWN, "t1": Vector3.RIGHT, "t2": Vector3.BACK, "e1": W / 2, "e2": D / 2, "col": Color("#5a3b6b")},
		{"c": Vector3(-W / 2, H / 2, 0), "n": Vector3.RIGHT, "t1": Vector3.BACK, "t2": Vector3.UP, "e1": D / 2, "e2": H / 2, "col": Color("#6b4a2e")},
		{"c": Vector3(W / 2, H / 2, 0), "n": Vector3.LEFT, "t1": Vector3.BACK, "t2": Vector3.UP, "e1": D / 2, "e2": H / 2, "col": Color("#2e6b63")},
		{"c": Vector3(0, H / 2, -D / 2), "n": Vector3.BACK, "t1": Vector3.RIGHT, "t2": Vector3.UP, "e1": W / 2, "e2": H / 2, "col": Color("#3e6b2e")},
		{"c": Vector3(0, H / 2, D / 2), "n": Vector3.FORWARD, "t1": Vector3.RIGHT, "t2": Vector3.UP, "e1": W / 2, "e2": H / 2, "col": Color("#6b2e3a")},
	]


func _build() -> void:
	# Couvertures posées sur chaque face : [u, v (fractions), taille u, taille v, hauteur]
	var covers := [
		[0.25, 0.6, 3.0, 3.0, 1.6],
		[-0.6, 0.25, 3.0, 3.0, 1.6],
		[-0.25, -0.6, 3.0, 3.0, 1.6],
		[0.6, -0.25, 3.0, 3.0, 1.6],
		[0.0, 0.45, 8.0, 1.0, 1.2],
		[0.0, -0.45, 8.0, 1.0, 1.2],
	]
	for f in _faces():
		var n: Vector3 = f.n
		var t1: Vector3 = f.t1
		var t2: Vector3 = f.t2
		var col: Color = f.col
		# Paroi
		var shell_size: Vector3 = t1.abs() * (2.0 * f.e1 + 2.0) + t2.abs() * (2.0 * f.e2 + 2.0) + n.abs() * 1.0
		_add_box(f.c - n * 0.5, shell_size, col, col.lightened(0.35))
		# Couvertures
		for cv in covers:
			var pos: Vector3 = f.c + t1 * cv[0] * f.e1 + t2 * cv[1] * f.e2 + n * cv[4] / 2.0
			var size: Vector3 = t1.abs() * cv[2] + t2.abs() * cv[3] + n.abs() * cv[4]
			_add_box(pos, size, col.lightened(0.15), col.lightened(0.5))
		# Points d'apparition
		for u in [0.75, -0.75]:
			spawn_points.append({"pos": f.c + t1 * u * f.e1 + n * 1.2, "up": n})

	var neutral := Color("#555a66")
	var accent := Color("#c9cfdc")
	# Piliers sol -> plafond
	for x in [-15.0, 15.0]:
		for z in [-15.0, 15.0]:
			_add_box(Vector3(x, H / 2, z), Vector3(3, H, 3), neutral, accent)
	# Cube flottant central : on peut atterrir sur ses 6 faces
	_add_box(CENTER, Vector3(8, 8, 8), Color("#8a6d2e"), Color("#ffd27a"))
	# Poutres qui traversent la salle
	_add_box(Vector3(0, 24, 0), Vector3(W, 1.5, 1.5), neutral, accent)
	_add_box(Vector3(0, 8, 0), Vector3(1.5, 1.5, D), neutral, accent)
	# Plateformes flottantes (marchables des deux côtés)
	for p in [Vector3(-22, 9, 22), Vector3(22, 23, -22), Vector3(22, 14, 22), Vector3(-22, 20, -22)]:
		_add_box(p, Vector3(6, 0.6, 6), Color("#2e4f6b"), Color("#7fd3ff"))


func _add_box(pos: Vector3, size: Vector3, base: Color, line: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("base_color", Vector3(base.r, base.g, base.b))
	mat.set_shader_parameter("line_color", Vector3(line.r, line.g, line.b))
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
