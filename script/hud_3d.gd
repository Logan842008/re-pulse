class_name Hud3D
extends CanvasLayer

signal leave_pressed
signal rematch_pressed

const WHITE := Color("ece8e1")
const SLATE := Color("0f1923")
const ACCENT := Color("ff4655")
const FONT := preload("res://Rajdhani-SemiBold.ttf")
const THEME := preload("res://lobby_theme.tres")

var _game: Game3D
var _msg_t := 0.0
var _hit_t := 0.0
var _hurt_t := 0.0

var _hp_lbl: Label
var _hp_bar: ProgressBar
var _al: Label
var _gl: Label
var _score_box: HBoxContainer
var _scores := []
var _list: VBoxContainer
var _grey: ColorRect
var _grey_amt := 0.0
var _board: Scoreboard
var _rows := []
var _fill: StyleBoxFlat
var _bord: Array[StyleBoxFlat] = []
var _round_lbl: Label
var _ml: Label
var _hit: Control
var _hurt: ColorRect
var _pause: Control
var _rb: Button
var _hint: Label
var _touch: TouchControls
var _lines: Array[ColorRect] = []
var _cross: Control
var _scope: Control
var _recap: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_grey = ColorRect.new()
	_grey.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grey.material = ShaderMaterial.new()
	_grey.material.shader = preload("res://script/grey.gdshader")
	_grey.hide()
	root.add_child(_grey)

	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(ACCENT, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt)

	_crosshair(root)

	_score_box = HBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 22)
	_score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_score_box)
	_score_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_box.offset_left = -300
	_score_box.offset_right = 300
	_score_box.offset_top = 14

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_list)
	_list.anchor_top = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = 30
	_list.offset_top = -170
	_list.offset_bottom = -116
	_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_list.alignment = BoxContainer.ALIGNMENT_END
	_round_lbl = _label(root, 18, Control.PRESET_CENTER_TOP, Vector2(0, 64))
	_round_lbl.modulate = Color(WHITE, 0.7)

	var hp_box := _panel(root, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24), Vector2(260, 84))
	_hp_lbl = _label(hp_box, 44, -1, Vector2.ZERO)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(230, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(WHITE, 0.15)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = WHITE
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.add_theme_stylebox_override("fill", _fill)
	hp_box.add_child(_hp_bar)

	var gb := _panel(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -24), Vector2(220, 84))
	_al = _label(gb, 44, -1, Vector2.ZERO)
	_al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gl = _label(gb, 18, -1, Vector2.ZERO)
	_gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var tip := _label(root, 16, Control.PRESET_CENTER_BOTTOM, Vector2(0, -20))
	tip.text = "Pulses only hurt after they bounce"
	tip.modulate = Color(WHITE, 0.5)

	_ml = Label.new()
	_ml.theme = THEME
	_ml.theme_type_variation = &"BigMessageLabel"
	_ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ml.add_theme_constant_override("shadow_outline_size", 22)
	_ml.add_theme_constant_override("shadow_offset_x", 0)
	_ml.add_theme_constant_override("shadow_offset_y", 0)
	root.add_child(_ml)
	_ml.set_anchors_preset(Control.PRESET_CENTER)
	_ml.offset_left = -420
	_ml.offset_right = 420
	_ml.offset_top = -160
	_ml.offset_bottom = -30

	_pause = VBoxContainer.new()
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.position = Vector2(-120, 40)
	_pause.custom_minimum_size = Vector2(240, 0)
	_pause.add_theme_constant_override("separation", 10)
	root.add_child(_pause)
	_hint = _label(_pause, 16, -1, Vector2.ZERO)
	_hint.text = "Click the game to keep playing"
	_button(_pause, "RESUME", &"PrimaryButton", Vector2(180, 42), capture)
	_button(_pause, "CONTROLS", &"PinkButton", Vector2(180, 42), _keys)
	_rb = _button(_pause, "REMATCH", &"PrimaryButton", Vector2(180, 42), rematch_pressed.emit)
	_button(_pause, "LEAVE", &"PinkButton", Vector2(100, 44), leave_pressed.emit)
	_pause.hide()
	_rb.hide()


func setup(game: Game3D) -> void:
	_game = game
	_board = Scoreboard.new(game, rematch_pressed.emit, leave_pressed.emit)
	get_child(0).add_child(_board)
	Controls.touch_changed.connect(_on_touch)
	_on_touch(Controls.touch)
	_build_combat()
	get_child(0).move_child(_board, -1)
	_score_box.hide()
	_round_lbl.hide()
	var me := Network.my_slot()
	var everyone: Array = Network.slots() if not Network.roster.is_empty() else [0, 1]
	var sides := [Network.team_of(me)]
	for s: int in everyone:
		if not sides.has(Network.team_of(s)):
			sides.append(Network.team_of(s))
	for i in sides.size():
		if i > 0:
			_label(_score_box, 40, -1, Vector2.ZERO).text = ":" if sides.size() == 2 else "·"
		var l := _label(_score_box, 40, -1, Vector2.ZERO)
		l.add_theme_color_override("font_color", Network.side_color(sides[i]))
		_scores.append([sides[i], l])

	var mates := everyone.filter(func(s: int) -> bool: return s != me and Network.team_of(s) == Network.team_of(me))
	for s: int in mates:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(row)
		var n := _label(row, 17, -1, Vector2.ZERO)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		n.text = Network.name_of(s).to_upper() + "  ·  TEAM"
		n.add_theme_color_override("font_color", Network.color_of(s).lightened(0.3))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 5)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(WHITE, 0.15)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Network.color_of(s)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		_rows.append([s, row, bar])


func capture() -> void:
	if Controls.touch:
		Controls.paused = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _keys() -> void:
	get_child(0).add_child(ControlsScreen.new(true, Controls.touch))


func release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_touch(on: bool) -> void:
	if on and _touch == null:
		_touch = TouchControls.new(_game, true, pause)
		get_child(0).add_child(_touch)
		get_child(0).move_child(_touch, _board.get_index())
	elif not on and _touch:
		_touch.queue_free()
		_touch = null
		if not _game.match_over:
			capture()


func pause() -> void:
	if Controls.touch:
		Controls.paused = true
	else:
		release()


func show_msg(txt: String, secs := 0.0) -> void:
	_ml.text = txt
	_msg_t = secs


func show_rematch() -> void:
	_rb.show()


func hide_rematch() -> void:
	_rb.hide()


func hit_marker(kill: bool, head := false) -> void:
	_hit_t = 0.22 if head else 0.18
	_hit.modulate = ACCENT if kill else Color("f2c45a") if head else WHITE
	_hit.scale = Vector2.ONE * (1.35 if head else 1.0)


func hurt() -> void:
	_hurt_t = 0.35


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		pause()
	elif e is InputEventMouseButton and e.pressed and not _game.match_over and not Controls.touch:
		capture()


func _process(delta: float) -> void:
	if _game == null:
		return
	_pause.visible = not Controls.live() and not _game.match_over
	_hint.visible = not Controls.touch
	if _touch:
		_touch.visible = Controls.live() and not _game.match_over

	var me := Network.my_slot()
	var hp: int = _game.hp[me]
	_grey_amt = move_toward(_grey_amt, 0.0 if _game.is_alive(me) else 1.0, delta * 2.5)
	_grey.material.set_shader_parameter("amount", _grey_amt)
	_grey.visible = _grey_amt > 0.0
	_hp_lbl.text = str(hp)
	_hp_lbl.modulate = ACCENT if hp <= _game.max_hp * 0.3 else WHITE
	_hp_bar.max_value = _game.max_hp
	_hp_bar.value = hp
	for sc: Array in _scores:
		sc[1].text = str(_game.scores[sc[0]])
	for r: Array in _rows:
		r[2].max_value = _game.max_hp
		r[2].value = _game.hp[r[0]]
		r[1].modulate.a = 1.0 if _game.is_alive(r[0]) else 0.35
	var col := Network.color_of(me)
	_fill.bg_color = col
	for sb in _bord:
		sb.border_color = col
	_gl.add_theme_color_override("font_color", col)
	_ml.add_theme_color_override("font_shadow_color", Color(col, 0.55))
	_round_lbl.text = "ROUND %d   ·   FIRST TO %d   ·   %s" % [_game.round_num, _game.wins_needed(), _versus(me)]

	var w: int = _game.gun[me]
	var left: int = _game.ammo[me]
	_gl.text = Weapons.LIST[w]["name"]
	_al.text = "∞" if left < 0 else str(left)
	_al.modulate = ACCENT if left >= 0 and left <= 3 else WHITE

	if _game.countdown > 0.0:
		var head: String = "MATCH POINT" if _game.match_point() else "ROUND %d" % _game.round_num
		_ml.text = "%s\n%d" % [head, ceili(_game.countdown)]
	elif _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_ml.text = ""

	_aim_view()
	if _game.is_alive(me) or _game.match_over:
		_recap.hide()
	_hit_t = maxf(_hit_t - delta, 0.0)
	_hit.visible = _hit_t > 0.0
	_hurt_t = maxf(_hurt_t - delta, 0.0)
	_hurt.color.a = _hurt_t * 0.6


func _versus(me: int) -> String:
	if Network.mode == "ffa":
		return "FREE FOR ALL"
	var foes := Network.slots().filter(func(s: int) -> bool: return Network.team_of(s) != Network.team_of(me))
	if foes.is_empty():
		foes = [1 - me]
	return "vs " + " & ".join(foes.map(func(s: int) -> String: return Network.name_of(s).to_upper()))


func _crosshair(root: Control) -> void:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	_cross = c
	for r: Rect2 in [Rect2(-1, -12, 2, 7), Rect2(-1, 5, 2, 7), Rect2(-12, -1, 7, 2), Rect2(5, -1, 7, 2)]:
		_lines.append(_rect(c, r, WHITE))
	_rect(c, Rect2(-1, -1, 2, 2), WHITE)
	_hit = Control.new()
	_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(_hit)
	for a in [45, 135, 225, 315]:
		var t := _rect(_hit, Rect2(9, -1, 7, 2), Color.WHITE)
		t.pivot_offset = Vector2(-9, 1)
		t.rotation_degrees = a
	_hit.hide()


func _rect(p: Control, r: Rect2, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.position = r.position
	cr.size = r.size
	cr.color = col
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cr)
	return cr


func _label(p: Control, size: int, preset: int, offset: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", WHITE)
	l.add_theme_color_override("font_outline_color", Color(SLATE, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	if preset >= 0:
		l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.position += offset
	return l


func _panel(p: Control, preset: int, offset: Vector2, size: Vector2) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SLATE, 0.55)
	sb.set_content_margin_all(12)
	sb.border_color = ACCENT
	sb.border_width_left = 3
	_bord.append(sb)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = size
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(pc)
	pc.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	pc.position += offset
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(box)
	return box


func _button(p: Control, txt: String, kind: StringName, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.theme = THEME
	b.theme_type_variation = kind
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	p.add_child(b)
	return b


func _build_combat() -> void:
	var root: Control = get_child(0)
	_scope = Control.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.draw.connect(_draw_scope)
	_scope.hide()
	root.add_child(_scope)
	root.move_child(_scope, 1)
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_recap = PanelContainer.new()
	_recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap.hide()
	root.add_child(_recap)
	_recap.anchor_left = 0.5
	_recap.anchor_right = 0.5
	_recap.anchor_top = 1.0
	_recap.anchor_bottom = 1.0
	_recap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_recap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_recap.offset_bottom = -130


func _aim_view() -> void:
	var p := _game.me()
	if p == null:
		return
	var sniper: bool = Weapons.LIST[_game.gun[p.slot]]["scope"]
	var scoped := sniper and p.scope > 0.85
	_scope.visible = scoped
	if scoped:
		_scope.queue_redraw()
	_cross.visible = not scoped and _game.is_alive(p.slot)
	var half := get_viewport().get_visible_rect().size.y / 2.0
	var gap := 5.0 + tan(deg_to_rad(p.err)) / tan(deg_to_rad(p.cam.fov) / 2.0) * half
	gap = minf(gap, 80.0)
	_lines[0].position = Vector2(-1, -gap - 7)
	_lines[1].position = Vector2(-1, gap)
	_lines[2].position = Vector2(-gap - 7, -1)
	_lines[3].position = Vector2(gap, -1)


func _draw_scope() -> void:
	var sz := _scope.size
	var c := sz / 2.0
	var r := sz.y * 0.46
	var far := c.length() + 4.0
	_scope.draw_arc(c, (r + far) / 2.0, 0.0, TAU, 96, Color.BLACK, far - r, true)
	_scope.draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 0.85), 3.0, true)
	var line := Color(0, 0, 0, 0.9)
	_scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 14, c.y), line, 2.0)
	_scope.draw_line(Vector2(c.x + 14, c.y), Vector2(c.x + r, c.y), line, 2.0)
	_scope.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - 14), line, 2.0)
	_scope.draw_line(Vector2(c.x, c.y + 14), Vector2(c.x, c.y + r), line, 2.0)
	_scope.draw_circle(c, 2.0, Network.color_of(Network.my_slot()))


func feed(by: int, victim: int, w: int, head: bool) -> void:
	_board.feed(by, victim, w, head)


func killed_by(by: int, w: int, head: bool, taken: Array, dealt: Array) -> void:
	for c in _recap.get_children():
		c.queue_free()
	var col := Network.color_of(by)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SLATE, 0.88)
	sb.border_color = col
	sb.border_width_top = 3
	sb.set_content_margin_all(14)
	_recap.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_recap.add_child(v)
	var top := _label(v, 14, -1, Vector2.ZERO)
	top.text = "ELIMINATED BY"
	top.modulate = Color(WHITE, 0.6)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 12)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(who)
	who.add_child(_board._portrait(by, 52))
	var n := _label(who, 30, -1, Vector2.ZERO)
	n.text = Network.name_of(by).to_upper()
	n.add_theme_color_override("font_color", col.lightened(0.3))
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ic := TextureRect.new()
	ic.texture = _board.gun_icon(w)
	ic.custom_minimum_size = Vector2(90, 36)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	who.add_child(ic)
	if head:
		var hs := _label(who, 16, -1, Vector2.ZERO)
		hs.text = "HEADSHOT"
		hs.add_theme_color_override("font_color", Color("f2c45a"))
		hs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(_report_row("DAMAGE TAKEN", taken, ACCENT))
	v.add_child(_report_row("DAMAGE DEALT", dealt, Network.color_of(Network.my_slot()).lightened(0.2)))
	_recap.show()


func _report_row(title: String, r: Array, col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var t := _label(row, 15, -1, Vector2.ZERO)
	t.text = title
	t.custom_minimum_size = Vector2(130, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.modulate = Color(WHITE, 0.7)
	var d := _label(row, 24, -1, Vector2.ZERO)
	d.text = str(r[0])
	d.custom_minimum_size = Vector2(56, 0)
	d.add_theme_color_override("font_color", col)
	var hits := _label(row, 15, -1, Vector2.ZERO)
	hits.text = "HEAD %d   ·   BODY %d   ·   LEGS %d" % [r[1], r[2], r[3]]
	hits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row
