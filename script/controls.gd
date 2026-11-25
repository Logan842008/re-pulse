extends Node

signal touch_changed(on: bool)
signal binds_changed

const SAVE := "user://settings.cfg"
# negative = mouse button
const DEF := {
	"move_up": [KEY_W],
	"move_left": [KEY_A],
	"move_down": [KEY_S],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C],
	"walk": [KEY_SHIFT],
	"fire": [-MOUSE_BUTTON_LEFT],
	"scope": [-MOUSE_BUTTON_RIGHT],
	"scoreboard": [KEY_TAB],
	"ghost": [KEY_G],
	"shoot": [KEY_SPACE],
}

var touch := false
var paused := false
var aim := Vector2.ZERO
var binds := {}
var sens := 1.0
var tsens := 1.0
var auto := true
var _tt := -10000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply()
	get_tree().root.window_input.connect(_sniff)
	var mobile := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	# ipads say they're macs
	set_touch(mobile or OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available())


# tablets can have a keyboard and mouse too, so go with whatever was used last
func _sniff(e: InputEvent) -> void:
	if not auto or e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventScreenTouch:
		_tt = Time.get_ticks_msec()
		if not touch:
			set_touch(true)
		return
	if not touch:
		return
	# browsers fire fake mouse events right after a tap
	var fake := Time.get_ticks_msec() - _tt < 800
	var kb := false
	if e is InputEventKey:
		var fo := get_viewport().gui_get_focus_owner()
		kb = e.pressed and not e.echo and e.physical_keycode != KEY_F2 and not (fo is LineEdit or fo is TextEdit)
	elif e is InputEventMouseButton:
		kb = e.pressed and not fake
	elif e is InputEventMouseMotion:
		kb = e.relative.length() > 3.0 and not fake
	if kb:
		set_touch(false)


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
		auto = false
		set_touch(not touch)


func key_names(a: String) -> Array:
	return binds.get(a, []).map(name_of)


static func name_of(c: int) -> String:
	match c:
		-MOUSE_BUTTON_LEFT:
			return "LEFT CLICK"
		-MOUSE_BUTTON_RIGHT:
			return "RIGHT CLICK"
		-MOUSE_BUTTON_MIDDLE:
			return "MIDDLE CLICK"
		-MOUSE_BUTTON_XBUTTON1:
			return "MOUSE 4"
		-MOUSE_BUTTON_XBUTTON2:
			return "MOUSE 5"
	if c < 0:
		return "MOUSE %d" % -c
	return OS.get_keycode_string(c).to_upper()


static func code_of(e: InputEvent) -> int:
	if e is InputEventMouseButton:
		return -e.button_index
	if e is InputEventKey:
		return e.physical_keycode if e.physical_keycode != 0 else e.keycode
	return 0


func rebind(a: String, c: int) -> void:
	var old: Array = binds[a]
	for b: String in binds:
		if b != a and _clash(a, b) and binds[b].has(c):
			binds[b].erase(c)
			if binds[b].is_empty():
				binds[b] = [old[0]]
	binds[a] = [c]
	_apply()
	save()


func reset() -> void:
	binds = DEF.duplicate(true)
	_apply()
	save()


# 2d shoot only fights with the keys 2d uses
static func _clash(a: String, b: String) -> bool:
	if a == "shoot" or b == "shoot":
		var o := b if a == "shoot" else a
		return o.begins_with("move") or o == "scoreboard"
	return true


func _apply() -> void:
	for a: String in DEF:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey or ev is InputEventMouseButton:
				InputMap.action_erase_event(a, ev)
		for c: int in binds[a]:
			var ev: InputEvent
			if c < 0:
				ev = InputEventMouseButton.new()
				ev.button_index = -c
			else:
				ev = InputEventKey.new()
				ev.physical_keycode = c
			ev.device = -1
			InputMap.action_add_event(a, ev)
	binds_changed.emit()


func save() -> void:
	var cf := ConfigFile.new()
	for a: String in binds:
		cf.set_value("keys", a, binds[a])
	cf.set_value("look", "mouse", sens)
	cf.set_value("look", "touch", tsens)
	cf.save(SAVE)


func _load() -> void:
	binds = DEF.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	for a: String in DEF:
		var v = cf.get_value("keys", a, null)
		if v is Array and not v.is_empty():
			binds[a] = v
	sens = cf.get_value("look", "mouse", 1.0)
	tsens = cf.get_value("look", "touch", 1.0)
