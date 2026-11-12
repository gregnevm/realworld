# RealWorld — sim/clone_tuning.gd : spec 0011 REQ-0011-43/60/21/18/71 — every number of the Orbit lives in this table, never in code.
# One interface `value(key)`; the default provider is the local table below, swappable without touching the sim (`provider`
# is a Callable key -> Variant or null). No provider ever grants resources or combat advantage (REQ-0011-73).
# Rates the spec left as TBD (OD-C5/C7/C19/C21/C24/C26) are fixed here by the agent under the owner's delegation (OD-151).
extends RefCounted

const MICRO := 1000000                 # 1 bio unit = 1 000 000 micro-units (integers only, REQ-0011-20)
const DEFAULT := {
	"base_cooldown_ms": 300000,        # OD-54: 5 min
	"quantum_ms": 60000,               # Q (OD-C5): settle works in whole minutes
	"bio_per_hour": 3,                 # OD-C5: bio units per real hour per sleeping clone
	"degrade_after_ms": 259200000,     # OD-95: 3 days without bio
	"dead_after_ms": 604800000,        # OD-95: 7 days without bio
	"catchup_cap_ms": 86400000,        # OD-49: 24 h
	"roster_slots": 4,                 # OD-C23: clone slots
	"create_ms": 43200000,             # OD-94: ~12 h
	"create_bio": 10,                  # OD-63/101: ~1-2 h of gathering
	"create_genome": 1,
	"genome_start_permille": 100,      # OD-82/100: +10 % to the start stat of the genome axis
	"genome_growth_permille": 50,      # +5 % average growth on the axis
	"tech_bonus_permille": 10,         # per tech level, all axes
}

static var provider: Variant = null


static func value(key: String) -> int:
	if provider != null:
		var v: Variant = (provider as Callable).call(key)
		if v != null:
			return int(v)
	return int(DEFAULT[key])


# REQ-0011-24/OD-C21: which items are `bio` (renewable) and which of them can be eaten by a sleeper.
const BIO_TAGS := ["food", "meat", "hide", "berries", "mushroom", "fibre", "wood", "water"]
const RATION := ["food", "meat", "berries", "mushroom"]


static func is_bio(id: String) -> bool:
	return BIO_TAGS.has(id)


static func is_ration(id: String) -> bool:
	return RATION.has(id)


# REQ-0011-69: three genome types = three player verbs. Data, not code branches.
const GENOMES := {
	"gatherer": {"name": "Добувач", "axis": "gather"},
	"builder": {"name": "Будівельник", "axis": "build"},
	"rider": {"name": "Райдер", "axis": "ride"},
}
const AXES := ["gather", "build", "ride"]
