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

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_zones()

func _build_zones() -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(232, 0)
	WidgetBase.Widget.pin_top_left(left)
	add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(250, 0)
	WidgetBase.Widget.pin_top_right(right)
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
	registry.bind_visible(snap)
