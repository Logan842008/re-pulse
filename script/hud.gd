class_name Hud
extends CanvasLayer

signal leave_pressed
signal rematch_pressed

const CAPS := preload("res://ui/fonts/caps_font.tres")

var _game: Game
var _msg_t := 0.0
var _rows := []
var _scores := []
var _grey: ColorRect
var _grey_amt := 0.0
var _board: Scoreboard
var _touch: TouchControls

@onready var mnl: Label = %YouName
@onready var my_hp: ProgressBar = %YouHealth
@onready var bl: Label = %BoostLabel
@onready var eb: VBoxContainer = $Root/Opponent
@onready var yb: VBoxContainer = $Root/You
@onready var rl: Label = %RoundLabel
@onready var gl: Label = %GoalLabel
@onready var sr: HBoxContainer = $Root/ScorePanel/Row
@onready var ml: Label = %MessageLabel
@onready var rb: Button = %RematchButton
@onready var leave_btn: Button = %LeaveButton


func _ready() -> void:
	_grey = ColorRect.new()
	_grey.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grey.material = ShaderMaterial.new()
	_grey.material.shader = preload("res://script/grey.gdshader")
	_grey.hide()
	$Root.add_child(_grey)
	$Root.move_child(_grey, 0)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leave_btn.pressed.connect(leave_pressed.emit)
	rb.pressed.connect(rematch_pressed.emit)


func setup(game: Game) -> void:
	_game = game
	var me := Network.my_slot()
	_board = Scoreboard.new(game, rematch_pressed.emit, leave_pressed.emit)
	$Root.add_child(_board)
	Controls.touch_changed.connect(_on_touch)
	_on_touch(Controls.touch)
	Scoreboard.paint(leave_btn, Network.color_of(me))
	Scoreboard.paint(rb, Network.color_of(me), true)
	$Root/ScorePanel.hide()
	mnl.text = "%s  (you)" % Network.name_of(me)
	_tint_bar(my_hp, Network.color_of(me))

	eb.hide()
	var everyone: Array = Network.slots() if not Network.roster.is_empty() else [0, 1]
	for s: int in everyone:
		if s == me or Network.team_of(s) != Network.team_of(me):
			continue
		var name := _label(Network.name_of(s) + "  (team)", 14)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(200, 8)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tint_bar(bar, Network.color_of(s))
		yb.add_child(bar)
		yb.add_child(name)
		yb.move_child(bar, 0)
		yb.move_child(name, 0)
		_rows.append([s, name, bar])

	for n in ["YouScore", "Dash", "OppScore"]:
		sr.get_node(n).hide()
	var sides := [Network.team_of(me)]
	for s: int in everyone:
		if not sides.has(Network.team_of(s)):
			sides.append(Network.team_of(s))
	var at := sr.get_node("Sep2").get_index()
	for i in sides.size():
		if i > 0:
			var dash := Label.new()
			dash.theme_type_variation = &"MutedLabel"
			dash.text = "—" if sides.size() == 2 else "·"
			sr.add_child(dash)
			sr.move_child(dash, at)
			at += 1
		var l := Label.new()
		l.theme_type_variation = &"ScoreLabel"
		l.add_theme_color_override("font_color", Network.side_color(sides[i]))
		sr.add_child(l)
		sr.move_child(l, at)
		at += 1
		_scores.append([sides[i], l])


func show_msg(txt: String, secs := 0.0) -> void:
	ml.text = txt
	_msg_t = secs


func feed(by: int, victim: int) -> void:
	_board.feed(by, victim, 0)


func _on_touch(on: bool) -> void:
	if on and _touch == null:
		_touch = TouchControls.new(_game, false)
		_touch.blockers = [leave_btn]
		$Root.add_child(_touch)
		$Root.move_child(_touch, _board.get_index())
	elif not on and _touch:
		_touch.queue_free()
		_touch = null


func show_rematch() -> void:
	pass


func hide_rematch() -> void:
	rb.hide()


func _process(delta: float) -> void:
	if _game == null:
		return
	var me := Network.my_slot()
	my_hp.max_value = _game.max_hp
	leave_btn.visible = not _game.match_over
	if _touch:
		_touch.visible = not _game.match_over
	my_hp.value = _game.hp[me]
	yb.modulate.a = 1.0 if _game.is_alive(me) else 0.5
	_grey_amt = move_toward(_grey_amt, 0.0 if _game.is_alive(me) else 1.0, delta * 2.5)
	_grey.material.set_shader_parameter("amount", _grey_amt)
	_grey.visible = _grey_amt > 0.0
	for r: Array in _rows:
		r[2].max_value = _game.max_hp
		r[2].value = _game.hp[r[0]]
		var a := 1.0 if _game.is_alive(r[0]) else 0.3
		r[1].modulate.a = a
		r[2].modulate.a = a
	for sc: Array in _scores:
		sc[1].text = str(_game.scores[sc[0]])
	rl.text = "ROUND %d" % _game.round_num
	gl.text = "FIRST TO %d" % _game.wins_needed()

	var boost: float = _game.boost_t[me]
	bl.text = "WEAPON BOOST  %.1fs" % boost if boost > 0.0 else ""

	if _game.countdown > 0.0:
		var head: String = "MATCH POINT" if _game.match_point() else "ROUND %d" % _game.round_num
		ml.text = "%s\n%d" % [head, ceili(_game.countdown)]
	elif _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			ml.text = ""


func _label(txt: String, size: int) -> Label:
	var l := Label.new()
	l.text = txt
	l.uppercase = true
	l.add_theme_font_override("font", CAPS)
	l.add_theme_font_size_override("font_size", size)
	return l


func _tint_bar(bar: ProgressBar, c: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
