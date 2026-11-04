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
	var bare := false              # chromeless: medallion clusters float on the world without a panel box
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
		theme_type_variation = &"RwBare" if bare else &"RwPanel"   # == UITheme.V_BARE / V_PANEL
		build_once()

	var collapsed_default := false     # start folded (long, secondary panels: the player unfolds on demand)
	var _fold_body: Control = null          # everything under the header, grouped once so a fold is ONE visibility flip

	func build_once() -> void:              # idempotent: a manual test call + a real tree-entry
		if rebuild_count > 0:               # can never double-fire _build (§5.3 headless note)
			return
		_build()
		_install_fold()

	# Progressive disclosure: when the panel is «VBox → [H2Header, rows…]», move the rows into one body
	# container and let a click on the header fold it. Rows keep their own visibility flags and node refs
	# (bind() code is untouched); panels with any other shape are left alone.
	func _install_fold() -> void:
		for c in get_children():
			if not (c is VBoxContainer) or c.get_child_count() < 2:
				continue
			var head: Node = c.get_child(0)
			if not (head is Control) or not head.has_signal("toggled") or not head.has_method("set_collapsed"):
				continue
			var body := VBoxContainer.new()
			body.add_theme_constant_override("separation", int(c.get_theme_constant("separation")))
			var movers: Array = c.get_children().slice(1)
			for m in movers:
				c.remove_child(m)
				body.add_child(m)
			c.add_child(body)
			_fold_body = body
			head.collapsible = true
			head.toggled.connect(func(folded: bool) -> void: body.visible = not folded)
			if collapsed_default:
				head.set_collapsed(true)
			return

	func _build() -> void:                  # override: create child Widgets ONCE. Must do rebuild_count += 1.
		rebuild_count += 1
	func bind(_vm) -> void:                  # override: set values on EXISTING children only.
		rebind_count += 1
	func wants_reveal(_vm) -> bool:          # override with a pure check on the snapshot
		return false
	func emit_intent(verb: StringName, args: Dictionary) -> void:
		intent.emit(verb, args)
