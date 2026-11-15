
class_name Hud
extends CanvasLayer

signal leave_pressed
signal rematch_pressed

var game: Game
var message_timer := 0.0

@onready var you_name: Label = %YouName
@onready var you_health: ProgressBar = %YouHealth
@onready var boost_label: Label = %BoostLabel
@onready var opponent_name: Label = %OpponentName
@onready var opponent_health: ProgressBar = %OpponentHealth
@onready var score_label: Label = %ScoreLabel
@onready var message_label: Label = %MessageLabel
@onready var rematch_button: Button = %RematchButton
@onready var leave_button: Button = %LeaveButton


func _ready() -> void:
	leave_button.pressed.connect(leave_pressed.emit)
	rematch_button.pressed.connect(rematch_pressed.emit)


func setup(current_game: Game) -> void:
	game = current_game

	var my_slot = Network.local_slot()
	var enemy_slot = 1 - my_slot

	you_name.text = Network.get_player_name(my_slot) + " (you)"
	opponent_name.text = Network.get_player_name(enemy_slot)

	set_health_color(you_health, Network.get_color(my_slot))
	set_health_color(opponent_health, Network.get_color(enemy_slot))


func show_message(text: String, seconds := 0.0) -> void:
	message_label.text = text
	message_timer = seconds


func show_rematch() -> void:
	rematch_button.show()


func hide_rematch() -> void:
	rematch_button.hide()


func _process(delta: float) -> void:
	if game == null:
		return

	update_health()
	update_score()
	update_boost()
	update_message(delta)


func update_health() -> void:
	var my_slot = Network.local_slot()
	var enemy_slot = 1 - my_slot

	you_health.max_value = game.max_health
	you_health.value = game.health[my_slot]

	opponent_health.max_value = game.max_health
	opponent_health.value = game.health[enemy_slot]


func update_score() -> void:
	var my_slot = Network.local_slot()
	var enemy_slot = 1 - my_slot

	score_label.text = "Round %d     You %d - %d Opponent     (first to %d)" % [
		game.round_number,
		game.scores[my_slot],
		game.scores[enemy_slot],
		game.rounds_to_win()
	]


func update_boost() -> void:
	var my_slot = Network.local_slot()
	var boost_time = game.boost_left[my_slot]

	if boost_time > 0:
		boost_label.text = "WEAPON BOOST  %.1fs" % boost_time
	else:
		boost_label.text = ""


func update_message(delta: float) -> void:
	if game.countdown_left > 0:
		message_label.text = "ROUND %d\n%d" % [
			game.round_number,
			ceili(game.countdown_left)
		]
	elif message_timer > 0:
		message_timer -= delta

		if message_timer <= 0:
			message_label.text = ""


func set_health_color(bar: ProgressBar, color: Color) -> void:
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
