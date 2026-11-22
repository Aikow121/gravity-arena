class_name Player
extends CharacterBody3D
## Joueur (humain ou bot) avec gravité personnelle orientable.
## Le joueur qui "possède" ce nœud (autorité multijoueur) le simule et diffuse
## sa position ; les autres ne font qu'interpoler.

const WALK_SPEED := 8.0
const SPRINT_SPEED := 12.0
const GROUND_ACCEL := 70.0
const AIR_ACCEL := 18.0
const AIR_DRAG := 2.0
const GRAVITY := 24.0
const JUMP_SPEED := 9.0
const MAX_FALL_SPEED := 45.0
const MOUSE_SENS := 0.0022
const SWITCH_TIME := 0.35        # durée de la rotation lors d'un changement de gravité
const SWITCH_RANGE := 80.0       # portée du "visé" de surface
const SWITCH_COOLDOWN := 0.5
const MAX_AMMO := 12
const FIRE_DELAY := 0.15
const RELOAD_TIME := 1.3
const BODY_DAMAGE := 25
const HEAD_DAMAGE := 60
const GUN_POS := Vector3(0.25, -0.22, -0.45)
const ROOM_CENTER := Vector3(0, 16, 0)
const ROOM_HALF := Vector3(30, 16, 30)

var main: Node
var display_name := "Joueur"
var is_bot := false
var color := Color.WHITE
var hp := 100
var alive := true
var ammo := MAX_AMMO
var can_switch_target := false

## Direction "haut" actuelle du joueur (la gravité tire dans -grav_up).
var grav_up := Vector3.UP

var head: Node3D
var camera: Camera3D
var gun: Node3D
var muzzle: Node3D
var _shape: CollisionShape3D
var _body_mesh: MeshInstance3D
var _visor: MeshInstance3D
var _label: Label3D

var _q_from := Quaternion.IDENTITY
var _q_to := Quaternion.IDENTITY
var _switch_t := 1.0
var _switch_cd := 0.0
var _fire_cd := 0.0
var _reload_t := 0.0
var _gun_kick := 0.0

var _net_xform := Transform3D.IDENTITY
var _net_pitch := 0.0
var _has_net := false

var _bot_think := 0.0
var _bot_switch_timer := 3.0
var _bot_fire_cd := 1.0
var _bot_strafe := 1.0
var _bot_target: Player = null


func is_local() -> bool:
	return is_multiplayer_authority() and not is_bot


func is_reloading() -> bool:
	return _reload_t > 0.0


static func make_transform(pos: Vector3, up: Vector3, look_point: Vector3) -> Transform3D:
	var to := look_point - pos
	to -= up * to.dot(up)
	if to.length() < 0.01:
		to = up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.FORWARD)
	return Transform3D(Basis.looking_at(to.normalized(), up), pos)


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_shape.shape = cap
	add_child(_shape)

	_body_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	_body_mesh.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = color
	bmat.roughness = 0.5
	_body_mesh.material_override = bmat
	add_child(_body_mesh)

	head = Node3D.new()
	head.position = Vector3(0, 0.6, 0)
	add_child(head)

	_visor = MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.5, 0.16, 0.12)
	_visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.05, 0.05, 0.08)
	vmat.emission_enabled = true
	vmat.emission = color.lightened(0.3)
	vmat.emission_energy_multiplier = 1.5
	_visor.material_override = vmat
	_visor.position = Vector3(0, 0.05, -0.36)
	head.add_child(_visor)

	camera = Camera3D.new()
	camera.fov = 85
	camera.near = 0.05
	head.add_child(camera)

	gun = Node3D.new()
	gun.position = GUN_POS
	head.add_child(gun)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.15, 0.18)
	gmat.metallic = 0.7
	gmat.roughness = 0.35
	var grip := MeshInstance3D.new()
	var gm1 := BoxMesh.new()
	gm1.size = Vector3(0.07, 0.18, 0.1)
	grip.mesh = gm1
	grip.material_override = gmat
	grip.position = Vector3(0, -0.08, 0.06)
	grip.rotation_degrees.x = -12
	gun.add_child(grip)
	var slide := MeshInstance3D.new()
	var gm2 := BoxMesh.new()
	gm2.size = Vector3(0.08, 0.09, 0.32)
	slide.mesh = gm2
	slide.material_override = gmat
	gun.add_child(slide)
	var stripe := MeshInstance3D.new()
	var gm3 := BoxMesh.new()
	gm3.size = Vector3(0.082, 0.02, 0.2)
	stripe.mesh = gm3
	var smat := StandardMaterial3D.new()
	smat.albedo_color = color
	smat.emission_enabled = true
	smat.emission = color
	stripe.material_override = smat
	stripe.position = Vector3(0, 0.02, -0.02)
	gun.add_child(stripe)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.0, -0.18)
	gun.add_child(muzzle)

	_label = Label3D.new()
	_label.text = display_name
	_label.modulate = color
	_label.outline_size = 8
	_label.font_size = 48
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.position = Vector3(0, 1.3, 0)
	add_child(_label)

	if is_local():
		camera.current = true
		_body_mesh.visible = false
		_visor.visible = false
		_label.visible = false
	_net_xform = global_transform


# ---------------------------------------------------------------- Entrées

func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or not alive:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_apply_yaw(-event.relative.x * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, deg_to_rad(-89), deg_to_rad(89))


func _apply_yaw(angle: float) -> void:
	var r := Quaternion(Vector3.UP, angle)
	if _switch_t < 1.0:
		# Pendant la rotation de gravité, on applique le lacet aux deux extrémités.
		_q_from = (_q_from * r).normalized()
		_q_to = (_q_to * r).normalized()
	else:
		rotate_object_local(Vector3.UP, angle)


# ---------------------------------------------------------------- Simulation

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_switch_cd = maxf(0.0, _switch_cd - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			ammo = MAX_AMMO
	if not alive:
		return

	var move := Vector2.ZERO
	var jump := false
	var sprint := false
	if is_bot:
		var r := _bot_brain(delta)
		move = r[0]
		jump = r[1]
	elif main.input_enabled():
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		jump = Input.is_action_pressed("jump")
		sprint = Input.is_action_pressed("sprint")
		if Input.is_action_just_pressed("shoot"):
			_shoot(camera.global_position, -camera.global_transform.basis.z)
		if Input.is_action_just_pressed("reload"):
			_start_reload()
		if Input.is_action_just_pressed("gravity_switch"):
			_try_switch_from_aim()
		if Input.is_action_just_pressed("gravity_reset"):
			start_gravity_switch(Vector3.UP)

	_update_switch(delta)
	_move(delta, move, jump, sprint)

	if is_local():
		var hit := _aim_surface()
		can_switch_target = not hit.is_empty() and hit.normal.dot(grav_up) < 0.98 and _switch_cd <= 0.0

	_check_bounds()
	if not multiplayer.get_peers().is_empty():
		net_state.rpc(global_transform, head.rotation.x, grav_up)


func _move(delta: float, input: Vector2, jump: bool, sprint: bool) -> void:
	var up := grav_up
	up_direction = up
	var b := global_transform.basis
	var fwd := -b.z
	fwd -= up * fwd.dot(up)
	var right := b.x
	right -= up * right.dot(up)
	var wish := Vector3.ZERO
	if fwd.length() > 0.01 and right.length() > 0.01:
		wish = right.normalized() * input.x - fwd.normalized() * input.y
	wish = wish.limit_length(1.0)

	var vert := up * velocity.dot(up)
	var horiz := velocity - vert
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	if is_on_floor():
		horiz = horiz.move_toward(wish * speed, GROUND_ACCEL * delta)
		if jump:
			vert = up * JUMP_SPEED
	else:
		if wish != Vector3.ZERO:
			horiz = horiz.move_toward(wish * speed, AIR_ACCEL * delta)
		else:
			horiz = horiz.move_toward(Vector3.ZERO, AIR_DRAG * delta)
		vert -= up * GRAVITY * delta
		if -vert.dot(up) > MAX_FALL_SPEED:
			vert = -up * MAX_FALL_SPEED
	velocity = horiz + vert
	move_and_slide()


# ---------------------------------------------------------------- Gravité

func _aim_surface() -> Dictionary:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * SWITCH_RANGE, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _try_switch_from_aim() -> void:
	var hit := _aim_surface()
	if hit.is_empty():
		return
	start_gravity_switch(hit.normal)


## Change la gravité pour que new_up devienne le "haut" du joueur.
func start_gravity_switch(new_up: Vector3) -> void:
	if _switch_cd > 0.0:
		return
	new_up = new_up.normalized()
	if new_up.dot(grav_up) > 0.98:
		return
	var b := global_transform.basis.orthonormalized()
	var q_cur := b.get_rotation_quaternion()
	var cur_up := b.y
	var rot: Quaternion
	if cur_up.dot(new_up) < -0.995:
		rot = Quaternion(b.x.normalized(), PI)   # retournement complet (sol <-> plafond)
	else:
		rot = Quaternion(cur_up, new_up)
	_q_from = q_cur
	_q_to = (rot * q_cur).normalized()
	_switch_t = 0.0
	if is_on_floor():
		velocity += grav_up * 3.0   # petite impulsion pour décoller de la surface
	grav_up = new_up
	_switch_cd = SWITCH_COOLDOWN


func _update_switch(delta: float) -> void:
	if _switch_t >= 1.0:
		return
	_switch_t = minf(1.0, _switch_t + delta / SWITCH_TIME)
	var t := smoothstep(0.0, 1.0, _switch_t)
	var xf := global_transform
	xf.basis = Basis(_q_from.slerp(_q_to, t))
	global_transform = xf


# ---------------------------------------------------------------- Tir

func _shoot(from: Vector3, dir: Vector3) -> void:
	if not alive or _reload_t > 0.0 or _fire_cd > 0.0:
		return
	if ammo <= 0:
		_start_reload()
		return
	ammo -= 1
	_fire_cd = FIRE_DELAY
	_gun_kick = 1.0
	var to := from + dir * 250.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 3, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	var impact := false
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col is Player:
			var target := col as Player
			if target.alive:
				var local_y := (target.global_transform.affine_inverse() * end).y
				var dmg := HEAD_DAMAGE if local_y > 0.45 else BODY_DAMAGE
				main.report_hit(String(name), String(target.name), dmg)
		else:
			impact = true
	main.fire_fx(muzzle.global_position, end, impact)
	if is_local():
		head.rotation.x = clampf(head.rotation.x + 0.02, deg_to_rad(-89), deg_to_rad(89))
	if ammo == 0:
		_start_reload()


func _start_reload() -> void:
	if _reload_t > 0.0 or ammo == MAX_AMMO:
		return
	_reload_t = RELOAD_TIME


# ---------------------------------------------------------------- Vie / mort

func die() -> void:
	alive = false
	velocity = Vector3.ZERO
	_shape.set_deferred("disabled", true)
	_set_visuals(false)


func respawn(xf: Transform3D, up: Vector3) -> void:
	alive = true
	hp = 100
	ammo = MAX_AMMO
	_reload_t = 0.0
	teleport(xf, up)
	_shape.set_deferred("disabled", false)
	_set_visuals(true)


func teleport(xf: Transform3D, up: Vector3) -> void:
	grav_up = up
	_switch_t = 1.0
	velocity = Vector3.ZERO
	global_transform = xf
	_net_xform = xf
	head.rotation.x = 0.0


func _set_visuals(v: bool) -> void:
	gun.visible = v
	if not is_local():
		_body_mesh.visible = v
		_visor.visible = v
		_label.visible = v


func _check_bounds() -> void:
	var p := global_position - ROOM_CENTER
	if absf(p.x) > ROOM_HALF.x + 3 or absf(p.y) > ROOM_HALF.y + 3 or absf(p.z) > ROOM_HALF.z + 3:
		var sp: Dictionary = main.pick_spawn()
		teleport(Player.make_transform(sp.pos, sp.up, ROOM_CENTER), sp.up)


# ---------------------------------------------------------------- Réseau / rendu

@rpc("authority", "call_remote", "unreliable_ordered")
func net_state(xf: Transform3D, pitch: float, up: Vector3) -> void:
	_net_xform = xf
	_net_pitch = pitch
	grav_up = up
	_has_net = true


func _process(delta: float) -> void:
	if not is_multiplayer_authority() and _has_net:
		var t := clampf(delta * 18.0, 0.0, 1.0)
		global_transform = global_transform.interpolate_with(_net_xform, t)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, t)
	_gun_kick = move_toward(_gun_kick, 0.0, delta * 8.0)
	gun.position = GUN_POS + Vector3(0, 0, _gun_kick * 0.08)
	gun.rotation.x = _gun_kick * 0.25


# ---------------------------------------------------------------- IA des bots

func _bot_brain(delta: float) -> Array:
	_bot_think -= delta
	_bot_switch_timer -= delta
	_bot_fire_cd -= delta
	if _bot_think <= 0.0:
		_bot_think = randf_range(0.4, 0.9)
		_bot_target = main.find_target(self)
		_bot_strafe = [-1.0, 0.0, 1.0].pick_random()

	# Change de temps en temps de surface (mur, plafond…)
	if _bot_switch_timer <= 0.0 and is_on_floor() and _switch_t >= 1.0:
		_bot_switch_timer = randf_range(5.0, 10.0)
		var choices: Array = []
		for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			if d.dot(grav_up) < 0.5:
				choices.append(d)
		start_gravity_switch(choices.pick_random())

	var move := Vector2(_bot_strafe, 0.0)
	var jump := false
	if is_instance_valid(_bot_target) and _bot_target.alive:
		var to := _bot_target.head.global_position - head.global_position
		var flat := to - grav_up * to.dot(grav_up)
		if _switch_t >= 1.0 and flat.length() > 0.5:
			var want := Basis.looking_at(flat.normalized(), grav_up).get_rotation_quaternion()
			var cur := global_transform.basis.orthonormalized().get_rotation_quaternion()
			var xf := global_transform
			xf.basis = Basis(cur.slerp(want, clampf(delta * 6.0, 0.0, 1.0)))
			global_transform = xf
		var local := global_transform.basis.inverse() * to
		head.rotation.x = atan2(local.y, Vector2(local.x, local.z).length())
		var dist := to.length()
		if dist > 14.0:
			move.y = -1.0
		elif dist < 6.0:
			move.y = 1.0
		if _bot_fire_cd <= 0.0 and _has_line_of_sight(_bot_target):
			var facing := 1.0
			if flat.length() > 0.1:
				facing = (-global_transform.basis.z).dot(flat.normalized())
			if facing > 0.85:
				_bot_fire_cd = randf_range(0.45, 0.9)
				var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.035
				_shoot(head.global_position, (to.normalized() + spread).normalized())
	else:
		move.y = -1.0
	if is_on_wall() and is_on_floor():
		jump = true
	return [move, jump]


func _has_line_of_sight(t: Player) -> bool:
	var q := PhysicsRayQueryParameters3D.create(head.global_position, t.head.global_position, 3, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == t
