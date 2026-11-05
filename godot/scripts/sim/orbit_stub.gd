# RealWorld — sim/orbit_stub.gd : STUBS of the spec 0011 (Орбіта) seams that spec 0010 consumes (0010-W1b, D2).
#
# Spec 0011 (Orbit: roster of clones, safe stock) is frozen for step 1 (OD-60): only the SEAMS exist, and they live
# in this file — NOT in sim/capsule.gd — so that 0011, when it lands, replaces THIS file's bodies and never edits the
# capsule domain. Static funcs over the sim instance `s`, no state, no preload of sim.gd (no cycle).
#
# Seam owned here today:
#   respawn_source(s) — WHOSE BODY comes back after death. 0011 will answer with the roster (1 active clone + the free
#   base clone on a 5-minute cooldown, OD-51/54/57); until then it is the existing starter pawn, `_default_player`.
#   WHERE the body stands is NOT decided here: the position is set by MainCapsule.landing (one landing seam, REQ-0010-98).
# The safe-zone container is `Session.orbit.safe_stock` once 0011 exists (never `Session.safe_stock`); no deposit or
# reinforcement stub lives here yet — REQ-0010-28/29 are blocked on 0011 and stay untouched.
extends RefCounted


# The body a respawn brings: a fresh starter pawn standing on the map spawn (landing moves it next to the capsule).
static func respawn_source(s) -> Dictionary:
	return s._default_player(s.map.spawn)
