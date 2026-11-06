# RealWorld — sim/haul.gd : auto-haul, the gather loop that closes itself (domain module of the live sim; stateless static funcs on `s`).
#
# One click on a tree used to mean: chop 30, stop, walk the load home by hand, click the tree again.
# Now full hands walk the load to the nearest storage (the ordinary auto-deposit unloads it there) and
# come back to the SAME node; a node that runs dry hands over to its nearest same-kind neighbour.
# Pure functions of state (paths, dict order, explicit tie-breaks) — twins and rejoiners agree.
#
# Винесено з sim.gd БЕЗ зміни поведінки (spec 0010 W2b: sim.gd впирався в стелю max-file-lines 1300, а гачкам бафів потрібне місце);
# тіла перенесені дослівно, `n`/`player`/`map` читаються крізь `s`. Захищено S0-пінами (gather_haul, WORLD_HASH_FINAL).
extends RefCounted

const HAUL_RESUME_RADIUS := 7   # Euclidean tiles: «keep chopping this grove», not «wander the map»

static func start_haul(s, cell: int, kind: String) -> void:
	var st: Variant = s._nearest_storage()
	if st == null:
		s._flash("Несеш максимум — збудуй склад (4).")
		s.player.action = null
		return
	var path: Array = s.compute_path(int(s.player.px), int(s.player.py), int(st.x), int(st.y))
	s.player.action = {"type": "haul", "path": path, "cell": int(st.y) * int(s.n) + int(st.x),
		"resume": {"cell": cell, "kind": kind}}

static func do_haul(s, step: float) -> void:
	var p: Dictionary = s.player
	var a: Dictionary = p.action
	var n: int = int(s.n)
	if s.carry_total() == 0:
		# unloaded (the auto-deposit fired within reach of the storage): back to work
		var res: Dictionary = a.get("resume", {})
		var cell := int(res.get("cell", -1))
		p.action = null
		if cell >= 0 and s.map.nodes.has(cell):
			s.order_gather(cell % n, cell / n)
		else:
			continue_gather(s, cell, String(res.get("kind", "")))
		return
	if s._follow_path(p, a.path, step):
		if not s._near_storage(1.8):
			s._flash("Склад недосяжний — віднеси вантаж сам.")
			p.action = null
		elif s.storage_cap() - s.stock_total() <= 0:
			p.action = null   # full storage: the deposit flash already names the fix
		# else: standing at the storage — the next deposit tick (dep_cd) unloads the hands

# A node ran dry (or a haul came back to an empty cell): keep working the same kind nearby, or carry
# what is in hand home when the grove is done. Silent no-op when there is nothing left to do.
static func continue_gather(s, cell: int, kind: String) -> void:
	var n: int = int(s.n)
	var next := nearest_node_of_kind(s, cell, kind, HAUL_RESUME_RADIUS)
	if next >= 0:
		if s.carry_total() >= int(s.player.carry_cap):
			start_haul(s, next, kind)
		else:
			s.order_gather(next % n, next / n)
	elif s.carry_total() > 0 and kind != "":
		start_haul(s, -1, "")   # the grove is done: deliver the last load and stand by the storage

static func nearest_node_of_kind(s, cell: int, kind: String, radius: int) -> int:
	if cell < 0 or kind == "":
		return -1
	var n: int = int(s.n)
	var cx := cell % n
	var cy := cell / n
	var best := -1
	var bd := radius * radius + 1
	for k in s.map.nodes:
		if String(s.map.nodes[k].kind) != kind:
			continue
		var dx: int = int(k) % n - cx
		var dy: int = int(k) / n - cy
		var d := dx * dx + dy * dy
		if d < bd or (d == bd and int(k) < best):
			bd = d
			best = int(k)
	return best
