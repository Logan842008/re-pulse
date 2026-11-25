class_name Scoreboard
extends Control

const GOLD := Color("f2c45a")
const DARK := Color("0f1923")
const WHITE := Color("ece8e1")
const BODY := preload("res://Rajdhani-SemiBold.ttf")
const BIG := preload("res://ui/fonts/title_font.tres")
const HEAD := preload("res://ui/fonts/heading_font.tres")
const THEME := preload("res://lobby_theme.tres")
const CHAR := "res://assets/models/character/character-%s.glb"
const CHARS := ["p", "b", "h", "d", "c", "e"]

var game: Node
var _rm: Callable
var _leave: Callable
var _shots := {}
var _guns := {}
var _top: HBoxContainer
var _tiles := []
var _ms: Label
var _ts: Label
var _round_lbl: Label
var _clock: Label
var _tab: PanelContainer
var _tab_t := 0.0
var _end: Control
var _es := false
var _feed: VBoxContainer
var _nl: Label
var _net_t := 0.0
var _cc := Color(0, 0, 0, 0)


func _init(g: Node, ore: Callable, ol: Callable) -> void:
	game = g
	_rm = ore
	_leave = ol


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top()
	_tab = PanelContainer.new()
	_tab.add_theme_stylebox_override("panel", _box(Color(DARK, 0.95), Color(WHITE, 0.12)))
	_tab.mouse_filter = MOUSE_FILTER_IGNORE
	var mid := CenterContainer.new()
	mid.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(mid)
	mid.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mid.add_child(_tab)
	_tab.hide()
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_feed)
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.offset_right = -20
	_feed.offset_top = 18
	_feed.grow_horizontal = GROW_DIRECTION_BEGIN
	_nl = _label(self, 16, Color(1.0, 0.62, 0.25), HEAD)
	_nl.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_nl.offset_top = 104
	_end = Control.new()
	_end.hide()
	add_child(_end)
	_end.set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if game == null:
		return
	var me := Network.my_slot()
	_ms.text = str(game.scores[_mine()])
	if _ts.visible:
		_ts.text = str(game.scores[_theirs()])
	_round_lbl.text = "ROUND %d" % game.round_num
	var t: float = game.countdown if game.countdown > 0.0 else game.round_t
	_clock.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
	var cc := GOLD if game.countdown > 0.0 else WHITE
	if cc != _cc:
		_cc = cc
		_clock.add_theme_color_override("font_color", cc)
	for tl: Array in _tiles:
		var alive: bool = game.is_alive(tl[0])
		tl[1].modulate = Color.WHITE if alive else Color(0.75, 0.75, 0.75, 0.45)
		if tl[2] is ProgressBar:
			tl[2].value = game.hp[tl[0]]
		elif tl[2] is Label:
			tl[2].text = str(game.scores[Network.team_of(tl[0])])

	_net_t -= delta
	if _net_t <= 0.0:
		_net_t = 0.25
		var who := Network.lagging()
		_nl.text = "" if who.is_empty() else "WAITING ON %s'S CONNECTION..." % who
	var over: bool = game.match_over
	_top.visible = not over
	_feed.visible = not over
	var wt := Input.is_action_pressed("scoreboard") and not over
	if wt:
		_tab_t -= delta
		if not _tab.visible or _tab_t <= 0.0:
			_tab_t = 0.3
			_fill_tab(me)
	_tab.visible = wt
	if over and not _es:
		_fill_end(me)
	_es = over
	_end.visible = over


func _mine() -> int:
	return Network.team_of(Network.my_slot())


func _theirs() -> int:
	for s: int in _everyone():
		if Network.team_of(s) != _mine():
			return Network.team_of(s)
	return 1 - _mine()


func _everyone() -> Array:
	if not Network.roster.is_empty():
		return Network.slots()
	return game.in_play()


func _ally(s: int) -> bool:
	return Network.team_of(s) == _mine()


func _build_top() -> void:
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 6)
	_top.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_top)
	_top.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	_top.offset_top = 10
	_top.alignment = BoxContainer.ALIGNMENT_CENTER

	var me := Network.my_slot()
	var ffa := Network.mode == "ffa"
	var allies := _everyone().filter(_ally)
	allies.erase(me)
	allies.append(me)
	var foes := _everyone().filter(func(s: int) -> bool: return not _ally(s))
	for s: int in allies:
		_top.add_child(_tile(s, true, false))
	_ms = _score_box(Network.side_color(_mine()))
	var back := PanelContainer.new()
	var bsb := _box(Color(DARK, 0.72), Color(0, 0, 0, 0))
	bsb.content_margin_top = 2
	bsb.content_margin_bottom = 2
	back.add_theme_stylebox_override("panel", bsb)
	back.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_child(back)
	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(90, 0)
	mid.add_theme_constant_override("separation", -4)
	mid.mouse_filter = MOUSE_FILTER_IGNORE
	back.add_child(mid)
	_round_lbl = _label(mid, 12, Color(WHITE, 0.7))
	_clock = _label(mid, 34, WHITE)
	var goal := _label(mid, 11, Color(WHITE, 0.55))
	goal.text = "FIRST TO %d" % game.wins_needed()
	_ts = _score_box(Network.side_color(_theirs()))
	_ts.get_parent().visible = not ffa
	_ts.visible = not ffa
	for s: int in foes:
		_top.add_child(_tile(s, false, ffa))


func _score_box(col: Color) -> Label:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(54, 50)
	p.add_theme_stylebox_override("panel", _box(Color(col, 0.85), Color(0, 0, 0, 0)))
	p.mouse_filter = MOUSE_FILTER_IGNORE
	_top.add_child(p)
	var l := _label(p, 40, DARK)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _tile(s: int, ally: bool, ffa: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	var mine := s == Network.my_slot()
	var t := _portrait(s, 46, mine)
	v.add_child(t)
	var extra: Control = null
	if ally:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(46, 4)
		bar.max_value = game.max_hp
		bar.show_percentage = false
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.5)))
		bar.add_theme_stylebox_override("fill", _flat(Network.color_of(s).lightened(0.2)))
		v.add_child(bar)
		extra = bar
	elif ffa:
		var l := _label(v, 17, WHITE)
		extra = l
	_tiles.append([s, t, extra])
	return v


func _portrait(s: int, px: int, mark := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(px, px)
	var c := Network.color_of(s)
	var sb := _box(Color(c.darkened(0.55), 0.92), Color(0, 0, 0, 0))
	sb.set_content_margin_all(0)
	sb.border_color = c.lightened(0.15)
	sb.border_width_bottom = 3
	if mark:
		_glow(sb, c)
		sb.bg_color = Color(c.darkened(0.3), 0.95)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = _shot(s)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(tr)
	return p


func _shot(s: int) -> Texture2D:
	var ci := Network.char_of(s)
	if _shots.has(ci):
		return _shots[ci]
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var m: Node3D = load(CHAR % CHARS[ci % CHARS.size()]).instantiate()
	vp.add_child(m)
	var acc := [null]
	ArenaMap._bounds(m, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0]
	var h := box.size.y
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 0.42
	cam.position = Vector3(box.get_center().x, box.end.y - h * 0.2, box.end.z + 5.0)
	vp.add_child(cam)
	cam.look_at(Vector3(box.get_center().x, box.end.y - h * 0.2, 0.0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	vp.add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_CLEAR_COLOR
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.7
	vp.add_child(we)
	_shots[ci] = vp.get_texture()
	return _shots[ci]


func gun_icon(w: int) -> Texture2D:
	if _guns.has(w):
		return _guns[w]
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 64)
	vp.transparent_bg = true
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var m := Weapons.build_model(w, Color.WHITE, 1.0)
	vp.add_child(m)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.93, 0.92, 0.88)
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = white
	var acc := [null]
	Weapons._bounds(m, Transform3D.IDENTITY, acc)
	var box: AABB = acc[0]
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.z * 0.42, box.size.y * 1.05)
	cam.position = box.get_center() + Vector3(-5.0, 0, 0)
	vp.add_child(cam)
	cam.look_at(box.get_center())
	_guns[w] = vp.get_texture()
	return _guns[w]


func feed(by: int, victim: int, w: int, head := false) -> void:
	var me := Network.my_slot()
	var p := PanelContainer.new()
	var sb := _box(Color(Network.color_of(by).darkened(0.55), 0.82), WHITE if by == me or victim == me else Color(0, 0, 0, 0))
	sb.set_border_width_all(2 if by == me or victim == me else 0)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	_feed_name(row, by)
	var ic := TextureRect.new()
	ic.texture = gun_icon(w)
	ic.custom_minimum_size = Vector2(64, 24)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(ic)
	if head:
		row.add_child(_head_mark())
	_feed_name(row, victim)
	_feed.add_child(p)
	while _feed.get_child_count() > 5:
		_feed.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _feed_name(row: HBoxContainer, s: int) -> void:
	var l := _label(row, 19, Network.color_of(s).lightened(0.35))
	l.text = Network.name_of(s)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _head_mark() -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(22, 22)
	m.draw.connect(func():
		var c := Vector2(11, 11)
		m.draw_arc(c, 8.0, 0.0, TAU, 24, WHITE, 2.0, true)
		m.draw_circle(c, 3.5, WHITE)
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			m.draw_line(c + d * 8.0, c + d * 11.0, WHITE, 2.0))
	return m


const COLS := [["PLAYER", 230], ["K", 54], ["D", 54], ["A", 54], ["DMG", 70], ["WEAPON", 100], ["PING", 64]]


func _fill_tab(me: int) -> void:
	for c in _tab.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_tab.add_child(box)
	var cols := COLS.duplicate()
	if not "gun" in game:
		cols.remove_at(5)
	box.add_child(_head_row(cols))
	var rows := _everyone()
	if Network.mode == "ffa":
		rows.sort_custom(_by_wins)
		for s: int in rows:
			box.add_child(_tab_row(s, cols, s == me))
		return
	for s: int in rows.filter(_ally):
		box.add_child(_tab_row(s, cols, true))
	box.add_child(_history_strip())
	for s: int in rows.filter(func(o: int) -> bool: return not _ally(o)):
		box.add_child(_tab_row(s, cols, false))


func _by_wins(a: int, b: int) -> bool:
	var wa: int = game.scores[Network.team_of(a)]
	var wb: int = game.scores[Network.team_of(b)]
	if wa != wb:
		return wa > wb
	return game.ms.stats[a][MatchStats.K] > game.ms.stats[b][MatchStats.K]


func _head_row(cols: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 0)
	for c: Array in cols:
		var l := _cell(r, c[0], c[1], 12, Color(WHITE, 0.6))
		if c[0] == "PLAYER":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return r


func _tab_row(s: int, cols: Array, ally: bool) -> PanelContainer:
	var me := s == Network.my_slot()
	var col := Network.color_of(s)
	var p := PanelContainer.new()
	var sb := _box(Color(col.darkened(0.25 if me else 0.45), 0.85 if me else 0.7), Color(0, 0, 0, 0))
	if me:
		_glow(sb, col)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	if not game.is_alive(s):
		p.modulate.a = 0.55
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 0)
	p.add_child(r)
	var st: Array = game.ms.stats[s]
	for c: Array in cols:
		match c[0]:
			"PLAYER":
				var who := HBoxContainer.new()
				who.custom_minimum_size = Vector2(c[1], 0)
				who.add_theme_constant_override("separation", 8)
				r.add_child(who)
				who.add_child(_portrait(s, 32, me))
				var n := _label(who, 18, WHITE)
				n.text = Network.name_of(s)
				n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				n.size_flags_vertical = SIZE_EXPAND_FILL
			"K":
				_cell(r, str(st[MatchStats.K]), c[1], 18, WHITE)
			"D":
				_cell(r, str(st[MatchStats.D]), c[1], 18, WHITE)
			"A":
				_cell(r, str(st[MatchStats.A]), c[1], 18, WHITE)
			"DMG":
				_cell(r, str(st[MatchStats.DMG]), c[1], 18, WHITE)
			"WEAPON":
				var ic := TextureRect.new()
				ic.texture = gun_icon(game.gun[s])
				ic.custom_minimum_size = Vector2(c[1], 30)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ic.tooltip_text = Weapons.LIST[game.gun[s]]["name"]
				r.add_child(ic)
			"PING":
				_cell(r, "HOST" if s == 0 else str(game.ms.pings[s]), c[1], 16, Color(WHITE, 0.7))
	return p


func _history_strip() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.custom_minimum_size = Vector2(0, 30)
	var a := _label(r, 24, Network.side_color(_mine()).lightened(0.15))
	a.text = str(game.scores[_mine()])
	a.custom_minimum_size = Vector2(40, 0)
	for w: int in game.ms.history:
		var b := Panel.new()
		b.custom_minimum_size = Vector2(16, 16)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.add_theme_stylebox_override("panel", _flat(Network.side_color(w)))
		r.add_child(b)
	for i in maxi(0, game.wins_needed() * 2 - 1 - game.ms.history.size()):
		var b := Panel.new()
		b.custom_minimum_size = Vector2(16, 16)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.add_theme_stylebox_override("panel", _flat(Color(WHITE, 0.12)))
		r.add_child(b)
	var e := _label(r, 24, Network.side_color(_theirs()).lightened(0.15))
	e.text = str(game.scores[_theirs()])
	e.custom_minimum_size = Vector2(40, 0)
	return r


const ORD := ["1ST", "2ND", "3RD", "4TH"]
const END_COLS := [["INDIVIDUALLY SORTED", 250], ["SCORE", 110], ["K / D / A", 130], ["DMG", 90], ["FIRST BLOODS", 130]]


func _fill_end(me: int) -> void:
	for c in _end.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.82)
	_end.add_child(dim)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_end.add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	center.add_child(v)

	var ffa := Network.mode == "ffa"
	var rows := _everyone()
	rows.sort_custom(func(a: int, b: int) -> bool: return MatchStats.score(game.ms.stats[a]) > MatchStats.score(game.ms.stats[b]))
	var mine: int = game.scores[_mine()]
	var best := 0
	for s: int in _everyone():
		if Network.team_of(s) != _mine():
			best = maxi(best, game.scores[Network.team_of(s)])
	var won: bool = mine >= game.wins_needed()

	if ffa:
		var order := _everyone()
		order.sort_custom(_by_wins)
		var place := order.find(me) + 1
		_label(v, 58, WHITE, BIG).text = "VICTORY" if place == 1 else "DEFEAT"
		_label(v, 20, Network.color_of(me).lightened(0.25), HEAD).text = ORD[place - 1] + " PLACE"
		v.add_child(_standings(order, me))
	else:
		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_theme_constant_override("separation", 36)
		v.add_child(head)
		_label(head, 76, Network.side_color(_mine()).lightened(0.15)).text = str(mine)
		var word := _label(head, 58, WHITE, BIG)
		word.text = "VICTORY" if won else "DEFEAT"
		word.size_flags_vertical = SIZE_SHRINK_CENTER
		_label(head, 76, _best_color(best)).text = str(best)
	var tag := _label(v, 13, WHITE, HEAD)
	tag.text = "SCOREBOARD"
	var line := ColorRect.new()
	line.color = Network.color_of(me)
	line.custom_minimum_size = Vector2(120, 2)
	line.size_flags_horizontal = SIZE_SHRINK_CENTER
	v.add_child(line)

	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 3)
	v.add_child(table)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 0)
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", _box(Color(DARK, 0.9), Color(0, 0, 0, 0)))
	hp.add_child(hr)
	table.add_child(hp)
	for c: Array in END_COLS:
		_cell(hr, c[0], c[1], 12, Color(WHITE, 0.6))
	for s: int in rows:
		var st: Array = game.ms.stats[s]
		var p := PanelContainer.new()
		var sb := _box(Color(Network.color_of(s).darkened(0.25 if s == me else 0.45), 0.82), Color(0, 0, 0, 0))
		if s == me:
			_glow(sb, Network.color_of(s))
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		p.add_theme_stylebox_override("panel", sb)
		table.add_child(p)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 0)
		p.add_child(r)
		var who := HBoxContainer.new()
		who.custom_minimum_size = Vector2(END_COLS[0][1], 0)
		who.add_theme_constant_override("separation", 8)
		r.add_child(who)
		who.add_child(_portrait(s, 34, s == me))
		var n := _label(who, 18, WHITE)
		n.text = Network.name_of(s)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		n.size_flags_vertical = SIZE_EXPAND_FILL
		_cell(r, str(MatchStats.score(st)), END_COLS[1][1], 18, WHITE)
		_cell(r, "%d   /   %d   /   %d" % [st[MatchStats.K], st[MatchStats.D], st[MatchStats.A]], END_COLS[2][1], 18, WHITE)
		_cell(r, str(st[MatchStats.DMG]), END_COLS[3][1], 18, WHITE)
		_cell(r, str(st[MatchStats.FB]), END_COLS[4][1], 18, WHITE)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	if multiplayer.is_server():
		btns.add_child(_button("REMATCH", &"PrimaryButton", _rm))
	else:
		var w := _label(btns, 16, Color(WHITE, 0.7))
		w.text = "Waiting for the host to start a rematch..."
	btns.add_child(_button("LEAVE", &"PinkButton", _leave))


func _standings(order: Array, me: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for i in order.size():
		var s: int = order[i]
		var c := Network.color_of(s)
		var p := PanelContainer.new()
		var sb := _box(Color(c.darkened(0.3 if s == me else 0.5), 0.85), Color(0, 0, 0, 0))
		if s == me:
			_glow(sb, c)
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size = Vector2(118, 0)
		row.add_child(p)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		p.add_child(col)
		_label(col, 14, GOLD if i == 0 else Color(WHITE, 0.75), HEAD).text = ORD[i]
		var pic := _portrait(s, 44, s == me)
		pic.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(pic)
		_label(col, 16, WHITE).text = Network.name_of(s)
		var w: int = game.scores[Network.team_of(s)]
		_label(col, 26, c.lightened(0.3)).text = str(w)
		_label(col, 11, Color(WHITE, 0.55)).text = "ROUND WIN" if w == 1 else "ROUND WINS"
	return row


func _best_color(best: int) -> Color:
	for s: int in _everyone():
		var t := Network.team_of(s)
		if t != _mine() and game.scores[t] == best:
			return Network.side_color(t).lightened(0.15)
	return WHITE


func _button(txt: String, kind: StringName, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.theme = THEME
	b.theme_type_variation = kind
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(170, 44)
	b.pressed.connect(cb)
	paint(b, Network.color_of(Network.my_slot()), kind == &"PrimaryButton")
	return b


func _label(p: Control, size: int, col: Color, font: Font = BODY) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(DARK, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(l)
	return l


func _cell(p: Control, txt: String, w: int, size: int, col: Color) -> Label:
	var l := _label(p, size, col)
	l.text = txt
	l.custom_minimum_size = Vector2(w, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = SIZE_EXPAND_FILL
	return l


# buttons in your color during a match
static func paint(b: Button, col: Color, solid := false) -> void:
	var kind := &"PrimaryButton" if solid else &"PinkButton"
	var glow := Color(col.r * 1.6, col.g * 1.6, col.b * 1.6)
	for st: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := THEME.get_stylebox(st, kind).duplicate() as StyleBoxFlat
		if solid:
			sb.border_color = col
			sb.bg_color = col.darkened(0.35) if st.ends_with("pressed") else glow if st == "hover" else col
		else:
			sb.border_color = Color(col, 0.6) if st == "normal" else glow if st == "hover" else col
			if st != "normal":
				sb.bg_color = Color(col, 0.14 if st == "hover" else 0.28)
		b.add_theme_stylebox_override(st, sb)
	if not solid:
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_focus_color", col)


# your box glows a bit
static func _glow(sb: StyleBoxFlat, c: Color) -> void:
	sb.shadow_color = Color(c.lightened(0.25), 0.5)
	sb.shadow_size = 6
	sb.border_color = Color(c.lightened(0.45), 0.9)
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(2)
	return sb


func _flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	return sb
