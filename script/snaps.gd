class_name Snaps
extends RefCounted

const MAX_EXTRA := 100.0

var buf := []
var off := 0.0
var jit := 0.0
var n := 0


func push(t: int, d: Array) -> void:
	var o := float(Time.get_ticks_msec() - t)
	if n == 0 or o < off:
		off = o
	else:
		off += 0.02
	n += 1
	jit = lerpf(jit, o - off, 0.05)
	if not buf.is_empty() and t <= buf[-1][0]:
		return
	buf.append([t, d])
	if buf.size() > 40:
		buf.pop_front()


func delay() -> float:
	return clampf(jit * 2.0 + 30.0, 40.0, 220.0)


# run a bit behind so lag spikes dont look jittery
func sample() -> Array:
	if buf.is_empty():
		return []
	if buf.size() == 1:
		return [buf[0][1], buf[0][1], 0.0]
	var rt := Time.get_ticks_msec() - off - delay()
	if rt <= buf[0][0]:
		return [buf[0][1], buf[0][1], 0.0]
	for i in range(1, buf.size()):
		if buf[i][0] >= rt:
			var a: Array = buf[i - 1]
			var b: Array = buf[i]
			if i > 2:
				buf = buf.slice(i - 2)
			return [a[1], b[1], (rt - a[0]) / maxf(b[0] - a[0], 1.0)]
	var a: Array = buf[-2]
	var b: Array = buf[-1]
	var span := maxf(b[0] - a[0], 1.0)
	return [a[1], b[1], 1.0 + minf(rt - b[0], MAX_EXTRA) / span]
