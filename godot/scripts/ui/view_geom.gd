# RealWorld — ui/view_geom.gd : PURE viewport culling math (spec 0005 §2.9).
#
# The SINGLE definition of "which tiles are visible", shared by world_view.gd's _draw() and the
# new OverlayHost, so the base tilemap and every overlay stay in lockstep (no cull drift).
# Node-free: takes the numbers, returns the rect. Faithfully extracted from world_view._draw().
extends RefCounted

# cam_pos = camera screen-center world position (Camera2D.get_screen_center_position()).
# zoom    = Camera2D.zoom. vp_size = get_viewport_rect().size. Returns {x0,y0,x1,y1} clamped to [0,n).
static func cull_rect(cam_pos: Vector2, zoom: Vector2, vp_size: Vector2, n: int, tile: int) -> Dictionary:
	if n <= 0:
		return {"x0": 0, "y0": 0, "x1": 0, "y1": 0}
	var zx: float = zoom.x if zoom.x != 0.0 else 1.0
	var zy: float = zoom.y if zoom.y != 0.0 else 1.0
	var vr := Vector2(vp_size.x / zx, vp_size.y / zy)
	var tl := cam_pos - vr / 2.0
	return {
		"x0": clampi(int(tl.x / tile) - 1, 0, n - 1),
		"y0": clampi(int(tl.y / tile) - 1, 0, n - 1),
		"x1": clampi(int((tl.x + vr.x) / tile) + 1, 0, n - 1),
		"y1": clampi(int((tl.y + vr.y) / tile) + 1, 0, n - 1),
	}

# Whole-map rect (fallback when there is no camera, matching world_view's default).
static func full_rect(n: int) -> Dictionary:
	return {"x0": 0, "y0": 0, "x1": maxi(0, n - 1), "y1": maxi(0, n - 1)}

static func contains(cull: Dictionary, x: int, y: int) -> bool:
	return x >= int(cull.x0) and x <= int(cull.x1) and y >= int(cull.y0) and y <= int(cull.y1)
