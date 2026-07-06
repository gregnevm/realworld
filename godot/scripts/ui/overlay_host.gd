# RealWorld — ui/overlay_host.gd : the world-space overlay renderer (spec 0005 §2.3, §2.8).
#
# A Node2D child of the world camera space with its OWN _draw(). It pulls the active overlays from the
# OverlayRegistry and draws them over the visible tile rect (shared ViewGeom.cull_rect, §2.9), so
# overlays pan/zoom with the world for free and never drift from the base tilemap. It does NOT draw into
# WorldView's canvas (that would make the sim-facing WorldView reach up into ui/ — an R1 violation).
extends Node2D

const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const TILE := 28

var oreg                          # OverlayRegistry
var snap: Dictionary = {}         # latest HudModel snapshot (env/clock the overlays read; R12)
var map_n: int = 56               # live region size — set from sim.n so overlay cull matches the tilemap
                                  # (world_view.gd culls from sim.n; a hardcoded 56 would drift when n != 56)

func _draw() -> void:
	if oreg == null:
		return
	var cam := get_viewport().get_camera_2d()
	var cull: Dictionary
	if cam != null:
		cull = ViewGeom.cull_rect(cam.get_screen_center_position(), cam.zoom, get_viewport_rect().size, map_n, TILE)
	else:
		cull = ViewGeom.full_rect(map_n)
	for o in oreg.active_and_markers():
		o.draw_overlay(self, snap, cull)
