# RealWorld — ui/panel.gd : the Panel BASE (spec 0005 §2.6). The `SimSystem` analogue.
#
# A dock/modal unit built ONCE in _build() (via the idempotent build_once, called from _ready), and
# thereafter only bind(vm)-mutated (R2 — never the monolith's _clear+rebuild-on-toggle). Base is an
# inner class; concrete panels are inner classes in panels.gd that preload this and `extends PanelBase.Panel`.
extends RefCounted

const UITheme = preload("res://scripts/ui/theme.gd")

# Dock zones (design-system §2). Concrete panels set `dock` to one of these.
const DOCK_LEFT := 0
const DOCK_RIGHT := 1
const DOCK_TOP := 2
const DOCK_BAR := 3
const DOCK_MODAL := 4

# NOTE: named `Base` (not `Panel`) — an inner class named `Panel` would shadow Godot's native Panel.
class Base extends PanelContainer:
	signal intent(verb: StringName, args: Dictionary)   # bubbles to InputController (R9)

	var panel_id: StringName = &"panel"
	var dock: int = 0
	var priority: int = 0
	var hotkey: int = 0            # KEY_* toggle, 0 = none (metadata, not a switch — R12)
	var default_open := false
	# design-system §2 «advanced panels open on first relevance»: a hidden panel with reveal_once set
	# is shown ONCE, the first frame wants_reveal(snapshot) says it has something to show; after that
	# the player owns its visibility (a hotkey/close never fights a re-reveal).
	var reveal_once := false
	var revealed := false
	# Touch/compact frame (phones): the label its ☰ menu toggle shows, and whether the panel starts
	# open there (-1 = same as default_open, 0 = closed, 1 = open) — a phone has room for less.
	var menu_label := ""
	var compact_open := -1
	var rebuild_count := 0         # R2 enforcement: incremented ONLY inside _build()
	var rebind_count := 0

	func _ready() -> void:
		theme_type_variation = &"RwPanel"   # == UITheme.V_PANEL
		build_once()

	func build_once() -> void:              # idempotent: a manual test call + a real tree-entry
		if rebuild_count > 0:               # can never double-fire _build (§5.3 headless note)
			return
		_build()

	func _build() -> void:                  # override: create child Widgets ONCE. Must do rebuild_count += 1.
		rebuild_count += 1
	func bind(_vm) -> void:                  # override: set values on EXISTING children only.
		rebind_count += 1
	func wants_reveal(_vm) -> bool:          # override with a pure check on the snapshot
		return false
	func emit_intent(verb: StringName, args: Dictionary) -> void:
		intent.emit(verb, args)
