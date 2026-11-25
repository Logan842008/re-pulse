class_name SettingsScreen
extends Control

signal closed

const THEME := preload("res://lobby_theme.tres")
const CAPS := preload("res://ui/fonts/caps_font.tres")
const ROWS := [
	["move_up", "Forward"],
	["move_down", "Back"],
	["move_left", "Left"],
	["move_right", "Right"],
	["jump", "Jump"],
	["crouch", "Crouch / slide"],
	["walk", "Walk"],
	["scoreboard", "Scoreboard"],
	["fire", "Shoot (3D)"],
	["scope", "Scope (3D)"],
	["ghost", "Ghost cam"],
	["shoot", "Shoot (2D)"],
]

var _box: PanelContainer
var _keys := {}
var _wait := ""
var tint := Color(0, 0, 0, 0)


func _ready() -> void:
	theme = THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.88)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(cc)
	_box = PanelContainer.new()
	cc.add_child(_box)
	_build()
	Controls.touch_changed.connect(_on_touch)


func _on_touch(_on: bool) -> void:
	_build.call_deferred()


func _build() -> void:
	_wait = ""
	_keys.clear()
	for c in _box.get_children():
		c.free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_box.add_child(v)

	_head(v, "SETTINGS")
	if Controls.touch:
		_slider(v, "Touch sensitivity", Controls.tsens, func(x: float) -> void: Controls.tsens = x)
	else:
		_slider(v, "Mouse sensitivity", Controls.sens, func(x: float) -> void: Controls.sens = x)
		v.add_child(HSeparator.new())
		var top := HBoxContainer.new()
		v.add_child(top)
		var kh := _head(top, "KEYBINDS")
		kh.size_flags_horizontal = SIZE_EXPAND_FILL
		var tip := Label.new()
		tip.theme_type_variation = &"MutedLabel"
		tip.text = "Click one, then press the new key"
		top.add_child(tip)
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 8)
		v.add_child(g)
		for r: Array in ROWS:
			var l := Label.new()
			l.text = r[1]
			l.custom_minimum_size.x = 130
			g.add_child(l)
			var b := Button.new()
			b.focus_mode = FOCUS_NONE
			b.custom_minimum_size = Vector2(190, 36)
			b.add_theme_font_override("font", CAPS)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_listen.bind(r[0]))
			if tint.a > 0.0:
				Scoreboard.paint(b, tint)
			g.add_child(b)
			_keys[r[0]] = b

	var bot := HBoxContainer.new()
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 12)
	v.add_child(bot)
	if not Controls.touch:
		_button(bot, "RESET KEYS", &"PinkButton", func() -> void:
			_wait = ""
			Controls.reset()
			_fill())
	_button(bot, "BACK", &"PrimaryButton", close)
	_fill()


func close() -> void:
	Controls.save()
	closed.emit()
	queue_free()


func _head(p: Control, txt: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeaderLabel"
	l.text = txt
	p.add_child(l)
	return l


func _button(p: Control, txt: String, kind: StringName, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.theme_type_variation = kind
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 42)
	b.pressed.connect(cb)
	if tint.a > 0.0:
		Scoreboard.paint(b, tint, kind == &"PrimaryButton")
	p.add_child(b)


func _slider(p: Control, txt: String, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var l := Label.new()
	l.text = txt
	l.custom_minimum_size.x = 190
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.2
	s.max_value = 3.0
	s.step = 0.05
	s.value = val
	s.focus_mode = FOCUS_NONE
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.custom_minimum_size.x = 320
	var acc := tint if tint.a > 0.0 else THEME.get_color("font_color", &"HeaderLabel")
	var tr := StyleBoxFlat.new()
	tr.bg_color = Color(1, 1, 1, 0.14)
	tr.set_corner_radius_all(3)
	tr.content_margin_top = 3
	tr.content_margin_bottom = 3
	var fl := tr.duplicate()
	fl.bg_color = acc
	s.add_theme_stylebox_override("slider", tr)
	s.add_theme_stylebox_override("grabber_area", fl)
	s.add_theme_stylebox_override("grabber_area_highlight", fl)
	row.add_child(s)
	var n := Label.new()
	n.custom_minimum_size.x = 60
	n.text = "%.2fx" % val
	row.add_child(n)
	s.value_changed.connect(func(x: float) -> void:
		n.text = "%.2fx" % x
		cb.call(x))


func _fill() -> void:
	for a: String in _keys:
		_keys[a].text = "PRESS A KEY..." if a == _wait else " / ".join(Controls.key_names(a))


func _listen(a: String) -> void:
	_wait = a
	_fill()


func _input(e: InputEvent) -> void:
	if _wait != "":
		if e is InputEventKey and e.pressed and not e.echo:
			get_viewport().set_input_as_handled()
			if e.physical_keycode != KEY_ESCAPE:
				Controls.rebind(_wait, Controls.code_of(e))
			_wait = ""
			_fill()
		elif e is InputEventMouseButton and e.pressed and e.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			get_viewport().set_input_as_handled()
			Controls.rebind(_wait, -e.button_index)
			_wait = ""
			_fill()
		return
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _process(_d: float) -> void:
	var room := get_viewport_rect().size - Vector2(40, 40)
	var need := _box.get_combined_minimum_size()
	_box.pivot_offset = _box.size / 2.0
	_box.scale = Vector2.ONE * minf(1.0, minf(room.x / need.x, room.y / need.y))
