extends Node

signal touch_changed(on: bool)

const BINDS := {
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C],
	"walk": [KEY_SHIFT],
	"fire": [MOUSE_BUTTON_LEFT],
	"scope": [MOUSE_BUTTON_RIGHT],
	"scoreboard": [KEY_TAB],
}

var touch := false
var paused := false
var aim := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in BINDS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for code: int in BINDS[a]:
			var ev: InputEvent
			if a in ["fire", "scope"]:
				ev = InputEventMouseButton.new()
				ev.button_index = code
			else:
				ev = InputEventKey.new()
				ev.physical_keycode = code
			InputMap.action_add_event(a, ev)
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	set_touch(mobile)


func set_touch(on: bool) -> void:
	touch = on
	paused = false
	aim = Vector2.ZERO
	Input.emulate_touch_from_mouse = on and not DisplayServer.is_touchscreen_available()
	if on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	touch_changed.emit(on)


func live() -> bool:
	if touch:
		return not paused
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F2:
		set_touch(not touch)
