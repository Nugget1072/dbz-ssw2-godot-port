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

enum { NONE, MENU, SELECT, BATTLE, RECORDS }

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


## the session starts (ALL-STAR or, part 38, ENDLESS chosen on the Gamemode menu)
func start(is_endless := false) -> void:
	active = true
	stage = SELECT
	battles = 0
	result = ""
	endless = is_endless
	start_index = 0 if endless else _as_start
	if not endless:
		order = _as_order.duplicate()
	_log("session start (%s)" % ("ENDLESS" if endless else "ALL-STAR"))


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
		print("AS %s (stage %d index %d beaten %d result %s%s)" % [s, stage, index, beaten, result, " ENDLESS" if endless else ""])
