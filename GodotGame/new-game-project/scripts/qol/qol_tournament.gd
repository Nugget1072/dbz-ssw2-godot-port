class_name QoLTournament
extends RefCounted
# ---- TOURNAMENT (part 43)
## The TOURNAMENT bracket (docs/ALLSTAR_DESIGN.md 9): 8 teams of 3 fighters, player 1's team (picked on the All-Star
## select) and 7 CPU teams of random distinct fighters, in a seeded draw; 3 rounds (quarter-final, semi-final, final).
## Player 1 fights each of its matches as a normal Free Battle (QoLGame `# ---- TOURNAMENT`); the other matches of a
## round are decided when player 1's match ends, by a seeded roll weighted by the teams' total max HP (the game has no
## CPU-vs-CPU battle). Owned by QoLAllStar (`tour`, made at the first tournament start). Written on the game thread
## (QoLGame), except `hold` / `quit_req`, which the bracket page (QoLTournamentPage, main thread, game thread parked)
## clears / sets. Debug: `tnseed=N` (draw / rolls repeatable), `tndbg` (TN log lines).

const SIZE := 8
const ROUNDS := 3
const ROUND_NAMES := ["QUARTER-FINAL", "SEMI-FINAL", "FINAL"]
const EMPTY_ID := 38
## max HP per fighter at boss level 0 (DATA_NOTES part 34 "Max HP per character"; 4 Krillin: as the lightest)
const HP := [13000, 16300, 18500, 14500, 10000, 13000, 13000, 16300, 14500, 21000, 11500, 13000, 10000, 10000, 11500,
	18500, 18500, 21000, 14500, 16300, 18500, 21000, 11500, 16300, 10000, 14500]
const STAGES := 15                       ## stage ids 0..14 (the select's random icon draws from the same range)
const LEVEL_UP := [0, 2, 4]              ## CPU level added per round (the Option difficulty's level first)
const LEVEL_MAX := 10                    ## the highest CPU level the game itself uses (Maximum Expert course)

var teams: Array = []                    ## per bracket slot: [id, id, id] (player 1: its fighters, support not here)
var p1_slot := -1
var p1_support := EMPTY_ID               ## player 1's support (party block +0x20)
var p1_count := 3
var winners: Array = []                  ## per round: Array of the winning slot of each match (-1 = not played yet)
var round := 0                           ## the round player 1 plays next (or played last when it is over)
var state := ""                          ## "" no bracket, "on" running, "out" player 1 lost, "champion" player 1 won
var stages: Array = []                   ## stage id per round
var hold := false                        ## the battle scene waits for the bracket page's FIGHT (QoLGame f_02013064)
var page_req := false                    ## game thread -> bracket page: open (main thread clears it)
var quit_req := false                    ## bracket page -> game thread: QUIT (back to the team select)
var battle_time := 0                     ## game frames fought in this tournament's battles (the champion's time)
var dbg := false
var _rng := RandomNumberGenerator.new()
var _draws := 0


func _init() -> void:
	dbg = Game.args.has("tndbg")
	clear()


func clear() -> void:
	teams = []
	p1_slot = -1
	p1_support = EMPTY_ID
	winners = []
	round = 0
	state = ""
	stages = []
	hold = false
	page_req = false
	quit_req = false
	battle_time = 0


func drawn() -> bool:
	return state != ""


## a new bracket around player 1's team (fighter ids, support): 21 different CPU fighters, none of player 1's
func draw(p1: Array, support: int) -> void:
	var h := hold
	clear()
	hold = h                                 # (the battle scene keeps waiting for the page)
	_draws += 1
	_rng.seed = (int(Game.flag("tnseed")) + _draws) if Game.args.has("tnseed") else randi()
	var pool: Array = QoLAllStar.ROSTER.filter(func(i): return not i in p1)
	_shuffle(pool)
	var cpu: Array = []
	for t in SIZE - 1:
		cpu.append(pool.slice(t * 3, t * 3 + 3))
	p1_slot = _rng.randi_range(0, SIZE - 1)
	p1_support = support
	p1_count = clampi(p1.size(), 1, 3)
	var k := 0
	for s in SIZE:
		if s == p1_slot:
			teams.append(p1.duplicate())
		else:
			teams.append(cpu[k])
			k += 1
	for r in ROUNDS:
		var w: Array = []
		w.resize(SIZE >> (r + 1))
		w.fill(-1)
		winners.append(w)
		stages.append(_rng.randi_range(0, STAGES - 1))
	state = "on"
	_log("draw: player 1 at slot %d %s support %d, teams %s, stages %s" % [p1_slot, str(p1), support, str(teams), str(stages)])


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## the two slots of match m in round r (-1 = not decided yet)
func match_slots(r: int, m: int) -> Array:
	if r == 0:
		return [2 * m, 2 * m + 1]
	return [winners[r - 1][2 * m], winners[r - 1][2 * m + 1]]


## the match player 1 plays in round r
func p1_match(r: int) -> int:
	return p1_slot >> (r + 1)


## player 1's opponent slot this round (-1 = none)
func opponent() -> int:
	if state != "on":
		return -1
	var s := match_slots(round, p1_match(round))
	return s[1] if s[0] == p1_slot else s[0]


## the slot that won a round-r match it was in (-1 = lost / not played)
func reached(slot: int) -> int:
	var r := 0
	while r < ROUNDS and winners[r][slot >> (r + 1)] == slot:
		r += 1
	return r


func strength(slot: int) -> int:
	var s := 0
	for id in teams[slot]:
		s += HP[id] if id >= 0 and id < HP.size() else 13000
	return s


## player 1's match ended (won / lost): the round's other matches are rolled; player 1 lost -> the rest of the
## tournament is rolled too (the page shows who goes on and who wins)
func p1_result(won: bool, frames: int) -> void:
	if state != "on":
		return
	battle_time += frames
	var m := p1_match(round)
	var opp := opponent()
	winners[round][m] = p1_slot if won else opp
	_log("round %d (%s): player 1 %s against slot %d %s" % [round, ROUND_NAMES[round], "WON" if won else "lost", opp, str(teams[opp])])
	_roll(round)
	if not won:
		state = "out"
		for r in range(round + 1, ROUNDS):
			_roll(r)
	elif round == ROUNDS - 1:
		state = "champion"
	else:
		round += 1


func _roll(r: int) -> void:
	for m in winners[r].size():
		if winners[r][m] >= 0:
			continue
		var s := match_slots(r, m)
		var a: int = strength(s[0])
		var b: int = strength(s[1])
		winners[r][m] = s[0] if _rng.randi_range(1, a + b) <= a else s[1]
		_log("round %d match %d: slot %d %s (%d) vs slot %d %s (%d) -> slot %d" % [r, m, s[0], str(teams[s[0]]), a, s[1],
			str(teams[s[1]]), b, winners[r][m]])


## the CPU level of this round's battle from the level the game set (the Option difficulty)
func cpu_level(base: int) -> int:
	return clampi(base + LEVEL_UP[clampi(round, 0, ROUNDS - 1)], 1, maxi(base, LEVEL_MAX))


func champion() -> int:
	return winners[ROUNDS - 1][0] if winners.size() == ROUNDS else -1


func _log(s: String) -> void:
	if dbg:
		print("TN %s" % s)
