class_name Hud
extends CanvasLayer

signal leave_pressed
signal rematch_pressed

var _game: Game
var _message_time_left := 0.0

@onready var you_name: Label = %YouName
@onready var you_health: ProgressBar = %YouHealth
@onready var boost_label: Label = %BoostLabel
@onready var opponent_name: Label = %OpponentName
@onready var opponent_health: ProgressBar = %OpponentHealth
@onready var round_label: Label = %RoundLabel
@onready var you_score: Label = %YouScore
@onready var opp_score: Label = %OppScore
@onready var goal_label: Label = %GoalLabel
@onready var message_label: Label = %MessageLabel
@onready var rematch_button: Button = %RematchButton
@onready var leave_button: Button = %LeaveButton


func _ready() -> void:
	leave_button.pressed.connect(leave_pressed.emit)
	rematch_button.pressed.connect(rematch_pressed.emit)


func setup(game: Game) -> void:
	_game = game
	var me := Network.local_slot()
	var them := 1 - me
	you_name.text = "%s  (you)" % Network.get_player_name(me)
	opponent_name.text = Network.get_player_name(them)
	_tint_bar(you_health, Network.get_color(me))
	_tint_bar(opponent_health, Network.get_color(them))
	you_score.add_theme_color_override("font_color", Network.get_color(me))
	opp_score.add_theme_color_override("font_color", Network.get_color(them))


func show_message(text: String, seconds := 0.0) -> void:
	message_label.text = text
	_message_time_left = seconds


func show_rematch() -> void:
	rematch_button.show()


func hide_rematch() -> void:
	rematch_button.hide()


func _process(delta: float) -> void:
	if _game == null:
		return
	var me := Network.local_slot()
	var them := 1 - me
	you_health.max_value = _game.max_health
	you_health.value = _game.health[me]
	opponent_health.max_value = _game.max_health
	opponent_health.value = _game.health[them]
	round_label.text = "ROUND %d" % _game.round_number
	you_score.text = str(_game.scores[me])
	opp_score.text = str(_game.scores[them])
	goal_label.text = "FIRST TO %d" % _game.rounds_to_win()

	var boost: float = _game.boost_left[me]
	boost_label.text = "WEAPON BOOST  %.1fs" % boost if boost > 0.0 else ""

	if _game.countdown_left > 0.0:
		message_label.text = "ROUND %d\n%d" % [_game.round_number, ceili(_game.countdown_left)]
	elif _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			message_label.text = ""


func _tint_bar(bar: ProgressBar, color: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0)
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
