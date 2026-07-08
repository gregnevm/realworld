# RealWorld — ui/mechanics.gd : per-mechanic UI registrars (spec 0005 §2.12).
#
# This is where a mechanic's UI plugs in — it registers panels/overlays into the registries and edits
# NO controller (R4). Adding the 30th mechanic's UI means adding a line here (or a new registrar),
# never touching hud_root.gd. The literal transplant of "adding a mechanic never edits the tick loop".
extends RefCounted

const Panels = preload("res://scripts/ui/panels.gd")
const CatalogPanels = preload("res://scripts/ui/catalog_panels.gd")
const Overlays = preload("res://scripts/ui/overlays.gd")

# Register the currently-implemented UI surfaces into the given registries.
static func register_all(panel_registry, overlay_registry) -> void:
	# LEFT dock — hero body
	panel_registry.register(Panels.VitalsPanel.new())
	# RIGHT dock — world / economy / director / content tree
	panel_registry.register(Panels.StockPanel.new())
	panel_registry.register(Panels.BalancePanel.new())
	panel_registry.register(CatalogPanels.TechPanel.new())
	# world overlays (spatial state) keyed to their LOCKED hotkeys (design-system §3)
	overlay_registry.register(Overlays.LightOverlay.new())
	overlay_registry.register(Overlays.TemperatureOverlay.new())
