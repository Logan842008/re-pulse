extends Node

enum State { OFFLINE, CONNECTING, ROOM }

const GAME_SCENE := preload("res://scene/game.tscn")
const GAME_3D_SCENE := preload("res://scene/game_3d.tscn")
const MODES: Array[String] = ["3D Arena", "Classic 2D"]
const WIN_OPTS: Array[int] = [1, 2, 3, 5]
const MENU_H := 650.0
const MODE_NAMES := {"1v1": "1v1", "2v2": "2v2", "ffa": "Free for all"}

var _state := State.OFFLINE
var _mp: PanelContainer
var _ml: Label
var _bb: Button
var _prv: Node
var _pc: Camera3D
var _cam2d: Camera2D
var _pk := []
var _dim: ColorRect
var _orbit := 0.0
var _to: OptionButton
var _seen := 0

@onready var level: Node = $Level
@onready var ls: MultiplayerSpawner = $LevelSpawner
@onready var lobby: CanvasLayer = $Lobby
@onready var ne: LineEdit = %NameEdit
@onready var swat: HBoxContainer = %Swatches
@onready var rr: HBoxContainer = %RoundsRow
@onready var ro: OptionButton = %Rounds
@onready var mr: HBoxContainer = %ModeRow
@onready var mo: OptionButton = %Mode
@onready var ge: WorldEnvironment = $GlowEnvironment
@onready var _glow: Environment = ge.environment
@onready var cb: VBoxContainer = %ConnectBox
@onready var hb: Button = %HostButton
@onready var ce: LineEdit = %CodeEdit
@onready var jb: Button = %JoinButton
@onready var rb: VBoxContainer = %RoomBox
@onready var pl: VBoxContainer = %PlayerList
@onready var sbt: Button = %StartButton
@onready var rh: Label = %RoomHint
@onready var leave_btn: Button = %LeaveButton
@onready var sl: Label = %Status
@onready var border: NinePatchRect = $Lobby/Border

const RECOLOR := "shader_type canvas_item;
uniform vec4 tint : source_color;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(tint.rgb * max(t.g, t.b) * 1.3, t.a * 0.9);
}"


func _ready() -> void:
	ls.add_spawnable_scene(GAME_SCENE.resource_path)
	ls.add_spawnable_scene(GAME_3D_SCENE.resource_path)
	ls.spawned.connect(_on_game_spawned)
	ls.despawned.connect(_on_game_despawned)

	for n in WIN_OPTS:
		ro.add_item("First to %d" % n)
	ro.select(WIN_OPTS.find(Network.first_to))
	$Lobby/Center/Layout/Panel/Box/RoundsRow/RoundsLabel.text = "Match (host picks)"
	_to = OptionButton.new()
	_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m: String in Network.MODES:
		_to.add_item(MODE_NAMES[m])
	_to.select(Network.MODES.find(Network.mode))
	_to.item_selected.connect(_on_team_mode)
	rr.add_child(_to)
	$Lobby/Center/Layout/Panel/Box/ModeRow/ModeLabel.text = "Map (host picks)"
	mo.item_selected.connect(_on_map_selected)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.06, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	lobby.add_child(_dim)
	lobby.move_child(_dim, $Lobby/Grid.get_index() + 1)
	_build_mode_select()
	ne.max_length = Network.MAX_NAME_LEN
	ne.text = Network.my_name
	ne.text_changed.connect(_on_name_changed)
	ce.max_length = Network.CODE_LEN
	ce.text_submitted.connect(_on_join.unbind(1))
	_build_swatches()
	get_viewport().size_changed.connect(_fit_layout)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	leave_btn.get_parent().add_child(btns)
	leave_btn.get_parent().move_child(btns, leave_btn.get_index())
	sbt.reparent(btns)
	leave_btn.reparent(btns)
	for b: Button in [sbt, leave_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	hb.pressed.connect(_on_host)
	jb.pressed.connect(_on_join)
	sbt.pressed.connect(_on_start)
	leave_btn.pressed.connect(_return_to_lobby)
	Network.roster_changed.connect(_refresh)
	Network.room_opened.connect(_on_room_opened)
	Network.failed.connect(_return_to_lobby)
	Network.failed.connect(func(_r: String): Sfx.play("error", -4.0))
	Network.status.connect(func(msg: String): sl.text = msg)

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_refresh()
	Sfx.music("menu")
	var fade := ColorRect.new()
	fade.color = get_tree().root.get_meta("fade_from", Color("07070f"))
	get_tree().root.remove_meta("fade_from")
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ft := fade.create_tween()
	ft.tween_property(fade, "color:a", 0.0, 0.5)
	ft.tween_callback(fade.queue_free)


func _on_name_changed(nn: String) -> void:
	Network.my_name = nn
	Network.save_profile()
	Network.submit_profile()


func _on_swatch(idx: int) -> void:
	Network.my_color = idx
	Network.save_profile()
	Network.submit_profile()
	_refresh()


func _build_swatches() -> void:
	for i in Network.PALETTE.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(30, 30)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = Network.COLOR_NAMES[i]
		sw.pressed.connect(_on_swatch.bind(i))
		swat.add_child(sw)


func _my_color() -> int:
	var slot := Network.my_slot()
	if _state == State.ROOM and Network.roster.has(slot):
		return Network.roster[slot]["color"]
	return Network.my_color


func _taken_colors() -> Array:
	var out := []
	if _state != State.ROOM:
		return out
	for s: int in Network.roster:
		if s != Network.my_slot() and not (Network.mode == "2v2" and Network.team_of(s) == Network.team_of(Network.my_slot())):
			out.append(Network.roster[s]["color"])
	return out


func _refresh_swatches() -> void:
	var mine := _my_color()
	var taken := _taken_colors()
	Network.tint_theme(Network.PALETTE[mine])
	if border.material == null:
		var sh := Shader.new()
		sh.code = RECOLOR
		border.material = ShaderMaterial.new()
		border.material.shader = sh
	var accent := Network.PALETTE[mine]
	border.material.set_shader_parameter("tint", accent)
	$Lobby/Center/Layout/Title.add_theme_color_override("font_color", Color(accent.lerp(Color.WHITE, 0.45) * 1.7, 1.0))
	$Lobby/Center/Layout/Title/TitleGhost.add_theme_color_override("font_color", Color(accent * 1.4, 0.85))
	sl.add_theme_color_override("font_color", accent.lightened(0.35))
	$Lobby/Orbs.tint(accent)
	for i in swat.get_child_count():
		var sw: Button = swat.get_child(i)
		var col := Network.PALETTE[i]
		var gone := taken.has(i)
		sw.disabled = gone
		sw.text = "X" if gone else ""
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.7) if gone else col
		sb.set_corner_radius_all(15)
		sb.border_color = Color(0.91, 0.98, 1.0)
		sb.set_border_width_all(3 if i == mine else 0)
		if i == mine:
			sb.shadow_color = Color(col, 0.7)
			sb.shadow_size = 10
		var hover := sb.duplicate()
		if i != mine and not gone:
			hover.bg_color = col.lightened(0.25)
		for s in ["normal", "pressed", "disabled", "focus"]:
			sw.add_theme_stylebox_override(s, sb)
		sw.add_theme_stylebox_override("hover", hover)
		sw.add_theme_color_override("font_disabled_color", Color(0.48, 0.5, 0.66))


func _on_host() -> void:
	var err := Network.host_game()
	if err != OK:
		sl.text = _err_text(err)
		return
	_state = State.CONNECTING
	sl.text = "Opening a room..."
	_refresh()


func _on_room_opened() -> void:
	_state = State.ROOM
	Sfx.play("confirm", -4.0)
	sl.text = ""
	_refresh()


func _on_join() -> void:
	if _state != State.OFFLINE:
		return
	var code := ce.text.strip_edges().to_upper()
	if code.is_empty():
		sl.text = "Type the room code first."
		return
	var err := Network.join_game(code)
	if err != OK:
		sl.text = _err_text(err)
		return
	_state = State.CONNECTING
	sl.text = "Joining %s..." % code
	_refresh()


func _err_text(err: Error) -> String:
	if err == ERR_UNAVAILABLE:
		return "WebRTC not available (desktop needs the webrtc-native plugin)."
	return "Couldn't start (%s)." % error_string(err)


func _on_connected() -> void:
	_state = State.ROOM
	Sfx.play("confirm", -4.0)
	sl.text = ""
	_refresh()


func _on_start() -> void:
	if not multiplayer.is_server() or not Network.can_start():
		return
	Network.first_to = WIN_OPTS[ro.selected]
	Network.in_match = true
	_push_mode()
	_clear_preview()
	var game: Node = (GAME_3D_SCENE if Network.is_3d else GAME_SCENE).instantiate()
	game.exit_requested.connect(_return_to_lobby)
	_set_glow(not game is Game3D)
	level.add_child(game, true)
	lobby.hide()


func _on_game_spawned(node: Node) -> void:
	_clear_preview()
	node.exit_requested.connect(_return_to_lobby)
	_set_glow(not node is Game3D)
	lobby.hide()


func _set_glow(on: bool) -> void:
	ge.environment = _glow if on else null


func _on_team_mode(idx: int) -> void:
	Network.mode = Network.MODES[idx]
	Network.fix_colors()
	_push_mode()
	_refresh()


func _on_map_selected(idx: int) -> void:
	Network.map_id = idx
	_show_preview()
	_push_mode()


func _push_mode() -> void:
	if _state == State.ROOM and multiplayer.is_server() and Network.roster.size() > 1:
		_sync_mode.rpc(Network.is_3d, Network.map_id, Network.mode)


@rpc("authority", "call_remote", "reliable")
func _sync_mode(is_3d: bool, map: int, mode: String) -> void:
	var changed := is_3d != Network.is_3d or map != Network.map_id
	Network.is_3d = is_3d
	Network.map_id = map
	Network.mode = mode if Network.MODES.has(mode) else "1v1"
	_to.select(Network.MODES.find(Network.mode))
	if changed:
		_fill_maps()
		_show_preview()
	_refresh()


func _build_mode_select() -> void:
	var layout: VBoxContainer = $Lobby/Center/Layout
	var panel: PanelContainer = $Lobby/Center/Layout/Panel
	_mp = PanelContainer.new()
	layout.add_child(_mp)
	layout.move_child(_mp, panel.get_index())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_mp.add_child(box)
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = "CHOOSE YOUR GAME"
	box.add_child(head)
	for is_3d in [true, false]:
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton" if is_3d else &"PinkButton"
		b.custom_minimum_size = Vector2(420, 64)
		b.text = "3D ARENA" if is_3d else "CLASSIC 2D"
		b.pressed.connect(_pick_mode.bind(is_3d))
		b.mouse_entered.connect(func(): _preview_mode(is_3d))
		box.add_child(b)
		var hint := Label.new()
		hint.theme_type_variation = &"MutedLabel"
		hint.text = "First person, pulses bounce off walls and floor. 3 maps." if is_3d else "Top-down, the original. 3 maps."
		box.add_child(hint)

	var lb: VBoxContainer = $Lobby/Center/Layout/Panel/Box
	var header: Label = $Lobby/Center/Layout/Panel/Box/PlayerHeader
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	lb.add_child(row)
	lb.move_child(row, header.get_index())
	header.reparent(row)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ml = Label.new()
	_ml.theme_type_variation = &"MutedLabel"
	row.add_child(_ml)
	_bb = Button.new()
	_bb.text = "CHANGE"
	_bb.theme_type_variation = &"PinkButton"
	_bb.custom_minimum_size = Vector2(100, 30)
	_bb.pressed.connect(_show_mode_select)
	row.add_child(_bb)
	_show_mode_select()


func _show_mode_select() -> void:
	if _state != State.OFFLINE:
		return
	_mp.show()
	$Lobby/Center/Layout/Panel.hide()
	_preview_mode(Network.is_3d)
	_fit_layout.call_deferred()


func _pick_mode(is_3d: bool) -> void:
	if Network.is_3d != is_3d:
		Network.map_id = 0
	Network.is_3d = is_3d
	_fill_maps()
	_mp.hide()
	$Lobby/Center/Layout/Panel.show()
	_show_preview()
	_refresh()


func _preview_mode(is_3d: bool) -> void:
	if _pk != [is_3d, 0] or _prv == null:
		_show_preview(is_3d, 0)


func _fill_maps() -> void:
	mo.clear()
	for m: Dictionary in Maps.list(Network.is_3d):
		mo.add_item("%s  ·  %s" % [m["name"], m["time"]])
	mo.select(Network.map_id)


func _show_preview(is_3d := Network.is_3d, idx := Network.map_id) -> void:
	_clear_preview()
	_pk = [is_3d, idx]
	_prv = MapCache.take(is_3d, idx)
	if is_3d:
		add_child(_prv)
		_pc = Camera3D.new()
		_pc.fov = 55
		_prv.add_child(_pc)
		_pc.current = true
	else:
		add_child(_prv)
		_cam2d = Camera2D.new()
		_cam2d.position = _prv.get_center()
		_prv.add_child(_cam2d)
		_cam2d.make_current()
	_set_glow(false)
	$Lobby/Background.visible = false
	$Lobby/Grid.visible = false
	_dim.visible = true


func _clear_preview() -> void:
	for c in [_pc, _cam2d]:
		if c:
			c.free()
	if _prv:
		MapCache.give_back(_prv)
	_prv = null
	_pc = null
	_cam2d = null
	_pk = []
	$Lobby/Background.visible = true
	$Lobby/Grid.visible = true
	if _dim:
		_dim.visible = false


func _process(delta: float) -> void:
	if _pc:
		_orbit += delta * 0.07
		var r := 21.0
		_pc.position = Vector3(cos(_orbit) * r, 13.0 + sin(_orbit * 0.6) * 1.5, sin(_orbit) * r)
		_pc.look_at(Vector3(0, 10.5, 0))
	elif _cam2d:
		_orbit += delta * 0.25
		var fit := minf(get_viewport().get_visible_rect().size.x / 1152.0, get_viewport().get_visible_rect().size.y / 648.0)
		_cam2d.zoom = Vector2.ONE * fit * (1.08 + sin(_orbit) * 0.04)
		_cam2d.offset = Vector2(cos(_orbit * 0.7) * 24.0, sin(_orbit * 0.5) * 14.0)


func _on_peer_disconnected(_pid: int) -> void:
	if multiplayer.is_server() and level.get_child_count() > 0:
		_player_left.call_deferred()


func _player_left() -> void:
	_close_game()
	lobby.show()
	sl.text = "A player left, so the match ended."
	_show_preview()
	_refresh()


func _on_game_despawned(_node: Node) -> void:
	if multiplayer.is_server() or _state != State.ROOM:
		return
	_set_glow(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby.show()
	sl.text = "A player left, so the match ended."
	_show_preview()
	_refresh()


func _on_server_disconnected() -> void:
	_return_to_lobby.call_deferred("The host left.")


func _return_to_lobby(msg := "") -> void:
	_close_game()
	Network.leave_game()
	_state = State.OFFLINE
	lobby.show()
	sl.text = msg
	_show_preview()
	_refresh()


func _close_game() -> void:
	for c in level.get_children():
		level.remove_child(c)
		c.queue_free()
	_set_glow(true)
	Network.in_match = false
	Sfx.music("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh() -> void:
	var ir := _state == State.ROOM
	if ir and Network.roster.size() > _seen and _seen > 0:
		Sfx.play("join", -4.0)
	_seen = Network.roster.size() if ir else 0
	var ih := ir and multiplayer.is_server()
	var ready := Network.can_start()

	cb.visible = not ir
	hb.disabled = _state != State.OFFLINE
	jb.disabled = _state != State.OFFLINE
	ce.editable = _state == State.OFFLINE
	rr.visible = not ir or ih
	mr.visible = rr.visible
	rb.visible = ir
	sbt.visible = ih
	sbt.disabled = not ready
	leave_btn.visible = _state != State.OFFLINE
	_ml.text = "3D ARENA" if Network.is_3d else "CLASSIC 2D"
	_bb.visible = _state == State.OFFLINE

	if ih:
		rh.text = _host_hint(ready)
	else:
		var mn: String = Maps.list(Network.is_3d)[Network.map_id]["name"]
		rh.text = "%s  ·  %s  ·  %s\nWaiting for the host to start the match..." % [
			MODES[0 if Network.is_3d else 1], mn, MODE_NAMES[Network.mode]]

	if ih and Network.roster.size() > 1:
		_push_mode()
	_refresh_players()
	_fit_layout.call_deferred()
	_refresh_swatches()


func _host_hint(ready: bool) -> String:
	var n := Network.roster.size()
	var code := "\nRoom code:  %s" % Network.room_code
	match Network.mode:
		"2v2":
			if n < 4:
				return "Waiting for players  (%d/4)%s" % [n, code]
			if not ready:
				return "Teams need to be 2 and 2, someone switch sides."
			return "Teams are set. Press Start Match when everyone's ready."
		"ffa":
			if n < 3:
				return "Waiting for players  (%d/3-4)%s" % [n, code]
			if n == 3:
				return "3 players in. Start now, or wait for a 4th.%s" % code
			return "Everyone's here. Press Start Match when you're ready."
	if n < 2:
		return "Waiting for an opponent...%s" % code
	if n > 2:
		return "1v1 is for 2 players, pick 2v2 or Free for all."
	return "Opponent is here. Press Start Match when you're both ready."


func _refresh_players() -> void:
	for c in pl.get_children():
		pl.remove_child(c)
		c.queue_free()
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	pl.add_child(cols)
	var lists := []
	var teams := Network.mode == "2v2"
	$Lobby/Center/Layout/Panel/Box/RoomBox/PlayersLabel.visible = not teams
	for t in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		lists.append(col)
		if teams:
			col.add_child(_team_head(t))
	var slots := Network.slots()
	if teams:
		for t in 2:
			var mems := Network.team_slots(t)
			for s: int in mems:
				_player_row(lists[t], s)
			for i in 2 - mems.size():
				_player_row(lists[t], -1)
	else:
		var total := 2 if Network.mode == "1v1" else Network.MAX_PLAYERS
		for i in maxi(total, slots.size()):
			_player_row(lists[i % 2], slots[i] if i < slots.size() else -1)


func _team_head(t: int) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.custom_minimum_size = Vector2(0, 32)
	var l := Label.new()
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.theme_type_variation = &"HeaderLabel"
	l.text = "TEAM %s" % ["A", "B"][t]
	head.add_child(l)
	var me := Network.my_slot()
	if Network.roster.has(me) and Network.team_of(me) != t and Network.team_slots(t).size() < 2:
		var b := Button.new()
		b.text = "JOIN"
		b.theme_type_variation = &"PinkButton"
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(56, 22)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(Network.request_team.bind(t))
		head.add_child(b)
	return head


func _player_row(list: VBoxContainer, slot: int) -> void:
	var row := HBoxContainer.new()
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(16, 16)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	var lbl := Label.new()
	if slot < 0:
		sb.bg_color = Color(1, 1, 1, 0.08)
		lbl.text = "open"
		lbl.theme_type_variation = &"MutedLabel"
		lbl.modulate.a = 0.6
	else:
		var col := Network.color_of(slot)
		sb.bg_color = col
		sb.shadow_color = Color(col, 0.6)
		sb.shadow_size = 6
		lbl.text = Network.name_of(slot)
		if slot == 0:
			lbl.text += "  (host)"
		if slot == Network.my_slot():
			lbl.text += "  - you"
	chip.add_theme_stylebox_override("panel", sb)
	row.add_child(chip)
	row.add_child(lbl)
	list.add_child(row)


func _fit_layout() -> void:
	var center: Control = $Lobby/Center
	var layout: VBoxContainer = $Lobby/Center/Layout
	layout.custom_minimum_size.y = MENU_H
	layout.alignment = BoxContainer.ALIGNMENT_BEGIN
	var room := get_viewport().get_visible_rect().size - Vector2(64, 64)
	var need: Vector2 = layout.get_combined_minimum_size()
	center.pivot_offset = center.size / 2.0
	center.scale = Vector2.ONE * minf(1.0, minf(room.x / need.x, room.y / need.y))
