# RealWorld — ui/feedback_bus.gd : the ONE adapter that quarantines the sim's push channels (spec 0005 §2.7, R10).
#
# Instance owned by HudRoot, passed by reference (NOT an autoload). Panels/widgets NEVER read
# sim.messages/banner/flash_msg directly (R10); they subscribe to these typed signals instead.
#
# The feed drains an APPEND-ONLY TAIL by a monotonic sequence counter, not an index cursor: sim._log is
# a sliding window (append then trim at 40), so an index cursor breaks at the trim boundary (pins at 40,
# and every remove_at(0) shifts survivors). sim.messages_seq counts lifetime appends and is NEVER reset
# by the 40-cap trim, so (messages_seq - _last_seq) is exactly the count of unseen tail entries.
extends RefCounted

class FeedbackBus extends RefCounted:
	signal banner(evt: Dictionary)   # {status:StringName, params:{text}}  — top urgent strip
	signal flash(evt: Dictionary)    # {id, cls, params:{text}}            — transient center toast
	signal feed(evt: Dictionary)     # {cls, text}                          — scrolling event log card

	var _last_banner := ""
	var _last_flash := ""
	var _last_seq: int = 0           # monotonic; survives the sim's 40-message sliding-window trim

	func ingest(sim, _dt: float) -> void:
		if sim == null:
			return
		# banner: emit only on change
		var b: String = String(sim.banner)
		if b != _last_banner:
			banner.emit({"status": _banner_status(b), "params": {"text": b}})
			_last_banner = b
		# flash: gated on the sim's own decay timer during migration (avoids a two-clock double-decay)
		if float(sim.flash_t) > 0.0 and String(sim.flash_msg) != _last_flash:
			flash.emit({"id": &"blocked", "cls": "warn", "params": {"text": String(sim.flash_msg)}})
			_last_flash = String(sim.flash_msg)
		elif float(sim.flash_t) <= 0.0:
			_last_flash = ""   # allow the same message to re-fire after it expired
		# feed: emit every message whose append-seq is newer than _last_seq
		var seq: int = int(sim.messages_seq)
		if seq > _last_seq:
			var msgs: Array = sim.messages
			var pending: int = mini(seq - _last_seq, msgs.size())
			var start: int = msgs.size() - pending
			for i in range(start, msgs.size()):
				var m: Dictionary = msgs[i]
				feed.emit({"cls": String(m.get("cls", "")), "text": String(m.get("text", ""))})
			_last_seq = seq

	func reset_cursors() -> void:   # HudRoot calls this on session.travel_to (§2.5)
		_last_seq = 0
		_last_banner = ""
		_last_flash = ""

	func _banner_status(text: String) -> StringName:
		if text == "":
			return &"none"
		if "РЕЙД" in text and "НАБЛИЖА" not in text:
			return &"raid_active"
		if "НАБЛИЖА" in text or "підході" in text:
			return &"raid_incoming"
		return &"info"
