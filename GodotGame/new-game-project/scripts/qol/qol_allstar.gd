class_name QoLAllStar
extends RefCounted
# ---- ALLSTAR (part 34)
## NEW GAMEMODES / ALL-STAR session state (docs/ALLSTAR_DESIGN.md section 2). One instance lives in QoLController
## (`allstar`) and is shared with QoLGame (`QoLGame.allstar`, set in QoLController.setup like `mp`). It is only "in
## use" while `active`: with NEW GAMEMODES off or outside a session every QoLGame override just calls super.
##
## Owners: phase 1 (menus, routing: QoLGame `# ---- ALLSTAR MENU (part 34)`, QoLController `# ---- ALLSTAR (part
## 34)`) starts / ends the session and moves `stage`; phase 2 (battle rules: QoLGame `# ---- ALLSTAR BATTLE (part
## 34)`) advances `index` / `beaten` / `elapsed_frames` / `hearts_used` during a battle and may set `result`.
## Written on the game thread (QoLGame overrides); the main thread (QoLController, panels) only reads, except where
## noted.
##
## Part 38 ENDLESS (docs/ALLSTAR_DESIGN.md section 7) is a session of the same kind with `endless` set: the same menu
## routing, select, battle rules, stage, music and hearts, but a never-ending random enemy list (`at()`), and the
## battle only ends when player 1's team is out -> the ENDLESS RECORDS page.
##
## Part 43: `mode` names the session (ALLSTAR / ENDLESS / BOSSRUSH / TOURNAMENT = Gamemode menu slot 0..3; `endless` stays
## as the ENDLESS flag the older code reads). BOSS RUSH (docs/ALLSTAR_DESIGN.md 8) is ALL-STAR's battle with BOSS_ORDER
## as the enemies, each made the game's boss at BOSS_LEVELS (QoLGame `# ---- BOSS RUSH`), one heart, boss music.
## TOURNAMENT (design 9) is a bracket of 8 teams fought as separate normal battles (QoLTournament holds the bracket).

enum { NONE, MENU, SELECT, BATTLE, RECORDS }
enum { ALLSTAR, ENDLESS, BOSSRUSH, TOURNAMENT }   ## part 43: `mode` = the Gamemode menu slot
const MODE_NAMES := ["ALL-STAR", "ENDLESS", "BOSS RUSH", "TOURNAMENT"]
## part 43 BOSS RUSH: every fighter the game has a boss version of (BOSS_CHARACTERS.txt), weakest level first, each
## level in story order, the Final Boss SSJ Goku last (the Expert course's final battle)
const BOSS_ORDER := [0, 6, 12, 11, 13, 25, 10, 18, 8, 7, 2, 21, 16, 9, 17, 15, 20, 1]

## Fighters 0-25 in story order (design 1.4): the enemies come in this order. `asorder=a,b,c` replaces it.
const ROSTER := [0, 4, 5, 24, 6, 12, 10, 1, 18, 11, 22, 8, 19, 13, 7, 14, 25, 15, 20, 2, 3, 21, 16, 23, 9, 17]
const STAGE_ID := 4                 ## Hyperbolic Time Chamber (u8 0x020DD54A)
const GAME_MODE := 5                ## Free Battle rules (u32 0x020DD514) for the select and the battle
const EMPTY_ID := 38                ## empty party slot / no support
const ENDLESS_TOTAL := 1 << 30      ## ENDLESS: total() = "no end"

var active := false                 ## a session runs: from ALL-STAR / ENDLESS on the Gamemode menu (or `allstar=1`) until Mode Select
var stage := NONE                   ## MENU (Gamemode menu, scene 0xB), SELECT (scene 4), BATTLE (scene 0), RECORDS
var order: Array = ROSTER.duplicate()   ## enemy ids in fight order (ENDLESS: grows during the battle)
var start_index := 0                ## first enemy of a battle (`asstart=N`; 0 normally; ENDLESS: always 0)
var index := 0                      ## order index of the enemy now active on side 1 (phase 2 advances it)
var beaten := 0                     ## enemies KO'd in this battle
var hearts_used := 0                ## hearts used in this battle (0..3)
var elapsed_frames := 0             ## battle clock in game frames (phase 2 counts it)
var result := ""                    ## "" while fighting / in menus, then "win", "lose" or "quit" (set when the battle is left)
var p1_ids: Array = []              ## P1's team (fighter ids, support last; 38 = none) at the start of the battle
var battles := 0                    ## battles started in this session
var debug_battle := false           ## `allstar=1`: the btnrun Free Battle is an All-Star battle (no menus)
var debug_endless := false          ## part 38 `endless=1` (with `allstar=1`): that battle is an ENDLESS battle
## battle (phase 2, `# ---- ALLSTAR BATTLE (part 34)`; reset by QoLGame at the battle start)
var hearts: Array = [true, true, true]   ## the three hearts: true = still usable (lit)
var heart_req := -1                 ## heart asked for (tap / SELECT): written by QoLAllStarHearts on the MAIN thread
var done := false                   ## the last enemy was KO'd: the clock stopped (result "win" when the battle ends)
var done_frame := -1                ## port frame of that KO (debug)
var dbg := false                    ## `asdbg`: AS log lines
## Gamemode menu (phase 1): cursor 0..3 (0 = ALL-STAR, 1 = ENDLESS (part 38), 2-3 = EMPTY)
var menu_cursor := 0
var menu_note := ""                 ## top-screen note after A on an EMPTY slot ("" = the slot's description)
## records (phase 4, QoLGame `# ---- ALLSTAR RECORDS`, QoLAllStarRecords): set on the game thread when a won battle asks
## for its results (scene 10) -- part 38: or a lost ENDLESS battle asks for Game Over (0x14); the records page (main
## thread) clears it when it opens
var records_req := false
var p1_support := 38                ## P1's support at the end of that battle (u32 0x020DD53C; 38 = none)
## part 38 ENDLESS: each new enemy is random among the 26 fighters but never one of the two before it (so the two
## CPU fighters on the field always differ and nobody comes twice in a row); a new list every battle
var endless := false                ## this session is ENDLESS (Gamemode menu slot 1, or `allstar=1 endless=1`)
var mode := ALLSTAR                 ## part 43: the session's mode (set by start())
var debug_mode := -1                ## part 43 `bossrush=1` / `tournament=1` (with `allstar=1`): that mode instead
var tour: QoLTournament = null      ## part 43: the TOURNAMENT bracket (made at the first tournament start)
var _as_order: Array = ROSTER.duplicate()   ## ALL-STAR's order (ROSTER or `asorder=`), put back when ALL-STAR starts
var _as_start := 0                          ## ALL-STAR's start index (`asstart=`); ENDLESS always starts at 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	dbg = Game.args.has("asdbg")
	if Game.args.has("asorder"):
		var ids: Array = []
		for s in Game.flag("asorder").split(",", false):
			var v := int(s)
			if v >= 0 and v <= 25:
				ids.append(v)
		if not ids.is_empty():
			order = ids
			_as_order = ids.duplicate()
	if Game.args.has("asstart"):
		start_index = clampi(int(Game.flag("asstart")), 0, order.size() - 1)
		_as_start = start_index
	if Game.args.has("allstar") and Game.flag("allstar") != "0":
		debug_battle = true             # the session becomes active at the first Free Battle start (QoLGame f_020140c8)
	debug_endless = Game.args.has("endless") and Game.flag("endless") != "0"
	if Game.args.has("bossrush") and Game.flag("bossrush") != "0":
		debug_mode = BOSSRUSH
	elif Game.args.has("tournament") and Game.flag("tournament") != "0":
		debug_mode = TOURNAMENT
	elif debug_endless:
		debug_mode = ENDLESS


## the session starts (ALL-STAR or, part 38, ENDLESS chosen on the Gamemode menu; part 43: any mode, by slot)
func start(m: Variant = false) -> void:
	if m is bool:
		m = ENDLESS if m else ALLSTAR
	mode = clampi(int(m), ALLSTAR, TOURNAMENT)
	active = true
	stage = SELECT
	battles = 0
	result = ""
	endless = mode == ENDLESS
	start_index = _as_start if mode == ALLSTAR else 0
	if mode == ALLSTAR:
		order = _as_order.duplicate()
	elif mode == BOSSRUSH:
		order = _br_order()
		start_index = clampi(int(Game.flag("brstart", "0")), 0, order.size() - 1)
	elif mode == TOURNAMENT:
		if tour == null:
			tour = QoLTournament.new()
		tour.clear()
	_log("session start (%s)" % MODE_NAMES[mode])


## part 43: BOSS RUSH's enemies (`brorder=a,b,c`: ids with a boss version only, debug)
func _br_order() -> Array:
	if Game.args.has("brorder"):
		var ids: Array = []
		for s in Game.flag("brorder").split(",", false):
			if int(s) in BOSS_ORDER:
				ids.append(int(s))
		if not ids.is_empty():
			return ids
	return BOSS_ORDER.duplicate()


func is_bossrush() -> bool:
	return active and mode == BOSSRUSH


func is_tournament() -> bool:
	return active and mode == TOURNAMENT


## the session ends (back to Mode Select)
func end() -> void:
	if active:
		_log("session end")
	active = false
	stage = NONE
	result = ""
	menu_cursor = 0
	menu_note = ""
	endless = false
	mode = ALLSTAR


## a battle starts (QoLGame f_020140c8 pre-hook, before the party is written): counters back to the start
func battle_reset() -> void:
	index = start_index
	beaten = 0
	hearts_used = 0
	elapsed_frames = 0
	result = ""
	battles += 1
	stage = BATTLE
	if endless:                          # part 38: a new random list (`esseed=N`: repeatable, N + battle number)
		_rng.seed = (int(Game.flag("esseed")) + battles) if Game.args.has("esseed") else randi()
		order = []


## order[i]; part 38 ENDLESS: the list grows with random fighters as far as asked
func at(i: int) -> int:
	if i < 0:
		return EMPTY_ID
	if endless:
		while order.size() <= i:
			var last: Array = order.slice(maxi(0, order.size() - 2))
			var n: int = ROSTER[_rng.randi_range(0, ROSTER.size() - 1)]
			while n in last:
				n = ROSTER[_rng.randi_range(0, ROSTER.size() - 1)]
			order.append(n)
	return order[i] if i < order.size() else EMPTY_ID


## the enemy fighting now / the one after it (EMPTY_ID past the end)
func enemy(k: int = 0) -> int:
	return at(index + k)


func total() -> int:
	return ENDLESS_TOTAL if endless else order.size()


func _log(s: String) -> void:
	if dbg:
		print("AS %s (stage %d index %d beaten %d result %s%s)" % [s, stage, index, beaten, result, " ENDLESS" if endless else
			(" " + MODE_NAMES[mode] if mode > ENDLESS else "")])
