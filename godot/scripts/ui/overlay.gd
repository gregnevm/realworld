# RealWorld — ui/overlay.gd : the Overlay BASE (spec 0005 §2.8). The spatial half of the view.
#
# main.gd has NO overlay layer at all — this is net-new, purely additive. A world overlay is a
# toggleable tile-layer keyed to a LOCKED hotkey (design-system §3: R/T/L/P/G/Z/F/K/M) that draws into
# the world-space OverlayHost (never into WorldView's canvas — that would be an R1 up-reference). A
# mechanic with per-tile state ships an Overlay + register(...) and edits no HUD (R6).
extends RefCounted

class Overlay extends RefCounted:
	var overlay_id: StringName = &"overlay"
	var hotkey: int = 0                 # KEY_R/T/L/P/G/Z/F/K/M (LOCKED, design-system §3)
	var radio := true                   # false = an always-on marker layer (fire F, cover K)
	var legend_rows: Array = []         # [{icon:String, label:String}] — Ukrainian legend rows

	# Draw into the world-space host (a CanvasItem) over the visible tile rect. Reads ONLY the snapshot
	# (never a climate provider) so overlays are deterministic and one-way (R12).
	func draw_overlay(_host: CanvasItem, _snap: Dictionary, _cull: Dictionary) -> void:
		pass
