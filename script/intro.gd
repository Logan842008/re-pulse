extends Control

const NEXT := "res://scene/main.tscn"
const BG := Color("07070f")
const BIG := preload("res://ui/fonts/title_font.tres")
const HEAD := preload("res://ui/fonts/heading_font.tres")
const FLASH := ["muzzle_01", "muzzle_02", "muzzle_03", "muzzle_04", "muzzle_05"]
const SCORCH := ["scorch_01", "scorch_02", "scorch_03"]
const MIN_LOAD := 2.0

var _stage: Control
var _logo: VBoxContainer
var _word: HBoxContainer
var _games: HBoxContainer
var _bb: Control
var _track: ColorRect
var _bar: ColorRect
var _status: Label
var _white: ColorRect
var _black: ColorRect

var _t := 0.0
var _prog := 0.0
var _shown := 0.0
var _loaded := false
var _firing := false
var _skip := false
var _fire_t := 0.0
var _done := false
var _next: PackedScene


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CANVAS
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.9
	env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	add_child(env)

	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_stage = Control.new()
	add_child(_stage)
	_stage.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_stage.add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_logo = VBoxContainer.new()
	_logo.alignment = BoxContainer.ALIGNMENT_CENTER
	_logo.add_theme_constant_override("separation", 6)
	center.add_child(_logo)
	_word = HBoxContainer.new()
	_word.alignment = BoxContainer.ALIGNMENT_CENTER
	_word.add_theme_constant_override("separation", 1)
	_logo.add_child(_word)
	for ch in "LOGAN-RITHM":
		var l := _label(ch, BIG, 80, Color.WHITE)
		l.modulate.a = 0.0
		_word.add_child(l)

	_bb = Control.new()
	_bb.custom_minimum_size = Vector2(0, 6)
	_logo.add_child(_bb)
	_track = ColorRect.new()
	_track.color = Color(1, 1, 1, 0.08)
	_bb.add_child(_track)
	_bar = ColorRect.new()
	_bb.add_child(_bar)

	_games = HBoxContainer.new()
	_games.alignment = BoxContainer.ALIGNMENT_CENTER
	_games.add_theme_constant_override("separation", 110)
	_games.modulate.a = 0.0
	for ch in "GAMES":
		_games.add_child(_label(ch, HEAD, 30, Color(0.92, 0.92, 0.96)))
	_logo.add_child(_games)
	_status = _label("LOADING", HEAD, 12, Color(1, 1, 1, 0.4))
	_logo.add_child(_status)

	_white = _overlay(Color(1, 1, 1, 0))
	_black = _overlay(Color(BG, 1))
	await get_tree().process_frame
	_bb.custom_minimum_size.x = _word.size.x
	_track.size = Vector2(_word.size.x, 6)
	_bar.size = Vector2(0, 6)
	_logo_in()
	_load_all()


func _label(txt: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _overlay(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(r)
	r.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	return r


func _rainbow(t: float) -> Color:
	var p := Network.PALETTE
	var x := fposmod(t, float(p.size()))
	var i := int(x)
	return p[i].lerp(p[(i + 1) % p.size()], x - i)


func _process(delta: float) -> void:
	_t += delta
	var cap := minf(_t / MIN_LOAD, 1.0)
	_shown = move_toward(_shown, minf(_prog, cap), delta * 1.5)
	if _bar:
		_bar.size.x = _track.size.x * _shown
		var c := _rainbow(_t * 1.6)
		_bar.color = Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0)
		if not _firing:
			_status.text = "LOADING  %d%%" % roundi(_shown * 100.0)
	if _loaded and _shown >= 1.0 and not _firing:
		if OS.has_feature("web") and not _skip:
			_status.text = "TAP TO START" if DisplayServer.is_touchscreen_available() else "CLICK TO START"
			_status.add_theme_font_size_override("font_size", 18)
			_status.add_theme_color_override("font_color", Color.WHITE)
			_status.modulate.a = 0.55 + 0.45 * sin(_t * 5.0)
			return
		_firing = true
		_fire_t = _t
		_gunfire()


func _logo_in() -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.0, 0.3)
	var ltrs: Array = _word.get_children()
	for i in ltrs.size():
		var l: Label = ltrs[i]
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2.ONE * 2.2
		var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.2 + i * 0.045)
		t.tween_property(l, "modulate:a", 1.0, 0.1)
		t.parallel().tween_property(l, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(0.55)
	tw.tween_callback(func():
		Sfx.play("slam", -2.0)
		_shake(8.0))
	tw.tween_property(_games, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_method(_space_games, 110.0, 18.0, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_callback(Sfx.play.bind("slide", -6.0))


func _space_games(v: float) -> void:
	_games.add_theme_constant_override("separation", int(v))


func _load_all() -> void:
	var paths: Array[String] = [NEXT]
	for l: Array in [Maps.D3, Maps.D2]:
		for m: Dictionary in l:
			paths.append(m["scene"])
	for p in paths:
		ResourceLoader.load_threaded_request(p, "", true)
	while true:
		var sum := 0.0
		var busy := false
		for p in paths:
			var pr := []
			var st := ResourceLoader.load_threaded_get_status(p, pr)
			if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				busy = true
				sum += pr[0] if not pr.is_empty() else 0.0
			else:
				sum += 1.0
		_prog = 0.35 * sum / paths.size()
		if not busy:
			break
		await get_tree().process_frame
	for p in paths:
		var r := ResourceLoader.load_threaded_get(p)
		MapCache.keep.append(r)
		if p == NEXT:
			_next = r

	var warm := SubViewport.new()
	warm.size = Vector2i(640, 360)
	warm.own_world_3d = true
	warm.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	warm.scaling_3d_mode = ProjectSettings.get_setting_with_override("rendering/scaling_3d/mode")
	add_child(warm)
	var cam := Camera3D.new()
	cam.fov = 55
	warm.add_child(cam)
	cam.current = true
	var list := []
	for i in Maps.D3.size():
		list.append([true, i])
	for i in Maps.D2.size():
		list.append([false, i])
	for k in list.size():
		var three: bool = list[k][0]
		var m := MapCache.take(three, list[k][1])
		warm.add_child(m)
		if three:
			cam.position = Vector3(21, 13, 0)
			cam.look_at(Vector3(0, 10.5, 0))
		for f in (4 if three else 14):
			await get_tree().process_frame
		MapCache.give_back(m)
		_prog = 0.35 + 0.65 * (k + 1) / list.size()
	warm.queue_free()
	_prog = 1.0
	_loaded = true


func _gunfire() -> void:
	_status.text = "READY"
	var tw := create_tween()
	tw.tween_property(_status, "modulate:a", 0.0, 0.3)
	var gaps := [0.05, 0.2, 0.16, 0.18, 0.1, 0.13, 0.08, 0.09, 0.07]
	for g in gaps:
		tw.tween_interval(g)
		tw.tween_callback(_shot)
	tw.tween_interval(0.3)
	tw.tween_callback(_finale)
	tw.tween_property(_white, "color:a", 1.0, 0.07)
	tw.tween_callback(_go)


func _shot(big := false) -> void:
	var sz := size
	var at := Vector2(randf_range(0.08, 0.92) * sz.x, randf_range(0.1, 0.9) * sz.y)
	var mark := Sprite2D.new()
	mark.texture = load("res://assets/particles/%s.png" % SCORCH.pick_random())
	mark.position = at
	mark.rotation = randf() * TAU
	mark.scale = Vector2.ONE * randf_range(0.18, 0.3) * (2.0 if big else 1.0)
	mark.modulate = Color(2.4, 1.0, 0.35, 0.9)
	_stage.add_child(mark)
	_stage.move_child(mark, 0)
	mark.create_tween().tween_property(mark, "modulate", Color(0.42, 0.4, 0.44, 0.55), 0.9)
	_tracer(at)
	var fl := Sprite2D.new()
	fl.texture = load("res://assets/particles/%s.png" % FLASH.pick_random())
	fl.position = at
	fl.rotation = randf() * TAU
	fl.scale = Vector2.ONE * randf_range(0.35, 0.55) * (2.2 if big else 1.0)
	fl.modulate = Color(3.2, 2.4, 1.4, 1.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fl.material = mat
	add_child(fl)
	var t := fl.create_tween()
	t.tween_property(fl, "scale", fl.scale * 1.4, 0.08)
	t.parallel().tween_property(fl, "modulate:a", 0.0, 0.1)
	t.tween_callback(fl.queue_free)
	_white.color.a = 0.12 if not big else 0.0
	create_tween().tween_property(_white, "color:a", 0.0, 0.08)
	Sfx.gunshot(-3.0)
	_shake(14.0 if big else 7.0)


func _tracer(to: Vector2) -> void:
	var sz := size
	var from: Vector2 = [Vector2(-40, randf() * sz.y), Vector2(sz.x + 40, randf() * sz.y), Vector2(randf() * sz.x, sz.y + 40)].pick_random()
	var ln := Line2D.new()
	ln.points = PackedVector2Array([from, to])
	ln.width = 3.0
	ln.default_color = Color(3.0, 2.2, 1.2, 1.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 1))
	ln.gradient = grad
	add_child(ln)
	var t := ln.create_tween()
	t.tween_property(ln, "modulate:a", 0.0, 0.12)
	t.tween_callback(ln.queue_free)


func _finale() -> void:
	_shot(true)
	Sfx.gunshot(0.0)


func _shake(px: float) -> void:
	var t := create_tween()
	for i in 4:
		t.tween_property(_stage, "position", Vector2(randf_range(-px, px), randf_range(-px, px)), 0.03)
		px *= 0.6
	t.tween_property(_stage, "position", Vector2.ZERO, 0.04)


func _go() -> void:
	if _done:
		return
	_done = true
	_enter()


func _enter() -> void:
	get_tree().root.set_meta("fade_from", Color.WHITE)
	get_tree().change_scene_to_packed(_next)


func _input(e: InputEvent) -> void:
	var tap := (e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch) and e.is_pressed()
	if not tap or _done:
		return
	get_viewport().set_input_as_handled()
	_skip = true
	if _firing and _t - _fire_t > 0.4:
		_done = true
		var t := create_tween()
		t.tween_property(_white, "color:a", 1.0, 0.1)
		t.tween_callback(_enter)
