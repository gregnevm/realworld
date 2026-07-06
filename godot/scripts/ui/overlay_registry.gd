# RealWorld — ui/overlay_registry.gd : the spatial registry (spec 0005 §2.8).
#
# One radio overlay active at a time + any number of always-on markers. The register() contract asserts
# a spatial mechanic supplied its hotkey + legend (R6) — a cell-keyed payload has nowhere else to plug in.
extends RefCounted

class OverlayRegistry extends RefCounted:
	var overlays: Array = []
	var active: StringName = &""        # the one radio overlay currently on
	var _markers: Dictionary = {}       # overlay_id -> bool (always-on toggles)

	func register(o) -> void:
		assert(o.hotkey != 0 and not o.legend_rows.is_empty())   # R6 contract: no hotkey/legend = reject
		overlays.append(o)

	func _get(id: StringName):
		for o in overlays:
			if o.overlay_id == id:
				return o
		return null

	func toggle(id: StringName) -> void:
		var o = _get(id)
		if o == null:
			return
		if o.radio:
			active = (&"" if active == id else id)               # radio exclusivity
		else:
			_markers[id] = not _markers.get(id, false)

	func is_on(id: StringName) -> bool:
		var o = _get(id)
		if o == null:
			return false
		return (o.radio and active == id) or (not o.radio and bool(_markers.get(id, false)))

	func active_and_markers() -> Array:                          # 1 radio + all enabled always-on
		var out: Array = []
		for o in overlays:
			if (o.radio and o.overlay_id == active) or (not o.radio and bool(_markers.get(o.overlay_id, false))):
				out.append(o)
		return out

	func legend_for_active() -> Array:
		var o = _get(active)
		return o.legend_rows if o != null else []

	func count() -> int:
		return overlays.size()
