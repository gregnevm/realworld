# RealWorld — net/realm_client.gd : the client-side reducer of the RealGPS channel (spec 0013 §3.9).
#
# Transport-free and UI-free: feed it server messages with handle(); read the world it describes from
# `view` (the latest presence slice, rebuilt from keyframe + deltas), `region` (the shared world the
# server assigned) and `refusals` (why a request was not applied). The HUD's "nearby" panel binds to
# these value-data fields only (spec 0005 R1/R8) — it never sees a socket or a delta.
extends RefCounted

const Protocol = preload("res://scripts/net/realm_protocol.gd")
const Snapshot = preload("res://scripts/net/snapshot.gd")

const MAX_REFUSALS := 8

var client_id: int = -1
var joined: bool = false
var region: Dictionary = {}
var cell: String = ""
var view: Dictionary = {}
var refusals: Array = []        # newest last, capped; each {for, reason}
var presence_updates: int = 0


func _init(p_client_id: int = -1) -> void:
	client_id = p_client_id


func handle(msg: Variant) -> void:
	if not (msg is Dictionary):
		return
	var m := msg as Dictionary
	match str(m.get("t", "")):
		Protocol.T_WELCOME:
			joined = true
			region = (m.get("region", {}) as Dictionary).duplicate(true)
			cell = str(m.get("cell", ""))
		Protocol.T_PRESENCE:
			var next: Variant = Snapshot.apply(view, m.get("d"))
			if next is Dictionary:
				view = next
				presence_updates += 1
		Protocol.T_REFUSE:
			refusals.append({"for": str(m.get("for", "?")), "reason": str(m.get("reason", "?"))})
			if refusals.size() > MAX_REFUSALS:
				refusals.pop_front()


func handle_all(msgs: Array) -> void:
	for m in msgs:
		handle(m)


# Nearby players as a sorted-by-distance list of value rows — what a panel renders.
func nearby_rows() -> Array:
	var rows: Array = []
	var near: Dictionary = view.get("near", {})
	for k in near:
		var e: Dictionary = near[k]
		rows.append({"id": int(k), "name": str(e.name), "dist_m": int(e.dist_m), "dir": str(e.dir), "brg": int(e.brg), "same_region": bool(e.same_region)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.dist_m) < int(b.dist_m) or (int(a.dist_m) == int(b.dist_m) and int(a.id) < int(b.id)))
	return rows
