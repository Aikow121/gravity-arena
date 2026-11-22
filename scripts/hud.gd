class_name Hud
extends CanvasLayer
## Interface en jeu : viseur, vie, munitions, gravité, fil des éliminations, tableau des scores.


class Crosshair extends Control:
	var ring := false
	var hit := 0.0
	var hit_kill := false

	func _process(delta: float) -> void:
		hit = maxf(0.0, hit - delta)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var col := Color(1, 1, 1, 0.9)
		var g := 5.0
		var l := 8.0
		draw_line(c + Vector2(-g - l, 0), c + Vector2(-g, 0), col, 2.0)
		draw_line(c + Vector2(g, 0), c + Vector2(g + l, 0), col, 2.0)
		draw_line(c + Vector2(0, -g - l), c + Vector2(0, -g), col, 2.0)
		draw_line(c + Vector2(0, g), c + Vector2(0, g + l), col, 2.0)
		draw_circle(c, 1.5, col)
		if ring:
			# Cercle vert : la surface visée peut devenir votre nouveau sol
			draw_arc(c, 22.0, 0.0, TAU, 40, Color(0.3, 1.0, 0.6, 0.85), 2.0)
		if hit > 0.0:
			var hc := Color(1, 0.2, 0.2) if hit_kill else Color(1, 1, 1)
			hc.a = hit / 0.25
			for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + s * 7.0, c + s * 14.0, hc, 2.5)


var local_player: Player
var _root: Control
var _crosshair: Crosshair
var _health_label: Label
var _ammo_label: Label
var _grav_label: Label
var _center_label: Label
var _pause_label: Label
var _damage_rect: ColorRect
var _killfeed: VBoxContainer
var _scoreboard: PanelContainer
var _score_grid: GridContainer
var _center_t := 0.0


func _ready() -> void:
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_damage_rect = ColorRect.new()
	_damage_rect.color = Color(1, 0, 0, 0)
	_damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage_rect)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	var bl := VBoxContainer.new()
	_root.add_child(bl)
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_grav_label = _make_label(18)
	bl.add_child(_grav_label)
	_health_label = _make_label(40)
	bl.add_child(_health_label)

	_ammo_label = _make_label(40)
	_root.add_child(_ammo_label)
	_ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_ammo_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_center_label = _make_label(30)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_center_label)
	_center_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 140)
	_center_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_pause_label = _make_label(22)
	_pause_label.text = "PAUSE — cliquez pour reprendre"
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_pause_label)
	_pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 120)
	_pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var help := _make_label(13)
	help.modulate = Color(1, 1, 1, 0.7)
	help.text = "ZQSD/WASD bouger · Maj sprint · Ctrl/C glissade · Espace (x2) sauter · Clic G tirer · Clic D ou E : gravité vers la surface visée · F : gravité normale · R recharger · Tab scores · Échap souris"
	_root.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 6)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_killfeed = VBoxContainer.new()
	_killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_killfeed.custom_minimum_size = Vector2(420, 0)
	_root.add_child(_killfeed)
	_killfeed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_killfeed.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_scoreboard = PanelContainer.new()
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	_scoreboard.add_child(m)
	_score_grid = GridContainer.new()
	_score_grid.columns = 3
	_score_grid.add_theme_constant_override("h_separation", 40)
	m.add_child(_score_grid)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_local_player(p: Player) -> void:
	local_player = p


func _process(delta: float) -> void:
	_damage_rect.color.a = move_toward(_damage_rect.color.a, 0.0, delta * 1.5)
	if _center_t > 0.0:
		_center_t -= delta
		if _center_t <= 0.0:
			_center_label.text = ""
	_pause_label.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	_scoreboard.visible = Input.is_action_pressed("scoreboard")
	if not is_instance_valid(local_player):
		return
	var p := local_player
	_health_label.text = "PV %d" % maxi(p.hp, 0)
	_health_label.modulate = Color(1, 0.35, 0.35) if p.hp <= 30 else Color.WHITE
	if p.is_reloading():
		_ammo_label.text = "RECHARGE…"
	else:
		_ammo_label.text = "%d / %d" % [p.ammo, Player.MAX_AMMO]
	_grav_label.text = "Gravité : " + _surface_name(p.grav_up)
	_crosshair.ring = p.can_switch_target and p.alive


func _surface_name(up: Vector3) -> String:
	if up.dot(Vector3.UP) > 0.9:
		return "SOL"
	if up.dot(Vector3.DOWN) > 0.9:
		return "PLAFOND"
	if absf(up.y) < 0.1:
		return "MUR"
	return "OBLIQUE"


func flash_damage() -> void:
	_damage_rect.color.a = 0.35


func hit_marker(kill: bool) -> void:
	_crosshair.hit = 0.25
	_crosshair.hit_kill = kill


func show_center(text: String, duration: float) -> void:
	_center_label.text = text
	_center_t = duration


func add_kill(killer: String, kcol: Color, victim: String, vcol: Color, headshot: bool) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var a := _make_label(18)
	a.text = killer
	a.modulate = kcol
	var mid := _make_label(18)
	mid.text = "  >>  " if not headshot else "  >> (tête) >>  "
	var b := _make_label(18)
	b.text = victim
	b.modulate = vcol
	row.add_child(a)
	row.add_child(mid)
	row.add_child(b)
	_killfeed.add_child(row)
	while _killfeed.get_child_count() > 6:
		_killfeed.get_child(0).queue_free()
		_killfeed.remove_child(_killfeed.get_child(0))
	get_tree().create_timer(6.0).timeout.connect(row.queue_free)


func update_scoreboard(stats: Dictionary) -> void:
	for c in _score_grid.get_children():
		c.queue_free()
	for h in ["Joueur", "Éliminations", "Morts"]:
		var l := _make_label(20)
		l.text = h
		l.modulate = Color(1, 0.85, 0.4)
		_score_grid.add_child(l)
	var rows := stats.values()
	rows.sort_custom(func(x, y): return x.kills > y.kills)
	for s in rows:
		var n := _make_label(18)
		n.text = s.name
		n.modulate = s.color
		var k := _make_label(18)
		k.text = str(s.kills)
		var d := _make_label(18)
		d.text = str(s.deaths)
		_score_grid.add_child(n)
		_score_grid.add_child(k)
		_score_grid.add_child(d)
