class_name MatchStats
extends RefCounted

enum { K, D, A, DMG, FB }

var stats := []
var history := []
var pings := [0, 0, 0, 0]
var _hb := []
var _first := false
var _pair := {}


func _init() -> void:
	reset_match()


func reset_match() -> void:
	stats = []
	for i in 4:
		stats.append([0, 0, 0, 0, 0])
	history = []
	reset_round()


func reset_round() -> void:
	_hb = [{}, {}, {}, {}]
	_first = false
	_pair = {}


func hit(by: int, victim: int, dmg: int, killed: bool, zone := 1) -> void:
	if by < 0 or by > 3:
		return
	stats[by][DMG] += dmg
	var p: Array = _pair.get(by * 4 + victim, [0, 0, 0, 0])
	p[0] += dmg
	p[1 + zone] += 1
	_pair[by * 4 + victim] = p
	_hb[victim][by] = true
	if not killed:
		return
	stats[by][K] += 1
	stats[victim][D] += 1
	if not _first:
		_first = true
		stats[by][FB] += 1
	for a: int in _hb[victim]:
		if a != by and Network.team_of(a) != Network.team_of(victim):
			stats[a][A] += 1


func report(a: int, v: int) -> Array:
	return _pair.get(a * 4 + v, [0, 0, 0, 0])


static func score(row: Array) -> int:
	return row[DMG] + row[K] * 150 + row[A] * 50
