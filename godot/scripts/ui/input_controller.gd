# RealWorld — ui/input_controller.gd : the verb router (spec 0005 §2.10, R9).
#
# The ONLY node that translates a view intent into a sim command. Panels/widgets emit intents; this
# dispatches. Sim command names appear here (and input_verbs.gd), never in panels/widgets (R9 grep).
extends RefCounted

class InputController extends RefCounted:
	var _verbs: Dictionary = {}                      # StringName -> Callable(session, args)

	func bind(verb: StringName, fn: Callable) -> void:
		_verbs[verb] = fn

	func has(verb: StringName) -> bool:
		return _verbs.has(verb)

	func dispatch(verb: StringName, args: Dictionary, session) -> void:
		if _verbs.has(verb):
			(_verbs[verb] as Callable).call(session, args)
