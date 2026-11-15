class_name Hud
extends CanvasLayer
# not rotated with the camera, so your bar is always the bottom one

signal leave_pressed
signal rematch_pressed

var _game: Game
var _msg_t := 0.0

@onready var my_name_lbl: Label = %YouName
@onready var my_hp: ProgressBar = %YouHealth
@onready var boost_lbl: Label = %BoostLabel
@onready var opp_name_lbl: Label = %OpponentName
@onready var opp_hp: ProgressBar = %OpponentHealth
@onready var round_lbl: Label = %RoundLabel
@onready var my_score: Label = %YouScore
@onready var opp_score: Label = %OppScore
@onready var goal_lbl: Label = %GoalLabel
@onready var msg_lbl: Label = %MessageLabel
@onready var rematch_btn: Button = %RematchButton
@onready var leave_btn: Button = %LeaveButton


func _ready() -> void:
	leave_btn.pressed.connect(leave_pressed.emit)
	rematch_btn.pressed.connect(rematch_pressed.emit)


func setup(game: Game) -> void:
	_game = game
	var me := Network.my_slot()
	var opp := 1 - me
	my_name_lbl.text = "%s  (you)" % Network.name_of(me)
	opp_name_lbl.text = Network.name_of(opp)
	_tint_bar(my_hp, Network.color_of(me))
	_tint_bar(opp_hp, Network.color_of(opp))
	my_score.add_theme_color_override("font_color", Network.color_of(me))
	opp_score.add_theme_color_override("font_color", Network.color_of(opp))


# secs = 0 keeps it up until something replaces it
func show_msg(txt: String, secs := 0.0) -> void:
	msg_lbl.text = txt
	_msg_t = secs


func show_rematch() -> void:
	rematch_btn.show()


func hide_rematch() -> void:
	rematch_btn.hide()


func _process(delta: float) -> void:
	if _game == null:
		return
	var me := Network.my_slot()
	var opp := 1 - me
	my_hp.max_value = _game.max_hp
	my_hp.value = _game.hp[me]
	opp_hp.max_value = _game.max_hp
	opp_hp.value = _game.hp[opp]
	round_lbl.text = "ROUND %d" % _game.round_num
	my_score.text = str(_game.scores[me])
	opp_score.text = str(_game.scores[opp])
	goal_lbl.text = "FIRST TO %d" % _game.wins_needed()

	var boost: float = _game.boost_t[me]
	boost_lbl.text = "WEAPON BOOST  %.1fs" % boost if boost > 0.0 else ""

	if _game.countdown > 0.0:
		msg_lbl.text = "ROUND %d\n%d" % [_game.round_num, ceili(_game.countdown)]
	elif _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			msg_lbl.text = ""


func _tint_bar(bar: ProgressBar, c: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
