# RealWorld — ui/hud_root.gd : the thin HUD controller (spec 0005 §2.3). The `sim.update()` analogue.
#
# Owns the registries + feedback bus + ViewModel and runs the 6-line frame: build snapshot -> ingest
# feedback -> bind visible panels. It contains NO mechanic logic and names NO mechanic (R4): it mounts
# whatever the registries hold into the §2 dock zones. Adding a mechanic's UI never edits this file.
extends Control

const HudModel = preload("res://scripts/ui/hud_model.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")

var registry: Variant       # PanelRegistry
var overlays: Variant       # OverlayRegistry (optional in the minimal assembly)
var bus: Variant            # FeedbackBus
var balance: Variant        # Balance director (constructed once by the entry scene)
var session: Variant        # SessionScript (has .sim)

var _docks: Dictionary = {}   # dock int -> container Control
var last_snap: Dictionary = {}   # the most recent snapshot (OverlayHost reads env/clock from it)
# VIEW state the entry scene owns and hands in each frame (hovered cell, armed ghost, time speed,
# whether the cursor is over the map). Merged into the snapshot ctx — the model stays the one
# place that turns state into presentation data (R8), the controller only forwards it.
var view_ctx: Dictionary = {}
# The §2.7 feedback channels + the §5 inspect tooltip: the frame's own furniture (not mechanics),
# subscribed ONCE to the bus in mount() and freed with the HUD (their _exit_tree disconnects).
var banner_w: Widgets.BannerWidget
var flash_w: Widgets.FlashWidget
var feed_w: Widgets.FeedWidget
var tip_w: Widgets.HoverTip

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
	WidgetBase.Widget.fit_viewport(self)

# The side docks scroll: Vitals + Goals + Research (+ Gear/browsers on hotkeys) outgrow a 720p screen
# and the bottom panel used to slide under the build bar. Each dock is a ScrollContainer sized to its
# CONTENT (capped above the bar) every frame, so an empty strip never blocks clicks on the map.
const DOCK_BOTTOM_GAP := 84.0          # keep docks clear of the BAR dock (build palette)
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
# Compact frame (phones, set by the entry scene before mount): the side docks start BELOW the top
# strip (a 950x430 logical screen has no room to share it), panels honour their compact_open default
# and the feed shrinks. Desktop keeps the authored layout.
var compact := false
var dock_top := 10.0
var dock_bottom_gap := DOCK_BOTTOM_GAP

func set_compact(on: bool) -> void:
	compact = on
	dock_top = 52.0 if on else 10.0
	dock_bottom_gap = 76.0 if on else DOCK_BOTTOM_GAP
	if feed_w != null:
		feed_w.set_compact(on)

func _build_zones() -> void:
	_left_scroll = _dock_scroll()
	add_child(_left_scroll)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(214, 0)
	_left_scroll.add_child(left)
	# Right dock: an explicit-width right strip (design-system §2 RIGHT DOCK width, 250px). A
	# right-anchored container growing BEGIN from a zero nominal size does not reliably expand to its
	# combined min width, so the strip's width is set explicitly in _fit_docks.
	_right_scroll = _dock_scroll()
	add_child(_right_scroll)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(214, 0)
	_right_scroll.add_child(right)
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

func _dock_scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	return sc

# Size each dock to its content, capped above the build bar (a scrollbar appears past the cap).
func _fit_docks() -> void:
	var cap: float = maxf(120.0, size.y - dock_bottom_gap - dock_top + 10.0)
	_fit_one(_left_scroll, false, cap)
	_fit_one(_right_scroll, true, cap)

func _fit_one(sc: ScrollContainer, right_edge: bool, cap: float) -> void:
	var box: Control = sc.get_child(0)
	var need: Vector2 = box.get_combined_minimum_size()
	var w: float = maxf(box.custom_minimum_size.x, need.x) + (10.0 if need.y > cap else 0.0)   # + scrollbar
	sc.position = Vector2((size.x - 12.0 - w) if right_edge else 12.0, dock_top)
	sc.size = Vector2(w, minf(need.y, cap))

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
			p.visible = _starts_open(p)        # hotkey'd panels start hidden; registry.toggle flips them
	_mount_feedback()
	if compact:
		feed_w.set_compact(true)

func _starts_open(p) -> bool:
	if compact and int(p.compact_open) >= 0:
		return int(p.compact_open) == 1
	return bool(p.default_open)

# Banner under the top bar, flash in the upper-middle (where the eye is after a map click), the
# feed bottom-right above the bar, the tooltip at the cursor (design-system §2 + §5).
func _mount_feedback() -> void:
	if banner_w != null:
		return   # idempotent: a second mount would double-subscribe every channel
	banner_w = Widgets.BannerWidget.new()
	WidgetBase.Widget.pin_top_center(banner_w, 50.0)
	add_child(banner_w)
	flash_w = Widgets.FlashWidget.new()
	WidgetBase.Widget.pin_center_at(flash_w, 0.30)
	add_child(flash_w)
	feed_w = Widgets.FeedWidget.new()
	WidgetBase.Widget.pin_bottom_right(feed_w, 14.0, 74.0)
	add_child(feed_w)
	tip_w = Widgets.HoverTip.new()
	add_child(tip_w)
	if bus != null:
		banner_w.subscribe(bus)
		flash_w.subscribe(bus)
		feed_w.subscribe(bus)

func _process(dt: float) -> void:
	refresh(dt)
	if _left_scroll != null:
		_fit_docks()

# The whole per-frame contract, one direction (R1): snapshot -> ingest -> bind_visible.
func refresh(dt: float) -> void:
	if session == null or session.sim == null or registry == null:
		return
	var world: Dictionary = HudModel.world_of(session.sim)
	var ctx: Dictionary = {"day": int(session.sim.time.day), "hostile_pressure": 1.0}
	for k in view_ctx:
		ctx[k] = view_ctx[k]
	if bus != null:
		bus.ingest(session.sim, dt)
	var snap: Dictionary = HudModel.snapshot(session, world, ctx, balance)
	last_snap = snap
	registry.bind_visible(snap)
	if tip_w != null:
		tip_w.bind(snap.get("inspect", {}) if bool(view_ctx.get("in_world", false)) else {})
		var at: Vector2 = view_ctx.get("pointer", get_viewport().get_mouse_position())
		tip_w.follow(at, size, bool(view_ctx.get("touch", false)))
