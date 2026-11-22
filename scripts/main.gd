extends Node3D
## Point d'entrée : menu, réseau (ENet), apparition des joueurs, dégâts et scores.
## Le serveur (hôte) fait autorité sur la vie, les morts et les scores ;
## chaque joueur simule son propre déplacement.

const PORT := 7777
const MAX_CLIENTS := 8
const RESPAWN_DELAY := 2.5
const PALETTE := [Color("#ff5a5f"), Color("#3ec1d3"), Color("#ffd166"), Color("#8ac926"),
	Color("#c77dff"), Color("#ff9f1c"), Color("#f15bb5"), Color("#00f5d4")]
const BOT_NAMES := ["Newton", "Kepler", "Galilée", "Halley", "Hubble", "Laplace", "Lagrange", "Cassini"]

var arena: Arena
var hud: Hud
var players_root: Node3D
var players := {}   # nom du nœud -> Player
var stats := {}     # nom du nœud -> { name, kills, deaths, color }
var in_game := false

var _menu_layer: CanvasLayer
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _bots_spin: SpinBox
var _status: Label
var _buttons: Array = []
var _menu_cam: Camera3D
var _orbit := 0.0
var _bot_counter := 0
var _color_index := 0
var _capture_grace := 0.0


func _ready() -> void:
	randomize()
	_setup_input()
	_setup_environment()
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	_menu_cam = Camera3D.new()
	_menu_cam.fov = 70
	add_child(_menu_cam)
	_menu_cam.current = true
	_build_menu()

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- Mise en place

func _setup_input() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])
	_add_key("sprint", [KEY_SHIFT])
	_add_key("slide", [KEY_CTRL, KEY_C])
	_add_key("reload", [KEY_R])
	_add_key("gravity_switch", [KEY_E])
	_add_key("gravity_reset", [KEY_F])
	_add_key("scoreboard", [KEY_TAB])
	_add_mouse("shoot", MOUSE_BUTTON_LEFT)
	_add_mouse("gravity_switch", MOUSE_BUTTON_RIGHT)


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k   # touches physiques : ZQSD sur AZERTY = WASD sur QWERTY
		InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(50, -145, 0)
	fill.light_energy = 0.45
	add_child(fill)


func _build_menu() -> void:
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 10
	add_child(_menu_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(420, 0)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "GRAVITY ARENA"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Changez votre gravité. Courez sur les murs. Tirez."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(sub)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Pseudo"
	_name_edit.text = "Joueur%d" % randi_range(100, 999)
	_name_edit.max_length = 16
	vb.add_child(_name_edit)

	var bots_row := HBoxContainer.new()
	var bl := Label.new()
	bl.text = "Nombre de bots :"
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots_row.add_child(bl)
	_bots_spin = SpinBox.new()
	_bots_spin.min_value = 0
	_bots_spin.max_value = 7
	_bots_spin.value = 3
	bots_row.add_child(_bots_spin)
	vb.add_child(bots_row)

	var solo := Button.new()
	solo.text = "Jouer en solo (contre les bots)"
	solo.pressed.connect(_on_solo)
	vb.add_child(solo)
	var host := Button.new()
	host.text = "Héberger une partie (port %d)" % PORT
	host.pressed.connect(_on_host)
	vb.add_child(host)
	var join_row := HBoxContainer.new()
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "Adresse IP de l'hôte"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	var join := Button.new()
	join.text = "Rejoindre"
	join.pressed.connect(_on_join)
	join_row.add_child(join)
	vb.add_child(join_row)
	_buttons = [solo, host, join]

	_status = Label.new()
	_status.modulate = Color(1, 0.8, 0.4)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_status)

	var help := Label.new()
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	help.text = "Clic droit ou E : la surface visée devient votre sol (cercle vert = possible)\nF : gravité normale · Maj : sprint · Ctrl/C : glissade · Espace x2 : double saut\nTête = 60 dégâts, corps = 25 · Les bots sont ajoutés par l'hôte, en solo comme en réseau."
	vb.add_child(help)


# ---------------------------------------------------------------- Menu / connexion

func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Joueur"


func _on_solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_as_server()


func _on_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		_status.text = "Impossible d'ouvrir le port %d (erreur %d)" % [PORT, err]
		return
	multiplayer.multiplayer_peer = peer
	_start_as_server()


func _on_join() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_ip_edit.text.strip_edges(), PORT)
	if err != OK:
		_status.text = "Adresse invalide (erreur %d)" % err
		return
	multiplayer.multiplayer_peer = peer
	_status.text = "Connexion…"
	for b in _buttons:
		b.disabled = true


func _start_as_server() -> void:
	_enter_game()
	_server_add(str(1), _player_name(), false, 1)
	for i in int(_bots_spin.value):
		_server_add_bot()


func _enter_game() -> void:
	in_game = true
	_menu_layer.visible = false
	hud.visible = true
	get_viewport().gui_release_focus()
	_capture_mouse()


func _on_connected_to_server() -> void:
	_enter_game()
	register_player.rpc_id(1, _player_name())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_status.text = "Échec de la connexion."
	for b in _buttons:
		b.disabled = false


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var n := str(id)
	if players.has(n):
		remove_player.rpc(n)
		stats.erase(n)
		sync_stats.rpc(stats)


# ---------------------------------------------------------------- Boucle

func _process(delta: float) -> void:
	_capture_grace = maxf(0.0, _capture_grace - delta)
	if not in_game:
		_orbit += delta * 0.12
		_menu_cam.position = Vector3(cos(_orbit) * 26.0, 16.0 + sin(_orbit * 0.7) * 6.0, sin(_orbit) * 26.0)
		_menu_cam.look_at(Arena.CENTER)


func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		get_viewport().set_input_as_handled()


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_capture_grace = 0.2


func input_enabled() -> bool:
	return in_game and _capture_grace <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- Serveur : joueurs

@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname == "":
		pname = "Joueur"
	_server_add(str(id), pname, false, id)


func _server_add_bot() -> void:
	_bot_counter += 1
	var display := "Bot %s" % BOT_NAMES[(_bot_counter - 1) % BOT_NAMES.size()]
	_server_add("bot_%d" % _bot_counter, display, true, 1)


func _server_add(node_name: String, display: String, is_bot: bool, authority: int) -> void:
	var col: Color = PALETTE[_color_index % PALETTE.size()]
	_color_index += 1
	# Le nouveau venu reçoit d'abord les joueurs déjà présents
	if authority != 1:
		for n in players:
			var p: Player = players[n]
			spawn_player.rpc_id(authority, n, p.display_name, p.is_bot, p.color, p.get_multiplayer_authority(),
				p.global_transform, p.grav_up, p.hp, p.alive)
	var sp := pick_spawn()
	spawn_player.rpc(node_name, display, is_bot, col, authority,
		Player.make_transform(sp.pos, sp.up, Arena.CENTER), sp.up, 100, true)
	stats[node_name] = {"name": display, "kills": 0, "deaths": 0, "color": col}
	sync_stats.rpc(stats)


func pick_spawn() -> Dictionary:
	# Choisit, parmi quelques tirages, le point le plus éloigné des joueurs vivants.
	var best: Dictionary = arena.spawn_points.pick_random()
	var best_score := -1.0
	for i in 6:
		var sp: Dictionary = arena.spawn_points.pick_random()
		var score := 1e9
		for p in players.values():
			if p.alive:
				score = minf(score, p.global_position.distance_to(sp.pos))
		if score > best_score:
			best_score = score
			best = sp
	return best


func find_target(bot: Player) -> Player:
	var best: Player = null
	var best_d := INF
	for p in players.values():
		if p != bot and p.alive:
			var d: float = bot.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


# ---------------------------------------------------------------- RPC diffusés par le serveur

@rpc("authority", "call_local", "reliable")
func spawn_player(node_name: String, display: String, is_bot: bool, col: Color, authority: int,
		xform: Transform3D, up: Vector3, hp: int, alive: bool) -> void:
	if players.has(node_name):
		return
	var p := Player.new()
	p.name = node_name
	p.main = self
	p.display_name = display
	p.is_bot = is_bot
	p.color = col
	p.hp = hp
	p.set_multiplayer_authority(authority)
	players_root.add_child(p)
	p.teleport(xform, up)
	players[node_name] = p
	if not alive:
		p.die()
	if p.is_local():
		hud.set_local_player(p)


@rpc("authority", "call_local", "reliable")
func remove_player(node_name: String) -> void:
	if players.has(node_name):
		players[node_name].queue_free()
		players.erase(node_name)


@rpc("authority", "call_local", "reliable")
func sync_stats(s: Dictionary) -> void:
	stats = s
	hud.update_scoreboard(stats)


@rpc("authority", "call_local", "reliable")
func sync_hp(target: String, hp: int, shooter: String) -> void:
	var p: Player = players.get(target)
	if p == null:
		return
	p.hp = hp
	if p.is_local():
		hud.flash_damage()
	var s: Player = players.get(shooter)
	if s != null and s.is_local():
		hud.hit_marker(hp <= 0)


@rpc("authority", "call_local", "reliable")
func player_died(victim: String, killer: String, headshot: bool) -> void:
	var v: Player = players.get(victim)
	var k: Player = players.get(killer)
	if v != null:
		v.die()
	var kname := k.display_name if k != null else "?"
	var vname := v.display_name if v != null else "?"
	hud.add_kill(kname, k.color if k != null else Color.WHITE, vname, v.color if v != null else Color.WHITE, headshot)
	if v != null and v.is_local():
		hud.show_center("Éliminé par %s" % kname, RESPAWN_DELAY)
	elif k != null and k.is_local():
		hud.show_center("Vous avez éliminé %s" % vname, 1.5)


@rpc("authority", "call_local", "reliable")
func respawn_player(node_name: String, xform: Transform3D, up: Vector3) -> void:
	var p: Player = players.get(node_name)
	if p != null:
		p.respawn(xform, up)


# ---------------------------------------------------------------- Dégâts

func report_hit(shooter: String, target: String, dmg: int) -> void:
	if multiplayer.is_server():
		_server_hit(shooter, target, dmg)
	else:
		request_hit.rpc_id(1, shooter, target, dmg)


@rpc("any_peer", "call_remote", "reliable")
func request_hit(shooter: String, target: String, dmg: int) -> void:
	if not multiplayer.is_server():
		return
	if shooter != str(multiplayer.get_remote_sender_id()):
		return   # un client ne peut tirer qu'en son propre nom
	_server_hit(shooter, target, clampi(dmg, 0, Player.HEAD_DAMAGE))


func _server_hit(shooter: String, target: String, dmg: int) -> void:
	var t: Player = players.get(target)
	var s: Player = players.get(shooter)
	if t == null or not t.alive or (s != null and not s.alive):
		return
	var hp := t.hp - dmg
	sync_hp.rpc(target, hp, shooter)
	if hp <= 0:
		if stats.has(shooter):
			stats[shooter].kills += 1
		if stats.has(target):
			stats[target].deaths += 1
		player_died.rpc(target, shooter, dmg >= Player.HEAD_DAMAGE)
		sync_stats.rpc(stats)
		get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_server_respawn.bind(target))


func _server_respawn(node_name: String) -> void:
	if not players.has(node_name):
		return
	var sp := pick_spawn()
	respawn_player.rpc(node_name, Player.make_transform(sp.pos, sp.up, Arena.CENTER), sp.up)


# ---------------------------------------------------------------- Effets de tir

func fire_fx(from: Vector3, to: Vector3, impact: bool) -> void:
	_spawn_fx(from, to, impact)
	if not multiplayer.get_peers().is_empty():
		remote_fx.rpc(from, to, impact)


@rpc("any_peer", "call_remote", "unreliable")
func remote_fx(from: Vector3, to: Vector3, impact: bool) -> void:
	_spawn_fx(from, to, impact)


func _spawn_fx(from: Vector3, to: Vector3, impact: bool) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, length)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.9)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = (from + to) / 2.0
	var dir := (to - from).normalized()
	mi.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)
	if impact:
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		spark.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color(1.0, 0.7, 0.3)
		spark.material_override = smat
		add_child(spark)
		spark.global_position = to
		var tw2 := create_tween()
		tw2.tween_property(spark, "scale", Vector3.ZERO, 0.2)
		tw2.tween_callback(spark.queue_free)
