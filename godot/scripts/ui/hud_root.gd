# RealWorld — ui/hud_root.gd : the thin HUD controller (spec 0005 §2.3). The `sim.update()` analogue.
#
# Owns the registries + feedback bus + ViewModel and runs the 6-line frame: build snapshot -> ingest
# feedback -> bind visible panels. It contains NO mechanic logic and names NO mechanic (R4): it mounts
# whatever the registries hold into the §2 dock zones. Adding a mechanic's UI never edits this file.
extends Control

const HudModel = preload("res://scripts/ui/hud_model.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")

var registry                # PanelRegistry
var overlays                # OverlayRegistry (optional in the minimal assembly)
var bus                     # FeedbackBus
var balance                 # Balance director (constructed once by the entry scene)
var session                 # SessionScript (has .sim)

var _docks: Dictionary = {}   # dock int -> container Control
var last_snap: Dictionary = {}   # the most recent snapshot (OverlayHost reads env/clock from it)

func _ready() -> void:
	# A Control under a CanvasLayer does not inherit the viewport size, so PRESET_FULL_RECT leaves
	# width 0 and any right-edge anchor collapses. Pin to TOP_LEFT and size explicitly to the viewport
	# (re-fit on resize) so right/bottom-anchored docks resolve against the true screen width.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	_build_zones()

func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size

func _build_zones() -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(232, 0)
	WidgetBase.Widget.pin_top_left(left)
	add_child(left)
	# Right dock: an explicit-width right strip. A right-anchored VBoxContainer growing BEGIN from a
	# zero nominal size does not reliably expand to its combined min width, so we anchor a fixed 250px
	# strip to the right edge (design-system §2 RIGHT DOCK width) rather than rely on grow-to-content.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.anchor_left = 1.0; right.anchor_right = 1.0
	right.anchor_top = 0.0; right.anchor_bottom = 0.0
	right.offset_left = -262; right.offset_right = -12; right.offset_top = 10
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_END
	add_child(right)
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_docks = {0: left, 1: right, 2: top, 3: bar}   # LEFT / RIGHT / TOP / BAR

func setup(p_session, p_balance, p_bus, p_registry, p_overlays = null) -> void:
	session = p_session
	balance = p_balance
	bus = p_bus
	registry = p_registry
	overlays = p_overlays

# Mount every registered dock panel into its zone. Modals (dock 4) are mounted by the entry scene's
# ModalLayer, not here. No panel is referenced by type — the registry is the only source (R4).
func mount() -> void:
	if registry == null:
		return
	for p in registry.panels:
		var d: int = int(p.dock)
		if _docks.has(d):
			_docks[d].add_child(p)
			p.visible = true

func _process(dt: float) -> void:
	refresh(dt)

# The whole per-frame contract, one direction (R1): snapshot -> ingest -> bind_visible.
func refresh(dt: float) -> void:
	if session == null or session.sim == null or registry == null:
		return
	var world: Dictionary = HudModel.world_of(session.sim)
	var ctx: Dictionary = {"day": int(session.sim.time.day), "hostile_pressure": 1.0}
	if bus != null:
		bus.ingest(session.sim, dt)
	var snap: Dictionary = HudModel.snapshot(session, world, ctx, balance)
	last_snap = snap
	registry.bind_visible(snap)
