# RealWorld — ui/latlon.gd : PURE GPS coordinate parse + validation (spec 0005).
#
# Lifted verbatim (behaviour-preserving) from main.gd._parse_latlon so the spawn/capsule panels can
# reuse it without pulling in the whole controller. Node-free, headless-testable.
# Accepts two fields OR a single "lat, lon" pasted into the first field (the shareable address form).
# Validates legal ranges so we never seed a phantom world.
extends RefCounted

static func parse(a: String, b: String) -> Dictionary:
	var la := a.strip_edges()
	var lo := b.strip_edges()
	if "," in la and (lo == "" or not ("," in lo)):
		var parts := la.split(",")
		la = parts[0].strip_edges()
		if lo == "" and parts.size() > 1:
			lo = parts[1].strip_edges()
	if la == "" or lo == "":
		return {"ok": false, "msg": "Введи координати (напр. 50.4501, 30.5234)."}
	var lat := la.to_float()
	var lon := lo.to_float()
	if absf(lat) > 90.0 or absf(lon) > 180.0:
		return {"ok": false, "msg": "Поза межами: широта ±90°, довгота ±180°."}
	return {"ok": true, "lat": lat, "lon": lon}
