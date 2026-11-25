class_name ControlsScreen
extends Control

signal closed

const THEME := preload("res://lobby_theme.tres")
const CAPS := preload("res://ui/fonts/caps_font.tres")

const PC3 := [
	[["@move_up", "@move_left", "@move_down", "@move_right"], "Move"],
	[["MOUSE"], "Look around"],
	[["@fire"], "Shoot"],
	[["@scope"], "Scope in (sniper)"],
	[["@jump"], "Jump"],
	[["@crouch"], "Crouch, slide if you're running"],
	[["@walk"], "Walk, quiet and accurate"],
	[["@scoreboard"], "Scoreboard"],
	[["ESC"], "Pause"],
	[["@fire", "/", "@scope"], "Next / previous player when spectating"],
	[["@ghost"], "Ghost cam when spectating"],
]
const PC2 := [
	[["@move_up", "@move_left", "@move_down", "@move_right"], "Move"],
	[["MOUSE"], "Aim"],
	[["@shoot"], "Shoot"],
	[["@scoreboard"], "Scoreboard"],
]
const MOB3 := [
	[["LEFT SIDE"], "Drag to move"],
	[["RIGHT SIDE"], "Drag to look around"],
	[["FIRE"], "Hold to shoot, drag to aim"],
	[["SCOPE"], "Tap to scope in, tap again to stop"],
	[["JUMP"], "Jump"],
	[["SLIDE"], "Crouch, slide if you're running"],
	[["SCORES"], "Scoreboard"],
	[["MENU"], "Pause"],
	[["PREV", "/", "NEXT"], "Switch player when spectating"],
	[["GHOST"], "Fly around when spectating"],
]
const MOB2 := [
	[["LEFT STICK"], "Move"],
	[["RIGHT STICK"], "Aim, push it all the way to shoot"],
	[["DOTS"], "Where your shot goes and bounces"],
	[["SCORES"], "Scoreboard"],
]

var three := true
var mob := false
var _acc := Color.WHITE
var _box: PanelContainer
var _body: HBoxContainer
var _sub: Label
var tint := Color(0, 0, 0, 0)


func _init(is_3d := true, phone := false) -> void:
	three = is_3d
	mob = phone


func _ready() -> void:
	theme = THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_acc = THEME.get_color("font_color", &"HeaderLabel")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.88)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(cc)
	_box = PanelContainer.new()
	cc.add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_box.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = "CONTROLS"
	head.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(head)
	_sub = Label.new()
	_sub.theme_type_variation = &"MutedLabel"
	top.add_child(_sub)

	_body = HBoxContainer.new()
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_theme_constant_override("separation", 30)
	_body.custom_minimum_size.x = 560
	v.add_child(_body)

	var back := Button.new()
	back.text = "BACK"
	back.theme_type_variation = &"PinkButton"
	back.focus_mode = FOCUS_NONE
	back.custom_minimum_size = Vector2(180, 42)
	back.size_flags_horizontal = SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	if tint.a > 0.0:
		Scoreboard.paint(back, tint)
	v.add_child(back)
	Controls.touch_changed.connect(_on_touch)
	_fill()


func _on_touch(on: bool) -> void:
	mob = on
	_fill()


func close() -> void:
	closed.emit()
	queue_free()


func _fill() -> void:
	_sub.text = "%s  ·  %s" % ["3D ARENA" if three else "CLASSIC 2D", "PHONE" if mob else "PC"]
	for c in _body.get_children():
		c.queue_free()
	if mob:
		_body.add_child(Phone.new(three, _acc))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_vertical = SIZE_SHRINK_CENTER
	_body.add_child(g)
	var rows: Array = (MOB3 if three else MOB2) if mob else (PC3 if three else PC2)
	for r: Array in rows:
		var keys := HBoxContainer.new()
		keys.alignment = BoxContainer.ALIGNMENT_END
		keys.add_theme_constant_override("separation", 5)
		for k: String in r[0]:
			var caps: Array = Controls.key_names(k.substr(1)) if k.begins_with("@") else [k]
			for i in caps.size():
				if caps[i] == "/" or i > 0:
					var sl := Label.new()
					sl.theme_type_variation = &"MutedLabel"
					sl.text = "/"
					keys.add_child(sl)
				if caps[i] != "/":
					keys.add_child(_cap(caps[i]))
		g.add_child(keys)
		var d := Label.new()
		d.text = r[1]
		d.add_theme_font_size_override("font_size", 19)
		g.add_child(d)


func _cap(txt: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.15)
	sb.border_color = Color(_acc, 0.85)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(14 if mob else 6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", CAPS)
	l.add_theme_font_size_override("font_size", 14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 16
	p.add_child(l)
	return p


func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(_d: float) -> void:
	var room := get_viewport_rect().size - Vector2(40, 40)
	var need := _box.get_combined_minimum_size()
	_box.pivot_offset = _box.size / 2.0
	_box.scale = Vector2.ONE * minf(1.0, minf(room.x / need.x, room.y / need.y))


# mini phone screen with the touch buttons where the game puts them
class Phone extends Control:
	const REF := Vector2(1152, 648)
	const K := 0.4
	const FONT := preload("res://Rajdhani-SemiBold.ttf")
	var three := true
	var acc := Color.WHITE

	func _init(t: bool, a: Color) -> void:
		three = t
		acc = a
		custom_minimum_size = REF * K + Vector2(20, 20)
		size_flags_vertical = SIZE_SHRINK_CENTER

	func _draw() -> void:
		var fr := StyleBoxFlat.new()
		fr.bg_color = Color(0.04, 0.04, 0.07)
		fr.border_color = Color(0.91, 0.98, 1.0, 0.35)
		fr.set_border_width_all(2)
		fr.set_corner_radius_all(20)
		draw_style_box(fr, Rect2(Vector2.ZERO, size))
		var o := Vector2(10, 10)
		var sc := REF * K
		draw_rect(Rect2(o, sc), Color(0.13, 0.15, 0.22))
		if three:
			var x := o.x + sc.x * 0.45
			draw_dashed_line(Vector2(x, o.y + sc.y * 0.3), Vector2(x, o.y + sc.y - 8), Color(1, 1, 1, 0.18), 1.5, 6.0)
			_text(o + Vector2(sc.x * 0.72, sc.y * 0.22), "DRAG TO LOOK", 12, 0.45)
		_stick(o + Vector2(170, REF.y - 245) * K, "MOVE")
		if not three:
			var c := o + Vector2(REF.x - 170, REF.y - 245) * K
			_stick(c, "AIM")
			var p := o + sc * Vector2(0.5, 0.42)
			var dir := Vector2(1, -0.55).normalized()
			draw_circle(p, 7, Color(acc, 0.9))
			for i in range(1, 9):
				draw_circle(p + dir * i * 11.0, 1.8, Color(1, 1, 1, 0.75 - i * 0.07))
		for b: Array in TouchControls.layout(three):
			var at: Vector2 = b[2]
			var c := o + Vector2(at.x if at.x >= 0.0 else REF.x + at.x, at.y if at.y >= 0.0 else REF.y + at.y) * K
			var r: float = b[3] * K
			draw_circle(c, r, Color(1, 1, 1, 0.1))
			draw_arc(c, r, 0.0, TAU, 40, Color(acc.lightened(0.3), 0.8), 2.0, true)
			if r > 14.0:
				_text(c, b[4], 11 if r > 18.0 else 9, 0.95)
			else:
				_text(c + Vector2(0, r + 8), b[4], 8, 0.8)

	func _stick(c: Vector2, lbl: String) -> void:
		var r := 70.0 * K
		draw_circle(c, r, Color(1, 1, 1, 0.06))
		draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5, true)
		draw_circle(c, 30.0 * K, Color(acc, 0.55))
		_text(c + Vector2(0, r + 9), lbl, 11, 0.7)

	func _text(c: Vector2, s: String, fs: int, a: float) -> void:
		var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(FONT, c + Vector2(-w / 2.0, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
