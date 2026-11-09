# RealWorld — net/shard_router.gd : which server owns which grid cell (spec 0013 §3.4).
#
# Rendezvous (highest-random-weight) hashing: every (cell, shard) pair gets a deterministic score and
# the cell goes to the best-scoring shard. Properties that matter for a geo-sharded world:
#   * stateless  — a client and every server compute the same owner from (cell_key, shard list) alone;
#   * minimal churn — removing a shard moves ONLY that shard's cells, adding one steals ~1/N;
#   * order-free — the shard list may arrive in any order; ties break by shard id, ascending.
# The hash is the same FNV-1a 32 the terrain seed uses (WorldGen.hash_seed folds a coordinate string;
# here we fold "<shard>|<cell>"), so the repo has one hash family and no second RNG.
extends RefCounted


static func _fnv(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xffffffff
		h = (h * 16777619) & 0xffffffff
	return h


static func score(shard_id: String, cell_key: String) -> int:
	return _fnv(shard_id + "|" + cell_key)


# Owner of one cell, or "" when no shard is configured.
static func route(cell_key: String, shards: Array) -> String:
	var best := ""
	var best_score := -1
	for s in shards:
		var id := str(s)
		var sc := score(id, cell_key)
		if sc > best_score or (sc == best_score and id < best):
			best = id
			best_score = sc
	return best


# The top `n` shards for a cell (owner first) — replica / hand-over candidates. Deterministic order.
static func route_n(cell_key: String, shards: Array, n: int) -> Array:
	var ranked: Array = []
	for s in shards:
		ranked.append({"id": str(s), "score": score(str(s), cell_key)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.score) > int(b.score) or (int(a.score) == int(b.score) and str(a.id) < str(b.id)))
	var out: Array = []
	for i in mini(maxi(n, 0), ranked.size()):
		out.append(ranked[i].id)
	return out
