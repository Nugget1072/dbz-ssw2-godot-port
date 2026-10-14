class_name QoLGame
extends DSGame
## The translated game with the QoL cheats hooked in (part 13). Each override below replaces one translated game
## function (direct calls and function-pointer calls both reach it: GDScript methods are virtual, and the
## indirect-call table `_fn` holds method references). With every cheat off each override only calls the original
## (`super`), so the game runs exactly as before. Cheats act for player 1's side only (fighter / object +0x1A == 0).
## Findings behind every hook: decomp/DATA_NOTES.md "Session 1 part 13".

var cheats: QoLSettings = null           ## set by QoLController; null = all off
var mp: QoLMp = null                     ## part 27: set by QoLController; null / not active = no multiplayer

const TEAMS := 0x020DE3D0                ## u32 -> team blocks (stride 0x8E8; 3 fighter records of 0x2D8 each)
const KI_FULL := 0xC800                  ## 200 % (team block +0x8D0)
const SIN := 0x020B64D4                  ## the game's sine table: s16, 256 steps, 1.0 = 256
const KI_BLAST_HANDLER := 0x020209E0     ## per-frame handler of plain projectiles (ki blasts)
const NO_DAMAGE_HIT := 0x0201F74C        ## hit handler of effects that deal no damage
const SELECT_TEAM := 0x020DE64C          ## s32[3] the side being picked (character select)
## attack actions a new attack may cut short (NO COOLDOWN): R+B, melee combo, dash, R+A, ki blast, Y+B,
## super charge / fire, ultimate
const ATTACKS := [0x19, 0x1A, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x23, 0x24, 0x2A, 0x2C, 0x2D, 0x2E, 0x2F]
const BEAM_KEEP_FRAMES := 60             ## a beam whose action was cut short keeps going this long

var _act_frames := {}                    ## fighter -> [action, frames in it] (NO COOLDOWN)

## BOSS CHARACTERS (part 14): a boss is a normal fighter id with a boss level (DATA_NOTES part 14). Every character
## the game itself uses as a boss (Z-Battle round 8, Maximum courses), at the highest level the game gives it.
const BOSS_LEVELS := {0: 1, 1: 3, 2: 2, 6: 1, 7: 2, 8: 2, 9: 2, 10: 2, 11: 1, 12: 1, 13: 1, 15: 3, 16: 2, 17: 2,
	18: 2, 20: 3, 21: 2, 25: 1}
const PARTY := 0x020DD524                ## s32[3] P1 party (P2 at +0xC), 38 = empty
const PARTY_COUNT := 0x020DD548          ## u8 P1 member count (P2 +1)
const PARTY_SUPPORT := 0x020DD53C        ## s32 P1 support id or 38 (P2 +4)
const GAME_MODE := 0x020DD514            ## u32 0 Z-Battle, 1 Story, 2 VS, 3 Maximum, 5 Free Battle
var boss_pending := -1                   ## character just picked with L held (QoLController assigns it to a slot)
var boss_pending_side := 0
var boss_teams := [{}, {}]               ## per side: {"team": sorted picked ids, "boss": [ids picked as bosses]}
var battle_bosses: Array = []            ## [record address, level] of bosses loaded in the current battle
var battle_loaded := false               ## set by the battle loader; QoLController clears it when a menu runs
var _assists := -1                       ## P1 assists at battle start (INFINITE ASSISTS)
var _party_saved: Array = []             ## RANDOM CHARACTERS: the real party while a random one is loaded


func _on(name: String) -> bool:
	return cheats != null and cheats.cheat(name)


# ------------------------------------------------------------------------------------------------ damage
## FUN_020293A4(fighter, damage, type): the only place fighters lose HP from hits
func f_020293a4(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if (_vp_coll or _db_coll) and param_2 > 0 and not _vp_in:   # part 41 VAMPIRE / DRAGON BALL HUNT: the HP really lost
		_vp_in = true                                  # (measured around the whole call: the cheats below count)
		var hp0: int = _ld(param_1 + 0x24A, 2, true)
		var rv := f_020293a4(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_vp_in = false
		var lost := hp0 - maxi(_ld(param_1 + 0x24A, 2, true), 0)
		if _vp_coll:
			_vp.hit(param_1, lost)
		if _db_coll:
			_db.hit(param_1, lost)
		return rv
	if _kb_on and param_2 > 0:
		_kb_hit[param_1] = true                         # part 39 SMASH KNOCKBACK: scaled after the collision pass
	if _hp_coll and param_2 > 0:
		_hp.hit(param_1)                                # part 40 HOT POTATO: a hit by the holder's side passes it
	if cheats != null and cheats.blood and param_2 > 0:
		_blood_hit(param_1, param_2)                    # part 22 BLOOD: droplets (drawing only)
	if cheats != null and cheats.screen_shake and param_2 > 0:
		shake_dmg = maxi(shake_dmg, param_2)            # part 23 SCREEN SHAKE: read by DSDisplay (picture only)
	if cheats != null and cheats.damage_numbers and param_2 > 0:
		_w3_hit(param_1, param_2)                       # part 24 DAMAGE NUMBERS (drawing only)
	if cheats != null and not _gd_killing:             # (part 36 GREEN DEMON: its KO ignores the damage cheats)
		var p1 := _helped(param_1)                     # part 27: in an MP battle both players count as "player 1"
		if _on("hard_mode") and param_2 > 0:
			# HARD MODE (part 18): enemy hits on player 1 do double damage; enemies take half damage, i.e. they have
			# double health (HP is a signed 16-bit value: boss HP x2 would not fit, so the damage is halved instead)
			param_2 = mini(param_2 * 2, 0x7FFF) if p1 else (param_2 + 1) / 2
		if p1 and _on("infinite_health"):
			param_2 = 0                          # the hit still lands (reaction, effects), no HP lost
		elif (not p1 or _mp_on()) and param_2 > 0 and _on("one_hit_ko") and (_ld(param_1 + 0x250, 4, false) & 1) == 0:   # not guarding
			var r := super.f_020293a4(param_1, param_2, param_3)
			if _ld(param_1 + 0x24A, 2, true) > 0:   # what the original does for a hit bigger than the HP left
				if param_3 == 5:
					_st(param_1 + 0x254, 2, _ld(param_1 + 0x254, 2, false) | 0x800)
				_st(param_1 + 0x24A, 2, 0)
			return r
	return super.f_020293a4(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


# ------------------------------------------------------------------------------------------------ ki
## FUN_02027950(fighter, amount, mode): spend ki
func f_02027950(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats != null and _on("infinite_ki") and _helped(param_1):
		return 0
	return super.f_02027950(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


# ------------------------------------------------------------------------------------------------ fighter update
## FUN_0202954C(fighter, ...): once per fighter per battle frame (before its action handler picks new actions)
func f_0202954c(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _dash_dbg != 0:
		_dash_trace(param_1)                           # part 18 debug (`dashdbg`): per-frame motion trace
	if _p2keys_dbg != 0:
		_p2keys(param_1)                               # part 19 debug (`p2keys=F:MASK:N`): scripted P2 input
	_fx_upd = true                                     # part 22 BLOOD / AFTERIMAGES: a battle frame ran
	if cheats != null and cheats.bomb_rain:
		_br_tick()                                     # part 25 BOMB RAIN (once per battle frame)
	if cheats != null and _on("green_demon"):
		_gd_tick()                                     # part 36 GREEN DEMON (once per battle frame)
	if cheats != null and _on("hot_potato"):
		if _hp == null:
			_hp = _POTATO_GD.new(self, _bomb_img)
		_hp.tick(_port_frame())                        # part 40 HOT POTATO (once per battle frame)
	if cheats != null and _on("dragon_balls"):
		if _db == null:
			_db = _DB_GD.new(self)
		_db.tick(_port_frame())                        # part 41 DRAGON BALL HUNT (once per battle frame)
	if cheats != null and _on("body_change"):
		if _bc == null:
			_bc = _BC_GD.new(self)
		_bc.tick(_port_frame())                        # part 42 BODY CHANGE (once per battle frame)
	if cheats != null and _on("time_skip"):
		if _ts == null:
			_ts = _TS_GD.new(self)
		_ts.tick(_port_frame())                        # part 41 TIME SKIP (once per battle frame: Select, countdown)
		if _ts.frozen(param_1):
			_ts.freeze_step(param_1)                   # the frozen side's fighter: hittable, nothing else
			return 0
	if cheats != null and _on("z_vanish"):
		if _zv == null:
			_zv = _ZV_GD.new(self)
		_zv.tick(param_1)                              # part 42 Z-VANISH (active fighters: B in a hit stun)
	if cheats != null:
		_c39_tick(param_1)                             # part 39 FLIGHTLESS / ULTRA INSTINCT / RANDOMIZER (active fighters)
	if cheats != null and _helped(param_1):            # part 27: side 0, and side 1 in an MP battle
		var side: int = _ld(param_1 + 0x1A, 1, false)
		if _on("character_shuffle") or _on("chaos_shuffle"):
			_shuffle_tick(param_1)                     # part 16 / 18: may reload this record as another character
		if _on("stage_shuffle") and side == 0 and not _asb_on:   # (part 34: never in an All-Star battle: Time Chamber)
			_stage_tick(param_1)                       # part 18: may move the battle to another stage
		if _on("infinite_ki"):
			_st(_ld(TEAMS, 4, false) + side * 0x8E8 + 0x8D0, 2, KI_FULL)
		var asst: int = _assists if side == 0 else _assists2
		if _on("infinite_assists") and asst > 0:
			_st(_ld(TEAMS, 4, false) + side * 0x8E8 + 0x8CA, 1, asst)
		if _on("no_cooldown"):
			_cancel_attack(param_1)
		if _on("attack_spam"):
			_spam_tick(param_1)                        # part 18
	if mp != null and _mp_on():
		var r29 := super.f_0202954c(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_mta_tick(param_1)                             # part 29: Team Arts light per side (`# ---- MP TEAM ARTS LIGHT`)
		return r29
	return super.f_0202954c(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## NO COOLDOWN: an attack button pressed during an attack ends that attack, so the neutral handler starts the new
## one this very frame. Melee combos keep their own Y chaining; a ki blast is not restarted before its first
## shot (frame 9), which would only delay the shots.
func _cancel_attack(f: int) -> void:
	var act: int = _ld(f + 6, 1, false)
	var st: Array = _act_frames.get(f, [-1, 0])
	if st[0] != act:
		st = [act, 0]
	else:
		st[1] += 1
	_act_frames[f] = st
	var pressed: int = _ld(f + 0x26C, 2, false)
	if (pressed & 0x801) == 0 or not act in ATTACKS:
		return
	var held: int = _ld(f + 0x270, 2, false)
	var melee: bool = act >= 0x1C and act <= 0x1F
	if (pressed & 0x801) == 0x800 and melee:
		return                                          # Y during a combo: the combo's own next hit
	if act == 0x24 and (pressed & 1) != 0 and (held & 0x400) == 0 and st[1] < 10:
		return                                          # plain ki blast before its first shot
	_nc_keep(f, act)                                    # part 20: the cut attack's beams keep going (GFX FIXES)
	f_02021b4c(f, 5 if (_ld(f + 0x10, 2, false) & 1) != 0 else 0)   # back to neutral (5 = on the ground, part 39 correction)
	_act_frames[f] = [-1, 0]


## (FUN_0202104C, an effect's life checks, is no longer overridden: part 20 moved NO COOLDOWN's "beams keep going"
## into _cancel_attack → _nc_keep, see `# ---- GFX FIXES (part 20)` at the end of this file.)


# ------------------------------------------------------------------------------------------------ ki homing
## FUN_020209E0(object): per-frame handler of plain projectiles (ki blasts; beams use other handlers)
func f_020209e0(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats != null and _on("ki_homing") and _helped(param_1) and _ld(param_1 + 8, 2, false) == 1:
		_home(param_1)
	if not _tri_new.is_empty() or not _tri_turn.is_empty():   # TRIPLE KI BLASTS (part 18)
		_tri_before(param_1)
		var r := super.f_020209e0(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_tri_after(param_1)
		if cheats != null and _on("ricochet_ki") and _helped(param_1):
			_rc_bounce(param_1)                        # part 40 RICOCHET KI
		return r
	if cheats != null and _on("ricochet_ki") and _helped(param_1):
		var r40 := super.f_020209e0(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_rc_bounce(param_1)                            # part 40 RICOCHET KI
		return r40
	return super.f_020209e0(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


const HOMING_TURN := 3                   ## direction steps (of 256) per frame


func _home(o: int) -> void:
	var owner: int = _ld(o, 4, false)
	var side: int = _ld(o + 0x1A, 1, false) & 1        # part 27: 0, or 1 in an MP battle (_helped)
	if owner == 0 or owner != f_02027c00(side) or (_ld(o + 0x10, 2, false) & 8) != 0:
		return
	if _ld(o + 0x34, 4, false) == NO_DAMAGE_HIT or _ld(o + 0x22, 2, true) == 0:
		return
	var tgt := f_02027bd0(side)
	if tgt == 0 or _ld(tgt + 0x24A, 2, true) <= 0:
		return
	var cur: int = _ld(o + 0x21, 1, false)
	var want := f_0201ee60(o, tgt) & 0xFF
	var nxt := f_020210c8(cur, HOMING_TURN, want) & 0xFF
	var d := (nxt - cur) & 0xFF
	if d == 0:
		return
	_st(o + 0x21, 1, nxt)
	var s: int = _ld(SIN + d * 2, 2, true)
	var c: int = _ld(SIN + ((d + 0x40) & 0xFF) * 2, 2, true)
	for off in [0x28, 0x2C, 0x30]:   # velocity, target velocity, acceleration (screen y points down)
		var x: int = _ld(o + off, 2, true)
		var yu: int = -_ld(o + off + 2, 2, true)
		var nx := (x * c - yu * s) >> 8
		var nyu := (x * s + yu * c) >> 8
		_st(o + off, 2, nx & 0xFFFF)
		_st(o + off + 2, 2, (-nyu) & 0xFFFF)


# ------------------------------------------------------------------------------------------------ same characters
## FUN_0206CC94: character select input -> picked character id (refuses characters already in the team and the
## same family); FUN_0206ABB0 greys out such portraits. With SAME CHARACTERS both see the team without its
## fighters (part 29, _hide_fighters): any fighter may be picked again, but a support stays in the team, so the game's
## own "one support per team" test (FUN_02066088: refusal SE 0xD, greyed SP tab) still applies -- the game's battle
## calls a support only when the touch is inside EVERY support panel (FUN_02026C00), and with one support its own
## START test (FUN_0206A6FC: a fighter id 0-25 in the team) and stage-exit reorder (FUN_02071374) keep a fighter
## first. (An MP select hides the whole team: its own rules, `# ---- MULTIPLAYER SELECT`.)
func f_0206cc94(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if lan != null and lan.sel_on() and _ld(0x020DD4C4, 1, false) == 4:
		return _lan_select()                           # part 30 phase 3: LAN team select (`# ---- LAN SELECT`)
	if _mp_sel():
		return _mp_select()                            # part 27: two players (`# ---- MULTIPLAYER SELECT`)
	if cheats == null or not _on("same_characters") or f_0206a76c() != 0:   # not while confirming the team
		var r0 := super.f_0206cc94(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_note_pick(r0)
		return r0
	var saved := _hide_fighters()
	var r := super.f_0206cc94(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_show_team(saved)
	if (r & 0xFFFFFFFF) == 0xFFFFFFFF and Game.args.has("cheatdbg"):
		print("CHT f%d same characters: pick refused (cursor %d, team %s)" % [_port_frame(), _ld(0x020DEA0F, 1, false), str(saved)])
	_note_pick(r)
	return r


func f_0206abb0(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	# part 27: in an MP select the greys of the players still picking (`# ---- MP QA`, _mp_grey; part 28: also
	# with SAME CHARACTERS, per player)
	if _mp_sel() and _ms_init:
		return _mp_grey()
	if (cheats == null or not _on("same_characters")) and not _mp_sel():
		return super.f_0206abb0(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var saved := _hide_team() if _mp_sel() else _hide_fighters()
	var r := super.f_0206abb0(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_show_team(saved)
	return r


func _hide_team() -> Array:
	var s := []
	for i in 3:
		s.append(_ld(SELECT_TEAM + 4 * i, 4, false))
		_st(SELECT_TEAM + 4 * i, 4, 0xFFFFFFFF)
	return s


func _show_team(s: Array) -> void:
	for i in 3:
		_st(SELECT_TEAM + 4 * i, 4, s[i])


## part 29 (single player): only the fighters (ids 0-25) are hidden; a support (26-37) stays, so the game refuses /
## greys a second support. Supports have family bytes 17-31 of their own (u8 0x020D04C8[id]; fighters 0-15), so a
## support left in the team never blocks a fighter through the family test FUN_0206A688.
func _hide_fighters() -> Array:
	var s := []
	for i in 3:
		var v: int = _ld(SELECT_TEAM + 4 * i, 4, false)
		s.append(v)
		if v < 26:
			_st(SELECT_TEAM + 4 * i, 4, 0xFFFFFFFF)
	return s


# ------------------------------------------------------------------------------------------------ boss characters
## a pick made with L held (KEYINPUT bit 9, active low) becomes a boss if the game has a boss version of it
func _note_pick(r: int) -> void:
	if r < 0 or cheats == null:
		return
	if _on("boss_characters") and BOSS_LEVELS.has(r) and (_ld(0x04000130, 2, false) & 0x200) == 0:
		boss_pending = r
		boss_pending_side = _ld(0x020DEA2C, 1, false) if _ld(0x020DE374, 4, false) == 0x0206D61C else 0
	else:
		boss_pending = -1


## FUN_0202A40C: the battle loader (all modes). Afterwards: boss levels for picked bosses, assists to keep.
func f_0202a40c(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, param_5: int = 0, param_6: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_0202a40c(param_1, param_2, param_3, param_4, param_5, param_6, _x6, _x7, _x8, _x9, _x10, _x11)
	if _fiddle_on():
		_fiddle_apply()                                # 2ND FIDDLE (part 21): P1 mirror palettes, P2 normal
	battle_bosses = []
	battle_loaded = true
	if lan != null and lan.in_battle:
		lan.on_battle_loaded()                         # part 30 phase 4: the desync checksum starts here
	_assists = -1
	_assists2 = -1                                     # part 27: P2's (MP battle)
	_clones = []
	_mda = [0, 0]                                      # part 29: per-side assists (MP battle)
	_clone_free = []
	_shuf_t = -1                                       # CHARACTER SHUFFLE: new battle, new timer
	_shuf_p2 = [-1, -1, false, "", 0, -1]              # part 27: P2's shuffle state (MP battle)
	_tri_new.clear()                                   # TRIPLE KI BLASTS (part 18)
	_chaos_sup.clear()                                 # CHAOS SHUFFLE (part 19)
	_panel_cache.clear()                               # CHAOS SHUFFLE (part 18): lower-screen panel cache
	_tri_turn.clear()
	_stg_t = -1                                        # STAGE SHUFFLE: new battle, new timer
	if _bombs != null:
		_bombs.reset()                                 # part 25 BOMB RAIN: new battle, no bombs, RNG reseeded
	if _gd != null:
		_gd.reset()                                    # part 36 GREEN DEMON: new battle, not spawned, RNG reseeded
	if _texblk != null:
		_texblk.reset()                                # part 36: the shared texture block is checked again
	if _ui != null:
		_ui.reset()                                    # part 39 ULTRA INSTINCT: no windows / flashes left
	_rz.clear()                                        # part 39 RANDOMIZER: the records are built anew
	_fl_v.clear()                                      # part 39 FLIGHTLESS
	_fl_gnd.clear()
	_fl_up.clear()
	if _hp != null:
		_hp.reset()                                    # part 40 HOT POTATO
	_rc.clear()                                        # part 40 RICOCHET KI
	_kb_free.clear()                                   # part 40 SMASH KNOCKBACK
	_kb_off.clear()
	_kb_flash.clear()
	if _vp != null:
		_vp.reset()                                    # part 41 VAMPIRE
	if _db != null:
		_db.reset()                                    # part 41 DRAGON BALL HUNT
	if _ts != null:
		_ts.reset()                                    # part 41 TIME SKIP
	if _bc != null:
		_bc.reset()                                    # part 42 BODY CHANGE
	if _zv != null:
		_zv.reset()                                    # part 42 Z-VANISH
	if cheats == null:
		return r
	var teams: int = _ld(TEAMS, 4, false)
	if _on("infinite_assists"):
		_assists = _ld(teams + 0x8CA, 1, false)
		_assists2 = _ld(teams + 0x8E8 + 0x8CA, 1, false)   # part 27: used only in an MP battle
	if _on("boss_characters"):
		for side in 2:
			var bt: Dictionary = boss_teams[side]
			if bt.is_empty() or (bt["boss"] as Array).is_empty() or _party_ids(side) != bt["team"]:
				continue
			var todo: Array = (bt["boss"] as Array).duplicate()
			var tb: int = teams + side * 0x8E8
			for k in _ld(tb + 0x8C9, 1, false):
				var f := tb + k * 0x2D8
				var id: int = _ld(f + 5, 1, false)
				if id in todo and BOSS_LEVELS.has(id):
					todo.erase(id)
					_make_boss(f, BOSS_LEVELS[id])
					battle_bosses.append([f, BOSS_LEVELS[id]])
	return r


func _party_ids(side: int) -> Array:
	var a := []
	for k in 3:
		var id: int = _ld(PARTY + side * 0xC + k * 4, 4, true)
		if id >= 0 and id < 38:
			a.append(id)
	a.sort()
	return a


## what the game does for a CPU boss (FUN_0202117C with the boss level): parameter block `lv` of the fighter's
## 'c' chunk, HP from it; and the boss-only script branches (VM opcode 0x92 "if CPU and boss level == L goto")
## become plain gotos (opcode 0x05, same layout) in this fighter's own copy of the chunk
func _make_boss(f: int, lv: int) -> void:
	var c: int = _ld(f + 0x44, 4, false)
	var blk: int = c + _ld(c + 0x10 + 4 * lv, 4, false)
	_st(f + 0x50, 4, blk)
	var hp: int = _ld(blk, 2, false)
	_st(f + 0x24A, 2, hp)
	_st(f + 0x24C, 2, hp)
	var n := 0
	var ops := _script_ops(c, 0x92)
	for at in ops:
		if _ld(c + at + 1, 1, false) == lv:
			_st(c + at, 1, 0x05)
			n += 1
	if Game.args.has("cheatdbg"):
		print("CHT boss fighter %x id %d level %d hp %d boss branches %d of %d" % [f, _ld(f + 5, 1, false), lv, hp, n, ops.size()])


## offsets of all instructions `op` in a 'c' chunk: walks the bytecode from every action like
## decomp/tools/charscript.py (lengths per opcode; branch targets are chunk offsets)
const _OPLEN := {0x00: 10, 0x01: 2, 0x02: 6, 0x03: 8, 0x04: 66, 0x05: 6, 0x06: 10, 0x07: 10, 0x08: 2, 0x09: 2,
	0x0a: 2, 0x0b: 2, 0x0c: 2, 0x0d: 2, 0x0e: 8, 0x0f: 4, 0x10: 2, 0x11: 4, 0x12: 6, 0x13: 6, 0x14: 2, 0x15: 6,
	0x16: 4, 0x18: 2, 0x19: 6, 0x1a: 2, 0x1b: 2, 0x1c: 6, 0x1d: 4, 0x1e: 6, 0x1f: 4, 0x20: 4, 0x21: 4, 0x22: 2,
	0x23: 4, 0x24: 6, 0x25: 4, 0x26: 4, 0x27: 4, 0x28: 2, 0x29: 2, 0x2a: 2, 0x2b: 4, 0x2c: 8, 0x2d: 2, 0x2e: 6,
	0x2f: 4, 0x30: 4, 0x31: 4, 0x32: 4, 0x33: 2, 0x34: 2, 0x35: 2, 0x36: 4, 0x37: 2, 0x38: 2, 0x39: 2, 0x3a: 10,
	0x3b: 2, 0x3c: 2, 0x3d: 14, 0x3e: 14, 0x3f: 8, 0x40: 2, 0x41: 14, 0x42: 2, 0x43: 6, 0x44: 2, 0x45: 6, 0x46: 8,
	0x47: 2, 0x48: 2, 0x49: 8, 0x4a: 8, 0x4b: 6, 0x4c: 6, 0x4d: 6, 0x4e: 6, 0x4f: 6, 0x50: 4, 0x51: 2, 0x52: 2,
	0x53: 2, 0x54: 6, 0x55: 6, 0x56: 6, 0x57: 4, 0x58: 4, 0x59: 8, 0x5a: 10, 0x5b: 4, 0x5c: 8, 0x5d: 8, 0x5e: 6,
	0x5f: 6, 0x60: 2, 0x63: 6, 0x64: 4, 0x65: 4, 0x66: 8, 0x67: 6, 0x68: 6, 0x69: 4, 0x6a: 4, 0x6b: 4, 0x6c: 6,
	0x6d: 2, 0x6e: 2, 0x70: 4, 0x71: 6, 0x72: 4, 0x73: 10, 0x74: 4, 0x75: 2, 0x76: 8, 0x77: 8, 0x78: 14, 0x79: 14,
	0x7a: 6, 0x7b: 6, 0x7c: 6, 0x7d: 2, 0x7e: 2, 0x7f: 2, 0x80: 2, 0x81: 2, 0x82: 2, 0x83: 2, 0x84: 6, 0x85: 14,
	0x86: 2, 0x87: 6, 0x88: 6, 0x89: 2, 0x8a: 6, 0x8b: 6, 0x8c: 2, 0x8d: 2, 0x8e: 6, 0x8f: 2, 0x90: 2, 0x91: 2,
	0x92: 6}
const _BRANCH := {0x05: 2, 0x12: 2, 0x45: 2, 0x4e: 2, 0x55: 2, 0x63: 2, 0x7a: 2, 0x7c: 2, 0x8e: 2, 0x92: 2,
	0x46: 4, 0x59: 4, 0x66: 4, 0x5a: 6, 0x73: 6}


func _script_ops(c: int, want: int) -> Array:
	var act_tab: int = _ld(c + 4, 4, false)
	var base: int = _ld(c + 0xC, 4, false)
	var work := []
	var p := act_tab
	while work.size() < 512:
		var v: int = _ld(c + p, 4, false)
		if v == 0xFFFFFFFF:
			break
		work.append(base + v)
		p += 4
	var seen := {}
	var found := []
	while not work.is_empty():
		var at: int = work.pop_back()
		while not seen.has(at) and at < 0x40000 and seen.size() < 20000:
			seen[at] = true
			var op: int = _ld(c + at, 1, false)
			if not _OPLEN.has(op):
				break
			if op == want:
				found.append(at)
			if _BRANCH.has(op):
				var t: int = _ld(c + at + _BRANCH[op], 4, false)
				if t != 0:
					work.append(t)
			if op == 0x04:
				for i in 16:
					var t4: int = _ld(c + at + 2 + i * 4, 4, false)
					if t4 != 0:
						work.append(t4)
			if op == 0x01 or op == 0x04 or op == 0x05:
				break
			at += _OPLEN[op]
	return found


# ------------------------------------------------------------------------------------------------ random characters
## FUN_020140C8: first step of every battle start (VS screen, bottom panels, loader read the party after it).
## RANDOM CHARACTERS puts a random P1 team of the same size in the party block for this battle only.
func f_020140c8(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	_lan_battle_start()                                # part 30: a LAN battle: the sync of LAN_DESIGN 1.2 (`# ---- LAN CORE`)
	_mp_battle_start()                                 # part 27: `mpbattle=1` (debug) / per-battle MP state
	if cheats != null and _on("random_characters") and _party_saved.is_empty() and _ld(GAME_MODE, 4, false) != 2:
		_randomize_party()
		if _mp_on() and _party_saved2.is_empty():
			_randomize_party(1)                        # part 27: an MP battle randomises both humans' teams
	if cheats != null and _on("random_stage") and _ld(GAME_MODE, 4, false) != 2:
		# RANDOM STAGE (part 19): the party block's stage id (u8 0x020DD54A, set by the stage select / the mode) is
		# replaced before the battle init (FUN_0201C150) and the BGM choice (FUN_02013064 case 4) read it: a random
		# one of the 15 stages (0-14, DATA_NOTES part 18), never the one that was set
		var cur: int = _ld(0x020DD54A, 1, false)
		var n := cur
		while n == cur:
			n = rng.randi_range(0, 14)
		_st(0x020DD54A, 1, n)
		if Game.args.has("cheatdbg"):
			print("CHT random stage %d -> %d" % [cur, n])
	_asb_battle_setup()                                # part 34: an All-Star battle: P2 / stage (`# ---- ALLSTAR BATTLE`)
	var r34 := super.f_020140c8(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_asb_battle_started()                              # part 34: no time limit (All-Star battle only)
	return r34


## FUN_02013D60: battle init (calls the loader); afterwards the real party comes back
func f_02013d60(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_02013d60(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if not _party_saved.is_empty():
		for k in 3:
			_st(PARTY + k * 4, 4, _party_saved[k])
		_st(PARTY_SUPPORT, 4, _party_saved[3])
		_st(PARTY_COUNT, 1, _party_saved[4])
		_party_saved = []
	if not _party_saved2.is_empty():                   # part 27: P2's (MP battle)
		for k in 3:
			_st(PARTY + 0xC + k * 4, 4, _party_saved2[k])
		_st(PARTY_SUPPORT + 4, 4, _party_saved2[3])
		_st(PARTY_COUNT + 1, 1, _party_saved2[4])
		_party_saved2 = []
	return r


var rng := RandomNumberGenerator.new()


## same number of members; fighters 0-25, at most one support (26-36), never only supports; a support goes last.
## side 1 (part 27): player 2's party (MP battle)
func _randomize_party(side := 0) -> void:
	var pa := PARTY + side * 0xC
	var ps := PARTY_SUPPORT + side * 4
	var pc := PARTY_COUNT + side
	var n: int = clampi(_ld(pc, 1, false), 1, 3)
	var saved := [_ld(pa, 4, false), _ld(pa + 4, 4, false), _ld(pa + 8, 4, false), _ld(ps, 4, false), _ld(pc, 1, false)]
	if side == 0:
		_party_saved = saved
	else:
		_party_saved2 = saved
	var ids := []
	var support := 38
	for k in n:
		if k == n - 1 and n >= 2 and rng.randf() < 0.3:
			support = rng.randi_range(26, 36)
			ids.append(support)
		else:
			ids.append(rng.randi_range(0, 25))
	for k in 3:
		_st(pa + k * 4, 4, ids[k] if k < n else 38)
	_st(ps, 4, support)
	_st(pc, 1, n)


# ------------------------------------------------------------------------------------------------ assist spam
## ASSIST SPAM (part 15). The game keeps ONE assist on screen: the global slot u32 [teams+0x11E0] = the fighter
## record of the support now acting (either player's). A call is refused while the slot is busy
## (FUN_02026C00); the arrival FUN_020277AC puts the team's support record in the slot. With the cheat, player 1
## may call while an assist is out, and each extra arrival runs a COPY of the support's record (spare RAM the game
## never uses), updated after the slot's own assist (FUN_020294B8) with the slot pointing at the copy, so the
## game's own end-of-assist code hides and releases the copy. Up to 8 copies; Shenron (0x23) is not copied.
const CLONE_BASE := 0x02700000
const CLONE_STRIDE := 0x2E0
const CLONE_MAX := 8
var _clones: Array = []
var _clone_free: Array = []
var _clone_frame := -1
var _in_clones := false


func _slot() -> int:
	return _ld(TEAMS, 4, false) + 0x11E0


## FUN_02026C00(fighter, touched): may this touch call the assist? (P1: the busy slot does not block)
func f_02026c00(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mda_guard == 0 and _mp_on():                     # part 29: one assist slot per side (`# ---- MP DUAL ASSISTS`)
		return _mda_call(param_1, param_2)
	if _ms2_guard == 0 and param_2 != 0 and _mp_on():   # part 28: two supports (`# ---- MP SUPPORTS`)
		return _ms2_call(param_1, param_2)
	if cheats != null and _on("assist_spam") and _helped(param_1):
		var slot := _slot()
		var s: int = _ld(slot, 4, false)
		_st(slot, 4, 0)
		var r := super.f_02026c00(param_1, param_2)
		_st(slot, 4, s)
		return r
	return super.f_02026c00(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_020277AC(caller): the assist arrives (end of the call pose). Slot busy + cheat: a copy arrives instead.
func f_020277ac(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mda_guard == 0 and _mp_on():                     # part 29 (`# ---- MP DUAL ASSISTS`)
		return _mda_arrive(param_1)
	if _ms2_guard == 0 and _mp_on() and _ms2_k[_ld(param_1 + 0x1A, 1, false) & 1] >= 0:   # part 28 (`# ---- MP SUPPORTS`)
		return _ms2_arrive(param_1)
	if cheats == null or not _on("assist_spam") or not _helped(param_1) or _ld(_slot(), 4, false) == 0:
		return super.f_020277ac(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var team: int = _ld(TEAMS, 4, false) + (_ld(param_1 + 0x1A, 1, false) & 1) * 0x8E8   # part 27: the caller's team
	var sup := 0
	for k in _ld(team + 0x8C9, 1, false):
		if _ld(team + k * 0x2D8 + 5, 1, false) > 0x19:
			sup = team + k * 0x2D8
	if sup == 0 or _ld(sup + 5, 1, false) == 0x23 or _mda_clones(param_1) >= CLONE_MAX:   # part 29: per side in MP
		_st(param_1 + 0x250, 4, _ld(param_1 + 0x250, 4, false) & ~0x100)   # end the call pose anyway
		return 0
	if _clone_free.is_empty():
		for i in CLONE_MAX * 2:                        # part 29: 8 per side in an MP battle (16 x 0x2E0 spare bytes)
			_clone_free.append(CLONE_BASE + i * CLONE_STRIDE)
	var c: int = _clone_free.pop_front()
	for o in range(0, 0x2D8, 4):
		_st(c + o, 4, _ld(sup + o, 4, false))
	f_02029e3c(param_1, 0x29)                          # the call voice
	_st(c + 0x250, 4, 0)
	_st(c + 0x25D, 1, _ld(c + 0x1A, 1, false))
	f_02021b4c(c, 0)
	f_02011d54(c + 0x124, 1)                           # visible
	_st(param_1 + 0x250, 4, _ld(param_1 + 0x250, 4, false) & ~0x100)
	if not _on("infinite_assists"):
		_st(team + 0x8CA, 1, maxi(0, _ld(team + 0x8CA, 1, false) - 1))
	_clones.append(c)
	return 1


## FUN_020294B8(record): the slot's assist runs each battle frame; the copies run right after it
func f_020294b8(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _ts != null and _ts.frozen(param_1) and _on("time_skip"):
		f_02019328(param_1)                            # part 41 TIME SKIP: the frozen side's support only drawn
		return 0
	if not _in_clones and _mp_on():                     # part 29 (`# ---- MP DUAL ASSISTS`)
		return _mda_run(param_1, param_2, param_3, param_4)
	var r := super.f_020294b8(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if _clones.is_empty() or _in_clones:
		return r
	var slot := _slot()
	if param_1 != _ld(slot, 4, false):
		return r
	var frame: int = _ld(0x020DD4C0, 2, false)         # the main loop's frame counter: once per frame
	if frame == _clone_frame:
		return r
	_clone_frame = frame
	_in_clones = true
	var saved: int = _ld(slot, 4, false)
	for c in _clones.duplicate():
		_st(slot, 4, c)
		super.f_020294b8(c)
		if _ld(slot, 4, false) == 0:                     # its assist ended (the game hid it and freed the slot)
			_clones.erase(c)
			_clone_free.append(c)
	_st(slot, 4, saved)
	_in_clones = false
	return r


# ------------------------------------------------------------------------------------------------ random music
## RANDOM MUSIC (part 15): every BGM the game starts is replaced by another of the same kind (stream -> stream,
## sequence -> sequence that fits the sound heap the scene sized for its own). A new shuffle each time the cheat is
## switched on (QoLSettings.music_seed). The jukebox sets music_bypass.
var music_bypass := false
var strm_map := {}                       ## stream id -> stream id
var seq_map := {}                        ## sequence id -> sequence id
var _seq_as := {}                        ## sequence id the game asked for -> the one loaded for it
const BGM := 0x020DE2A0


func shuffle_music(seed_v: int, seq_sizes: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var st := range(1, 20)                                 # 0 = the title's one-shot opening: kept
	var sh := st.duplicate()
	for i in range(sh.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = sh[i]
		sh[i] = sh[j]
		sh[j] = t
	strm_map = {}
	for i in st.size():
		strm_map[st[i]] = sh[i]
	seq_map = {}
	for a in seq_sizes:
		var fits := []
		for b in seq_sizes:
			if b != a and seq_sizes[b] <= seq_sizes[a] + 0x8000:   # no bigger than what the scene planned for
				fits.append(b)
		seq_map[a] = fits[r.randi_range(0, fits.size() - 1)] if not fits.is_empty() else a
	_seq_as = {}


func _music_on() -> bool:
	return cheats != null and not music_bypass and _on("random_music")


## FUN_0200FE98(id): load BGM sequence id (sequence mode) into the sound heap
func f_0200fe98(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _music_on() and (_ld(BGM + 0xA0, 2, false) & 1) != 0 and seq_map.has(param_1) and seq_map[param_1] != param_1:
		var lvl := f_02010044()
		if lvl >= 0:
			var r := super.f_0200fe98(seq_map[param_1])
			if r != 0:
				_seq_as[param_1] = seq_map[param_1]
				return r
			f_02010028(lvl)                                # free a partial load, then the original
	_seq_as.erase(param_1)
	return super.f_0200fe98(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_0200FE48(id): play BGM id (stream or sequence, by the manager's mode)
func f_0200fe48(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _music_on():
		if (_ld(BGM + 0xA0, 2, false) & 1) != 0:
			param_1 = _seq_as.get(param_1, param_1)
		else:
			param_1 = strm_map.get(param_1, param_1)
	return super.f_0200fe48(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


# ---- CHARACTER SHUFFLE (part 16) -------------------------------------------------------------------------------
## Every 600 battle frames player 1's active fighter turns into a random other fighter (ids 0-25). The record is
## reloaded in place the way the battle loader builds it (FUN_0202A094, DATA_NOTES part 16): the old character's
## heap data (file-cache entries of its 'c' chunk, sprite table, palette, effect chunk ...) and its two image
## archives are released, FUN_02020D4C / FUN_02020D0C load the new ones into the same record, the per-character
## init handler and tables run, and the action restarts. The palettes go into the record's existing palette slots
## (FUN_02010AE0: the game never frees a slot), the body sprite keeps its VRAM block (frames are streamed into it,
## keyed by character id), the life-bar face icon (rec+0x290) is re-uploaded and the lower screen portraits are
## redrawn by the game's own FUN_0201B78C. HP and max HP stay as they were (the life bar does not jump). The swap
## waits until the fighter is in a neutral / move action with no effect object of its own alive.
const SHUF_PERIOD := 600                 ## battle frames between swaps
const SHUF_SAFE := [0, 1, 2, 3, 4, 5]    ## neutral (ground 0 / air 5) and move (1-4) actions
const SHUF_SCRATCH := 0x02710000         ## port-only RAM (the port maps 8 MiB flat; the game uses the first 4)
const FS_MGR := 0x020DD7B8               ## u32 -> file manager: +0 open archives {struct, refs} x64, +0x200 file
										 ## cache {u16 archive handle, u16 index, u32 data} x48, +0x380 open count
const MAIN_HEAP := 0x020DE1E4            ## u32 -> the main NNS expanded heap (FUN_02009120 / FUN_020090B0)
const FACEICON_ARC := 0x020D7FE0         ## "/romdata/game/game_faceicon.arc" (entries 2*id gfx, 2*id+1 palette)
const BG_MGR := 0x020DD7BC               ## u32 -> BG manager: +0x1AC + 4*layer = map buffer of the layer
const SUBFILES := 0x020DE210             ## u8: packed-file system state (0 = idle, FUN_0200A85C / FUN_0200A788)
var _shuf_t := -1                        ## battle frames since the last swap (-1: battle not started yet)
var _shuf_frame := -1
var _shuf_n := 0                         ## swaps this run
var _shuf_down := false                  ## the old character's power-up was ended (FUN_020297DC mode 2)
var _shuf_wait := ""
var _shuf_panel := false                 ## FUN_0201B78C runs for a swap (uploads copied, no VBlank waits)
var _shuf_rng := RandomNumberGenerator.new()
var _shuf_voice_ok := ""                 ## debug: FUN_02029024 results of the last voice reload
var _shuf_seeded := false
var _shuf_ms := []                       ## debug: time of the last swap's steps


func _shuf_dbg() -> bool:
	return Game.args.has("cheatdbg")


## once per battle frame for player 1's fighters (called from f_0202954c). Part 27: in an MP battle also for
## player 2's, with P2's own timer / wait state (_shuf_p2, swapped in around the same code)
func _shuffle_tick(f: int) -> void:
	if _rz.has(f):
		return                                         # part 39 RANDOMIZER: transformed for a super, swaps wait
	if (_ld(f + 0x1A, 1, false) & 1) == 1:
		if f != f_02027c00(1):
			return
		_shuf_p2_swap()
		_shuffle_tick0(f)
		_shuf_p2_swap()
		return
	_shuffle_tick0(f)


func _shuffle_tick0(f: int) -> void:
	if f != f_02027c00(_ld(f + 0x1A, 1, false) & 1):
		return
	var fr: int = _ld(0x020DD4C0, 2, false)
	if fr == _shuf_frame:
		return
	_shuf_frame = fr
	if not _shuf_seeded:
		_shuf_seeded = true
		if Game.args.has("shufseed"):
			_shuf_rng.seed = int(Game.flag("shufseed"))
		else:
			_shuf_rng.randomize()
	if _shuf_t < 0:
		_shuf_t = 0
		_shuf_down = false
	_shuf_t += 1
	var chaos := _on("chaos_shuffle")                  # part 18: CHAOS SHUFFLE wins over CHARACTER SHUFFLE
	if chaos and _ld(BATTLE_STATE, 1, false) != 7:
		_shuf_t = 0                                    # chaos counts from the moment the fight runs (no intro swaps)
		return
	var at := _chaos_at_state() if chaos else -1       # part 19 debug `chaosat=F1,F2`: due at those port frames
	if at == 0 or (at < 0 and _shuf_t < (CHAOS_PERIOD if chaos else SHUF_PERIOD)):
		return
	var why := _chaos_blocked(f) if chaos else _shuffle_blocked(f)
	if why != "":
		if _shuf_dbg() and why != _shuf_wait:
			print("CHT shuffle f%d waits: %s (timer %d)" % [fr, why, _shuf_t])
		_shuf_wait = why
		return
	_shuf_wait = ""
	if at > 0:
		var pf := _port_frame()
		while not _chaos_at.is_empty() and _chaos_at[0] <= pf:
			_chaos_at.pop_front()                      # one swap per due frame passed while waiting
	_shuffle_swap(f, chaos)
	_shuf_t = 0
	_shuf_down = false


## "" = safe to swap now; otherwise why not. Not during KO, hit / attack / guard / super / team art / assist call,
## tag, pause or cut-in, nor while an effect object made from this fighter's chunks is alive (it points into them).
func _shuffle_blocked(f: int) -> String:
	if _ld(f + 0x24A, 2, true) <= 0:
		return "KO"
	var act: int = _ld(f + 6, 1, false)
	if not act in SHUF_SAFE:
		return "action %x" % act
	if (_ld(f + 0x250, 4, false) & 0x900) != 0:
		return "assist call / frozen"
	var g: int = _ld(TEAMS, 4, false)
	if _ld(g + 0x11DC, 4, false) != 0:
		return "tag"
	if f_02012fd4() != 0:
		return "pause / cut-in"
	var o := f_02027bd0(_ld(f + 0x1A, 1, false) & 1)
	if o == 0 or _ld(o + 0x24A, 2, true) <= 0:
		return "opponent KO"
	if not _shuf_down or _ld(f + 0x261, 1, false) != 0:
		f_020297dc(f, 2)                               # what a tag does to the member leaving: power-up off
		_shuf_down = true
	var n := _shuffle_objects(f)
	if n > 0:
		return "%d effect objects" % n
	return ""


## alive effect objects whose chunk copy (+0x44) is this fighter's 'c' or effect chunk (pool 0x020DE3CC, 56 x 0x164)
func _shuffle_objects(f: int) -> int:
	var pool: int = _ld(0x020DE3CC, 4, false)
	var c: int = _ld(f + 0x44, 4, false)
	var e: int = _ld(f + 0x164, 4, false)
	var n := 0
	for i in 56:
		var ob := pool + i * 0x164
		if (_ld(ob + 4, 1, false) & 3) != 0:
			var oc: int = _ld(ob + 0x44, 4, false)
			if oc == c or oc == e:
				n += 1
	return n


func _shuffle_swap(f: int, chaos := false) -> void:
	var old: int = _ld(f + 5, 1, false)
	var n := old
	while n == old:
		n = _shuf_rng.randi_range(0, 25)
	var hp: int = _ld(f + 0x24A, 2, true)
	var mx: int = _ld(f + 0x24C, 2, false)
	var act: int = _ld(f + 6, 1, false)
	var t0 := Time.get_ticks_usec()
	var h0 := _heap_free() if _shuf_dbg() else [0, 0]
	_shuf_loading = true                               # part 18: no VBlank texture / BG uploads while loading
	var killed := _chaos_prepare(f) if chaos else 0     # part 18: end the power-up, kill its effect objects
	var ok := _shuffle_load(f, n)
	if Game.args.has("dmaread"):   # debug (part 24): a card DMA read during the swap, see `_shuf_loading`
		var v0: int = _ld(0x027FFC3C, 4, false)
		var rr := f_020b20f4(3, 0x640800, 0x02780000, 0x26600, 0, 0, 0)
		print("CHT dmaread result %d vblanks during it %d" % [rr, _ld(0x027FFC3C, 4, false) - v0])
	if not ok:
		print("CHT shuffle: loading character %d failed (heap %s); reloading %d" % [n, str(_heap_free()), old])
		n = old
		ok = _shuffle_load(f, old)
	_shuffle_boss(f, n)
	_st(f + 0x24A, 2, hp)                              # the life bar does not move: same HP, same max
	_st(f + 0x24C, 2, mx)
	if chaos:
		_chaos_restart(f, act)                         # part 18: same reaction / movement, attacks end
	else:
		f_02021b4c(f, act)                             # restart the action with the new character's script
	f_02026548(f)                                      # team-art partners for the new member (as on a tag)
	var t1 := Time.get_ticks_usec()
	_shuffle_voices(f)
	var t2 := Time.get_ticks_usec()
	_shuffle_icon(f, n)
	var t3 := Time.get_ticks_usec()
	_shuffle_panel(f)
	_shuf_loading = false
	_shuf_ms = [(t1 - t0) / 1000, (t2 - t1) / 1000, (t3 - t2) / 1000, (Time.get_ticks_usec() - t3) / 1000]
	_shuf_n += 1
	if _shuf_dbg():
		var h1 := _heap_free()
		var m: int = _ld(FS_MGR, 4, false)
		var used := 0
		for i in 48:
			if _ld(m + 0x200 + i * 8 + 4, 4, false) != 0:
				used += 1
		print("CHT shuffle #%d%s f%d: id %d -> %d ok %s act %x->%x killed %d hp %d/%d -> %d/%d c %x eff %x heap free %d/%d -> %d/%d archives %d cache %d voices %s (%d ms: load/voices/icon/panel %s)" % [
			_shuf_n, " chaos" if chaos else "", _ld(0x020DD4C0, 2, false), old, n, ok, act, _ld(f + 6, 1, false), killed, hp, mx, _ld(f + 0x24A, 2, true), _ld(f + 0x24C, 2, false),
			_ld(f + 0x44, 4, false), _ld(f + 0x164, 4, false), h0[0], h0[1], h1[0], h1[1], _ld(m + 0x380, 4, false), used, _shuf_voice_ok,
			(Time.get_ticks_usec() - t0) / 1000, str(_shuf_ms)])
		if chaos:
			var o := f_02027bd0(_ld(f + 0x1A, 1, false) & 1)
			print("CHT chaos swap at port f%d: P1 visible %d +0x250 %x | opponent act %x +0x250 %x visible %d" % [_port_frame(),
				_ld(f + 0x161, 1, false), _ld(f + 0x250, 4, false), _ld(o + 6, 1, false), _ld(o + 0x250, 4, false), _ld(o + 0x161, 1, false)])


## BOSS CHARACTERS + SHUFFLE (part 17): a boss pick that is shuffled stays a boss if the new character has a boss
## version (its boss parameters and boss-only moves); otherwise it is no longer a boss and loses its skull marker
## (before: the skull stayed on the new, normal character's portrait).
func _shuffle_boss(f: int, n: int) -> void:
	for i in battle_bosses.size():
		if battle_bosses[i][0] == f:
			if BOSS_LEVELS.has(n):
				_make_boss(f, BOSS_LEVELS[n])
				battle_bosses[i] = [f, BOSS_LEVELS[n]]
			else:
				battle_bosses.remove_at(i)
			return


## release the record's character data, then load character n into it like FUN_0202A094 (minus the sprite object,
## palette slots and HP, which the record keeps). false = a load failed (out of memory).
func _shuffle_load(f: int, n: int) -> bool:
	for p in [f + 0x44, f + 0x70, f + 0xFC, f + 0x164, f + 0x190, f + 0x21C]:
		_cache_free(_ld(p, 4, false))                  # 'c' chunk, sprite table, palette (main, then effects)
		_st(p, 4, 0)
	_arc_close(f + 0xA8)                               # <id>_img.arc (frames streamed from the card)
	_arc_close(f + 0x1C8)                              # <id>_eff_img.arc (loaded whole)
	_st(f + 0x274, 4, 0x1F)
	_icall(_ld(0x020D78C4 + n * 4, 4, false), f, 0, _ld(f + 0x1A, 1, false), 0x020D78C4)   # per-character init
	_st(f + 0x280, 4, 0x020D7958)
	_st(f + 5, 1, n)
	var ok := f_02020d4c(f + 0x44, n, 0, 3) != 0
	ok = ok and f_02020d0c(f + 0x44, n, 1) != 0
	ok = ok and f_02020d4c(f + 0x164, n + 0x26, f + 0x100, 3) != 0
	ok = ok and f_02020d0c(f + 0x164, n + 0x26, 0) != 0
	if not ok:
		return false
	# palettes into the slots the record already owns (the loader allocated them with FUN_02010B6C)
	var pal: int = _ld(f + 0xFC, 4, false)
	var o := f_02027bd0(_ld(f + 0x1A, 1, false) & 1)
	if (_fiddle_on() and (_ld(f + 0x1A, 1, false) & 1) == 0) or (o != 0 and _ld(o + 5, 1, false) == n and _cache_index(_ld(o + 0xFC, 4, false), true) >= 0):
		pal += 0x100                                   # mirror match (or 2ND FIDDLE, part 21): P1 in P2's colours
		_st(f + 0xFC, 4, pal)
	f_02010ae0(_ld(f + 0x10A, 2, false), pal, 0x100)
	f_02010ae0(_ld(f + 0x22A, 2, false), _ld(f + 0x21C, 4, false), _ld(f + 0x228, 2, false))
	_st(f + 0x24F, 1, _ld(0x020CFCA8 + n, 1, false))
	_st(f + 0x27E, 2, _ld(0x020CFC8C + n, 1, false))
	return true


## index of the file-cache entry holding `p` (unless exact also p - 0x100: a mirror-match palette), -1 if none
func _cache_index(p: int, exact := false) -> int:
	if p == 0:
		return -1
	var t: int = _ld(FS_MGR, 4, false) + 0x200
	for i in 48:
		var d: int = _ld(t + i * 8 + 4, 4, false)
		if d == p or (d == p - 0x100 and not exact):
			return i
	return -1


## what FUN_02005FC4 does for the entry holding p (entries are keyed by an archive handle that is gone by now)
func _cache_free(p: int) -> void:
	var i := _cache_index(p)
	if i < 0:
		return
	var e: int = _ld(FS_MGR, 4, false) + 0x200 + i * 8
	var d: int = _ld(e + 4, 4, false)
	_st(e, 2, 0xFFFF)
	_st(e + 2, 2, 0xFFFF)
	f_020090b0(d)
	_st(e + 4, 4, 0)


## close an archive struct opened with FUN_0200626C. The table holds the FIRST opener's struct (later openers of the
## same path only add a reference). Last reference: free its data and drop the entry (moving the last entry into
## its place; the game's FUN_02005F18 copies the slot past the end instead, which hides the last open archive).
## Otherwise one reference less, and an entry pointing at this struct is moved to another opener's struct.
func _arc_close(s: int) -> void:
	var m: int = _ld(FS_MGR, 4, false)
	var cnt: int = _ld(m + 0x380, 4, false)
	var path := _cstr(s + 0x24)
	if path == "":
		return
	var k := -1
	for i in cnt:
		var st: int = _ld(m + i * 8, 4, false)
		if st != 0 and _cstr(st + 0x24) == path:
			k = i
			break
	if k < 0:
		return
	var refs: int = _ld(m + k * 8 + 4, 4, false) - 1
	if refs <= 0:
		f_020090b0(_ld(s + 0x1C, 4, false))
		_st(m + k * 8, 4, _ld(m + (cnt - 1) * 8, 4, false))
		_st(m + k * 8 + 4, 4, _ld(m + (cnt - 1) * 8 + 4, 4, false))
		_st(m + (cnt - 1) * 8, 4, 0)
		_st(m + (cnt - 1) * 8 + 4, 4, 0)
		_st(m + 0x380, 4, cnt - 1)
	else:
		_st(m + k * 8 + 4, 4, refs)
		if _ld(m + k * 8, 4, false) == s:
			var other := _arc_other(s, path)
			if other != 0:
				_st(m + k * 8, 4, other)
	_st(s + 0x24, 1, 0)


## another fighter record's archive struct (+0xA8 / +0x1C8, both teams) open on the same path
func _arc_other(s: int, path: String) -> int:
	var teams: int = _ld(TEAMS, 4, false)
	for side in 2:
		for k in 3:
			for off in [0xA8, 0x1C8]:
				var t: int = teams + side * 0x8E8 + k * 0x2D8 + off
				if t != s and _cstr(t + 0x24) == path:
					return t
	return 0


func _cstr(a: int) -> String:
	var b := PackedByteArray()
	for i in 0x30:
		var c: int = _ld(a + i, 1, false)
		if c == 0:
			break
		b.append(c)
	return b.get_string_from_ascii()


func _copy(dst: int, src: int, size: int) -> void:
	var d := dst - BASE
	var o := src - BASE
	for i in range(0, size, 8):
		M.encode_s64(d + i, M.decode_s64(o + i))


## voices, as after a tag (tag sequences FUN_02017358 / FUN_02017D68): the sound heap goes back to the level saved before the battle
## loader loaded the active fighters' voices (FUN_02013004), then both active fighters' voice data is loaded again
## (FUN_02029024 steps 0-6, player 1 first)
func _shuffle_voices(f: int) -> void:
	f_02010028(f_02013004())
	var o := f_02027bd0(_ld(f + 0x1A, 1, false) & 1)
	if (_ld(f + 0x1A, 1, false) & 1) == 1 and o != 0:   # part 27: a P2 swap (MP battle): still player 1 first
		var t := f
		f = o
		o = t
	_shuf_voice_ok = ""
	for k in 7:
		_shuf_voice_ok += str(f_02029024(f, k))
	if o != 0:
		_shuf_voice_ok += "/"
		for k in 7:
			_shuf_voice_ok += str(f_02029024(o, k))


## life-bar face icon (sprite rec+0x290, 32x32): new tiles into its VRAM block, new palette into its slot. The data
## is copied to scratch RAM first, so the archive can be closed before the VBlank upload (the loader waits instead).
## Part 28: one buffer per side (P2: +0xE100 / +0xF100). In an MP battle both sides often swap in the same frame;
## with one shared buffer the second swap overwrote the first one's data before the VBlank upload (P1's icon showed
## P2's new face, or a cached-tile icon got the other side's palette until the next swap).
func _shuffle_icon(f: int, n: int) -> void:
	var arc := SHUF_SCRATCH
	if f_0200626c(arc, FACEICON_ARC, 1, 0) == 0:
		return
	var g := f_02006074(arc, n * 2, 0, 0)
	var p := f_02006074(arc, n * 2 + 1, 0, 0)
	if g != 0 and p != 0:
		var buf := SHUF_SCRATCH + 0x100 + (_ld(f + 0x1A, 1, false) & 1) * 0xE000
		_copy(buf, g, mini(_ld(f + 0x290 + 4, 4, false), 0x1000))
		_copy(buf + 0x1000, p, 0x20)
		f_02010fb4(f + 0x290, ((n * 2) & 0xFFFFF) | 0x40000000, buf)
		f_02010ae0(_ld(f + 0x290 + 8, 2, false), buf + 0x1000, 0x20)
	f_02005fc4(arc, n * 2)
	f_02005fc4(arc, n * 2 + 1)
	_arc_close(arc)


## lower screen: the game's own panel builder FUN_0201B78C draws the three portraits from the party block, so it
## runs with the party block showing every member's current character (restored afterwards). Its uploads are copied to scratch RAM and its
## VBlank waits skipped (it reuses one buffer per panel); the panels' palette state (active / greyed / Team Arts)
## and the member <-> panel table (+0xCD8, as FUN_0201CB44 set it) are put back afterwards.
func _shuffle_panel(f: int) -> void:
	var side: int = f_02012fec()
	if side != 0 or _ld(SUBFILES, 1, false) != 0 or (_ld(f + 0x1A, 1, false) & 1) != side:   # (part 27: P2 swap)
		return
	var party := f_020028c8(side)
	var team: int = _ld(TEAMS, 4, false) + side * 0x8E8
	var keep := []
	for k in 3:
		keep.append(_ld(party + k * 4, 4, false))
	for k in _ld(team + 0x8C9, 1, false):              # every panel shows its member's CURRENT character
		var r := team + k * 0x2D8
		var s: int = (_ld(r + 0x2D0, 2, true) - 8) / 0x50
		if s >= 0 and s <= 2:
			_st(party + s * 4, 4, _ld(r + 5, 1, false))
	var bg: int = _ld(BG_MGR, 4, false)
	var saved := []
	for layer in [4, 5, 6]:
		var mp: int = _ld(bg + 0x1AC + layer * 4, 4, false) - BASE
		saved.append(M.slice(mp, mp + 0x800))
	var key := "%d,%d,%d" % [_ld(party, 4, false), _ld(party + 4, 4, false), _ld(party + 8, 4, false)]
	if _panel_cache.has(key):
		_panel_replay(_panel_cache[key], bg)         # part 18: these portraits were built before in this battle
	else:
		_panel_ups = []
		_shuf_panel = true
		f_0201b78c()
		_shuf_panel = false
		_panel_cache[key] = _panel_record(bg)
	for k in 3:
		_st(party + k * 4, 4, keep[k])
	for j in 3:
		var layer: int = 4 + j
		var mp: int = _ld(bg + 0x1AC + layer * 4, 4, false) - BASE
		var a: PackedByteArray = saved[j]
		for i in range(0, 0x800, 2):
			M.encode_u16(mp + i, (M.decode_u16(mp + i) & 0x0FFF) | (a.decode_u16(i) & 0xF000))
		f_02006b68(layer, 0x800)
	var g: int = _ld(0x020DE3BC, 4, false)
	for k in _ld(team + 0x8C9, 1, false):
		var r := team + k * 0x2D8
		var s: int = (_ld(r + 0x2D0, 2, true) - 8) / 0x50
		if s >= 0 and s <= 2:
			_st(g + 0xCD8 + s * 2, 2, _ld(r + 5, 1, false) + k * 0x100)


## FUN_02006E50(layer, chars, size): queue a BG character upload. During the panel redraw: from a scratch copy.
func f_02006e50(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _shuf_panel and param_1 >= 4 and param_1 <= 6 and param_3 <= 0x3800:
		var dst := SHUF_SCRATCH + 0x2000 + (param_1 - 4) * 0x4000
		_copy(dst, param_2, param_3)
		param_2 = dst
		_panel_ups.append([param_1, param_3])
	elif _stg_busy and (param_1 == 2 or param_1 == 3) and param_3 <= 0xC000:   # STAGE SHUFFLE: BG2 / BG3 chars
		_copy(STG_BG_SCRATCH + (param_1 - 2) * 0xC000, param_2, param_3)
		param_2 = STG_BG_SCRATCH + (param_1 - 2) * 0xC000
	return super.f_02006e50(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_0200077E: VBlankIntrWait (BIOS). Skipped during the panel redraw (the uploads read scratch copies).
func f_0200077e(a0: int = 0, a1: int = 0, a2: int = 0, a3: int = 0, a4: int = 0, a5: int = 0, a6: int = 0, a7: int = 0, a8: int = 0, a9: int = 0, a10: int = 0, a11: int = 0) -> int:
	if _shuf_panel or _stg_busy:                       # (STAGE SHUFFLE: the stage loader's waits)
		return a0
	if _lb_at != -1:
		_lb_debug_tick()                               # LEADERBOARD (part 23): debug flag lbreset=F only
	if _setest:
		_se_test()                                     # part 39 debug `setest`: every battle sound in turn
	return super.f_0200077e(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11)


## [total free bytes, largest free block] of the main heap (NNS expanded heap: free list head at +0x24, block
## header 'FR' u16, size u32 at +4, next at +0xC), [-1, -1] if it does not look like one
func _heap_free() -> Array:
	var h: int = _ld(MAIN_HEAP, 4, false)
	if h < 0x02000000 or h >= 0x02800000 or _ld(h, 4, false) != 0x45585048:
		return [-1, -1]
	var b: int = _ld(h + 0x24, 4, false)
	var tot := 0
	var big := 0
	var i := 0
	while b != 0 and i < 4096:
		var s: int = _ld(b + 4, 4, false)
		tot += s
		big = maxi(big, s)
		b = _ld(b + 0xC, 4, false)
		i += 1
	return [tot, big]


# ---- BOSS DASH (part 18) --------------------------------------------------------------------------------------
## The R + direction dash (start action 0x0B FUN_0202C3E8, then action 0x0A FUN_0202C1D4) re-aims every 4th frame;
## with no direction held it sets speed = (s16 blk+0xC * u16 blk+2 * 0x100) >> 16, an int32 product. The level-3
## boss block (+2 = 0x500 speed scale, +0xC = 0x1E00 dash speed) overflows it: 0x96000000 → -27136, a speed of
## 106 px/frame BACKWARDS (and the neutral handler FUN_0202CC70 then "brakes" a negative speed by speeding it up).
## Every other block stays below 0x8000 (level 2: 0x1000 * 0x14C → 0x14C0). The game only gives these blocks to
## CPU fighters. Fix for fighters the BOSS CHARACTERS cheat made bosses: that one speed uses the normal block's
## scale (+2 of block 0), so the boss keeps its own dash speed and the dash behaves like a normal fighter's.
## DATA_NOTES "part 18 findings (dash, attack spam)".
var _dash_dbg := -1                      ## `dashdbg`: per-frame motion trace of both active fighters (-1 = not read yet)


func f_0202c1d4(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats == null or battle_bosses.is_empty() or not _dash_overflows(param_1) or Game.args.has("nodashfix"):
		return super.f_0202c1d4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var held: int = _ld(param_1 + 0x270, 2, false)
	var t: int = _ld(param_1 + 8, 2, false)
	var r := super.f_0202c1d4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if (held & 0x100) != 0 and (t & 3) == 0 and (held & 0xF0) == 0:
		# the handler just set the overflowed speed (no direction held): set it again with the normal scale
		var c: int = _ld(param_1 + 0x44, 4, false)
		var blk: int = _ld(param_1 + 0x50, 4, false)
		var spd: int = mini(_ld(blk + 0xC, 2, true) * _ld(c + _ld(c + 0x10, 4, false) + 2, 2, false) >> 8, 0x7FFF)
		f_020213a8(param_1, spd, 0, spd, _ld(param_1 + 7, 1, false) & 0xE0)
		if _dash_dbg > 0:
			print("DSH fix f%x speed %d (game: %d)" % [param_1, spd, _ld(blk + 0xC, 2, true) * _ld(blk + 2, 2, false) * 0x100 << 32 >> 32 >> 16])
	return r


## true if `f` is a cheat-made boss whose no-direction dash speed does not fit the game's int32 / s16 maths
func _dash_overflows(f: int) -> bool:
	for b in battle_bosses:
		if b[0] == f:
			var blk: int = _ld(f + 0x50, 4, false)
			var v: int = _ld(blk + 0xC, 2, true) * _ld(blk + 2, 2, false) >> 8
			return v > 0x7FFF or v < -0x8000
	return false


func _dash_trace(f: int) -> void:
	if _dash_dbg < 0:
		_dash_dbg = 1 if Game.args.has("dashdbg") else 0
		if _dash_dbg == 0:
			return
	var teams: int = _ld(TEAMS, 4, false)
	var side: int = _ld(f + 0x1A, 1, false)
	if side > 1 or f != teams + side * 0x8E8 + _ld(teams + side * 0x8E8 + 0x8C8, 1, false) * 0x2D8:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var fr: int = tree.current_scene.get("frames") if tree != null and tree.current_scene != null else -1
	print("DSH t%d p%d act %x x %.1f y %.1f vx %d vy %d spd %d max %d acc %d dir %d face %d held %x hp %d f250 %x stun %d vm %d" % [fr, side + 1,
		_ld(f + 6, 1, false), _ld(f + 0x38, 4, true) / 256.0, _ld(f + 0x3C, 4, true) / 256.0, _ld(f + 0x28, 2, true),
		_ld(f + 0x2A, 2, true), _ld(f + 0x22, 2, true), _ld(f + 0x24, 2, true), _ld(f + 0x26, 2, true),
		_ld(f + 0x21, 1, false), _ld(f + 7, 1, false), _ld(f + 0x270, 2, false), _ld(f + 0x24A, 2, true),
		_ld(f + 0x250, 4, false), _ld(f + 0x25E, 2, false), _ld(f + 0x10C, 2, false)])


# ---- ATTACK SPAM (part 18) -------------------------------------------------------------------------------------
## Player 1's physical attacks can be restarted at once and repeated hits connect. What limits them in the game
## (DATA_NOTES part 18): no cooldown timer, but an attack only ends when its script sets u16 [f+0xE] & 1 (long
## recovery: the X dash attack 0x20 lasts ~33 frames), the dispatcher FUN_0202AEB4 only runs in the neutral / move
## handlers, and the melee combo needs the combo window u8 [f+0x257] (12 frames, FUN_02029804 on a hit).
## An attack button (Y / X / A) pressed during one of these attacks ends it like the game does (FUN_0202B630:
## +0x250 = 0, action 0 / 5), so the neutral handler starts the new attack this very frame; Y during a melee hit
## keeps the combo going (+0x257 set). Supers, ultimates, beams, R+B / R+A, Y+B throws (0x2A / 0x2B and the
## character's own throw actions) and team arts are never cut short.
const SPAM_ACTS := [0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x24]
var _spam_frames := {}                   ## fighter -> [action, frames in it]


func _spam_tick(f: int) -> void:
	var act: int = _ld(f + 6, 1, false)
	var st: Array = _spam_frames.get(f, [-1, 0])
	st = [act, 0] if st[0] != act else [act, st[1] + 1]
	_spam_frames[f] = st
	var pressed: int = _ld(f + 0x26C, 2, false)
	if (pressed & 0xC01) == 0 or not act in SPAM_ACTS:
		return
	if _ld(f + 0x24A, 2, true) <= 0 or (_ld(f + 0x250, 4, false) & 0x900) != 0:
		return                                          # KO / assist call / frozen
	if _ld(_ld(TEAMS, 4, false) + 0x11DC, 4, false) != 0 or f_02012fd4() != 0:
		return                                          # tag, pause or cut-in
	if act == 0x24 and (pressed & 0xC00) == 0 and st[1] < 10:
		return                                          # a ki blast before its first shot (frame 9)
	if (pressed & 0x800) != 0 and act >= 0x1C and act <= 0x1F:
		_st(f + 0x257, 1, 0xC)                          # Y during a melee hit: the combo's next hit
	f_0202b630(f)                                       # the game's own attack end (neutral / in the air)
	_spam_frames[f] = [-1, 0]
	if _dash_dbg > 0:
		print("SPAM restart act %x pressed %x -> act %x" % [act, pressed, _ld(f + 6, 1, false)])


## FUN_02027C2C(attacker, victim): the melee / dash-attack hit handler (attack box vs hurt box, FUN_0201E5BC). A
## hit pushes the victim away with FUN_020213A8(victim, header+4 speed, -0x40, 0, attacker's facing) (victim on the
## ground or at a wall, u16 [victim+0xC] & 6: the attacker is pushed back too), so the next attack misses.
## ATTACK SPAM: player 1's hits push both only SPAM_PUSH / 256 as fast (same deceleration: a shorter push).
const SPAM_PUSH := 64


func f_02027c2c(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats == null or not _on("attack_spam") or not _helped(param_1) or _ld(param_2 + 0x10E, 2, false) >= 0x25:
		return super.f_02027c2c(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var hp: int = _ld(param_2 + 0x24A, 2, true)
	var wall: int = _ld(param_2 + 0xC, 2, false) & 6
	var r := super.f_02027c2c(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if _ld(param_2 + 0x24A, 2, true) < hp and (_ld(param_2 + 0x250, 4, false) & 2) != 0:
		var spd: int = _ld(param_2 + 0x22, 2, true)
		if wall != 6:
			_spam_push(param_2)
		if wall != 0:
			_spam_push(param_1)
		if _dash_dbg > 0:
			print("SPAM hit act %x victim act %x hp %d -> %d wall %d push %d -> %d" % [_ld(param_1 + 6, 1, false), _ld(param_2 + 6, 1, false),
				hp, _ld(param_2 + 0x24A, 2, true), wall, spd, _ld(param_2 + 0x22, 2, true)])
	return r


## scales the push FUN_020213A8 just set (speed +0x22, velocity +0x28 / +0x2A; accel +0x30 / +0x32 and the target
## velocity 0 stay), keeping components the hit handler zeroed at a wall
func _spam_push(f: int) -> void:
	for o in [0x22, 0x28, 0x2A]:
		_st(f + o, 2, (_ld(f + o, 2, true) * SPAM_PUSH >> 8) & 0xFFFF)


# ---- STAGE SHUFFLE (part 18) -----------------------------------------------------------------------------------
## Every 600 battle frames the battle moves to another random stage (ids 0-14 = all fifteen Free Battle stages,
## never the current one). The game's own stage loader FUN_0201C150(stage), the first step of the battle init
## FUN_02013D60, runs again mid-battle: stage parameters (globals +0xCBE..+0xCCE), BG2 panorama / BG3 sky from
## game_bg.arc (BG mode, BG3CNT, the HBlank handler of affine skies), the 3D stage FUN_0201AC48 (stg_N.bin objects,
## stg_N_tex.bin textures + palettes, stg_N_scr.bin object scripts, fog). The old stage is released first: its
## texture VRAM blocks (FUN_02010C2C), its texture palette slots (the game never frees one: removed from the slot
## list here), its model and script data (heap), the object script states, fog off. The loader's VBlank waits are
## skipped: its texture file buffer (tail heap) is placed in port-only scratch RAM instead (never freed), and the BG
## characters it queues are queued from scratch copies, so every upload happens at the next VBlank from data that
## is still there (as with the battle's own per-frame uploads). Then the fighters' bounds (FUN_0201B3DC ->
## FUN_02021C68) and a move of both fighters, the effect objects (FUN_02021DD4) and the camera from the old stage's
## centre / ground line to the new one's (clamped on the bounded stages). Music is not touched: the stage BGM is only
## chosen in FUN_02013064 case 4 when the fight starts, and the party block's stage (0x020DD54A) keeps the stage the
## player picked (a rematch starts there, with its music). DATA_NOTES "part 18 findings (stage shuffle)".
const STG_PERIOD := 600                  ## battle frames between swaps
const STG_COUNT := 15                    ## stage ids 0-14 (stage select icons -> ids: table 0x020D0758)
const STG_BLOCK := 0x020DE3A8            ## u32 -> battle stage block (= *0x020DE3BC): +0 model data, +4 object ptrs x16,
										 ## +0x44 object script states 16 x 0x3C, +0x404 texture slots 8 x 0x14 (+0 VRAM
										 ## block, +8 u16 palette slot, +0xA palette size), +0x4B4 script data, +0x550
										 ## object count, +0x554 drawn, +0xCBE stage id, +0xCC0.. stage parameters
const STG_TEX_SCRATCH := 0x02740000      ## port-only RAM: the loader's texture file buffer (stg_N_tex.bin <= 74 KiB)
const STG_BG_SCRATCH := 0x02760000       ## port-only RAM: BG2 / BG3 character copies (<= 0xC000 each)
const STG_TMP := 0x0277F000              ## port-only RAM: small buffers
const VRAM_MGR := 0x020DE380             ## u32 -> texture VRAM / palette manager (+0x7B4 palette slots {u16 start, size})
var _stg_t := -1                         ## battle frames since the last swap (-1: battle not started yet)
var _stg_frame := -1
var _stg_n := 0                          ## swaps this run
var _stg_busy := false                   ## the stage loader runs for a swap
var _stg_wait := ""
var _stg_rng := RandomNumberGenerator.new()
var _stg_seeded := false
var _stg_list: Array = []                ## debug `stglist=a,b,...`: go to these stages in this order
var _stg_vbl := [0, 0]                   ## debug: VBlank uploads skipped during the last swap [all, with DMA3 armed]


## the battle VBlank handler ran while the stage loader waited for a card block (f_0201098C skips its uploads, see
## `_shuf_loading`): the card DMA (channel 3) may still be armed; the queues wait for the next VBlank after the load
func _stage_vbl() -> void:
	_stg_vbl[0] += 1
	if (io_read(0x40000DC, 4) & 0x80000000) != 0:
		_stg_vbl[1] += 1


## once per battle frame for player 1's fighters (called from f_0202954c)
func _stage_tick(f: int) -> void:
	if f != f_02027c00(0):
		return
	var fr: int = _ld(0x020DD4C0, 2, false)
	if fr == _stg_frame:
		return
	_stg_frame = fr
	if not _stg_seeded:
		_stg_seeded = true
		if Game.args.has("stgseed"):
			_stg_rng.seed = int(Game.flag("stgseed"))
		else:
			_stg_rng.randomize()
		if Game.args.has("stglist"):
			for s in str(Game.flag("stglist")).split(","):
				_stg_list.append(int(s))
	if _stg_t < 0:
		_stg_t = 0
	_stg_t += 1
	if _stg_t < STG_PERIOD:
		return
	var why := _stage_blocked()
	if why != "":
		if _shuf_dbg() and why != _stg_wait:
			print("CHT stage f%d waits: %s (timer %d)" % [fr, why, _stg_t])
		_stg_wait = why
		return
	_stg_wait = ""
	_stage_swap()
	_stg_t = 0


## "" = the stage can change now; otherwise why not: only while the fight runs (battle state 7) with both fighters
## alive, not during pause / cut-in, a tag, an assist, a frozen fighter (team arts, assist call), a camera sequence
## (camera mode != 0: supers, team arts) or while the stage is hidden.
func _stage_blocked() -> String:
	var st: int = _ld(0x020DD4C5, 1, false)
	if st != 7:
		return "battle state %d" % st
	if f_02012fd4() != 0:
		return "pause / cut-in"
	var g: int = _ld(TEAMS, 4, false)
	if _ld(g + 0x11DC, 4, false) != 0:
		return "tag"
	if _ld(g + 0x11E0, 4, false) != 0:
		return "assist"
	for p in 2:
		var a := f_02027c00(p)
		if a == 0 or _ld(a + 0x24A, 2, true) <= 0:
			return "KO"
		if (_ld(a + 0x250, 4, false) & 0x900) != 0:
			return "frozen"
	if _ld(_ld(0x020DE3A4, 4, false), 2, false) != 0:
		return "camera mode %d" % _ld(_ld(0x020DE3A4, 4, false), 2, false)
	if _ld(_ld(STG_BLOCK, 4, false) + 0x554, 4, false) == 0:
		return "stage hidden"
	return ""


func _stage_swap() -> void:
	var S: int = _ld(STG_BLOCK, 4, false)
	var old: int = _ld(S + 0xCBE, 1, false)
	var n := old
	if not _stg_list.is_empty():
		n = int(_stg_list.pop_front())
	while n == old or n < 0 or n >= STG_COUNT:
		n = _stg_rng.randi_range(0, STG_COUNT - 1)
	var t0 := Time.get_ticks_usec()
	var dbg := _shuf_dbg()
	var h0 := _heap_free() if dbg else [0, 0]
	var fx: int = _ld(0x020DE3CC, 4, false)
	var ob := [_ld(fx + 0x4DE8, 2, true), _ld(fx + 0x4DEA, 2, true), _ld(fx + 0x4DEC, 2, true), _ld(fx + 0x4DEE, 2, true)]
	var bgm: int = _ld(0x020DE2A0 + 0xA8, 4, false)
	# BG0 (3D) / BG1 offsets: the loader zeroes BG0-3 (BG2 / BG3 are set again every frame from the camera)
	var bgm_mgr: int = _ld(BG_MGR, 4, false)
	var scroll := []
	for layer in 2:
		scroll.append([_ld(bgm_mgr + 0x18C + layer * 4, 2, false), _ld(bgm_mgr + 0x18E + layer * 4, 2, false)])
	var drawn: int = _ld(S + 0x554, 4, false)
	var io0 := IO.slice(0, 0x380)                      # part 28: display registers before the swap (_stage_regs_defer)
	_stage_unload(S)
	_stg_vbl = [0, 0]
	_stg_busy = true                                   # also: no VBlank texture / BG uploads (card DMA 3, see `_shuf_loading`)
	var ok := f_0201c150(n) != 0
	if not ok:                                         # (a file failed to load / no memory): back to the old stage
		print("CHT stage: loading stage %d failed (heap %s); reloading %d" % [n, str(_heap_free()), old])
		_stage_unload(S)
		n = old
		ok = f_0201c150(old) != 0
	_stg_busy = false
	_st(S + 0x554, 4, drawn)
	for layer in 2:
		f_020069f8(layer, scroll[layer][0], scroll[layer][1])
	f_0201b3dc(STG_TMP, STG_TMP + 0x10)               # fighter bounds of the new stage (as the battle init does)
	f_02021c68(STG_TMP, _ld(STG_TMP + 0x10, 1, false))
	var nb := [_ld(fx + 0x4DE8, 2, true), _ld(fx + 0x4DEA, 2, true), _ld(fx + 0x4DEC, 2, true), _ld(fx + 0x4DEE, 2, true)]
	var mv := _stage_move(ob, nb, (_ld(fx + 0x4DE7, 1, false) & 1) != 0)
	_stage_regs_defer(io0)                             # part 28: new BG mode / BG3CNT / fog with the new data, not before
	_stg_n += 1
	if dbg:
		var h1 := _heap_free()
		var V: int = _ld(VRAM_MGR, 4, false)
		var tex := ""
		for i in 8:
			var sl := S + 0x404 + i * 0x14
			if _ld(sl, 4, false) != 0:
				var b: int = _ld(sl, 4, false)
				tex += " %x+%x/p%x+%x" % [_ld(b, 4, false), _ld(b + 4, 4, false), _ld(sl + 8, 2, false), _ld(sl + 0xA, 2, false)]
		var pos := []
		for p in 2:
			pos.append([_ld(f_02027c00(p) + 0x38, 4, true) >> 8, _ld(f_02027c00(p) + 0x3C, 4, true) >> 8])
		print("CHT stage #%d port f%d f%d: %d -> %d ok %s objects %d bounds %s -> %s flag %d move %s now at %s bgm" % [_stg_n,
			int((Engine.get_main_loop() as SceneTree).current_scene.get("frames")), _ld(0x020DD4C0, 2, false), old, n, ok,
			_ld(S + 0x550, 4, false), str(ob), str(nb), _ld(fx + 0x4DE7, 1, false), str(mv), str(pos)])
		print("CHT stage #%d bgm %d -> %d heap free %d/%d -> %d/%d vram blocks %d palettes %d tex%s (%d ms) vblanks skipped %s queues tex/pal/bg %d/%d/%d" % [
			_stg_n, bgm, _ld(0x020DE2A0 + 0xA8, 4, false), h0[0], h0[1], h1[0], h1[1], _ld(V + 0x7AE, 1, false),
			_ld(V + 0x8B8, 1, false), tex, (Time.get_ticks_usec() - t0) / 1000, str(_stg_vbl), _ld(V + 0x7AC, 1, false),
			_ld(V + 0x7AD, 1, false), _ld(_ld(BG_MGR, 4, false) + 0x180, 1, false)])


## release what FUN_0201AC48 loaded for the current stage, leaving the block as FUN_0201B0A4 (scene init) left it
func _stage_unload(S: int) -> void:
	for i in 8:
		var sl := S + 0x404 + i * 0x14
		if _ld(sl, 4, false) != 0:
			f_02010c2c(sl)                             # texture VRAM block (refs 1: removed from the block list)
		if _ld(sl + 0xA, 2, false) != 0:
			_pal_free(_ld(sl + 8, 2, false), _ld(sl + 0xA, 2, false))
		for k in range(0, 0x14, 4):
			_st(sl + k, 4, 0)
	for p in [S, S + 0x4B4]:                           # model (objects + display lists), object scripts
		if _ld(p, 4, false) != 0:
			f_020090b0(_ld(p, 4, false))
		_st(p, 4, 0)
	for i in 16:
		_st(S + 4 + i * 4, 4, 0)
		var e := S + 0x44 + i * 0x3C
		for k in range(0, 0x3C, 4):
			_st(e + k, 4, 0)
		_st(e + 0xA, 2, 1)                             # object visible (FUN_0201B0A4)
	_st(S + 0x550, 4, 0)
	f_020a6e00(0, 0, 0, 0)                             # fog off (the loader turns it on for stages that use it)


## free a texture palette slot: FUN_0201079C keeps {u16 start, u16 size} sorted at manager +0x7B4 (count u8 +0x8B8,
## unused entries 0xFFFF / 0) and the game only resets the list with the scene
func _pal_free(start: int, size: int) -> void:
	var V: int = _ld(VRAM_MGR, 4, false)
	var cnt: int = _ld(V + 0x8B8, 1, false)
	for j in cnt:
		var e := V + 0x7B4 + j * 4
		if _ld(e, 2, false) == start and _ld(e + 2, 2, false) == size:
			for k in range(j, cnt - 1):
				_st(V + 0x7B4 + k * 4, 4, _ld(V + 0x7B4 + (k + 1) * 4, 4, false))
			_st(V + 0x7B4 + (cnt - 1) * 4, 2, 0xFFFF)
			_st(V + 0x7B6 + (cnt - 1) * 4, 2, 0)
			_st(V + 0x8B8, 1, cnt - 1)
			return


## Part 28 (QA): the loader writes the display registers at once (FUN_020A5224 BG mode, BG3CNT, DISPSTAT HBlank bit
## FUN_020A535C, fog / DISP3DCNT) but its BG characters / maps / palettes and textures only reach VRAM at the next VBlank
## (queues); the picture drawn after the swap frame showed the new BG mode over the old stage's VRAM: one frame of a
## garbled sky (purple checkers / rays, V /tmp/ssw2/q28/g2 p4333). The swap's register changes (changed bits only) are
## put back and applied by the battle VBlank handler right after its BG uploads (f_02006518), so the picture changes in
## one step: the old stage complete, then the new one complete.
const STG_REG_SPANS := [[0x000, 0x004], [0x004, 0x005], [0x008, 0x010], [0x060, 0x064], [0x330, 0x380]]
var _stg_regs: Array = []                ## [IO offset, new bits, changed-bit mask], applied at the next VBlank


func _stage_regs_defer(io0: PackedByteArray) -> void:
	_stg_regs.clear()
	for sp in STG_REG_SPANS:
		for o in range(sp[0], sp[1]):
			var m: int = (io0[o] ^ IO[o]) & (0x10 if o == 4 else 0xFF)   # DISPSTAT: only the HBlank IRQ bit
			if m != 0:
				_stg_regs.append([o, IO[o] & m, m])
				IO.encode_u8(o, (IO[o] & ~m & 0xFF) | (io0[o] & m))
	if _shuf_dbg():
		print("CHT stage registers deferred to the VBlank: %s" % str(_stg_regs.map(func(e): return "%x:%x/%x" % e)))


## from f_02006518 (battle VBlank handler), after its uploads: once the BG queue is empty, the new registers
func _stage_regs_apply() -> void:
	if _ld(_ld(BG_MGR, 4, false) + 0x180, 1, false) != 0:
		return                                         # the BG uploads did not run this VBlank: wait for them
	for e in _stg_regs:
		IO.encode_u8(e[0], (IO[e[0]] & ~e[2] & 0xFF) | e[1])
	_stg_regs.clear()


## move both active fighters, the effect objects and the camera from the old bounds' centre / ground line (bottom)
## to the new ones'; on a bounded stage (flag bit 0) both fighters are then kept inside it. Returns [dx, dy] in px.
func _stage_move(ob: Array, nb: Array, bounded: bool) -> Array:
	var dx: int = ((nb[0] + nb[2]) >> 1) - ((ob[0] + ob[2]) >> 1)
	var dy: int = nb[3] - ob[3]
	var fs := [f_02027c00(0), f_02027c00(1)]
	if bounded:
		var lo: int = mini(_ld(fs[0] + 0x38, 4, true), _ld(fs[1] + 0x38, 4, true)) + (dx << 8)
		var hi: int = maxi(_ld(fs[0] + 0x38, 4, true), _ld(fs[1] + 0x38, 4, true)) + (dx << 8)
		if lo < nb[0] << 8:
			dx += ((nb[0] << 8) - lo + 255) >> 8
		elif hi > nb[2] << 8:
			dx -= (hi - (nb[2] << 8) + 255) >> 8
	for f in fs:
		var x: int = _ld(f + 0x38, 4, true) + (dx << 8)
		var y: int = _ld(f + 0x3C, 4, true) + (dy << 8)
		if bounded:
			x = clampi(x, nb[0] << 8, nb[2] << 8)
		y = maxi(y, nb[1] << 8)
		_st(f + 0x38, 4, x)
		_st(f + 0x3C, 4, y)
	f_02021dd4(dx << 8, dy << 8)                       # effect objects (what the stage wrap-around does)
	var cam: int = _ld(0x020DE3A4, 4, false)
	for k in [0xC, 0x14, 0x1C]:
		_st(cam + k, 4, _ld(cam + k, 4, true) + dx)
		_st(cam + k + 4, 4, _ld(cam + k + 4, 4, true) + dy)
	return [dx, dy]


## FUN_020090E4(size): heap allocation from the tail. During a swap the loader's texture file buffer goes to scratch RAM.
func f_020090e4(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _stg_busy and param_1 > 0 and param_1 <= 0x20000:
		return STG_TEX_SCRATCH
	return super.f_020090e4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_020090B0(p): heap free. The scratch texture buffer is not a heap block.
func f_020090b0(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _stg_busy and param_1 == STG_TEX_SCRATCH:
		return 0
	return super.f_020090b0(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


# ---- CHAOS SHUFFLE (part 18) -----------------------------------------------------------------------------------
## CHARACTER SHUFFLE every second, forced: the same swap (`_shuffle_swap(f, true)`), but it does not wait for a calm
## moment. It waits only while player 1 is in a super (charge 0x2C / fire 0x2D / ultimate 0x2E), a super / team-art
## sequence runs (camera mode != 0, cut-in / pause FUN_02012FD4, P1 frozen +0x250 & 0x800), a tag runs, or a fighter
## is KO; then it swaps the moment that ends. At the swap the old character's power-up ends (FUN_020297DC mode 2)
## and every effect object made from its chunks is killed the game's way (+4 = 2: the effect loop FUN_02021F54 then
## frees it with FUN_02021D90 without running it, as FUN_0202104C does). Generic reactions / movement (action ids
## < 0x19 and the shared 0x34-0x66 states: hit stun, knock-back, guard, dash, charge, being thrown) restart with the
## new character's script and keep velocity / stun; attacks, power-up, call pose, throws and character-specific
## actions (>= 0x85, handlers of rec+0x284) end like the game ends an attack (FUN_0202B630: neutral / in the air).
## When both shuffle cheats are on, this one wins (one timer). DATA_NOTES "part 18 findings (chaos shuffle, triple ki)".
const CHAOS_PERIOD := 60                 ## battle frames between forced swaps
const CHAOS_SUPER := [0x2C, 0x2D, 0x2E]
const CAMERA := 0x020DE3A4               ## u32 -> camera: u16 +0 mode (0 normal, 2 super, 4 team arts)
const BATTLE_STATE := 0x020DD4C5         ## u8 battle scene state (FUN_020010E4): 7 = the fight runs


## Lower-screen panels cache (CHAOS swaps every second; FUN_0201B78C decompresses all three portraits, ~26 ms here):
## after a redraw the queued character uploads (layer, bytes), the three map buffers and globals +0xCE0..+0xCE3 are
## kept per party-id triple; the same triple later is put back from the copies (same uploads, same maps).
var _panel_cache := {}
var _panel_ups := []


func _panel_record(bg: int) -> Dictionary:
	var ups := []
	for u in _panel_ups:
		var src: int = SHUF_SCRATCH + 0x2000 + (u[0] - 4) * 0x4000 - BASE
		ups.append([u[0], u[1], M.slice(src, src + u[1])])
	var maps := []
	for layer in [4, 5, 6]:
		var mp: int = _ld(bg + 0x1AC + layer * 4, 4, false) - BASE
		maps.append(M.slice(mp, mp + 0x800))
	var g: int = _ld(0x020DE3BC, 4, false) - BASE
	return {"ups": ups, "maps": maps, "sel": M.slice(g + 0xCE0, g + 0xCE4)}


func _panel_replay(c: Dictionary, bg: int) -> void:
	for u in c["ups"]:
		var dst: int = SHUF_SCRATCH + 0x2000 + (u[0] - 4) * 0x4000
		_put(dst, u[2])
		f_02006e50(u[0], dst, u[1])
	for j in 3:
		_put(_ld(bg + 0x1AC + (4 + j) * 4, 4, false), c["maps"][j])
	_put(_ld(0x020DE3BC, 4, false) + 0xCE0, c["sel"])


func _put(a: int, b: PackedByteArray) -> void:
	var o := a - BASE
	for i in range(0, b.size() & ~7, 8):
		M.encode_s64(o + i, b.decode_s64(i))
	for i in range(b.size() & ~7, b.size()):
		M.encode_u8(o + i, b[i])


## Card reads during a swap (the 'c' chunks, image archives, voices, portraits) run in many card blocks; the port
## delivers the VBlank IRQ while the thread waits for a block, with the card DMA (channel 3, mode 5, repeat) still
## armed. The battle VBlank handler FUN_02013030 then uploads queued textures (FUN_0201098C) and BG data
## (FUN_02006518) with DMA 3 and waits for the channel to be free: the game froze (port, chaos run, 16th swap:
## "busy-wait on 040000dc", DMA3CNT 0xAF000001 from 0x04100010). While a character swap runs, these two runners
## skip that VBlank; the queues are kept and uploaded at the next VBlank after the load.
## Part 24: not a port timing bug. The card DMA is a repeat DMA (enable stays set after each block, melonDS
## DMA.cpp too) that only the card IRQ handler stops (MI_StopDma), and the waiting VBlank handler blocks that IRQ:
## a DS hangs the same way. The original never reads the card by DMA while these queues run; the swaps do, so the
## skip is the fix. Only reads with ROM offset, length and destination aligned use DMA (ROM: only ghn_img.arc
## whole), so it is rare. Debug: `noloadskip` turns the skip off, `dmaread` adds an aligned 0x26600-byte DMA read
## (ghn_img.arc into 0x02780000) to every character swap: with both → freeze at the first swap; `dmaread` alone runs.
var _shuf_loading := false


func f_0201098c(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if (_shuf_loading or _stg_busy) and not Game.args.has("noloadskip"):   # (STAGE SHUFFLE: its loader's card reads too)
		if _stg_busy:
			_stage_vbl()
		return 0
	return super.f_0201098c(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


func f_02006518(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if (_shuf_loading or _stg_busy) and not Game.args.has("noloadskip"):
		return 0
	if not _stg_regs.is_empty():                       # part 28: a stage swap's registers follow its BG uploads
		var r := super.f_02006518(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_stage_regs_apply()
		return r
	return super.f_02006518(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


func _chaos_blocked(f: int) -> String:
	if _ld(f + 0x24A, 2, true) <= 0:
		return "KO"
	var o := f_02027bd0(_ld(f + 0x1A, 1, false) & 1)
	if o == 0 or _ld(o + 0x24A, 2, true) <= 0:
		return "opponent KO"
	if _ld(f + 6, 1, false) in CHAOS_SUPER:
		return "super %x" % _ld(f + 6, 1, false)
	if f_02012fd4() != 0:
		return "pause / cut-in"
	if _ld(_ld(TEAMS, 4, false) + 0x11DC, 4, false) != 0:
		return "tag"
	if (_ld(f + 0x250, 4, false) & 0x800) != 0:
		return "frozen"
	var cam: int = _ld(CAMERA, 4, false)
	if cam != 0 and _ld(cam, 2, false) != 0:
		return "camera mode %d" % _ld(cam, 2, false)
	return _chaos_held(f, o)


## before the old character's data is released: power-up off, its effect objects killed. Returns how many.
func _chaos_prepare(f: int) -> int:
	f_020297dc(f, 2)
	var pool: int = _ld(0x020DE3CC, 4, false)
	var c: int = _ld(f + 0x44, 4, false)
	var e: int = _ld(f + 0x164, 4, false)
	var n := 0
	for i in 56:
		var ob := pool + i * 0x164
		if (_ld(ob + 4, 1, false) & 1) != 0:
			var oc: int = _ld(ob + 0x44, 4, false)
			if oc == c or oc == e:
				_st(ob + 4, 1, 2)
				n += 1
	return n


## a reaction restarted at the last swap and still running is ended instead (its new animation would start over
## every second and never finish: e.g. 0x34, ~240 frames); neutral / move (0-6) always continue
var _chaos_again := -1


func _chaos_restart(f: int, act: int) -> void:
	var generic := act < 0x19 or (act >= 0x34 and act <= 0x66 and act != 0x52)
	if generic and act < _ld(f + 0x110, 2, false) and (act <= 6 or act != _chaos_again):
		f_02021b4c(f, act)
		_chaos_again = act
	else:
		f_0202b630(f)
		_chaos_again = -1


# ---- TRIPLE KI BLASTS (part 18) --------------------------------------------------------------------------------
## Every plain projectile player 1's fighters fire (effect objects whose per-frame handler is FUN_020209E0: ki blasts,
## and any special move made of plain projectiles; beams use FUN_02020330 / 0x020203CC / 0x02020560 and are not
## touched; assists' projectiles neither) becomes three. The fighter's script spawns a shot with VM op 7:
## FUN_020225C8(fighter, kind, rec+0x164, rec+0x244 kind table) + FUN_0202216C(obj, script, position). At the shot's
## first handler call (FUN_020209E0 sub-state 0, before its own script has set its motion) two more objects are
## spawned with the same arguments (the game's allocation, pool count and sprite set-up) and given the shot's state
## (bytes 0-0x123: script, position, flags, hit handler; each keeps its own sprite struct +0x124); after the handler
## has taken the owner's facing (+7, FUN_02011F74 sprite rotation) the copies turn by +-TRI_SPREAD, so the script's
## FUN_020213A8(obj, speed, accel, max, +7) sends them fanned out. A full pool (48) skips copies.
const TRI_SPREAD := 9                    ## direction steps of 256 (about 12.7 degrees)
const PLAIN_SHOT := 0x020209E0
var _tri_new := {}                       ## shot object -> [kind, chunk, kind table] (spawned this frame, not run yet)
var _tri_turn := {}                      ## copy object -> direction offset (applied at its first handler call)
var _tri_busy := false


## FUN_020225C8(owner, kind, chunk struct, kind table, slot): spawn an effect object
func f_020225c8(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, param_5: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mp_end != 0:                                   # part 27 MP QA: the battle-end banner of an MP battle
		param_2 = _mp_end_kind(param_2)
	var r := super.f_020225c8(param_1, param_2, param_3, param_4, param_5, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if r != 0 and not _rc.is_empty():
		_rc.erase(r)                                   # part 40 RICOCHET KI: a new object in that slot
	if r != 0 and cheats != null and _on("chaos_shuffle"):
		_chaos_spawned(param_1, r)                     # part 19: objects of supers / throws / summons
	if r != 0 and cheats != null and not _tri_busy and _on("triple_ki") and param_1 != 0 and param_4 != 0 \
			and _helped(param_1) and _ld(param_1 + 0x10E, 2, false) < 0x1A \
			and _ld(param_4 + param_2 * 8, 4, false) == PLAIN_SHOT:
		_tri_new[r] = [param_2, param_3, param_4]
	return r


## called from f_020209e0 before the handler: a new P1 shot gets its two copies
func _tri_before(o: int) -> void:
	if not _tri_new.has(o):
		return
	var a: Array = _tri_new[o]
	_tri_new.erase(o)
	if _ld(o + 8, 2, false) != 0 or _ld(o + 6, 1, false) != a[0] or _ld(o + 0x40, 4, false) != a[2]:
		return                                          # not the object that was spawned (freed and reused)
	_tri_busy = true
	for d in [TRI_SPREAD, -TRI_SPREAD]:
		var c := f_020225c8(_ld(o, 4, false), a[0], a[1], a[2], 0)
		if c == 0:
			break                                       # pool full
		var b := c - BASE
		var s := o - BASE
		for i in range(8, 0x124, 4):                    # +0..+7 (owner, status, kind) are the same already
			M.encode_u32(b + i, M.decode_u32(s + i))
		_tri_turn[c] = d
	_tri_busy = false
	if _shuf_dbg():
		print("CHT triple shot %x kind %d copies %s" % [o, a[0], str(_tri_turn.keys())])


## called from f_020209e0 after the handler: a copy's facing turns once the handler has set it from the owner
func _tri_after(o: int) -> void:
	if not _tri_turn.has(o):
		return
	var d: int = _tri_turn[o]
	_tri_turn.erase(o)
	var fa: int = (_ld(o + 7, 1, false) + d) & 0xFF
	_st(o + 7, 1, fa)
	if (_ld(o + 0xE, 2, false) & 0x80) == 0:
		f_02011f74(o + 0x124, 0, 0, (0x100 - fa) & 0xFF)



# ---- DETAILED SHADOWS (part 19) ---------------------------------------------------------------------------------
## Setting DETAILED SHADOWS (QoLSettings.detailed_shadows, flag `shadows=1`). Battle sprites are orthographic 3D quads
## drawn from the sprite draw list by FUN_02011384 (DATA_NOTES part 19). The ground shadow is a 64x32 ellipse sprite
## per team (team block +0x888) that FUN_0202A254 registers for the ACTIVE member while it is less than 256 px above
## the ground line and record +0x161 != 0. With the setting on, the ellipses are taken out of the list while the
## drawer runs, and each one is replaced by a black copy of its fighter's quad (same texture = the same animation
## frame, same flip / rotation / scale), anchored at the ellipse centre by the fighter's feet, mirrored downward,
## squashed and sheared like a shadow cast toward the viewer. Drawn after the list (z of the ellipse: behind every
## sprite), so the polygon numbering stays stable for smooth motion. Supports and ASSIST SPAM copies on screen get
## one too, by the same rule the game uses for the active members (their ellipse does not exist in the original).
const SPR_LIST := 0x020DE384          ## u32 -> sprite draw list: u32[64] sprite objects, u8 count +0x183, scale +0x184
const SHADOW_SPR := 0x888             ## team block +0x888: the team's shadow sprite object (0x40 bytes)
const SHADOW_XOFF := 0x020CFCC4       ## s8[character id]: shadow x offset (negated when record +0x12 bit 0)
const SHADOW_FEET := 0x020CFCA8       ## u8[character id]: feet below the sprite centre (also record +0x24F)
const SPR_ROT := 0x020D0F5C           ## s16 (sin, cos) pairs, index = sprite +0x38 >> 4
const SIL_HIDDEN := 0x02720000        ## port-only RAM: an empty sprite object (not drawn) put in place of an ellipse
var _sil_k := float(Game.flag("shadowk", "0.35"))   ## vertical squash (debug flags shadowk / shadowc / shadowflip)
var _sil_c := float(Game.flag("shadowc", "0.3"))    ## shear: x shift per px of shadow length
var _sil_flip := Game.flag("shadowflip", "1") != "0"   ## 1: cast toward the viewer (head down), 0: upright
var _sil_dbg := Game.args.has("shadowdbg")


## FUN_02011384: draw the sprite list (3D quads), then clear it
func f_02011384(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats == null or not (cheats.detailed_shadows or _fx_any()):
		return super.f_02011384(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if not cheats.detailed_shadows:                   # part 22 BLOOD / AFTERIMAGES only
		var fx: Variant = _fx_before()
		var r0 := super.f_02011384(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_fx_draw(fx)
		return r0
	var fxs: Variant = _fx_before()
	var lst: int = _ld(SPR_LIST, 4, false)
	var n: int = _ld(lst + 0x183, 1, false)
	var sil: Array = []                  # [fighter sprite, shadow x, shadow y, z]
	var hidden: Array = []               # [list slot, pointer]
	if n > 0:
		var idx := {}
		for i in n:
			idx[_ld(lst + i * 4, 4, false)] = i
		var teams: int = _ld(TEAMS, 4, false)
		var done := {}
		var battle := false
		for side in 2:
			var tb := teams + side * 0x8E8
			var sh := tb + SHADOW_SPR
			var rec := tb + _ld(tb + 0x8C8, 1, false) * 0x2D8
			done[rec] = true
			if idx.has(rec + 0x124):
				battle = true                   # a team's active fighter is drawn: battle scene
			if not idx.has(sh):
				continue
			var i: int = idx[sh]
			hidden.append([i, sh])
			if idx.has(rec + 0x124):
				sil.append([rec + 0x124, _ld(sh + 0x1C, 2, true), _ld(sh + 0x1E, 2, true), _ld(sh + 0x3C, 1, false)])
		if battle:
			# the other fighter records drawn this frame (supports, ASSIST SPAM copies): the game's rule
			var recs: Array = []
			for side in 2:
				for k in 3:
					recs.append(teams + side * 0x8E8 + k * 0x2D8)
			recs.append_array(_clones)
			# the same reads as FUN_0202A254: ground line FUN_0201B488, camera FUN_0201301C (+6 zoom)
			var ground: int = _ld(_ld(_ld(0x0201B49C, 4, false), 4, false) + 0xCC2, 2, false)
			var zoom: int = _ld(_ld(_ld(0x0201302C, 4, false), 4, false) + 900 + 6, 2, false)
			for rec in recs:
				if done.has(rec) or not idx.has(rec + 0x124):
					continue
				done[rec] = true
				var h: int = ground - (_ld(rec + 0x3C, 4, true) >> 8)
				if _sil_dbg:
					print("SIL other %x id %d height %d +161 %d +12 %x" % [rec, _ld(rec + 5, 1, false), h, _ld(rec + 0x161, 1, false), _ld(rec + 0x12, 2, false)])
				if h >= 0x100 or _ld(rec + 0x161, 1, false) == 0 or (_ld(rec + 0x12, 2, false) & 8) != 0:
					continue                            # (+0x12 bit 3: drawn in screen coordinates, no ground)
				var id: int = _ld(rec + 5, 1, false)
				var xo: int = _ld(SHADOW_XOFF + id, 1, true)
				if (_ld(rec + 0x12, 2, false) & 1) != 0:
					xo = -xo
				var ft: int = _ld(SHADOW_FEET + id, 1, false)
				var spr: int = rec + 0x124
				sil.append([spr, _ld(spr + 0x1C, 2, true) + xo, _ld(spr + 0x1E, 2, true) + _zm_drop(h + ft, zoom) + ((zoom * (0x40 - ft)) >> 8), 1])
		for hd in hidden:
			_st(lst + hd[0] * 4, 4, SIL_HIDDEN)
		if not hidden.is_empty():
			for o in range(0, 0x40, 4):
				_st(SIL_HIDDEN + o, 4, 0)
	var r := super.f_02011384(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	for hd in hidden:
		_st(lst + hd[0] * 4, 4, hd[1])
	if not sil.is_empty():
		var g: int = _ld(lst + 0x184, 4, true)
		for s in sil:
			_sil_draw(s[0], s[1], s[2], s[3], g)
		io_write(0x4000480, 4, 0x7FFF)              # vertex colour back to white (what DIF_AMB left)
	_fx_draw(fxs)
	return r


## one black silhouette of sprite object `p` (a fighter's body quad) with its feet on (sx, sy)
func _sil_draw(p: int, sx: int, sy: int, z: int, g: int) -> void:
	if _ld(p + 0x3D, 1, false) == 0 or _ld(p + 0x3B, 1, false) <= 7 or _ld(p, 4, false) == 0:
		return                                          # the fighter itself is not drawn
	if sx < -256 or sx > 512 or sy < -64 or sy > 320:
		return                                          # far off screen (the shadow never reaches the picture)
	var fl: int = _ld(p + 0x3E, 2, false)
	var sw := float(_ld(p + 0x14, 4, true))
	var shh := float(_ld(p + 0x18, 4, true))
	if (fl & 8) == 0:
		sw = float((g * int(sw)) >> 8)
		shh = float((g * int(shh)) >> 8)
	sw /= 4096.0
	shh /= 4096.0                                       # drawn quad size in px
	var ri: int = _ld(p + 0x38, 2, false) >> 4
	var sn := _ld(SPR_ROT + ri * 4, 2, true) / 4096.0
	var cs := _ld(SPR_ROT + ri * 4 + 2, 2, true) / 4096.0
	# fighter: screen = F + R.S.v (v = quad corner +-0.5); feet anchor a = (sx - Fx, feet row) in the same frame
	var fx: int = _ld(p + 0x1C, 2, true)
	var ax := float(sx - fx)
	var ay := float(_ld(SHADOW_FEET + _ld(p - 0x124 + 5, 1, false), 1, false)) * shh / 128.0
	# shadow map Q: d = (dx, dy) from the feet -> (dx - c.k.dy, -k.dy) (flipped) or (dx + c.k.dy, k.dy)
	var k := _sil_k
	var q01 := -_sil_c * k
	var q11 := -k
	if not _sil_flip:
		q01 = _sil_c * k
		q11 = k
	# A = Q.R.S, t = (sx, sy) - Q.a
	var rs00 := cs * sw
	var rs01 := -sn * shh
	var rs10 := sn * sw
	var rs11 := cs * shh
	var a00 := rs00 + q01 * rs10
	var a01 := rs01 + q01 * rs11
	var a10 := q11 * rs10
	var a11 := q11 * rs11
	var tx := sx - (ax + q01 * ay)
	var ty := sy - q11 * ay
	var m := [a00, a10, 0.0, a01, a11, 0.0, 0.0, 0.0, 1.0, tx, ty, float(z)]
	var al: int = _ld(p + 0x3B, 1, false) >> 3
	# POLYGON_ATTR as the drawer (modulation), plus back faces: the mirrored quad turns its back to the camera;
	# COLOR black: texel x black = black, colour 0 stays clear
	_spr_emit(p, m, 0x80C0 | ((0x20 - al) << 24) | (al << 16), 0)
	if _sil_dbg:
		print("SIL f%d spr %x shadow %d,%d quad %.0fx%.0f rot %d flags %x alpha %d" % [_ld(0x020DD4C0, 2, false), p, sx, sy, sw, shh, ri, fl, al])


## sprite object p's own textured quad (texture, palette, texcoord flip, texture matrix as FUN_02011384 sets them)
## under the position matrix m (MTX_MULT_4x3 rows), with POLYGON_ATTR `attr` and vertex colour `col`
func _spr_emit(p: int, m: Array, attr: int, col: int, pal: int = -1) -> void:
	var fl: int = _ld(p + 0x3E, 2, false)
	io_write(0x4000440, 4, 2)                         # MTX_MODE position
	io_write(0x4000444, 4, 0)                         # MTX_PUSH
	for v in m:
		io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)   # MTX_MULT_4x3
	io_write(0x4000440, 4, 3)                         # texture matrix as the drawer sets it
	io_write(0x4000454, 4, 0)
	if (fl & 0x30) != 0:
		var w5: int = _ld(p + 0x14, 4, true)
		io_write(0x400046C, 4, ((w5 + ((w5 >> 16 & 0xFFFF) >> 15)) >> 17) << 12)
		io_write(0x400046C, 4, 0x1000)
		io_write(0x400046C, 4, 0x1000)
	io_write(0x4000440, 4, 2)
	var fmt: int = _ld(p + 0xC, 4, true)
	var tp: int = (_ld(_ld(p, 4, false), 4, false) >> 3) | (fmt << 26) | 0x40000000 | (_ld(p + 0x10, 1, false) << 20) \
		| (_ld(p + 0x11, 1, false) << 23) | (0x20070000 if (fl & 0x20) != 0 else 0x20030000)
	io_write(0x40004A8, 4, tp & 0xFFFFFFFF)          # TEXIMAGE_PARAM: the fighter's own texture
	io_write(0x40004AC, 4, (_ld(p + 8, 2, false) if pal < 0 else pal) >> (3 if fmt == 2 else 4))   # (part 39: another palette)
	io_write(0x40004A4, 4, attr)
	io_write(0x4000480, 4, col)
	io_write(0x4000500, 4, 1)                         # BEGIN quads
	var u0: int = ((_ld(p + 0x20, 4, true) << 8) >> 16) & 0xFFFF
	var v0: int = ((_ld(p + 0x24, 4, true) << 8) >> 16) & 0xFFFF
	var u1: int = ((_ld(p + 0x28, 4, true) << 8) >> 16) & 0xFFFF
	var v1: int = ((_ld(p + 0x2C, 4, true) << 8) >> 16) & 0xFFFF
	var flip: int = fl & 3
	if (flip & 1) != 0:
		var t := u0
		u0 = u1
		u1 = t
	if (flip & 2) != 0:
		var t2 := v0
		v0 = v1
		v1 = t2
	for c in [[u0, v0, 0xF800F800], [u0, v1, 0x0800F800], [u1, v1, 0x08000800], [u1, v0, 0xF8000800]]:
		io_write(0x4000488, 4, c[0] | (c[1] << 16))  # TEXCOORD
		io_write(0x400048C, 4, c[2])                  # VTX_16 (x, y)
		io_write(0x400048C, 4, 0)                     # (z)
	io_write(0x4000504, 4, 0)                         # END
	io_write(0x4000448, 4, 1)                         # MTX_POP


# ---- CHAOS SHUFFLE FIXES (part 19) -----------------------------------------------------------------------------
## A chaos swap never breaks an attack in progress that involves player 1 (user playtests: Kid Buu's ball super
## left P1 invisible and free, throws were broken, summoned Ginyu Force / Cooler squadron vanished). It also waits:
## - while P1 runs its own throw (Y+B 0x2A / 0x2B) or a character action (>= 0x85: the specials, super parts,
##   throws and summons of the per-character table rec+0x284),
## - while P1 is in a scripted victim state 0x34-0x66 (generic handler FUN_0202D128: thrown / grabbed / wrapped),
##   or P1 / the opponent has +0x250 & 0x20 / 0x400 (set on BOTH fighters by a throw that connects, FUN_0202B698 →
##   per-character throw u32[0x020D76BC + 4*id](thrower, victim), grab supers FUN_02028DDC → u32[0x020D7724 + 4*id],
##   and by the KO sequence FUN_0202759C),
## - while the opponent runs a throw / super / ultimate (0x2A-0x2E) or a character action >= 0x85,
## - while P1 is hidden (sprite +0x124 visible byte +0x3D = rec+0x161 == 0, e.g. inside Kid Buu's ball),
## - while an effect object made during a super / throw / character action (by a fighter in one of those actions,
##   or by such an object) is alive: summoned fighters, balls, lingering super beams — for at most CHAOS_OBJ_WAIT
##   frames (a persistent object made that way must not stop the cheat for good).
## Debug: `chaosat=F1,F2,…` (port frames): swaps become due only at those frames (waits still apply);
## `p2keys=F:MASK:N,…`: P2's input (+0x26C pressed at F, +0x270 held for N frames; masks as in DATA_NOTES part 13).
const CHAOS_OBJ_WAIT := 600
var _chaos_sup := {}                     ## effect object -> true: made by a super / throw / character action
var _chaos_obj_frames := 0               ## frames a swap has waited for such objects
var _chaos_at := []
var _chaos_at_dbg := -1
var _p2keys_dbg := -1
var _p2keys_list := []


func _chaos_super_act(a: int) -> bool:
	return (a >= 0x2A and a <= 0x2E) or a >= 0x85


## the spawn hook: remember objects of supers / throws / character actions (and objects those objects make)
func _chaos_spawned(p: int, r: int) -> void:
	var mark := false
	if p != 0:
		if _chaos_sup.has(p) and (_ld(p + 4, 1, false) & 1) != 0:
			mark = true
		elif _ld(p + 0x10E, 2, false) < 0x1A:
			mark = _chaos_super_act(_ld(p + 6, 1, false)) or (_ld(p + 0x250, 4, false) & 0x20) != 0
	if mark:
		_chaos_sup[r] = true
		if _shuf_dbg():
			print("CHT chaos super object %x from %x act %x kind %d" % [r, p, _ld(p + 6, 1, false), _ld(r + 6, 1, false)])
	else:
		_chaos_sup.erase(r)


func _chaos_held(f: int, o: int) -> String:
	var a: int = _ld(f + 6, 1, false)
	if a == 0x2A or a == 0x2B or a >= 0x85:
		return "own throw / character action %x" % a
	if a >= 0x34 and a <= 0x66 and a != 0x52:
		return "held (victim state %x)" % a
	if (_ld(f + 0x250, 4, false) & 0x420) != 0:
		return "held (+0x250 %x)" % _ld(f + 0x250, 4, false)
	var oa: int = _ld(o + 6, 1, false)
	if _chaos_super_act(oa):
		return "opponent throw / super %x" % oa
	if (_ld(o + 0x250, 4, false) & 0x420) != 0:
		return "opponent in a sequence (+0x250 %x)" % _ld(o + 0x250, 4, false)
	if _ld(f + 0x161, 1, false) == 0:
		return "P1 hidden"
	var n := 0
	for ob in _chaos_sup.keys():
		if (_ld(ob + 4, 1, false) & 1) == 0:
			_chaos_sup.erase(ob)
		else:
			n += 1
	if n > 0 and _chaos_obj_frames < CHAOS_OBJ_WAIT:
		_chaos_obj_frames += 1
		return "%d super / summon objects" % n
	_chaos_obj_frames = 0
	return ""


func _port_frame() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return -1
	var v = tree.current_scene.get("frames")
	return int(v) if v != null else -1


## -1 = no `chaosat` flag (normal timer); 0 = not due; 1 = due now
func _chaos_at_state() -> int:
	if _chaos_at_dbg < 0:
		_chaos_at_dbg = 1 if Game.args.has("chaosat") else 0
		if _chaos_at_dbg == 1:
			for v in Game.flag("chaosat").split(",", false):
				_chaos_at.append(int(v))
	if _chaos_at_dbg == 0:
		return -1
	if _chaos_at.is_empty():
		return 0
	return 1 if _port_frame() >= _chaos_at[0] else 0


func _p2keys(f: int) -> void:
	if _p2keys_dbg < 0:
		_p2keys_dbg = 1 if Game.args.has("p2keys") else 0
		for e in Game.flag("p2keys").split(",", false):
			var q := e.split(":")
			_p2keys_list.append([int(q[0]), q[1].hex_to_int(), int(q[2]) if q.size() > 2 else 4])
		return
	if _ld(f + 0x1A, 1, false) != 1 or f != f_02027c00(1):
		return
	var fr := _port_frame()
	var held := 0
	var pressed := 0
	for e in _p2keys_list:
		if fr >= e[0] and fr < e[0] + e[2]:
			held |= e[1]
			if fr == e[0]:
				pressed |= e[1]
	if held != 0:
		_st(f + 0x270, 2, held)
		_st(f + 0x26C, 2, pressed)


# ---- CAMERA ZOOM (part 20) --------------------------------------------------------------------------------------
## Setting CAMERA ZOOM (QoLSettings.camera_zoom 0..4, flag `zoom=N`; 2 = the game's own camera, every override below
## then only calls super). The battle camera (u32 0x020DE3A4 -> 0x021003CC) already zooms by itself: u16 +6 =
## 0x14000 / (d + 0x80) clamped to 0x80..0x100 (8.8 fixed point; d = the fighters' distance with dy weighted 4/3,
## FUN_02019594; at 0x80 the fighters are pulled together instead). Drawing reads +6 in: the sprite list scale
## (FUN_02012154, called only by the camera update FUN_02019980), sprite positions (FUN_02019328: fighters, effects,
## supports), the 3D stage depth (FUN_0201B5C0 via FUN_0201DDC4: S+0x54C = (0x100 - zoom) / 2 per object z scale),
## the ground shadows (FUN_0202A254 / FUN_02019180) and the DETAILED SHADOWS silhouettes (both inside FUN_02012D70).
## Game logic reads it too (effect script op 0x39 placement, FUN_020193FC zoom transitions, the on-screen tests
## FUN_0201921C / FUN_02031EC8): those keep the game's value, so +6 holds the game's value except while one of the
## drawing functions runs. Zoomed out = the game's zoom times k; zoomed in = times k but never closer than keeps
## both active fighters on screen (and never farther than the game's own).
const ZOOM_K := [0.7, 0.85, 1.0, 1.15, 1.3]   ## CAMERA ZOOM factor per level (0/1 out, 2 the game's, 3/4 in)
const ZOOM_MX := 40                      ## zoom in: active fighters' centres stay this far inside the screen (px)
const ZOOM_MY := 40
var _zm_in := false                      ## +6 holds the scaled zoom (a drawing function runs)
var _zm_ratio := 1.0                     ## scaled zoom / game zoom while _zm_in
var _zm_fit := 0x7FFF                    ## zoom-in limit of this frame (8.8)
var _zm_f := [0, 0]                      ## the active fighters passed to the camera update
var _zm_dbgk := float(Game.flag("zoomk", "0"))   ## debug: zoomk=F overrides the factor of levels != 2
var _zm_dbg := Game.args.has("zoomdbg")
var _zm_cyc := Game.args.has("zoomcycle")   ## debug: level = port frame % 5 (zoom only changes drawing)
var _zm_cycn := int(Game.flag("zoomcycle", "5")) if int(Game.flag("zoomcycle", "5")) >= 2 else 5   ## zoomcycle=2: levels 0 / 1


func _zm_k() -> float:
	if cheats == null:
		return 1.0
	var lv: int = cheats.camera_zoom
	if _zm_cyc:
		lv = posmod(_port_frame() + 2, _zm_cycn)   # debug `zoomcycle`: capture pN (3D drawn a frame later) shows level N % 5
	if lv == 2:
		return 1.0
	if _zm_dbgk > 0.0:
		return _zm_dbgk
	return ZOOM_K[clampi(lv, 0, 4)]


func _zm_scale(z: int, k: float) -> int:
	var s := int(round(z * k))
	if k > 1.0:
		s = maxi(z, mini(s, _zm_fit))
	return clampi(s, 0x10, 0x400)


## zoom-in limit: both active fighters' centres inside the screen minus ZOOM_MX / ZOOM_MY (camera centre = 128, 96)
func _zm_fit_now() -> void:
	_zm_fit = 0x7FFF
	var cam: int = _ld(CAMERA, 4, false)
	var cx: int = _ld(cam + 0xC, 4, true)
	var cy: int = _ld(cam + 0x10, 4, true)
	for f in _zm_f:
		if f == 0 or (_ld(f + 0x12, 2, false) & 8) != 0:
			continue
		var dx := absi((_ld(f + 0x38, 4, true) >> 8) - cx)
		var dy := absi((_ld(f + 0x3C, 4, true) >> 8) - cy)
		if dx > 0:
			_zm_fit = mini(_zm_fit, (128 - ZOOM_MX) * 256 / dx)
		if dy > 0:
			_zm_fit = mini(_zm_fit, (96 - ZOOM_MY) * 256 / dy)


func _zm_push(k: float) -> int:
	var cam: int = _ld(CAMERA, 4, false)
	var z: int = _ld(cam + 6, 2, false)
	var sz := _zm_scale(z, k)
	_st(cam + 6, 2, sz)
	_zm_ratio = float(sz) / float(maxi(z, 1))
	_zm_in = true
	return z


func _zm_pop(z: int) -> void:
	_st(_ld(CAMERA, 4, false) + 6, 2, z)
	_zm_in = false


## FUN_02019980: battle camera update (mode 0 follow / 1 pan / 2 super / 3 fixed / 4 team art), sets the sprite scale
func f_02019980(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _zm_k() == 1.0:
		return super.f_02019980(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_zm_f[0] = param_1
	_zm_f[1] = param_2
	return super.f_02019980(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_02012154(zoom): sprite list global scale (+0x184)
func f_02012154(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var k := _zm_k()
	if k == 1.0:
		return super.f_02012154(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if k > 1.0:
		_zm_fit_now()
	var s := _zm_scale(param_1, k)
	if _zm_dbg:
		var cam: int = _ld(CAMERA, 4, false)
		print("ZOOM f%d mode %d game %d -> %d fit %d cam %d,%d" % [_port_frame(), _ld(cam, 2, false), param_1, s, _zm_fit,
			_ld(cam + 0xC, 4, true), _ld(cam + 0x10, 4, true)])
	return super.f_02012154(s, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_02019328(record): registers a fighter / effect / support sprite at its zoomed screen position
func f_02019328(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var k := _zm_k()
	if k == 1.0 or _zm_in:
		return super.f_02019328(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var z := _zm_push(k)
	var r := super.f_02019328(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_zm_pop(z)
	return r


## FUN_020A7710(fovySin, fovyCos, aspect, near, far, scaleW, ...): the perspective projection; only the 3D stage draw
## FUN_02019C74 (inside FUN_02012D70) uses it. The stage depth keeps the game's own zoom (FUN_0201B5C0 runs outside
## the swap), and the projection is scaled by (scaled zoom / game zoom) around the screen centre: the 3D stage is
## the game's picture magnified exactly like the sprites, so fighters stay on the same spot of the ground
func f_020a7710(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, param_5: int = 0, param_6: int = 0, param_7: int = 0, param_8: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _zm_in and _zm_ratio != 1.0:
		param_2 = int(round(param_2 * _zm_ratio))       # cot(fovy / 2) = cos / sin: x and y scale by the ratio
	return super.f_020a7710(param_1, param_2, param_3, param_4, param_5, param_6, param_7, param_8, _x8, _x9, _x10, _x11)


## Stage object culling (part 21; zoomed-out levels only, i.e. while drawing with _zm_ratio < 1). The 3D stage hides
## objects for the game's 100 % view in two ways: (1) stage script op 0x11 (FUN_0201A794: visible only while camera x
## is in [a, b]; Roshi's house etc.) and (2) FUN_02019C74 draws a repeating prop (object +0x34 == 0, +0x32 0 / 1) only
## at its copy nearest the view (within half a stage period w, + the copy one period further for +0x32 == 0), so
## props jump from one edge to the other half a period from the centre. The script's visible flag (state +0xA) is
## widened by the extra view width at the object's depth; FUN_02019C74 is run two more times drawing only the
## props, each moved by whole periods (state +0x18 x offset) onto the copies the game skipped (fixed polygon count).
var _zm_cull := Game.flag("zoomcull", "1") != "0"   ## debug: zoomcull=0 turns the part-21 culling fixes off
var _zm_win := {}                        ## stage objects with a camera-window script (op 0x11), by object pointer
var _zm_win_o0 := 0
var _zm_vis_prev := {}                   ## debug (zoomdbg): last widened visible flag per object state


## extra view half-width (cam px) at the depth of stage object i when zoomed out by _zm_ratio
func _zm_obj_margin(S: int, i: int) -> int:
	var o: int = _ld(S + 4 + i * 4, 4, false)
	var st := S + 0x44 + i * 0x3C
	var o0: int = _ld(S + 4, 4, false)
	var w: int = maxi(_ld(o0 + 0x2C, 2, false), 1)
	var ccc: int = maxi(_ld(S + 0xCCC, 2, false), 1)
	var z: float = (_ld(o + 0x1C, 4, true) + _ld(st + 0x20, 4, true) - _ld(o + 0x10, 4, true) * _ld(S + 0x54C, 4, true)) / 4096.0
	var d: float = maxf(1.0 - z, 1.0)
	# visible half-width at depth d (fovy 60, aspect 4:3): 0.7698 d units; 1 cam px = w / ccc units; +25 % for size
	return int(0.7698 * d * (1.0 / _zm_ratio - 1.0) * ccc / w * 1.25) + 16


## FUN_0201A794: stage object scripts, one op per object per frame (runs at the start of FUN_02012D70)
func f_0201a794(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _zm_in or _zm_ratio >= 1.0 or not _zm_cull:
		return super.f_0201a794(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var S: int = _ld(STG_BLOCK, 4, false)
	var n: int = _ld(S + 0x550, 4, false)
	if _ld(S + 4, 4, false) != _zm_win_o0:            # another stage model (battle start, STAGE SHUFFLE)
		_zm_win_o0 = _ld(S + 4, 4, false)
		_zm_win.clear()
	var ops: Array = []                  # [state, a, b, object index]: op 0x11 about to run
	for i in mini(n, 16):
		var st := S + 0x44 + i * 0x3C
		var p: int = _ld(st + 4, 4, false)
		if p != 0 and _ld(p, 2, true) == 0x11:
			_zm_win[_ld(S + 4 + i * 4, 4, false)] = [_ld(p + 2, 2, true), _ld(p + 4, 2, true)]   # camera window [a, b]
			if _ld(st + 8, 2, true) == 0:
				ops.append([st, _ld(p + 2, 2, true), _ld(p + 4, 2, true), i])
	var r := super.f_0201a794(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if not ops.is_empty():
		var cx: int = _ld(_ld(CAMERA, 4, false) + 0xC, 4, true)
		for e in ops:
			# the window is the object's on-screen camera range at the game's view: it widens like the view (and
			# at least by the extra view width at the object's translation depth)
			var m := maxi(_zm_obj_margin(S, e[3]), int((e[2] - e[1]) * 0.5 * (1.0 / _zm_ratio - 1.0) * 1.1))
			var v := 1 if cx >= e[1] - m and cx <= e[2] + m else 0
			if _zm_dbg and v != _zm_vis_prev.get(e[0], -1):
				_zm_vis_prev[e[0]] = v
				print("ZWIN f%d object %d visible %d cam %d window %d..%d margin %d" % [_port_frame(), e[3], v, cx, e[1], e[2], m])
			_st(e[0] + 10, 2, v)
	return r


## FUN_02019C74: draw the 3D stage (only caller: FUN_0201B4EC inside FUN_02012D70)
func f_02019c74(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _zm_in or _zm_ratio >= 1.0 or not _zm_cull:
		return super.f_02019c74(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var moved := _zm_win_place()
	var r := super.f_02019c74(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	for e in moved:
		_st(e[0] + 0x18, 4, _ld(e[0] + 0x18, 4, true) - e[1])
	var S: int = _ld(STG_BLOCK, 4, false)
	var n: int = mini(_ld(S + 0x550, 4, false), 16)
	var o0: int = _ld(S + 4, 4, false)
	if _ld(S + 0x554, 4, false) == 0 or o0 == 0 or n == 0:
		return r
	var w: int = _ld(o0 + 0x2C, 2, false)
	if w <= 0:
		return r
	var iv7: int = _ld(S + 0x548, 2, true) % w     # FUN_020B5E30 remainder (camera >= 0)
	var props: Array = []                # [object, state, +0x32, extra shift A, extra shift B]
	for i in n:
		var o: int = _ld(S + 4 + i * 4, 4, false)
		var st := S + 0x44 + i * 0x3C
		if _ld(st + 10, 2, true) == 0 or _ld(o + 0x34, 2, true) != 0:
			continue
		var k: int = _ld(o + 0x32, 2, true)
		if k == 2 or _zm_win.has(o):
			continue                     # absolute camera x (S+0x558) / shown only inside a camera window (op 0x11)
		var ox: int = _ld(o + 0x14, 4, true)
		var sh := [-w, w]                # the game draws T1 only (+0x32 == 1)
		if k == 0:
			if ox < 1:
				sh = [-w, 2 * w]         # game copies T1, T1 + w
			elif (ox >> 12) <= iv7:
				sh = [-2 * w, w]         # game copies T1, T1 - w
		var tx: int = _ld(st + 0x18, 4, true)
		props.append([o, st, tx + sh[0] * 0x1000, tx + sh[1] * 0x1000, false])
	# the panorama pairs (+0x34 != 0: objects i, i + 1 = the two halves of one period): the game draws 3 half pieces
	# around the view (starts L, L + w/2, L + w); two more on each side, drawn through the prop path (+0x34 = 0,
	# +0x32 = 1: x = obj x + state x + T), state x set so that each lands at its half-period slot
	var half := w >> 1
	var u := half - iv7
	var lft := u - half if u >= 0 else u
	var i := 0
	while i + 1 < n:
		var o: int = _ld(S + 4 + i * 4, 4, false)
		var st := S + 0x44 + i * 0x3C
		if _ld(o + 0x34, 2, true) == 0 or _ld(st + 10, 2, true) == 0:
			i += 1
			continue
		var pos := [{}, {}]              # pass -> {object index: offset}
		for e in [[0, lft - half], [0, lft - 2 * half], [1, lft + 3 * half], [1, lft + 4 * half]]:
			var sp: int = e[1]
			if posmod(sp - u, w) == 0:
				pos[e[0]][i] = sp
			else:
				pos[e[0]][i + 1] = sp - half
		for j in [i, i + 1]:
			var oj: int = _ld(S + 4 + j * 4, 4, false)
			var tj := _zm_t1(_ld(oj + 0x14, 4, true), iv7, w)
			props.append([oj, S + 0x44 + j * 0x3C, (pos[0][j] - tj) * 0x1000, (pos[1][j] - tj) * 0x1000, true])
		i += 2
	if props.is_empty():
		return r
	var save := {}
	for i2 in n:
		var st2 := S + 0x44 + i2 * 0x3C
		var o2: int = _ld(S + 4 + i2 * 4, 4, false)
		save[i2] = [_ld(st2 + 10, 2, true), _ld(st2 + 0x18, 4, true), _ld(st2 + 0x1C, 4, true), _ld(st2 + 0x20, 4, true),
			_ld(st2 + 0x30, 4, false), _ld(st2 + 0x34, 2, false), _ld(o2 + 0x32, 2, true), _ld(o2 + 0x34, 2, true)]
	for pass_i in 2:
		for i2 in n:
			_st(S + 0x44 + i2 * 0x3C + 10, 2, 0)
		for p in props:
			_st(p[1] + 10, 2, 1)
			_st(p[1] + 0x18, 4, p[2 + pass_i])
			_st(p[0] + 0x32, 2, 1)
			if p[4]:                     # panorama piece: no state y / z / rotation in the game's panorama path
				_st(p[0] + 0x34, 2, 0)
				_st(p[1] + 0x1C, 4, 0)
				_st(p[1] + 0x20, 4, 0)
				_st(p[1] + 0x30, 4, 0)
				_st(p[1] + 0x34, 2, 0)
		super.f_02019c74(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	for i2 in n:
		var st2 := S + 0x44 + i2 * 0x3C
		var o2: int = _ld(S + 4 + i2 * 4, 4, false)
		var v: Array = save[i2]
		_st(st2 + 10, 2, v[0])
		_st(st2 + 0x18, 4, v[1])
		_st(st2 + 0x1C, 4, v[2])
		_st(st2 + 0x20, 4, v[3])
		_st(st2 + 0x30, 4, v[4])
		_st(st2 + 0x34, 2, v[5])
		_st(o2 + 0x32, 2, v[6])
		_st(o2 + 0x34, 2, v[7])
	return r


## the game's copy choice for a repeating prop: x term T (units) for camera remainder iv7 = (stage x) mod w
func _zm_t1(ox: int, iv7: int, w: int) -> int:
	if ox < 1 or (ox >> 12) <= iv7:
		return (w >> 1) - iv7
	return -(iv7 + (w >> 1))


## a windowed object (op 0x11) stands for ONE place in the battle world: draw the copy that continues the one in view
## at the window centre (no jump by a period inside the widened window). Returns [state, x shift] to undo.
func _zm_win_place() -> Array:
	var out: Array = []
	if _zm_win.is_empty():
		return out
	var S: int = _ld(STG_BLOCK, 4, false)
	var n: int = mini(_ld(S + 0x550, 4, false), 16)
	var o0: int = _ld(S + 4, 4, false)
	var w: int = _ld(o0 + 0x2C, 2, false)
	var ccc: int = _ld(S + 0xCCC, 2, false)
	if w <= 0 or ccc <= 0:
		return out
	var cx: int = _ld(_ld(CAMERA, 4, false) + 0xC, 4, true)
	var iv7: int = _ld(S + 0x548, 2, true) % w
	for i in n:
		var o: int = _ld(S + 4 + i * 4, 4, false)
		if not _zm_win.has(o) or _ld(o + 0x34, 2, true) != 0 or _ld(o + 0x32, 2, true) == 2:
			continue
		var st := S + 0x44 + i * 0x3C
		var cw: int = (_zm_win[o][0] + _zm_win[o][1]) / 2
		var ox: int = _ld(o + 0x14, 4, true)
		var want: float = _zm_t1(ox, ((w * posmod(cw, ccc)) / ccc) % w, w) - float(cx - cw) * w / ccc
		var sh: int = int(round((want - _zm_t1(ox, iv7, w)) / w)) * w * 0x1000
		if sh != 0:
			_st(st + 0x18, 4, _ld(st + 0x18, 4, true) + sh)
			out.append([st, sh])
	return out


## FUN_02012D70: battle draw (stage scripts, shadows, stage model, sprite list)
func f_02012d70(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var k := _zm_k()
	if k == 1.0 or _zm_in:
		return super.f_02012d70(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var z := _zm_push(k)
	var r := super.f_02012d70(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_zm_pop(z)
	return r


## the ground shadow's drop below an airborne fighter: FUN_0202A254 adds (ground - y) + feet unscaled (right only at
## zoom 1.0; the game's own zoom-out misplaces airborne shadows a little); zoomed levels scale it with the zoom
func _zm_drop(d: int, zoom: int) -> int:
	if _zm_k() == 1.0:
		return d
	return (zoom * d) >> 8


## FUN_0202A254: face icons + the two ground shadows (ellipse y = screen y + (ground - y) + f + zoom * (64 - f) / 256)
func f_0202a254(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _zm_k() == 1.0:
		return super.f_0202a254(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var lst: int = _ld(SPR_LIST, 4, false)
	var n0: int = _ld(lst + 0x183, 1, false)
	var r := super.f_0202a254(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var n: int = _ld(lst + 0x183, 1, false)
	var teams: int = _ld(TEAMS, 4, false)
	var ground: int = _ld(_ld(_ld(0x0201B49C, 4, false), 4, false) + 0xCC2, 2, false)
	var zoom: int = _ld(_ld(CAMERA, 4, false) + 6, 2, false)
	for i in range(n0, n):
		var p: int = _ld(lst + i * 4, 4, false)
		for side in 2:
			var tb := teams + side * 0x8E8
			if p != tb + SHADOW_SPR:
				continue
			var rec := tb + _ld(tb + 0x8C8, 1, false) * 0x2D8
			var d: int = ground - (_ld(rec + 0x3C, 4, true) >> 8) + _ld(SHADOW_FEET + _ld(rec + 5, 1, false), 1, false)
			_st(p + 0x1E, 2, _ld(p + 0x1E, 2, true) - d + _zm_drop(d, zoom))
	return r


# ---- GFX FIXES (part 20) ----------------------------------------------------------------------------------------
## NO COOLDOWN "beams keep going" (part 13) used to live in an FUN_0202104C override: every player-1 effect object
## with life flag 8 (= dies when its owner's action byte differs from the action stored at +0x1B) was turned into a
## BEAM_KEEP_FRAMES countdown as soon as P1's action changed for ANY reason. Flag 8 is not only on beams: the step
## dash speed lines (kind 5, flags 0x18, actions 7 / 8), the R-dash lines (kind 4, 0x18, action 0x0A) and the R
## charge auras (kinds 5 / 6, flag 8, action 0x0D) have it too (melonDS: DATA_NOTES part 20), so with the cheat on
## they all hung on the fighter for a second after the move ended. Now only the objects of the attack that
## _cancel_attack is cutting short this frame (owner = P1 fighter, flag 8, +0x1B = that attack's action) get the
## countdown; everything else dies when its move ends, as in the original.
const FX_POOL := 0x020DE3CC              ## u32 -> effect objects: 48 x 0x164 (+0 owner, +4 status 1 = alive, +0x10 life
                                          ## flags, +0x18 s16 countdown, +0x1A side, +0x1B owner's action)


func _nc_keep(f: int, act: int) -> void:
	var pool: int = _ld(FX_POOL, 4, false)
	if pool < 0x02000000 or pool >= 0x02400000:
		return
	for i in 48:
		var o := pool + i * 0x164
		if _ld(o + 4, 1, false) != 1 or _ld(o, 4, false) != f:
			continue
		var fl: int = _ld(o + 0x10, 2, false)
		var keep := (fl & 8) != 0 and _ld(o + 0x1B, 1, false) == act
		if _shuf_dbg():
			print("CHT nc cut f%d act %x obj %d kind %d flags %x oact %x handler %x hit %x keep %s" % [_port_frame(), act, i,
				_ld(o + 6, 1, false), fl, _ld(o + 0x1B, 1, false), _ld(_ld(o + 0x40, 4, false) + _ld(o + 6, 1, false) * 8, 4, false),
				_ld(o + 0x34, 4, false), keep])
		if keep:
			_st(o + 0x10, 2, (fl & ~8) | 2)          # from now on: a countdown instead
			_st(o + 0x18, 2, BEAM_KEEP_FRAMES)


# ---- 2ND FIDDLE (part 21) --------------------------------------------------------------------------------------
## WEIRD SETTING: player 1 plays in the colours the game gives player 2. The game's rule (FUN_0202A094, battle
## loader): a fighter's palette file holds two 0x100-byte palettes (normal, mirror); only a PLAYER 2 fighter
## (+0x1A != 0, id < 0x1A) whose character is also in player 1's team at load time gets the mirror one
## (rec+0xFC += 0x100) before FUN_02010B6C uploads it into the record's own slot (u16 rec+0x10A). Effect palettes
## (rec+0x21C) are never mirrored (the second half of the effect palette file is empty for fighters), supports
## (ids 26-36) have no second palette (files of 32 bytes, or a zero second half), face icons and portraits have one.
## With the setting on, after the loader every player-1 fighter record (all members) gets the mirror palette and
## every player-2 fighter the normal one, uploaded into the records' own slots with FUN_02010AE0; CHARACTER / CHAOS
## SHUFFLE give a swapped-in player-1 character the mirror palette (_shuffle_load). DATA_NOTES part 21.
func _fiddle_on() -> bool:
	return cheats != null and bool(cheats.get("second_fiddle"))


func _fiddle_apply() -> void:
	var teams: int = _ld(TEAMS, 4, false)
	for side in 2:
		var tb := teams + side * 0x8E8
		for k in _ld(tb + 0x8C9, 1, false):
			var f := tb + k * 0x2D8
			if _ld(f + 5, 1, false) >= 0x1A:
				continue                                # supports: one palette only
			var cur: int = _ld(f + 0xFC, 4, false)
			var base := cur if _cache_index(cur, true) >= 0 else cur - 0x100
			var want := base + (0x100 if side == 0 else 0)
			if want != cur:
				_st(f + 0xFC, 4, want)
				f_02010ae0(_ld(f + 0x10A, 2, false), want, 0x100)
			if _shuf_dbg():
				print("CHT fiddle side %d member %d id %d palette %x -> %x (%s)" % [side, k, _ld(f + 5, 1, false), cur, want,
					"mirror" if want != base else "normal"])


# ---- EPIC MODE (part 21) ---------------------------------------------------------------------------------------
## WEIRD SETTING: the game's text as 2006-2011 internet humour (QoLEpic, scripts/qol/qol_epic.gd). The only text the
## game draws from strings is the story / tutorial script text (script.bin, opcodes 0x17 & co.): every string goes
## through FUN_0200B954(out, str, x, y, z, scale_x, scale_y, palette), which builds one sprite per glyph (glyph table
## 0x020CEAEC: 317 entries {u16 texture, u16 code, s16 x0, y0, x1, y1}, advance = x1 - x0 - 2) and stops the game on
## an escape past byte 127. With the setting on, the string is rewritten (cached) and the call gets a copy in
## port-only RAM. Every other text (Mode Select / Option descriptions, names, menus, the opening) is an image: the
## Mode Select and Option description boxes are redrawn with the game's font (own text, QoLEpic.MODE_DESC /
## OPTION_DESC) right after their loaders (FUN_02075CC4: 9 entries {+0 palette, +4 chars, +8 map, +0x14 chars size}
## at *0x020DECEC; FUN_020864E0: 7 entries {+0 palette, +4 chars, +8 map, +0xC chars size} at 0x020E14D8); the
## title rows (tile rows 0-6) stay. English only (FUN_02070F28() == 0). DATA_NOTES part 21 (text).
const EPIC_BUF := 0x027B0000            ## port-only RAM: the rewritten string handed to FUN_0200B954
const EPIC_GLYPHS := 0x020CEAEC
const EPIC_GLYPH_COUNT := 0x13D
var _epic: QoLEpic = null
var _epic_cells: Array = []


func _epic_on() -> bool:
	return cheats != null and bool(cheats.get("epic_mode"))


func _epic_dbg() -> bool:
	return Game.args.has("epicdbg")


func _epic_init() -> void:
	if _epic != null:
		return
	_epic = QoLEpic.new()
	for i in EPIC_GLYPH_COUNT:
		var e := EPIC_GLYPHS + i * 12
		_epic.adv[_ld(e + 2, 2, false)] = _ld(e + 8, 2, true) - _ld(e + 4, 2, true) - 2


## FUN_0200B954: text string -> glyph sprites (story / tutorial scripts)
func f_0200b954(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, param_5: int = 0, param_6: int = 0, param_7: int = 0, param_8: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _epic_on() and param_1 != 0 and param_2 != 0 and f_02070f28() == 0:
		_epic_init()
		var raw := PackedByteArray()
		var o := param_2 - BASE
		while raw.size() < 0x200 and M[o + raw.size()] != 0:
			raw.append(M[o + raw.size()])
		var x := ((param_3 + 0x80000000) & 0xFFFFFFFF) - 0x80000000
		var sc := ((param_6 + 0x80000000) & 0xFFFFFFFF) - 0x80000000
		var t := _epic.story(raw, x, sc if sc > 0 else 100)
		if _epic_dbg():
			print("EPIC x %d y %d s %d: %s\n  => %s" % [x, param_4, sc, raw.get_string_from_ascii(), t.get_string_from_ascii() if t != raw else "(same)"])
		if t != raw:
			var d := EPIC_BUF - BASE
			for i in t.size():
				M[d + i] = t[i]
			M[d + t.size()] = 0
			param_2 = EPIC_BUF
	return super.f_0200b954(param_1, param_2, param_3, param_4, param_5, param_6, param_7, param_8, _x8, _x9, _x10, _x11)


## FUN_02075CC4: Mode Select loads its 9 description images (top screen BG1)
func f_02075cc4(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_02075cc4(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if r != 0 and _epic_on() and f_02070f28() == 0:
		var tab: int = _ld(0x020DECEC, 4, false)
		for i in mini(9, QoLEpic.MODE_DESC.size()):
			_epic_desc(tab + i * 0x20 + 4, tab + i * 0x20 + 0x14, _ld(tab + i * 0x20 + 8, 4, false), QoLEpic.MODE_DESC[i])
	return r


## FUN_020864E0: the Option screen loads its 7 description images (top screen BG1)
func f_020864e0(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_020864e0(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if r != 0 and _epic_on() and f_02070f28() == 0:
		for i in mini(7, QoLEpic.OPTION_DESC.size()):
			var e := 0x020E14D8 + i * 0x14
			_epic_desc(e + 4, e + 0xC, _ld(e + 8, 4, false), QoLEpic.OPTION_DESC[i])
	return r


## redraws one description image: tile rows 0-6 (the title) kept, the rest = `text` in the game's font (colour 7,
## lines every 14 px centred on y 102, block centred), tiles de-duplicated; the chars buffer is rewritten in place
## or replaced by a new heap block when it grows. `pp` / `sp`: addresses of the chars pointer / size (u32).
func _epic_desc(pp: int, sp: int, map_p: int, text: String) -> void:
	var chars_p: int = _ld(pp, 4, false)
	var size: int = _ld(sp, 4, false)
	if chars_p == 0 or map_p == 0 or size <= 0:
		return
	if _epic_cells.is_empty():
		_epic_cells = QoLFont._rom_cells(hw.rom)
		if _epic_cells.is_empty():
			return
	var tiles := [PackedByteArray()]
	tiles[0].resize(32)
	var index := {tiles[0]: 0}
	var map := PackedInt32Array()
	map.resize(1024)
	for k in 1024:
		var e: int = _ld(map_p + k * 2, 2, false)
		if k >= 7 * 32:
			map[k] = 0x1000
			continue
		var t := e & 0x3FF
		var data: PackedByteArray = M.slice(chars_p - BASE + t * 32, chars_p - BASE + t * 32 + 32) if t * 32 + 32 <= size else tiles[0]
		if not index.has(data):
			index[data] = tiles.size()
			tiles.append(data)
		map[k] = (e & 0xFC00) | int(index[data])
	# text pixels
	var px := PackedByteArray()
	px.resize(256 * 256)
	var lines := text.split("\n")
	var n := lines.size()
	var bw := 0
	for l in lines:
		bw = maxi(bw, l.length() * 6 - 1)
	var left := maxi(14, (256 - bw) / 2)
	for li in n:
		var top := 97 - (n - 1) * 7 + li * 14
		var x := left
		for ch in lines[li]:
			var g := ch.unicode_at(0) - 0x21
			if g >= 0 and g < _epic_cells.size():
				var cell: PackedByteArray = _epic_cells[g]
				for cy in 15:
					for cx in 9:
						if cell[cy * 9 + cx]:
							var X := x - 2 + cx
							var Y := top - 3 + cy
							if X >= 0 and X < 256 and Y >= 56 and Y < 192:
								px[Y * 256 + X] = 7
			x += 6
	for ty in range(7, 24):
		for tx in 32:
			var data := PackedByteArray()
			data.resize(32)
			var ink := false
			for y in 8:
				for xx in 4:
					var a := px[(ty * 8 + y) * 256 + tx * 8 + xx * 2]
					var b := px[(ty * 8 + y) * 256 + tx * 8 + xx * 2 + 1]
					data[y * 4 + xx] = a | (b << 4)
					ink = ink or a != 0 or b != 0
			if not ink:
				continue
			if not index.has(data):
				index[data] = tiles.size()
				tiles.append(data)
			map[ty * 32 + tx] = 0x1000 | int(index[data])
	if tiles.size() > 1024:
		return
	var need := tiles.size() * 32
	var dst := chars_p
	if need > size:
		dst = f_020090e4(need)
		if dst == 0:
			return
	for i in tiles.size():
		var d: PackedByteArray = tiles[i]
		for j in 32:
			M[dst - BASE + i * 32 + j] = d[j]
	if dst != chars_p:
		f_020090b0(chars_p)
		_st(pp, 4, dst)
	_st(sp, 4, need)
	for k in 1024:
		_st(map_p + k * 2, 2, map[k])
	if _epic_dbg():
		print("EPIC desc %x: %d tiles (was %d bytes) -> %x" % [pp, tiles.size(), size, dst])


## FUN_02009B28(buf, member, pack): loads one member of an open resource pack (handle table *0x020DE214, 0x88 bytes
## per pack, +0 path) into buf. EPIC MODE (part 23): the Data File / help / credits images are rewritten here
## (QoLEpicImg, scripts/qol/qol_epic_img.gd).
func f_02009b28(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_02009b28(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if r != 0 and _epic_on() and param_3 < 0x20 and param_2 < 0x200:
		_epic_loaded(param_1, param_2, param_3)
	return r


var _epic_img: QoLEpicImg = null


func _epic_loaded(buf: int, idx: int, handle: int) -> void:
	var pk: int = _ld(0x020DE214, 4, false) + handle * 0x88
	var b := PackedByteArray()
	for i in 0x7C:
		var c: int = _ld(pk + i, 1, false)
		if c == 0:
			break
		b.append(c)
	var path := b.get_string_from_ascii()
	if not (path.ends_with("DataModeDataImage_EN.bin") or path.ends_with("HelpEU.bin") or path.ends_with("CreditRollEU.bin") or path.ends_with("DataSubScrEU.bin")):
		return
	if f_02070f28() != 0:
		return
	var size: int = _ld(_ld(pk + 0x84, 4, false) + idx * 0x10, 4, false)
	_epic_init()
	if _epic_img == null:
		_epic_img = QoLEpicImg.new(self, _epic, hw.rom)
		_epic_img.dbg = _epic_dbg()
	_epic_img.loaded(path, handle, idx, buf, size)


# ---- BLOOD / AFTERIMAGES (part 22) ------------------------------------------------------------------------------
## WEIRD settings BLOOD (QoLSettings.blood, flag `weird=blood`) and AFTERIMAGES (QoLSettings.afterimages, `weird=after`).
## Drawing only: nothing here writes game RAM. Both are drawn like the DETAILED SHADOWS silhouettes, as GX quads sent
## after the game's sprite list in the f_02011384 override (inside FUN_02012D70, so CAMERA ZOOM's scaled zoom is in
## camera +6 while they are placed). Positions are kept in battle world pixels (fighter +0x38 / +0x3C >> 8) and put
## on screen like FUN_02019328 does: camera +0x30 + zoom * (x - camera +0xC) / 256 (y: +0x34, +0x10).
## BLOOD: every hit that takes HP (FUN_020293A4, damage > 0; any fighter, supports and copies too) throws
## droplets (part 23: 2-30 scaled by the clamped damage; a guarded hit 1-3) from the victim's upper body, away from the attacker (the other team's active
## fighter), with gravity; they splat on the ground line (FUN_0201B488 ground + 64 = where fighters' feet stand) and
## fade. Untextured 1-3 px quads in three reds; a capped pool of 160 whose used slots are all sent while any droplet lives
## (dead slots far off screen) so each slot keeps its polygon number for smooth motion.
## AFTERIMAGES: a fighter moving >= AI_SPEED world px per frame (dash, step, knockback, teleport) leaves three
## translucent light-blue copies of its current sprite quad at its positions 2 / 4 / 6 frames ago, fading out over
## AI_TIME frames after it slows down; behind the fighters (z 2), copies of one fighter do not overdraw each other
## (same polygon ID). Simulation steps once per battle frame (f_0202954C ran: _fx_upd), so pauses freeze it.
const BL_POOL := 160                    ## part 23: was 64; a full pool reuses the oldest slots
const BL_HIT_MAX := 30                  ## droplets per hit (part 23)
const BL_DMG_MAX := 3000                ## damage used for the spray is clamped (ONE HIT KO / HARD MODE / boss HP)
const BL_FEET := 64                     ## feet line = ground + 64 world px (Goku stands at y 8224 with f = 32)
const BL_DARK := 0x000D                 ## #6b0000
const BL_RED := 0x0018                  ## #c00000
const BL_HI := 0x211F                   ## #ff4040 highlight (1 px droplets only)
const AI_SPEED := 5.0                   ## world px per frame
const AI_TIME := 12                     ## frames the copies stay after the last fast frame
const AI_LAGS := [2, 4, 6]
const AI_ALPHA := [16, 11, 6]           ## of 31
const AI_COLOR := 0x7F98                ## (24, 28, 31): light blue (modulation tint)
var _fx_upd := false                    ## a battle frame ran since the last draw
var _fx_rng := RandomNumberGenerator.new()
var _fx_seeded := false
var _bl_p: Array = []                   ## BL_POOL x [x, y, vx, vy, age, state 0 dead / 1 flying / 2 splat, size, colour, landing depth]
var _bl_next := 0
var _bl_hw := 0                         ## slots in use since the pool was last empty (only these are sent)
var _ai_hist := {}                      ## record -> Array of Vector2 world positions, newest last
var _ai_t := {}                         ## record -> frames of afterimages left
var _bl_dbg := Game.args.has("blooddbg")
## part 26: smooth motion pairs a polygon with the previous list's polygon of the same NUMBER when POLYGON_ATTR,
## TEXIMAGE_PARAM, PLTT_BASE and texture coordinates match. The untextured particle quads below were all alike, so
## after any change in the polygon count before them (the game's sprites) a particle was blended toward another one's
## corners. Each quad now gets its own PLTT_BASE (ignored by untextured polygons: the 60 fps picture is unchanged):
## per pool slot + spawn generation, so it pairs only with itself. DATA_NOTES part 26.
const FXK_BL := 0x0400                  ## PLTT_BASE pairing keys: blood slot * 4 + generation & 3
const FXK_SK := 0x0700                  ## sparkles (slot * 2 + quad) * 4 + generation & 3
const FXK_CF := 0x0900                  ## confetti slot * 4 + generation & 3
const FXK_DN := 0x1000                  ## damage numbers: 0x1000 | (per-number base + quad index) & 0xFFF
var _fxk_bl := PackedInt32Array()       ## per slot: spawn generation
var _fxk_sk := PackedInt32Array()
var _fxk_cf := PackedInt32Array()


func _fx_rand(a: float, b: float) -> float:
	if not _fx_seeded:
		_fx_rng.seed = 0x5EED22
		_fx_seeded = true
	return _fx_rng.randf_range(a, b)


## FUN_020293A4 hook: a hit took `dmg` HP from fighter record `rec`
func _blood_hit(rec: int, dmg: int) -> void:
	if (_ld(rec + 0x12, 2, false) & 8) != 0:
		return                                          # drawn in screen coordinates
	# part 23: the spray scales with the damage (clamped): 198 (light) 3-4 drops, 432 (ki blast) 6, 1080 (dash
	# attack) 12, 2000+ (heavy / super) 22-30 with more big drops, faster and wider
	var d := clampi(dmg, 0, BL_DMG_MAX)
	var n := clampi(2 + d / 100, 2, BL_HIT_MAX)
	if (_ld(rec + 0x250, 4, false) & 1) != 0:
		n = clampi(n / 5, 1, 3)                         # guarded: chip damage, a few drops
	var heavy := d / float(BL_DMG_MAX)                  # 0..1
	var sp := 1.0 + 1.6 * heavy                         # speed / spread factor
	if _bl_p.size() != BL_POOL:
		_bl_p.clear()
		for i in BL_POOL:
			_bl_p.append([0.0, 0.0, 0.0, 0.0, 0, 0, 1, 0, 0.0])
	var x := _ld(rec + 0x38, 4, true) / 256.0
	var y := _ld(rec + 0x3C, 4, true) / 256.0
	var side: int = _ld(rec + 0x1A, 1, false)
	var tb: int = _ld(TEAMS, 4, false) + (1 - side) * 0x8E8
	var att: int = tb + _ld(tb + 0x8C8, 1, false) * 0x2D8
	var ax := _ld(att + 0x38, 4, true) / 256.0
	var dir := 1.0 if x >= ax else -1.0                 # away from the attacker
	if absf(x - ax) < 1.0:
		var fa: int = _ld(rec + 7, 1, false)
		dir = -1.0 if (fa < 64 or fa >= 192) else 1.0   # facing right: hit from the right side's front
	var hx := x - dir * 6.0
	var hy := y - 14.0
	for i in n:
		var sz := 1
		var r := _fx_rand(0.0, 1.0)
		if r > 0.93 - 0.25 * heavy:
			sz = 3
		elif r > 0.5 - 0.2 * heavy:
			sz = 2
		var c := BL_DARK if _fx_rand(0.0, 1.0) < 0.45 else BL_RED
		if sz == 1 and _fx_rand(0.0, 1.0) < 0.3:
			c = BL_HI
		_bl_p[_bl_next] = [hx + _fx_rand(-3.0, 3.0), hy + _fx_rand(-6.0, 6.0) * sp, dir * _fx_rand(0.3, 2.0) * sp,
			-_fx_rand(0.4, 2.8) * sqrt(sp), 0, 1, sz, c, _fx_rand(-2.0, 12.0)]
		if _fxk_bl.size() != BL_POOL:
			_fxk_bl.resize(BL_POOL)
		_fxk_bl[_bl_next] += 1                          # part 26 pairing key
		_bl_next = (_bl_next + 1) % BL_POOL
		_bl_hw = maxi(_bl_hw, _bl_next if _bl_next > 0 else BL_POOL)
	if _bl_dbg:
		print("BLOOD f%d rec %x dmg %d drops %d at %.0f,%.0f dir %d" % [_port_frame(), rec, dmg, n, hx, hy, int(dir)])


## before the game's list is drawn (and cleared): the sprites in it, or null outside battle
func _fx_before() -> Variant:
	if not _fx_any():
		return null
	var lst: int = _ld(SPR_LIST, 4, false)
	var n: int = _ld(lst + 0x183, 1, false)
	var idx := {}
	for i in n:
		idx[_ld(lst + i * 4, 4, false)] = true
	var teams: int = _ld(TEAMS, 4, false)
	var battle := false
	for side in 2:
		var tb := teams + side * 0x8E8
		if idx.has(tb + _ld(tb + 0x8C8, 1, false) * 0x2D8 + 0x124):
			battle = true
	if not battle:
		_bl_p.clear()
		_bl_next = 0
		_bl_hw = 0
		_cf_p.clear()
		_cf_hp.clear()
		_fk_hist.clear()
		_ai_hist.clear()
		_ai_t.clear()
		_w3_clear()                                     # part 24 WEIRD 3
		_fx_upd = false
		return null
	if cheats.damage_numbers or cheats.rainbow_ki:
		_w3_prep(idx)                                   # part 24 WEIRD 3: step, tint for the game's drawer
	return idx


func _fx_draw(fx: Variant) -> void:
	if _w3_in or _rk_tinted:
		_w3_after()                                     # part 24 WEIRD 3: the game's drawer is done
	if fx == null:
		return
	var idx: Dictionary = fx
	var cam: int = _ld(CAMERA, 4, false)
	var zoom: int = _ld(cam + 6, 2, false)
	var cv := [_ld(cam + 0xC, 4, true), _ld(cam + 0x10, 4, true), _ld(cam + 0x30, 4, true), _ld(cam + 0x34, 4, true), zoom / 256.0]
	var step := _fx_upd
	_fx_upd = false
	var drew := false
	if cheats.afterimages:
		drew = _ai_frame(idx, cv, step) or drew
	if cheats.blood and not _bl_p.is_empty():
		drew = _bl_frame(cv, step) or drew
	if cheats.ko_confetti:
		drew = _cf_frame(cv, step) or drew              # part 23
	if cheats.flashy_ki:
		drew = _fk_frame(idx, cv, step) or drew         # part 23 (last: its polygon count varies most)
	if cheats.bomb_rain and _bombs != null:
		drew = _bombs.draw(cv) or drew                  # part 25 BOMB RAIN
	if _gd != null and _on("green_demon"):
		drew = _gd.draw(cv) or drew                     # part 36 GREEN DEMON
	if _ui != null and _on("ultra_instinct"):
		drew = _ui.draw(idx, cv, step) or drew          # part 39 ULTRA INSTINCT flashes
	if _hp != null and _on("hot_potato"):
		drew = _hp.draw(idx, cv) or drew                # part 40 HOT POTATO bomb + countdown
	if not _kb_off.is_empty() and _on("smash_knockback"):
		drew = _kb_draw() or drew                       # part 40 SMASH KNOCKBACK edge markers
	if _vp != null and _on("vampire"):
		drew = _vp.draw(idx, cv) or drew                # part 41 VAMPIRE sparks, pulse, +N
	if _db != null and _on("dragon_balls"):
		drew = _db.draw(idx, cv) or drew                # part 41 DRAGON BALL HUNT balls, HUD, wish
	if _ts != null and _on("time_skip"):
		drew = _ts.draw(idx, cv) or drew                # part 41 TIME SKIP tint, skipper, rings
	if _bc != null and _on("body_change"):
		drew = _bc.draw(idx, cv) or drew                # part 42 BODY CHANGE countdown, ray, glow
	if _zv != null and _on("z_vanish"):
		drew = _zv.draw(idx, cv) or drew                # part 42 Z-VANISH afterimages
	if cheats.damage_numbers:
		drew = _dn_frame(cv) or drew                    # part 24 DAMAGE NUMBERS (on top of everything)
	if drew:
		io_write(0x4000480, 4, 0x7FFF)                  # vertex colour back to white (what DIF_AMB left)


## blood: step (once per battle frame) and draw the whole pool while any droplet lives
func _bl_frame(cv: Array, step: bool) -> bool:
	var live := 0
	if step:
		var floor_y := float(_ld(_ld(_ld(0x0201B49C, 4, false), 4, false) + 0xCC2, 2, false) + BL_FEET)
		for p in _bl_p:
			if p[5] == 1:
				p[3] += 0.22
				p[0] += p[2]
				p[1] += p[3]
				p[4] += 1
				if p[1] >= floor_y + p[8]:               # the floor is a plane: land a little in front / behind
					p[1] = floor_y + p[8]
					p[5] = 2
					p[4] = 0
				elif p[4] > 75:
					p[5] = 0
			elif p[5] == 2:
				p[4] += 1
				if p[4] > 26:
					p[5] = 0
	for p in _bl_p:
		if p[5] != 0:
			live += 1
	if live == 0:
		_bl_p.clear()
		_bl_next = 0
		_bl_hw = 0
		return false
	var z: float = cv[4]
	for k in _bl_hw:                                    # part 23: only the slots used since the pool was empty
		var p: Array = _bl_p[k]
		var st: int = p[5]
		var bk := FXK_BL + k * 4 + ((_fxk_bl[k] & 3) if k < _fxk_bl.size() else 0)   # part 26
		if st == 0:
			_fx_box(-4000.0, -4000.0, 1, 1, 0, 0x001F80C0 | (0x3E << 24), 8, bk)
			continue
		var sx: float = cv[2] + z * (p[0] - cv[0])
		var sy: float = cv[3] + z * (p[1] - cv[1])
		var s := maxi(1, int(round(p[6] * z)))
		var w := s
		var h := s
		var al := 31
		if st == 2:                                     # splat: flat, fading
			w = maxi(2, s + 1)
			h = 1
			sy -= 1.0
			al = clampi(31 - (p[4] - 10) * 2, 6, 31)
		_fx_box(floorf(sx - w * 0.5), floorf(sy - h * 0.5), w, h, p[7], 0x80C0 | (al << 16) | (0x3E << 24), 8, bk)
	if _bl_dbg and step:
		print("BLOOD f%d live %d" % [_port_frame(), live])
	return true


## one untextured w x h px quad with its top-left at (x, y); `key` = its PLTT_BASE (smooth-motion pairing, part 26)
func _fx_box(x: float, y: float, w: int, h: int, col: int, attr: int, z: int = 8, key: int = 0) -> void:
	var m := [float(w), 0.0, 0.0, 0.0, float(h), 0.0, 0.0, 0.0, 1.0, x + w * 0.5, y + h * 0.5, float(z)]
	io_write(0x4000440, 4, 2)
	io_write(0x4000444, 4, 0)                         # MTX_PUSH
	for v in m:
		io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)   # MTX_MULT_4x3
	io_write(0x40004A8, 4, 0)                         # TEXIMAGE_PARAM: no texture
	io_write(0x40004AC, 4, key)                       # PLTT_BASE: unused without a texture; the pairing key
	io_write(0x40004A4, 4, attr)
	io_write(0x4000480, 4, col)
	io_write(0x4000500, 4, 1)
	for c in [0xF800F800, 0x0800F800, 0x08000800, 0xF8000800]:
		io_write(0x4000488, 4, 0)                     # TEXCOORD 0 (keeps the polygon key stable)
		io_write(0x400048C, 4, c)
		io_write(0x400048C, 4, 0)
	io_write(0x4000504, 4, 0)
	io_write(0x4000448, 4, 1)                         # MTX_POP


## afterimages: record positions (once per battle frame), draw 3 copies per fast fighter
func _ai_frame(idx: Dictionary, cv: Array, step: bool) -> bool:
	var teams: int = _ld(TEAMS, 4, false)
	var recs: Array = []
	for side in 2:
		for k in 3:
			recs.append(teams + side * 0x8E8 + k * 0x2D8)
	recs.append_array(_clones)
	var drew := false
	var g: int = _ld(_ld(SPR_LIST, 4, false) + 0x184, 4, true)
	var z: float = cv[4]
	for rec in recs:
		var p: int = rec + 0x124
		if not idx.has(p) or (_ld(rec + 0x12, 2, false) & 8) != 0:
			_ai_hist.erase(rec)
			_ai_t.erase(rec)
			continue
		var pos := Vector2(_ld(rec + 0x38, 4, true) / 256.0, _ld(rec + 0x3C, 4, true) / 256.0)
		if step:
			var h: Array = _ai_hist.get(rec, [])
			if not h.is_empty():
				var sp: float = (pos - (h[-1] as Vector2)).length()
				if sp >= AI_SPEED and sp < 200.0:
					_ai_t[rec] = AI_TIME
				elif _ai_t.get(rec, 0) > 0:
					_ai_t[rec] -= 1
			h.append(pos)
			if h.size() > 8:
				h.pop_front()
			_ai_hist[rec] = h
		var t: int = _ai_t.get(rec, 0)
		if t <= 0:
			continue
		if _ld(p + 0x3D, 1, false) == 0 or _ld(p + 0x3B, 1, false) <= 7 or _ld(p, 4, false) == 0:
			continue
		var hist: Array = _ai_hist[rec]
		var fl: int = _ld(p + 0x3E, 2, false)
		var sw := float(_ld(p + 0x14, 4, true))
		var shh := float(_ld(p + 0x18, 4, true))
		if (fl & 8) == 0:
			sw = float((g * int(sw)) >> 8)
			shh = float((g * int(shh)) >> 8)
		sw /= 4096.0
		shh /= 4096.0
		var ri: int = _ld(p + 0x38, 2, false) >> 4
		var sn := _ld(SPR_ROT + ri * 4, 2, true) / 4096.0
		var cs := _ld(SPR_ROT + ri * 4 + 2, 2, true) / 4096.0
		var fx0 := float(_ld(p + 0x1C, 2, true))
		var fy0 := float(_ld(p + 0x1E, 2, true))
		var fa: int = _ld(p + 0x3B, 1, false) >> 3
		var pid: int = 0x30 + mini(recs.find(rec), 13)   # one polygon ID per fighter: its copies never overdraw
		for j in AI_LAGS.size():
			var lag: int = AI_LAGS[j]
			var tx := -4000.0
			var ty := -4000.0
			if hist.size() > lag:
				var d: Vector2 = (hist[hist.size() - 1 - lag] as Vector2) - pos
				if d.length() >= 4.0:
					tx = fx0 + roundf(d.x * z)
					ty = fy0 + roundf(d.y * z)
			var al := clampi(int(AI_ALPHA[j] * fa / 31.0 * minf(1.0, t / 6.0)), 1, 30)
			var m := [cs * sw, sn * sw, 0.0, -sn * shh, cs * shh, 0.0, 0.0, 0.0, 1.0, tx, ty, 2.0]
			_spr_emit(p, m, 0x80C0 | (al << 16) | (pid << 24), AI_COLOR)
			drew = true
	return drew


# ---- FLASHY KI / KO CONFETTI (part 23) --------------------------------------------------------------------------
## WEIRD settings FLASHY KI (QoLSettings.flashy_ki, `weird=flashy`) and KO CONFETTI (QoLSettings.ko_confetti,
## `weird=confetti`); drawing only, sent after the game's sprite list by _fx_draw (part 22 path). Effect objects:
## pool u32 [0x020DE3CC] 48 x 0x164 (+0 owner, +4 1 alive, +6 kind, +0x40 kind table {handler, ...} x 8 bytes,
## +0x1B owner's action at spawn, +0x38 / +0x3C x / y, sprite object +0x124 like a fighter's).
## FLASHY KI classifies every drawn effect object by its per-frame handler: plain projectiles 0x020209E0 (ki blasts,
## Spirit Bomb shots) get a large faint halo copy and a 3-copy shrinking trail of their last positions; beam parts
## (head 0x02020330, body 0x020203CC, origin 0x02020560) get a pulsing wider glow copy (body: thicker only); auras
## (owned by a fighter, centred on it, made during R charge 0x0C / 0x0D or power-up 0x29, or while the fighter is
## powered up +0x261) get two pulsing enlarged copies (x1.4 / x1.2) behind the fighters, and a charging fighter
## (action 0x0D) throws small rising sparkles. Copies are translucent, own polygon IDs 0x28-0x2B (they blend over the
## game's sprites, IDs 1-31), z one below the original.
## KO CONFETTI: a fighter record whose HP (+0x24A) drops to 0 bursts into 64 small 2-3 px rectangles in 7 colours that
## flutter down (drag, sideways sway, turning between 2x1 / 1x2 / 1x1) for ~1.5-2 s, lie on the floor and fade.
const FK_BLAST := 0x020209E0
const FK_BEAMS := [0x02020330, 0x020203CC, 0x02020560]
const FK_AURA_ACTS := [0x0C, 0x0D, 0x29]
const SK_POOL := 48                     ## sparkles
const CF_POOL := 128                    ## confetti
const CF_BURST := 64
const CF_COLS := [0x001F, 0x03FF, 0x03E0, 0x7D40, 0x5C1F, 0x7FFF, 0x7FE0]   ## red, yellow, green, blue, pink, white, cyan
var _fk_hist := {}                      ## effect object -> [handler, Array of Vector2 world positions]
var _fk_t := 0                          ## battle frames (pulse phase)
var _sk_p: Array = []                   ## sparkles [x, y, vx, vy, age, alive, colour]
var _sk_next := 0
var _sk_hw := 0
var _cf_p: Array = []                   ## confetti [x, y, vx, vy, age, state 0 dead / 1 flying / 2 lying, colour, phase, depth]
var _cf_next := 0
var _cf_hw := 0
var _cf_hp := {}                        ## fighter record -> HP last battle frame
var _fk_dbg := Game.args.has("flashydbg")


func _fx_any() -> bool:
	return cheats.blood or cheats.afterimages or cheats.flashy_ki or cheats.ko_confetti \
		or cheats.damage_numbers or cheats.rainbow_ki \
		or cheats.bomb_rain or _on("green_demon") \
		or _on("ultra_instinct") or _on("smash_knockback") or _on("hot_potato") \
		or _on("vampire") or _on("dragon_balls") or _on("time_skip") or _on("body_change") or _on("z_vanish")   # part 24 WEIRD 3, part 25 BOMB RAIN, part 36 GREEN DEMON, parts 39-41


## the fighter records that can be on screen (both teams, ASSIST SPAM copies)
func _fx_recs() -> Array:
	var teams: int = _ld(TEAMS, 4, false)
	var recs: Array = []
	for side in 2:
		for k in 3:
			recs.append(teams + side * 0x8E8 + k * 0x2D8)
	recs.append_array(_clones)
	return recs


## a copy of sprite object p: its quad scaled by (kx, ky) in its own axes around its centre, moved by (dx, dy) px
func _spr_copy(p: int, g: int, kx: float, ky: float, dx: float, dy: float, z: int, al: int, pid: int, col: int = 0x7FFF, pal: int = -1) -> void:
	var fl: int = _ld(p + 0x3E, 2, false)
	var sw := float(_ld(p + 0x14, 4, true))
	var shh := float(_ld(p + 0x18, 4, true))
	if (fl & 8) == 0:
		sw = float((g * int(sw)) >> 8)
		shh = float((g * int(shh)) >> 8)
	sw = sw / 4096.0 * kx
	shh = shh / 4096.0 * ky
	var ri: int = _ld(p + 0x38, 2, false) >> 4
	var sn := _ld(SPR_ROT + ri * 4, 2, true) / 4096.0
	var cs := _ld(SPR_ROT + ri * 4 + 2, 2, true) / 4096.0
	var tx := float(_ld(p + 0x1C, 2, true)) + dx
	var ty := float(_ld(p + 0x1E, 2, true)) + dy
	var m := [cs * sw, sn * sw, 0.0, -sn * shh, cs * shh, 0.0, 0.0, 0.0, 1.0, tx, ty, float(maxi(z, 0))]
	_spr_emit(p, m, 0x80C0 | (clampi(al, 1, 30) << 16) | (pid << 24), col, pal)


func _fk_frame(idx: Dictionary, cv: Array, step: bool) -> bool:
	var pool: int = _ld(FX_POOL, 4, false)
	if pool < 0x02000000 or pool >= 0x02400000:
		return false
	if step:
		_fk_t += 1
	var g: int = _ld(_ld(SPR_LIST, 4, false) + 0x184, 4, true)
	var z: float = cv[4]
	var recs := _fx_recs()
	var drew := false
	var seen := {}
	var pulse := sin(_fk_t * 0.45)
	for i in 48:
		var o := pool + i * 0x164
		var p := o + 0x124
		if (_ld(o + 4, 1, false) & 3) == 0 or not idx.has(p):   # drawn this frame (alive: +4 & 3)
			continue
		if _ld(p + 0x3D, 1, false) == 0 or _ld(p + 0x3B, 1, false) <= 7 or _ld(p, 4, false) == 0:
			continue
		var kind: int = _ld(o + 6, 1, false)
		var hd: int = _ld(_ld(o + 0x40, 4, false) + kind * 8, 4, false)
		var a5: int = _ld(p + 0x3B, 1, false) >> 3
		var zo: int = _ld(p + 0x3C, 1, false)
		var own: int = _ld(o, 4, false)
		if _fk_dbg and step and _fk_t % 10 == 0:
			var ox := (_ld(o + 0x38, 4, true) - _ld(own + 0x38, 4, true)) >> 8 if own in recs else 9999
			var oy := (_ld(o + 0x3C, 4, true) - _ld(own + 0x3C, 4, true)) >> 8 if own in recs else 9999
			print("FLASHY f%d obj %d kind %d handler %x oact %x owner-act %x d %d,%d quad %x,%x alpha %d z %d fl %x" % [_port_frame(), i, kind, hd,
				_ld(o + 0x1B, 1, false), _ld(own + 6, 1, false) if own in recs else -1, ox, oy, _ld(p + 0x14, 4, true) >> 12,
				_ld(p + 0x18, 4, true) >> 12, a5, zo, _ld(o + 0x10, 2, false)])
		if hd == FK_BLAST:
			seen[o] = true
			var pos := Vector2(_ld(o + 0x38, 4, true) / 256.0, _ld(o + 0x3C, 4, true) / 256.0)
			var hrec: Array = _fk_hist.get(o, [hd, []])
			if hrec[0] != hd:
				hrec = [hd, []]
			var hist: Array = hrec[1]
			if step:
				hist.append(pos)
				if hist.size() > 7:
					hist.pop_front()
			_fk_hist[o] = hrec
			var rkc: int = _rk_obj(o) if cheats.rainbow_ki else 0x7FFF   # part 24 RAINBOW KI
			_spr_copy(p, g, 1.8 + 0.12 * pulse, 1.8 + 0.12 * pulse, 0, 0, zo - 1, a5 * 14 / 31, 0x28, rkc)   # halo
			for j in 3:                                 # trail: the last positions, shrinking and fading
				var lag := 2 + j * 2
				var dx := -4000.0
				var dy := -4000.0
				if hist.size() > lag:
					var d: Vector2 = (hist[hist.size() - 1 - lag] as Vector2) - pos
					if d.length() >= 3.0:
						dx = roundf(d.x * z)
						dy = roundf(d.y * z)
				var k := 0.75 - 0.15 * j
				_spr_copy(p, g, k, k, dx, dy, zo - 1, a5 * (14 - 4 * j) / 31, 0x29, rkc)
			drew = true
		elif hd in FK_BEAMS:
			var ky := 1.6 + 0.2 * pulse
			var kx := 1.0 if hd == FK_BEAMS[1] else ky      # the body only gets thicker
			_spr_copy(p, g, kx, ky, 0, 0, zo - 1, a5 * 15 / 31, 0x2A, _rk_obj(o) if cheats.rainbow_ki else 0x7FFF)
			drew = true
		elif own in recs and (_ld(own + 0x12, 2, false) & 8) == 0:
			var oact: int = _ld(o + 0x1B, 1, false)
			var fact: int = _ld(own + 6, 1, false)
			var aura := (oact in FK_AURA_ACTS or fact in FK_AURA_ACTS or _ld(own + 0x261, 1, false) != 0) \
				and absi((_ld(o + 0x38, 4, true) - _ld(own + 0x38, 4, true)) >> 8) <= 16 \
				and absi((_ld(o + 0x3C, 4, true) - _ld(own + 0x3C, 4, true)) >> 8) <= 40 \
				and (_ld(p + 0x14, 4, true) >> 12) >= 48
			if aura:
				_spr_copy(p, g, 1.4 + 0.08 * pulse, 1.4 + 0.08 * pulse, 0, 0, 2, a5 * 8 / 31, 0x2B)
				_spr_copy(p, g, 1.2, 1.2, 0, 0, 2, a5 * int(9 + 5 * pulse) / 31, 0x2B)
				drew = true
	for o in _fk_hist.keys():
		if not seen.has(o):
			_fk_hist.erase(o)
	if _fk_dbg:
		print("FLASHY draw f%d step %s blasts %d list %d st %s" % [_port_frame(), step, seen.size(), idx.size(), str(_fk_st(pool))])
	drew = _sk_frame(recs, idx, cv, step) or drew
	return drew


## sparkles rising around charging fighters (action 0x0D)
func _sk_frame(recs: Array, idx: Dictionary, cv: Array, step: bool) -> bool:
	if step:
		for rec in recs:
			if _ld(rec + 6, 1, false) != 0x0D or not idx.has(rec + 0x124) or (_ld(rec + 0x12, 2, false) & 8) != 0:
				continue
			if _sk_p.size() != SK_POOL:
				_sk_p.clear()
				for i in SK_POOL:
					_sk_p.append([0.0, 0.0, 0.0, 0.0, 0, 0, 0])
			for n in 2:
				var x := _ld(rec + 0x38, 4, true) / 256.0 + _fx_rand(-22.0, 22.0)
				var y := _ld(rec + 0x3C, 4, true) / 256.0 + _fx_rand(-30.0, 30.0)
				_sk_p[_sk_next] = [x, y, _fx_rand(-0.3, 0.3), -_fx_rand(0.8, 1.8), 0, 1, [0x7FFF, 0x13FF, 0x7F94][_sk_next % 3]]
				if _fxk_sk.size() != SK_POOL:
					_fxk_sk.resize(SK_POOL)
				_fxk_sk[_sk_next] += 1                  # part 26 pairing key
				_sk_next = (_sk_next + 1) % SK_POOL
				_sk_hw = maxi(_sk_hw, _sk_next if _sk_next > 0 else SK_POOL)
		for p in _sk_p:
			if p[5] == 1:
				p[0] += p[2]
				p[1] += p[3]
				p[4] += 1
				if p[4] > 16:
					p[5] = 0
	var live := 0
	for p in _sk_p:
		live += p[5]
	if live == 0:
		_sk_p.clear()
		_sk_next = 0
		_sk_hw = 0
		return false
	var z: float = cv[4]
	for k in _sk_hw:
		var p: Array = _sk_p[k]
		var kk := FXK_SK + k * 8 + ((_fxk_sk[k] & 3) if k < _fxk_sk.size() else 0)   # part 26: quad 2 = + 4
		if p[5] == 0:
			_fx_box(-4000.0, -4000.0, 1, 1, 0, 0x001F80C0 | (0x2C << 24), 8, kk)
			_fx_box(-4000.0, -4000.0, 1, 1, 0, 0x001F80C0 | (0x2C << 24), 8, kk + 4)
			continue
		var sx := floorf(cv[2] + z * (p[0] - cv[0]))
		var sy := floorf(cv[3] + z * (p[1] - cv[1]))
		var al := clampi(31 - (p[4] - 8) * 3, 8, 30)
		var big: bool = p[4] >= 4 and p[4] <= 9         # twinkle: a small cross in the middle of its life
		_fx_box(sx - (1.0 if big else 0.0), sy, 3 if big else 1, 1, p[6], 0x80C0 | (al << 16) | (0x2C << 24), 9, kk)
		_fx_box(sx, sy - (1.0 if big else 0.0), 1, 3 if big else 1, p[6], 0x80C0 | (al << 16) | (0x2C << 24), 9, kk + 4)
	return true


## KO CONFETTI: watch HP once per battle frame, burst on 0, flutter, lie, fade
func _cf_frame(cv: Array, step: bool) -> bool:
	if step:
		for rec in _fx_recs():
			if (_ld(rec + 0x12, 2, false) & 8) != 0:
				continue
			var hp: int = _ld(rec + 0x24A, 2, true)
			if _cf_hp.get(rec, 0) > 0 and hp <= 0:
				_cf_burst(rec)
			_cf_hp[rec] = hp
		if not _cf_p.is_empty():
			var floor_y := float(_ld(_ld(_ld(0x0201B49C, 4, false), 4, false) + 0xCC2, 2, false) + BL_FEET)
			for p in _cf_p:
				if p[5] == 1:
					p[3] = minf(p[3] + 0.09, 0.9)          # flutter: slow terminal speed
					p[2] *= 0.96
					p[0] += p[2] + 0.35 * sin(p[4] * 0.25 + p[7])
					p[1] += p[3]
					p[4] += 1
					if p[1] >= floor_y + p[8]:
						p[1] = floor_y + p[8]
						p[5] = 2
					if p[4] > 120:
						p[5] = 0
				elif p[5] == 2:
					p[4] += 1
					if p[4] > 120:
						p[5] = 0
	if _cf_p.is_empty():
		return false
	var live := 0
	for p in _cf_p:
		if p[5] != 0:
			live += 1
	if live == 0:
		_cf_p.clear()
		_cf_next = 0
		_cf_hw = 0
		return false
	var z: float = cv[4]
	for k in _cf_hw:
		var p: Array = _cf_p[k]
		var st: int = p[5]
		var ck := FXK_CF + k * 4 + ((_fxk_cf[k] & 3) if k < _fxk_cf.size() else 0)   # part 26
		if st == 0:
			_fx_box(-4000.0, -4000.0, 1, 1, 0, 0x001F80C0 | (0x2D << 24), 8, ck)
			continue
		var sx := floorf(cv[2] + z * (p[0] - cv[0]))
		var sy := floorf(cv[3] + z * (p[1] - cv[1]))
		var s3 := maxi(1, int(round(3.0 * z)))
		var s2 := maxi(1, int(round(2.0 * z)))
		var w := s3
		var h := s2
		if st == 1:                                     # turning while it falls: 3x2, 2x3, 2x2 (edge-on 2x1)
			var ph := int(p[4] / 4 + p[7] * 3) % 4
			if ph == 1:
				w = s2
				h = s3
			elif ph == 2:
				w = s2
			elif ph == 3:
				h = maxi(1, s2 / 2)
		var al := clampi(31 - (p[4] - 100) * 2, 4, 31)
		_fx_box(sx, sy, w, h, p[6], 0x80C0 | (al << 16) | (0x2D << 24), 9, ck)
	return true


func _cf_burst(rec: int) -> void:
	if _cf_p.size() != CF_POOL:
		_cf_p.clear()
		for i in CF_POOL:
			_cf_p.append([0.0, 0.0, 0.0, 0.0, 0, 0, 0, 0.0, 0.0])
	var x := _ld(rec + 0x38, 4, true) / 256.0
	var y := _ld(rec + 0x3C, 4, true) / 256.0 - 10.0
	for i in CF_BURST:
		var a := _fx_rand(-PI, 0.0)                     # upward half circle
		var v := _fx_rand(1.2, 4.2)
		if _fxk_cf.size() != CF_POOL:
			_fxk_cf.resize(CF_POOL)
		_fxk_cf[_cf_next] += 1                          # part 26 pairing key
		_cf_p[_cf_next] = [x + _fx_rand(-6.0, 6.0), y + _fx_rand(-10.0, 10.0), cos(a) * v * 1.3, sin(a) * v, 0, 1,
			CF_COLS[i % CF_COLS.size()], _fx_rand(0.0, 6.28), _fx_rand(-2.0, 12.0)]
		_cf_next = (_cf_next + 1) % CF_POOL
		_cf_hw = maxi(_cf_hw, _cf_next if _cf_next > 0 else CF_POOL)
	if _bl_dbg or _fk_dbg:
		print("CONFETTI f%d rec %x at %.0f,%.0f" % [_port_frame(), rec, x, y])


func _fk_st(pool: int) -> Array:                       # debug (flashydbg): status bytes of the first 8 objects
	var r := []
	for i in 8:
		r.append(_ld(pool + i * 0x164 + 4, 1, false))
	return r


# ---- SCREEN SHAKE (part 23) ------------------------------------------------------------------------------------------
## biggest hit damage (FUN_020293A4 argument, before cheats change it) since DSDisplay last looked; DSDisplay turns it
## into a short shake of the battle screen and sets it back to 0. Picture only: nothing in the game reads it.
var shake_dmg: int = 0


# ---- LEADERBOARD (part 23) ---------------------------------------------------------------------------------------
## The game's only leaderboard is the Z-Battle HI-SCORE RANKING: 5 entries of 0x14 bytes at the start of the save
## data (RAM copy of the save block at 0x020DD5B4, data from +0x10): {s32 member ids[3] (38 = empty), u32 score,
## u32 difficulty (0 Easy, 1 Normal)}, best first. FUN_02002560(score, ids, difficulty) is the only code that changes
## it (called once at a course end by FUN_0208B9B8, which keeps the returned rank 1..5, 0 = not ranked, for the
## ranking screen's highlight); the game's save formatter (FUN_02004EFC / FUN_02005378 / FUN_0200580C) copies the
## default table from 0x020B6888. Maximum progress (0x020DD798[3], with unlocks) and Story progress are not
## leaderboards and are never touched here. DATA_NOTES "Session 1 part 23 findings (leaderboard)".
const LB_TABLE := 0x020DD5C4             ## the ranking in the save copy (5 x 0x14 bytes)
const LB_DEFAULTS := 0x020B6888          ## the game's default ranking (ARM9 data used by the save formatter)
const LB_SIZE := 0x64
const SAVE_OPEN := 0x020DD7A8            ## s8 -1 while the save memory is open (FUN_02005D24 .. FUN_02005914)
var lb_save_result := -1                 ## FUN_02004D8C's result of the last reset (0 = written to the save memory)
var _lb_at := -2                         ## debug: lbreset=F queues reset_leaderboards() at port frame F


## FUN_02002560(score, ids, difficulty): enter a Z-Battle course score into the HI-SCORE RANKING. With any cheat on
## (QoLSettings.cheats_on(); settings and weird settings do not count) the score is not entered: the result is 0,
## exactly what the game gets for a score below 5th place (results / ranking screens show the old table, no rank).
func f_02002560(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats != null and cheats.cheats_on() > 0:
		if Game.args.has("cheatdbg") or Game.args.has("lbdbg"):
			print("LEADERBOARD f%d score %d (difficulty %d) not entered: %d cheat(s) on" % [_port_frame(), param_1,
				param_3, cheats.cheats_on()])
		return 0
	var r := super.f_02002560(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if Game.args.has("lbdbg"):
		print("LEADERBOARD f%d score %d (difficulty %d) -> rank %d" % [_port_frame(), param_1, param_3, r])
	return r


## Settings menu "reset leaderboard": the HI-SCORE RANKING back to the game's own default table, then the game's
## own save routine FUN_02004D8C (header, CRC, write to the save memory -> DBZ_SSW2_Port.sav). Only the ranking
## changes: the rest of the save data is written back as it is in RAM. Call it on the game thread:
## QoLController.on_game_thread(game.reset_leaderboards).
func reset_leaderboards() -> void:
	for i in range(0, LB_SIZE, 4):
		_st(LB_TABLE + i, 4, _ld(LB_DEFAULTS + i, 4, false))
	# the game's own sequence (e.g. FUN_0208690C): open the save memory FUN_02005D24(0xD01 = 8 KiB EEPROM), write
	# FUN_02004D8C, close FUN_02005914. 0x020DD7A8 = -1 while a mode keeps it open: then only write (the mode closes it)
	var was_open := _ld(SAVE_OPEN, 1, true) == -1
	if not was_open:
		lb_save_result = f_02005d24(0xD01)
	if lb_save_result == 0 or was_open:
		lb_save_result = f_02004d8c()
		if not was_open:
			f_02005914()
	if Game.args.has("cheatdbg") or Game.args.has("lbdbg"):
		print("LEADERBOARD f%d reset to defaults, save result %d" % [_port_frame(), lb_save_result])


## [[ids, score, difficulty] x 5] (debug / tests)
func leaderboard() -> Array:
	var r := []
	for i in 5:
		var e := LB_TABLE + i * 0x14
		r.append([[_ld(e, 4, true), _ld(e + 4, 4, true), _ld(e + 8, 4, true)], _ld(e + 0xC, 4, false),
			_ld(e + 0x10, 4, false)])
	return r


func _lb_debug_tick() -> void:                         # debug flag lbreset=F (tests the menu's path)
	if _lb_at == -2:
		_lb_at = int(Game.flag("lbreset")) if Game.args.has("lbreset") else -1
	if _lb_at >= 0 and _port_frame() >= _lb_at:
		_lb_at = -1
		print("LEADERBOARD before reset ", leaderboard())
		var m: DSMachine = (Engine.get_main_loop() as SceneTree).current_scene.get("machine")
		m.inject.append(func():
			reset_leaderboards()
			print("LEADERBOARD after reset ", leaderboard()))


# ---- AUTO SKIP (part 24) --------------------------------------------------------------------------------------------
## AUTO SKIP (QoLSettings.auto_skip, SETTINGS 3; debug `autoskip=1`, log `skipdbg`). Only the game's own skip paths
## are used, so its state machines (story progress, saves, unlocks, music) run exactly as when the player skips:
## - Story Mode dialogue / narration scripts (scene 1, story states 0x15 before and 0x1D after a fight): the lower
##   screen's SKIP button test FUN_0203E214 reports a touch once per script -> FUN_02037A7C puts the script in skip
##   mode (ctx +0x84D = 0xFF), the script runs to its end without drawing or waiting, then the scene goes on.
## - Z-Battle VS screen (the blue screen before every Z-Battle fight, FUN_02018714 sub-states 1-2): A, which the
##   game itself accepts there (then fades out to the battle load).
## Everything else (menus, character / chapter select, battles, results, Story / Free / VS / Maximum VS screens,
## the Story ending pictures (the game allows no skip there, only closing their final message box), tutorials, attract
## mode) is untouched. Off (or noqol): every override below only calls super.
## DATA_NOTES "Session 1 part 24 findings (auto skip)".
const AS_SCENE := 0x020DD4C4            ## u8 scene id (1 = Story), u8 +1 battle state, u16 +2 sub-state
const AS_PAD := 0x020DD4DC              ## u16 keys pressed this frame (FUN_02001230), +4 held
const AS_STORY_STATE := 0x020DE4EC      ## u8 story scene state (FUN_0203FE78)
const AS_SCRIPT_ON := 0x020DE420        ## u8 0xFF while a story script is loaded
const AS_SCRIPT := 0x020DE424           ## s32 -> script context (+0x84D = 0xFF: skipping)
const AS_DEMO := 0x020DD54E             ## u8 party block +0x32 (FUN_02002728): non-zero = no A skip on the VS screen


func _as_on() -> bool:
	return cheats != null and cheats.auto_skip


func _as_log(what: String) -> void:
	if Game.args.has("skipdbg"):
		print("SKIP f%d %s (scene %d state %x)" % [_port_frame(), what, _ld(AS_SCENE, 1, false),
			_ld(AS_STORY_STATE, 1, false) if _ld(AS_SCENE, 1, false) == 1 else _ld(AS_SCENE + 1, 1, false)])


## A added to this frame's pressed keys around one call (_as_a_on returns the old word for _as_a_off, which restores
## the A bit: nothing else sees it)
func _as_a_on() -> int:
	var old := _ld(AS_PAD, 2, false)
	_st(AS_PAD, 2, old | 1)
	return old


func _as_a_off(old: int) -> void:
	_st(AS_PAD, 2, (_ld(AS_PAD, 2, false) & ~1) | (old & 1))


## SKIP button of the story script player (touch x 203-255, y 110-191)
func f_0203e214(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _as_on() and _ld(AS_SCENE, 1, false) == 1 and _ld(AS_SCRIPT_ON, 1, false) == 0xFF:
		var ctx := _ld(AS_SCRIPT, 4, false)
		if ctx != 0 and _ld(ctx + 0x84D, 1, false) != 0xFF:
			_as_log("story script")
			return 1
	return super.f_0203e214()


## the battle's VS screen
func f_02018714(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _as_on() and _ld(GAME_MODE, 4, false) == 0 and _ld(AS_DEMO, 1, false) == 0:
		var sub := _ld(AS_SCENE + 2, 2, false)
		if sub == 1 or sub == 2:
			_as_log("Z-Battle VS screen (sub-state %d)" % sub)
			var old := _as_a_on()
			var r := super.f_02018714(param_1, param_2, param_3, param_4)
			_as_a_off(old)
			return r
	return super.f_02018714(param_1, param_2, param_3, param_4)


# ---- WEIRD 3 (part 24) ----------------------------------------------------------------------------------------------
## WEIRD STUFF 3 settings, looks only (nothing here writes game RAM; with all three off nothing below runs):
## DAMAGE NUMBERS (QoLSettings.damage_numbers, `weird=dmgnum`): every FUN_020293A4 hit (damage > 0, any fighter record)
## pops up its damage over the victim's head; it rises ~22 px and fades over 1 s. Hits on the same victim within
## DN_MERGE battle frames add to the same number (beam streams of 120-damage ticks become one growing number; while it
## grows it follows the victim). Size / colour by the (merged) damage: < 300 white, < 800 yellow (1x), < 1500 orange,
## >= 1500 red (2x), guarded hits grey 1x; a new number or a higher tier pops one size bigger for 3 frames. Digits are
## hand-drawn 5x7 pixel glyphs with a 1 px dark outline and a darker lower half, sent as untextured GX quads after the
## sprite list (_fx_draw, last) at z 40 / 41: CAMERA ZOOM and SCREEN SHAKE move them like the sprites, and under
## MIRROR MODE each number is drawn mirrored so the flipped picture reads correctly. Size does not follow the zoom.
## RAINBOW KI (QoLSettings.rainbow_ki, `weird=rainbow`): sprites of effect objects run by the plain projectile handler
## 0x020209E0 or a beam part handler (0x02020330 / 0x020203CC / 0x02020560) get a rainbow vertex colour (modulation)
## that cycles every RK_PERIOD battle frames, phase-shifted per object slot (beam segments form a moving gradient).
## The colour is written (GX COLOR) inside the game's own drawer FUN_02011384, from an override of the rotation helper
## FUN_020A71C8 that the drawer calls once per drawn sprite, just before that sprite's BEGIN; FLASHY KI's copies of the
## same objects take the same colour.
## (JELLY FIGHTERS, part 24, was removed in part 25 at the user's request.)
## Debug: `w3dbg` (hits, merges).
const DN_POOL := 8
const DN_LIFE := 60                     ## battle frames after the last hit added
const DN_FADE := 16
const DN_MERGE := 10                    ## hits this close (battle frames) on the same victim add up
const DN_RISE := 22.0
const DN_Z := 40
const DN_OUT := 0x0C63                  ## outline (3, 3, 3)
const DN_TIERS := [                     ## [damage below, scale, top colour, bottom colour]
	[300, 1, 0x7FFF, 0x6718],           ## white / (24, 24, 25)
	[800, 1, 0x23FF, 0x031F],           ## yellow (31, 31, 8) / (31, 24, 0)
	[1500, 2, 0x12DF, 0x01DF],          ## orange (31, 22, 4) / (31, 14, 0)
	[0x7FFFFFFF, 2, 0x191F, 0x0018],    ## red (31, 8, 6) / (24, 0, 0)
]
const DN_GUARD := [0, 1, 0x62D6, 0x4A10]   ## grey (22, 22, 24) / (16, 16, 18)
const DN_FONT := [
	[" ### ", "## ##", "## ##", "## ##", "## ##", "## ##", " ### "],
	["  ## ", " ### ", "  ## ", "  ## ", "  ## ", "  ## ", " ####"],
	[" ### ", "## ##", "   ##", "  ## ", " ##  ", "##   ", "#####"],
	["#### ", "   ##", "   ##", " ### ", "   ##", "   ##", "#### "],
	["  ###", " ####", "## ##", "## ##", "#####", "   ##", "   ##"],
	["#####", "##   ", "#### ", "   ##", "   ##", "## ##", " ### "],
	[" ### ", "##   ", "#### ", "## ##", "## ##", "## ##", " ### "],
	["#####", "   ##", "  ## ", "  ## ", " ##  ", " ##  ", " ##  "],
	[" ### ", "## ##", "## ##", " ### ", "## ##", "## ##", " ### "],
	[" ### ", "## ##", "## ##", " ####", "   ##", "   ##", " ### "],
	["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],   # part 41: "+" (character ':', VAMPIRE)
]
const RK_PERIOD := 36.0
const RK_SLOT_PHASE := 0.085
var _w3_t := 0                          ## battle frames (rainbow phase, wobble)
var _w3_in := false                     ## the game's sprite drawer runs with tint work to do
var _w3_list := 0
var _dn_glyphs: Array = []              ## per digit [outline rects, top rects, bottom rects], rect = [x, y, w, h]
var _dn_p: Array = []                   ## DN_POOL x [alive, record, total, world x, world y, age, dx, guarded, pop, tier, lift, serial]
var _dn_serial := 0
var _dn_merge := int(Game.flag("w3merge", str(DN_MERGE)))   ## debug: w3merge=N merge window (0: never merge)
var _rk_cols := {}                      ## sprite object -> GX colour (this frame)
var _rk_tinted := false
var _w3_dbg := Game.args.has("w3dbg")


## FUN_020A71C8(sin, cos): MTX_MULT_3x3 rotation about z. The sprite drawer FUN_02011384 calls it once per drawn sprite
## (after MTX_TRANS to the sprite centre, before its scale / texture / BEGIN); the drawer's loop index is its stack
## word +4 (frame 112 bytes), so the sprite is list[index].
func f_020a71c8(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _w3_in:
		_w3_sprite()
	return super.f_020a71c8(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


func _w3_sprite() -> void:
	var i: int = M.decode_u32(_sp - 112 + 4 - 0x2000000)
	if i < 0 or i >= 64:
		return
	var p: int = _ld(_w3_list + i * 4, 4, false)
	if not _rk_cols.is_empty() or _rk_tinted:
		var c: int = _rk_cols.get(p, -1)
		if c >= 0:
			io_write(0x4000480, 4, c)
			_rk_tinted = true
		elif _rk_tinted:
			io_write(0x4000480, 4, 0x7FFF)
			_rk_tinted = false


## FUN_020293A4 hook (damage > 0)
func _w3_hit(rec: int, dmg: int) -> void:
	if (_ld(rec + 0x12, 2, false) & 8) != 0:
		return                                          # drawn in screen coordinates
	if cheats.damage_numbers:
		_dn_hit(rec, dmg)


## battle sprite list about to be drawn (from _fx_before): step and prepare this frame's work
func _w3_prep(idx: Dictionary) -> void:
	_w3_list = _ld(SPR_LIST, 4, false)
	var step := _fx_upd
	if step:
		_w3_t += 1
	if cheats.rainbow_ki:
		_rk_prep(idx)
	elif not _rk_cols.is_empty():
		_rk_cols.clear()
	if cheats.damage_numbers and step:
		_dn_step()
	_w3_in = not _rk_cols.is_empty()


## the game's drawer has finished (start of _fx_draw)
func _w3_after() -> void:
	_w3_in = false
	if _rk_tinted:
		io_write(0x4000480, 4, 0x7FFF)
		_rk_tinted = false


func _w3_clear() -> void:
	_w3_in = false
	_dn_p.clear()
	_rk_cols.clear()


# --- rainbow ki
func _rk_prep(idx: Dictionary) -> void:
	_rk_cols.clear()
	var pool: int = _ld(FX_POOL, 4, false)
	if pool < 0x02000000 or pool >= 0x02400000:
		return
	for i in 48:
		var o := pool + i * 0x164
		var p := o + 0x124
		if (_ld(o + 4, 1, false) & 3) == 0 or not idx.has(p):
			continue
		var hd: int = _ld(_ld(o + 0x40, 4, false) + _ld(o + 6, 1, false) * 8, 4, false)
		if hd == FK_BLAST or hd == FK_BEAMS[0] or hd == FK_BEAMS[1] or hd == FK_BEAMS[2]:
			_rk_cols[p] = _rk_col(fposmod(_w3_t / RK_PERIOD + i * RK_SLOT_PHASE, 1.0))


func _rk_col(h: float) -> int:
	var c := Color.from_hsv(h, 0.72, 1.0)
	return int(c.r * 31.0 + 0.5) | (int(c.g * 31.0 + 0.5) << 5) | (int(c.b * 31.0 + 0.5) << 10)


## FLASHY KI copies of object o: its rainbow colour (white when it has none)
func _rk_obj(o: int) -> int:
	return _rk_cols.get(o + 0x124, 0x7FFF)


# --- damage numbers
func _dn_init() -> void:
	_dn_glyphs.clear()
	for d in DN_FONT.size():
		var bm: Array = DN_FONT[d]
		var fill := func(x: int, y: int) -> bool:
			return y >= 0 and y < 7 and x >= 0 and x < 5 and (bm[y] as String)[x] == "#"
		var out := func(x: int, y: int) -> bool:          # dilated (8 neighbours), glyph coords
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if fill.call(x + ox, y + oy):
						return true
			return false
		_dn_glyphs.append([_dn_rects(out, -1, 6, -1, 8), _dn_rects(fill, 0, 5, 0, 4), _dn_rects(fill, 0, 5, 4, 7)])
	_dn_p.clear()
	for i in DN_POOL:
		_dn_p.append([0, 0, 0, 0.0, 0.0, 0, 0.0, false, 0, 0, 0.0, 0])


## rectangles covering the set pixels of rows y0..y1-1, columns x0..x1-1 (row runs merged downward)
func _dn_rects(f: Callable, x0: int, x1: int, y0: int, y1: int) -> Array:
	var done: Array = []
	var open := {}                                      # Vector2i(run x, run w) -> rect
	for y in range(y0, y1):
		var runs := {}
		var x := x0
		while x < x1:
			if f.call(x, y):
				var s := x
				while x < x1 and f.call(x, y):
					x += 1
				runs[Vector2i(s, x - s)] = true
			else:
				x += 1
		for k in open.keys():
			if not runs.has(k):
				done.append(open[k])
				open.erase(k)
		for k in runs.keys():
			if open.has(k):
				open[k][3] += 1
			else:
				open[k] = [k.x, y, k.y, 1]
	done.append_array(open.values())
	return done


func _dn_tier(total: int, guard: bool) -> int:
	if guard:
		return -1
	for t in DN_TIERS.size():
		if total < DN_TIERS[t][0]:
			return t
	return DN_TIERS.size() - 1


func _dn_hit(rec: int, dmg: int) -> void:
	if _dn_p.size() != DN_POOL:
		_dn_init()
	var gact: int = _ld(rec + 6, 1, false)
	var guard := (_ld(rec + 0x250, 4, false) & 9) != 0 or gact == 0x18 or gact == 0x0E   # V: a blocked ki blast (108)
	# lands while the victim is in action 0x0E (0x18 = guard, the frame before); +0x250 & 9 = guarding (FUN_02027C2C)
	var x := _ld(rec + 0x38, 4, true) / 256.0
	var y := _ld(rec + 0x3C, 4, true) / 256.0 - 40.0
	var free := -1
	var oldest := 0
	var dx := 0.0
	for i in DN_POOL:
		var n: Array = _dn_p[i]
		if n[0] == 0:
			if free < 0:
				free = i
			continue
		if n[1] == rec and n[5] <= _dn_merge and n[7] == guard:   # stream / fast combo: add up
			n[2] += dmg
			n[5] = 0
			var t := _dn_tier(n[2], guard)
			if t > n[9]:
				n[8] = 3
				n[9] = t
			if _w3_dbg:
				print("DMGNUM f%d rec %x +%d = %d" % [_port_frame(), rec, dmg, n[2]])
			return
		if n[5] > (_dn_p[oldest] as Array)[5] or (_dn_p[oldest] as Array)[0] == 0:
			oldest = i
	var k := free if free >= 0 else oldest
	_dn_serial += 1
	_dn_p[k] = [1, rec, dmg, x, y, 0, dx, guard, 3, _dn_tier(dmg, guard), 0.0, _dn_serial]
	if _w3_dbg:
		print("DMGNUM f%d rec %x hit %d guard %s slot %d act %x +250 %x +254 %x +12 %x +10 %x" % [_port_frame(), rec, dmg, guard, k,
			_ld(rec + 6, 1, false), _ld(rec + 0x250, 4, false), _ld(rec + 0x254, 2, false), _ld(rec + 0x12, 2, false), _ld(rec + 0x10, 2, false)])


func _dn_step() -> void:
	for n in _dn_p:
		if n[0] == 0:
			continue
		n[5] += 1
		if n[8] > 0:
			n[8] -= 1
		if n[5] <= DN_MERGE:                             # still adding up: follow the victim's head
			n[3] = _ld(n[1] + 0x38, 4, true) / 256.0
			n[4] = _ld(n[1] + 0x3C, 4, true) / 256.0 - 40.0
		if n[5] >= DN_LIFE:
			n[0] = 0


func _dn_frame(cv: Array) -> bool:
	if _dn_p.is_empty():
		return false
	var bst: int = _ld(0x020DD4C5, 1, false)               # same rule as DSDisplay.mirror_active() (not paused: 9)
	var mirror: bool = cheats.mirror_mode and _ld(0x027E0004, 4, false) == 0x02013030 and bst >= 4 and bst != 9
	var z: float = cv[4]
	var lay: Array = []                                 # [slot, serial, centre x, natural centre y, w, h, ps, y]
	for i in DN_POOL:
		var n: Array = _dn_p[i]
		if n[0] == 0:
			continue
		var u := minf(int(n[5]) / float(DN_LIFE), 1.0)
		var rise := DN_RISE * (1.0 - (1.0 - u) * (1.0 - u))
		var tr: Array = DN_GUARD if n[9] < 0 else DN_TIERS[n[9]]
		var ps: int = tr[1] + (1 if n[8] > 0 else 0)
		var w := (str(n[2]).length() * 6 - 1) * ps + 2     # with the outline
		var h := 7 * ps + 2
		var sx := clampf(cv[2] + z * (float(n[3]) + float(n[6]) - cv[0]), w * 0.5 + 1.0, 255.0 - w * 0.5)
		var sy := clampf(cv[3] + z * (float(n[4]) - cv[1]) - rise, 30.0 + h * 0.5, 186.0 - h * 0.5)
		lay.append([i, n[11], sx, sy, w, h, ps, sy])
	if lay.is_empty():
		return false
	# stack: where each number would have to be for none to overlap (newest at its own place, older ones pushed up);
	# the older ones move there smoothly (lift only grows), and until they are clear the newest sits just below them
	lay.sort_custom(func(p, q): return p[1] > q[1])
	var placed: Array = []
	for e in lay:
		var y: float = e[3]
		y = _dn_clear(placed, e, y, -1.0)
		var n: Array = _dn_p[e[0]]
		var target := float(e[3]) - y
		if target > float(n[10]):
			n[10] = minf(target, float(n[10]) + maxf(1.5, (target - float(n[10])) * 0.45))
		placed.append([e[2], y, e[4], e[5]])
	lay.reverse()                                       # oldest first: placed at their lifted spots, newer ones below
	placed.clear()
	for e in lay:
		var y: float = float(e[3]) - float((_dn_p[e[0]] as Array)[10])
		y = _dn_clear(placed, e, y, 1.0)
		e[7] = y
		placed.append([e[2], y, e[4], e[5]])
	var drew := false
	for e in lay:
		var n: Array = _dn_p[e[0]]
		var y: float = e[7]
		if y - float(e[5]) * 0.5 < 4.0 or y + float(e[5]) * 0.5 > 190.0:
			continue                                    # pushed off the battle picture
		var a: int = n[5]
		var tr: Array = DN_GUARD if n[9] < 0 else DN_TIERS[n[9]]
		var ps: int = e[6]
		var w: float = float(e[4]) - 2.0
		var al := 31 if a < DN_LIFE - DN_FADE else clampi(31 * (DN_LIFE - a) / DN_FADE, 1, 30)
		var tx := floorf(float(e[2]) + w * 0.5) if mirror else floorf(float(e[2]) - w * 0.5)
		_dn_k = (int(n[11]) * 977 + int(n[2]) * 131 + ps * 17) & 0xFFF   # part 26: this number's pairing keys
		_dn_emit(str(n[2]), ps, tx, floorf(y - 3.5 * ps), mirror, tr[2], tr[3], al)
		drew = true
	return drew


## centre y for number e (w / h boxes incl. outline) moved in direction dir (-1 up, 1 down) until it keeps 2 px from
## every placed box [x, y, w, h]
func _dn_clear(placed: Array, e: Array, y: float, dir: float) -> float:
	var x: float = e[2]
	var w: float = e[4]
	var h: float = e[5]
	for it in 16:
		var moved := false
		for q in placed:
			if absf(x - float(q[0])) * 2.0 >= w + float(q[2]) + 2.0:
				continue                                # side by side
			var need := (h + float(q[3])) * 0.5 + 2.0
			if absf(y - float(q[1])) < need:
				y = float(q[1]) + dir * need
				moved = true
		if not moved:
			break
	return y


var _dn_k := 0                          ## part 26: running PLTT_BASE pairing key of the number being sent


## the next quad's PLTT_BASE: unused by untextured polygons, unique per quad of a number (its serial, total and size
## seed _dn_k), so smooth motion never pairs a quad with a different one (DATA_NOTES part 26)
func _dn_key() -> void:
	io_write(0x40004AC, 4, FXK_DN | (_dn_k & 0xFFF))
	_dn_k += 1


## one number: outline pass, then the fill pass (top / bottom colours) one z unit in front
func _dn_emit(digits: String, ps: int, tx: float, ty: float, mirror: bool, top: int, bot: int, al: int) -> void:
	var s := 16.0 * ps                                  # vertex unit 1/256 = 1 glyph pixel
	io_write(0x4000440, 4, 2)
	io_write(0x4000444, 4, 0)                         # MTX_PUSH
	for v in [-s if mirror else s, 0.0, 0.0, 0.0, s, 0.0, 0.0, 0.0, 1.0, tx, ty, float(DN_Z)]:
		io_write(0x4000464, 4, int(roundf(v * 4096.0)) & 0xFFFFFFFF)
	io_write(0x40004A8, 4, 0)                         # no texture
	io_write(0x4000488, 4, 0)
	for pz in 2:
		var pid := 0x26 if pz == 0 else 0x27        # own polygon IDs (game sprites 1-31, other effects 0x28-0x3E)
		io_write(0x40004A4, 4, 0x80C0 | (al << 16) | (pid << 24))
		io_write(0x4000480, 4, DN_OUT if pz == 0 else top)
		io_write(0x4000500, 4, 1)                     # BEGIN quads
		_dn_key()
		io_write(0x400048C, 4, 0)                     # VTX_16 (0, 0, z): sets this pass's z, then a hidden quad
		io_write(0x400048C, 4, 0 if pz == 0 else 0x1000)
		io_write(0x4000494, 4, 0)
		io_write(0x4000494, 4, 0)
		io_write(0x4000494, 4, 0)
		for k in digits.length():
			var g: Array = _dn_glyphs[digits.unicode_at(k) - 48]
			var gx := k * 6
			if pz == 0:
				_dn_quads(g[0], gx)
			else:
				_dn_quads(g[1], gx)
		if pz == 1:
			io_write(0x4000480, 4, bot)
			for k in digits.length():
				_dn_quads((_dn_glyphs[digits.unicode_at(k) - 48] as Array)[2], k * 6)
		io_write(0x4000504, 4, 0)                     # END
	io_write(0x4000448, 4, 1)                         # MTX_POP


func _dn_quads(rects: Array, gx: int) -> void:
	for r in rects:
		var x0: int = ((gx + r[0]) * 256) & 0xFFFF
		var x1: int = ((gx + r[0] + r[2]) * 256) & 0xFFFF
		var y0: int = ((r[1] * 256) & 0xFFFF) << 16
		var y1: int = (((r[1] + r[3]) * 256) & 0xFFFF) << 16
		_dn_key()                                       # part 26
		io_write(0x4000494, 4, x0 | y0)               # VTX_XY
		io_write(0x4000494, 4, x0 | y1)
		io_write(0x4000494, 4, x1 | y1)
		io_write(0x4000494, 4, x1 | y0)


# ---- BOMB RAIN (part 25) --------------------------------------------------------------------------------------------
## WEIRD STUFF 3 setting BOMB RAIN (QoLSettings.bomb_rain, `weird=bombs`): everything is in scripts/qol/qol_bombs.gd;
## hooks here: f_0202954C (tick once per battle frame), f_0202A40C (reset at every battle load), _fx_any / _fx_draw
## (drawn after the game's sprite list). DATA_NOTES "Session 1 part 25 findings (bomb rain)".
const _BOMBS_GD := preload("res://scripts/qol/qol_bombs.gd")
var _bombs = null                        ## created the first time a battle frame runs with the setting on
var _bomb_img: Image = _BOMBS_GD.load_image()   ## loaded here, on the main thread


func _br_tick() -> void:
	if _bombs == null:
		_bombs = _BOMBS_GD.new(self, _bomb_img)
	_bombs.tick(_port_frame())


# ---- GREEN DEMON (part 36) ------------------------------------------------------------------------------------------
## Cheat GREEN DEMON (page 10 CHALLENGES, `cheats=green_demon`): everything is in scripts/qol/qol_green_demon.gd; hooks
## here: f_0202954C (tick once per battle frame), f_0202A40C (reset at every battle load), _fx_any / _fx_draw (drawn
## after the game's sprite list), f_02021DD4 (the game moves every effect object: the 1-UP moves too), f_020293A4 (its
## KO skips the damage cheats: `_gd_killing`). The texture block it shares with BOMB RAIN: qol_texblock.gd.
## DATA_NOTES "part 36 findings (green demon)".
const _GD_GD := preload("res://scripts/qol/qol_green_demon.gd")
const _TEXBLOCK_GD := preload("res://scripts/qol/qol_texblock.gd")
var _gd = null                           ## created the first time a battle frame runs with the cheat on
var _gd_img: Image = _GD_GD.load_image()  ## loaded here, on the main thread
var _texblk = null                       ## the port's battle texture block (BOMB RAIN + GREEN DEMON)
var _gd_killing := false                 ## f_020293A4 runs for the 1-UP's KO: no damage cheats


func _tex_block():
	if _texblk == null:
		_texblk = _TEXBLOCK_GD.new(self)
	return _texblk


func _gd_tick() -> void:
	if _gd == null:
		_gd = _GD_GD.new(self, _gd_img)
	_gd.tick(_port_frame())


## The 1-UP touched fighter `r` (from x world px): KO like the game's own heavy blast hit (BOMB RAIN's _hurt, never
## guarded): push away FUN_020213A8, HP to 0 through FUN_020293A4 (all of it; scale +0x1676 undone; INFINITE HEALTH /
## HARD MODE skipped), hit reaction 0x11 FUN_02021B4C, stun +0x25E, hit flag +0x250 = 2. HP <= 0 starts the game's KO.
func _gd_kill(r: int, x: float) -> void:
	var hp: int = _ld(r + 0x24A, 2, true)
	f_0201df20(0x027C0010, r, 2, 0)                    # hurt box {x0, y0, x1, y1} (qol_green_demon.gd BOX)
	var cx: float = (_ld(0x027C0010, 2, true) + _ld(0x027C0014, 2, true)) * 0.5
	var dir := 0x10 if cx >= x else 0x70               # away from the 1-UP, a little upward (0 right, 0x40 up)
	f_020213a8(r, 0x500, -0x40, 0, dir)
	var sc: int = _ld(_ld(TEAMS, 4, false) + 0x1676, 2, false)
	if hp > 0 and sc > 0:
		_gd_killing = true
		f_020293a4(r, (hp * 256 + sc - 1) / sc, 0)
		_gd_killing = false
	if _ld(r + 0x24A, 2, true) > 0:
		_st(r + 0x24A, 2, 0)
	if _ld(r + 6, 1, false) != 0x33:
		_st(r + 0x250, 4, 0)
		_st(r + 0x25D, 1, _ld(r + 0x1A, 1, false))
		f_02021b4c(r, 0x11)
	_st(r + 0x25E, 2, 10)
	_st(r + 0x250, 4, _ld(r + 0x250, 4, false) | 2)


## FUN_02021DD4(dx, dy): moves every live effect object by (dx, dy) (24.8) when the battle wraps around / STAGE SHUFFLE
## moves the fight; the 1-UP is one more object in the world
func f_02021dd4(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_02021dd4(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if _gd != null and _on("green_demon"):
		_gd.shift(((param_1 + 0x80000000) & 0xFFFFFFFF) - 0x80000000, ((param_2 + 0x80000000) & 0xFFFFFFFF) - 0x80000000)
	return r


# ---- MULTIPLAYER BATTLE (part 27) -----------------------------------------------------------------------------------
## LOCAL MULTIPLAYER, battle core (docs/MULTIPLAYER_DESIGN.md 3.7 / 3.8; DATA_NOTES "part 27 findings (MP battle)").
## While a session is in its BATTLE stage (QoLMp.in_battle()) player 2's fighter takes its input from the second human
## instead of the CPU: FUN_0202DCE0 (the AI; called once per battle frame, only by the input function FUN_02012DA8,
## with P2's and P1's active records) returns the port-only RAM struct MP_AI_OUT {u16 pressed, released, held, 0,
## touch x, y, touching, validity 0; u8 flags at +0x10} that FUN_02012DA8 copies into P2's record (+0x26C/E/70/72,
## +0x264..+0x26A, +0x263). Filled from QoLMp: held[1] (written by the main thread before each frame), presses
## latched in latch[1] (none lost on frames without an input call: hit stop), P2's touch in panel coordinates
## (QoLMpPanel.route: touch[1], new touches in tap[1]) with the game's flags: 3 at the first CALL that sees a new
## touch, 2 while held, 4 at the call after the release, else 0. Edges are per call, not per port frame. No AI runs
## for P2 (its AI state / RNG simply do not advance). The cheats that help player 1 help both players in an MP
## battle (`_helped(rec)` replaces each "+0x1A == 0" test; P2's own shuffle timer _shuf_p2, assists _assists2,
## random party _party_saved2). With no MP battle every one of these is the old test: the game stays byte-identical.
## Debug: `mpbattle=1` makes every Free Battle (mode 5) an MP battle at FUN_020140C8 (session stage BATTLE, ended
## at the next non-Free battle start); `mpdbg` prints P2's struct whenever it is not empty.
const MP_AI_OUT := 0x027C1000            ## port-only RAM (0x20 bytes; the port maps 8 MiB flat)
var _mp_held := 0                        ## P2's held word at the last input call
var _mp_touching := false                ## P2 touched at the last input call
var _mp_tpos := Vector2i(-1, -1)         ## P2's touch position at the last input call (also sent on the release)
var _mp_dbg := Game.args.has("mpdbg")
var _assists2 := -1                      ## P2 assists at battle start (INFINITE ASSISTS, MP battle)
var _party_saved2: Array = []            ## RANDOM CHARACTERS: P2's real party (MP battle)
var _shuf_p2 := [-1, -1, false, "", 0, -1]   ## P2's CHARACTER / CHAOS SHUFFLE state (see _shuf_p2_swap)


func _mp_on() -> bool:
	return mp != null and mp.in_battle()


## the cheats' "player 1" test: side 0, and side 1 too while an MP battle runs
func _helped(rec: int) -> bool:
	var side: int = _ld(rec + 0x1A, 1, false)
	return side == 0 or (side == 1 and _mp_on())


## P2's shuffle state <-> the shared variables the shuffle code uses (swapped in and out around P2's tick)
func _shuf_p2_swap() -> void:
	var s := [_shuf_t, _shuf_frame, _shuf_down, _shuf_wait, _chaos_obj_frames, _chaos_again]
	_shuf_t = _shuf_p2[0]
	_shuf_frame = _shuf_p2[1]
	_shuf_down = _shuf_p2[2]
	_shuf_wait = _shuf_p2[3]
	_chaos_obj_frames = _shuf_p2[4]
	_chaos_again = _shuf_p2[5]
	_shuf_p2 = s


## FUN_020140C8 (battle start): debug `mpbattle=1` turns a Free Battle into an MP battle; per-battle input state
func _mp_battle_start() -> void:
	if mp == null:
		return
	if Game.args.has("mpbattle") and Game.flag("mpbattle") != "0":
		if _ld(GAME_MODE, 4, false) == 5:
			if not mp.active:
				mp.start()
				mp.debug_battle = true
			mp.stage = QoLMp.BATTLE
			print("MP battle (debug mpbattle): Free Battle as a two-player battle")
		elif mp.debug_battle:
			mp.stop()
			mp.debug_battle = false
	if mp.in_battle():
		_mp_held = 0
		_mp_touching = false
		_mp_tpos = Vector2i(-1, -1)
		mp.latch[1] = 0
		mp.tap[1] = Vector2i(-1, -1)


## FUN_0202DCE0(P2 record, P1 record): the CPU AI -> P2's fake pad / touch. MP battle: the second human.
func f_0202dce0(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_on():
		return super.f_0202dce0(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var held: int = int(mp.held[1]) & 0xFFF
	var pressed: int = ((held & ~_mp_held) | int(mp.latch[1])) & 0xFFF
	var released: int = _mp_held & ~held
	mp.latch[1] = 0
	_mp_held = held
	var t: Vector2i = mp.touch[1]
	var flags := 0
	if mp.tap[1].x >= 0:                               # a new touch (maybe already over): its first call
		_mp_tpos = mp.tap[1]
		mp.tap[1] = Vector2i(-1, -1)
		flags = 3
		_mp_touching = true
	elif t.x >= 0:
		_mp_tpos = t
		flags = 2 if _mp_touching else 3
		_mp_touching = true
	elif _mp_touching:
		flags = 4                                      # released: the last position once more
		_mp_touching = false
	_st(MP_AI_OUT, 2, pressed)
	_st(MP_AI_OUT + 2, 2, released)
	_st(MP_AI_OUT + 4, 2, held)
	_st(MP_AI_OUT + 6, 2, 0)
	_st(MP_AI_OUT + 8, 2, _mp_tpos.x if flags != 0 else 0)
	_st(MP_AI_OUT + 0xA, 2, _mp_tpos.y if flags != 0 else 0)
	_st(MP_AI_OUT + 0xC, 2, 1 if flags == 2 or flags == 3 else 0)
	_st(MP_AI_OUT + 0xE, 2, 0)
	_st(MP_AI_OUT + 0x10, 4, flags)
	if _mp_dbg and (held != 0 or pressed != 0 or released != 0 or flags != 0):
		print("MP f%d p2 pressed %x released %x held %x touch %d,%d flags %d act %x" % [_port_frame(), pressed, released,
			held, _mp_tpos.x, _mp_tpos.y, flags, _ld(param_1 + 6, 1, false)])
	return MP_AI_OUT


# ---- MULTIPLAYER MENU (part 27) -------------------------------------------------------------------------------------
## LOCAL MULTIPLAYER menu flow (docs/MULTIPLAYER_DESIGN.md 2 / 3.3). With MULTIPLAYER off / no session: super only.
## VS BATTLE menu (scene 0x11, FUN_0207BA08 state 2): FUN_0207B778 returns 1 (left = HOST, here LOCAL), 2 (right =
## CLIENT, here LAN), 3 (B) or 0. LOCAL / LAN are kept in the scene (returned as 0; QoLController opens the setup
## page / shows the LAN notice); after YES on "READY TO CONTINUE?" the override returns 2 once: the scene tears itself
## down and fades like for CLIENT, then calls FUN_02001014(4), redirected below to the character select (scene 3,
## Practice mode 0xB).

## FUN_0207B778 returned early (choice made) without its drawing tail: the yellow frame object (work +0x1068 at
## 0x37 / 200, 0x6E) and the message blink, drawn here when the choice is swallowed (no one-frame gap)
func _mp_vs_tail() -> void:
	var w := _ld(0x020E1148, 4, false)
	if _ld(w + 0x1066, 2, true) == 0:
		f_02011f98(w + 0x1068, 0x37, 0x6E, 1)
	else:
		f_02011f98(w + 0x1068, 0xC8, 0x6E, 0)
	f_0207a1f4(0)


func f_0207b778(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if lan != null and lan.state == QoLLan.SELECT and lan.connected():
		super.f_0207b778()                 # part 30 phase 3: ACCEPTed -> the game's HOST path on both machines (+0x33 = 1,
		return 1                           # scene 4 in mode 2: the single-team select)
	if mp == null or cheats == null or not cheats.multiplayer:
		return super.f_0207b778()
	if mp.go and mp.active:              # YES: leave through the CLIENT path (teardown, fade, FUN_02001014(4))
		mp.go = false
		return 2
	if mp.reopen_setup and mp.active:    # back from the character select with B: the setup page again
		mp.reopen_setup = false
		mp.menu_req = 1
	if mp.menu_req != 0 or (mp.active and mp.stage == QoLMp.SETUP):
		super.f_0207b778()               # the DS input is blank here: only its drawing tail runs
		return 0
	var r := super.f_0207b778()
	if r == 1 or r == 2:                 # LOCAL / LAN: stay; QoLController.after_step acts on it
		mp.menu_req = r
		_mp_vs_tail()
		return 0
	return r


## Scene changes while a LOCAL session runs (design section 2): the game's own screens, other exits and modes.
## (0x11 -> 4) => 3, mode 0xB, wireless / host flags +0x32 / +0x33 cleared (FUN_02002738(0));
## (3 -> 0xC) => 0x11 (setup page reopens); (5 -> 0x13) => 0, mode 5 (Free Battle rules, P2 human);
## (0 -> 0x14 / 10 / 3 / 0xD) => 3, mode 0xB; (0 -> 6) => 6 and the session ends. Anything else: unchanged.
func f_02001014(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if allstar != null and (allstar.active or allstar.stage != QoLAllStar.NONE or allstar.debug_battle):
		param_1 = _gm_route(param_1)                   # part 34: Gamemode menu / All-Star session (`# ---- ALLSTAR MENU`)
	if lan != null and lan.in_battle:                  # part 30: leaving a LAN battle (`# ---- LAN CORE`)
		return super.f_02001014(_lan_battle_exit(param_1))
	if lan != null and lan.sel_on() and (mp == null or not mp.active):   # part 30 phase 3: LAN select / stage
		return super.f_02001014(_lan_sel_redirect(param_1))
	if mp == null or not mp.active or mp.debug_battle:
		return super.f_02001014(param_1)
	var cur := _ld(0x020DD4C4, 1, false)
	var to := param_1 & 0xFF
	var nto := to
	match cur:
		0x11:
			if to == 4:
				f_02002738(0)
				f_0200297c(0xB)
				mp.stage = QoLMp.SELECT
				nto = 3
		3:
			if to == 0xC:
				f_02002738(0)
				mp.reopen_setup = true
				mp.stage = QoLMp.SETUP
				nto = MP_VS_SCENE_ID
		5:
			if to == 0x13:
				f_0200297c(5)
				mp.stage = QoLMp.BATTLE
				nto = 0
		0:
			if to in [0x14, 10, 3, 0xD]:
				f_0200297c(0xB)
				mp.stage = QoLMp.SELECT
				nto = 3
	if nto == 3 or nto == 5:                 # part 27 MP select / stage: a new screen, both players start over
		mp_sel_reset()
		mp.stage = QoLMp.SELECT if nto == 3 else QoLMp.STAGE
	if Game.args.has("mpdbg"):
		var fm := _ld(0x020DD7B8, 4, false)            # file manager: open archives, file-cache entries in use
		var cache := 0
		for i in 48:
			if _ld(fm + 0x200 + i * 8 + 4, 4, false) != 0:
				cache += 1
		print("MP scene %x -> %x (asked %x) mode %d heap free %s archives %d cache %d" % [cur, nto, to, _ld(GAME_MODE, 4, false),
			str(_heap_free()), _ld(fm + 0x380, 4, false), cache])
	return super.f_02001014(nto)

const MP_VS_SCENE_ID := 0x11


# ---- MULTIPLAYER SELECT (part 27) -----------------------------------------------------------------------------------
## LOCAL MULTIPLAYER character select (scene 3, Practice mode 0xB) and stage select (scene 5) for two players
## (docs/MULTIPLAYER_DESIGN.md 3.5 / 3.6; DATA_NOTES "part 27 findings (MP select / stage / loop)"). While the session
## is in its SELECT / STAGE stage the DS pad / touch are blank (QoLMp.port_stages) and these overrides drive the
## screens from both players' input (QoLMp.pressed / held / sel_tap, written by QoLController.mp_frame):
## - FUN_0206CC94 (select input → result) runs the game's own function once per player and frame, with that player's
##   pad words (pad block 0x020DD4DC), key-repeat counters (0x020DEA18/1C/20/28), cursor bytes (cursor block
##   0x020DE9B8 +0x57 id, +0x58..+0x5B neighbours), new tap (TPData 0x020DE208 / flags 0x020DE1F4), side byte
##   (0x020DEA2C) and own team (0x020DE64C) swapped in, so moves, tab changes, taps, refusals and SE are the game's.
##   The DP tab (0x020DB534) is shared: a tab change brings the other cursor to the same fighter. One result per frame
##   (the loop handles one pick); a second player's presses wait a frame. The loop's FUN_0206ED18 then commits a pick
##   for the side byte (PLAYER list = P1, ENEMY list = P2). B removes the player's own last pick (the game's B pops the
##   last pick of both sides, so it never reaches the loop) or, with both teams empty, is injected to leave (→ the
##   controller setup page, f_02001014 redirect). START = that player done; 3 entries = done; both done → the game's
##   READY? overlay (A / GO tap from either player → stage select; B / BACK tap → both pick on).
## - FUN_0206A3D8 (draws the cursor objects) draws the outline (+4) and its pulse ring (+8), tinted with GX COLOR (red
##   P1, blue P2, purple when both are on one fighter), and the DP digits (+0x28) once per player.
## - FUN_0207215C (stage input) runs with blank input (bar scroll, the game's cursor objects), then moves both
##   players' icons (Up / Down ±4, Left / Right within the row, a tap = choose that stage), A chooses, B un-chooses
##   (nothing chosen by anyone + B → back to the select). Both chosen → 50/50 (QoLMp.rng), a roulette flicker between
##   the two, then 0x81 (the loop's confirm → FUN_02071374 → scene 0x13 → redirected to the battle, mode 5).
## - FUN_02071E64 (stage draw) draws the cursor object once per player (object +0xC for columns 0 / 2, +0x10 for
##   1 / 3, as the game), tinted; FUN_02070718 (the cursor's pulse colour) is white in an MP stage select so the tint
##   shows (the pulse goes on as brightness of the tint).
## With no session in these stages every override is `super` only.
const MS_CUR := 0x020DE9B8               ## cursor block: +4 outline, +8 label, +0x28 DP digits objects, +0x57 id
const MS_TAB := 0x020DB534               ## u32 DP tab 0-6, 7 = SP
const MS_SIDE := 0x020DEA2C              ## u8 side being picked
const MS_PICKS := 0x020DE658             ## s32[6] picks (0-2 P1, 3-5 P2)
const MS_PAD := 0x020DD4DC               ## u16 pressed, released, held
const MS_REP := [0x020DEA18, 0x020DEA1C, 0x020DEA20, 0x020DEA28]   ## key-repeat counters (FUN_0206CA2C)
const MS_TP := 0x020DE208                ## TPData u16 x, y, touch, validity
const MS_TPF := 0x020DE1F4               ## u8 touch flags (bit 0 new touch)
const MS_GO := 0x020D05CC                ## READY? GO rect u8 x0, y0, x1, y1
const MS_BACK := 0x020D05C8              ## READY? BACK rect u8 x0, y0, x1, y1
const MS_DPS := [0x020DE7C8, 0x020DE7E4, 0x020DE800]   ## part 28: u8 DP of the current side's slots 0-2
const MS_DPT := 0x020DBC34               ## part 28: u8 DP of character id (stride 0x1C, FUN_0206ED18)
const ST_CUR := 0x020DEB0C               ## stage cursor block: +0xC / +0x10 cursor objects, +0x20 s16 icon
const ST_XY := 0x020D0768                ## u16 x, y per icon (stride 8)
const ST_RECTS := [0x020D07E8, 0x020D0868]   ## touch rects per icon (8 bytes: x0, x1, y0, y1)
const MP_COL := [0x10DF, 0x7D86, 0x7CD8]     ## GX colours: P1 red, P2 blue, both purple
const ST_STEPS := [3, 3, 3, 3, 4, 4, 5, 5, 6, 7, 8, 10]   ## roulette: frames between switches
const ST_HOLD := 36                      ## frames the winner shows before the battle loads
var _ms_init := false
var _ms_cur := [PackedByteArray(), PackedByteArray()]
var _ms_rep := [[0, 0, 0, 0], [0, 0, 0, 0]]
var _ms_pend := [0, 0]
var _ms_ptap := [Vector2i(-1, -1), Vector2i(-1, -1)]
var _ms_conf := false
var _st_init := false
var _st_last := 0
var _st_flick := -1                      ## roulette frame counter (-1 = not running)
var _st_win := -1
var _st_cand := -1
var _st_switch: Array = []               ## roulette: frames at which the candidate changes
var _st_done := false                    ## 0x81 returned (the loop's exit fade still calls the input function)


func _mp_sel() -> bool:
	return mp != null and mp.active and not mp.debug_battle and mp.stage == QoLMp.SELECT


func _mp_stg() -> bool:
	return (mp != null and mp.active and not mp.debug_battle and mp.stage == QoLMp.STAGE) or _lan_stg()   # part 30: + LAN


## a new character select / stage select (f_02001014 redirect table: every scene change into 3 / 5)
func mp_sel_reset() -> void:
	_ms_init = false
	_ms_conf = false
	_ms_pend = [0, 0]
	_ms_ptap = [Vector2i(-1, -1), Vector2i(-1, -1)]
	_st_init = false
	_st_done = false
	_st_flick = -1
	_st_win = -1
	_st_cand = -1
	if mp != null:
		mp.ready = [false, false]
		mp.chosen = [-1, -1]
		mp.winner = -1


func _ms_picks(p: int) -> Array:
	var a := []
	for k in 3:
		a.append(_ld(MS_PICKS + (3 * p + k) * 4, 4, true))
	return a


func _ms_count(p: int) -> int:
	var n := 0
	for v in _ms_picks(p):
		if v != -1:
			n += 1
	return n


## the side byte and the current side's team (duplicate / family / support tests, FUN_0206ED18) = player p's.
## Part 28: also the current side's per-slot DP bytes (FUN_02066CA4 / 94 / 84 = u8 0x020DE7C8 / 7E4 / 800, summed
## by FUN_020671F4 for the DP limit of FUN_0206ED18 and the DP grey-out of FUN_0206ABB0): the game reloads them
## from the picks whenever its side changes; left shared, one player's full 20-DP team refused / greyed every
## pick of the other (DATA_NOTES part 28)
func _ms_side(p: int) -> void:
	_st(MS_SIDE, 1, p)
	var a := _ms_picks(p)
	for k in 3:
		f_02065e70(k, a[k] & 0xFFFFFFFF)
		_st(MS_DPS[k], 1, 0 if a[k] < 0 or a[k] > 0x26 else _ld(MS_DPT + a[k] * 0x1C, 1, false))


## part 28: ids >= 26 are supports; a team needs a fighter (FUN_02071374 only moves ONE support behind the fighters,
## the battle takes party slot 0 as the first active fighter)
func _ms_fighters(p: int) -> int:
	var n := 0
	for v in _ms_picks(p):
		if v >= 0 and v < 26:
			n += 1
	return n


## part 28 (GO): each MP team as fighters first, supports last (the game's FUN_02071374 reorders one support only;
## two supports -- SAME CHARACTERS -- could leave a support in slot 0)
func _ms_order() -> void:
	for p in 2:
		var a := _ms_picks(p)
		var f := []
		var s := []
		for v in a:
			if v >= 26:
				s.append(v)
			elif v >= 0:
				f.append(v)
		var o: Array = f + s
		while o.size() < 3:
			o.append(-1)
		if o != a:
			for k in 3:
				f_02065e90(3 * p + k, int(o[k]) & 0xFFFFFFFF)
			if _mp_dbg:
				print("MPS f%d p%d team order %s -> %s" % [_port_frame(), p + 1, str(a), str(o)])


## one call of the game's own FUN_0206CC94 for player p (its pad words, repeat counters, cursor, tap, side, team)
func _ms_call(p: int, pressed: int, held: int, released: int, tap: Vector2i) -> int:
	var pad := [_ld(MS_PAD, 2, false), _ld(MS_PAD + 2, 2, false), _ld(MS_PAD + 4, 2, false)]
	var tp := [_ld(MS_TP, 2, false), _ld(MS_TP + 2, 2, false), _ld(MS_TP + 4, 2, false), _ld(MS_TP + 6, 2, false)]
	var tpf := _ld(MS_TPF, 1, false)
	_st(MS_PAD, 2, pressed & 0xFFF)
	_st(MS_PAD + 2, 2, released & 0xFFF)          # (a release resets that direction's repeat counter)
	_st(MS_PAD + 4, 2, held & 0xFFF)
	for i in 4:
		_st(MS_REP[i], 4, _ms_rep[p][i])
	for i in 5:
		_st(MS_CUR + 0x57 + i, 1, _ms_cur[p][i])
	_ms_side(p)
	if tap.x >= 0:
		_st(MS_TP, 2, tap.x)
		_st(MS_TP + 2, 2, tap.y)
		_st(MS_TP + 4, 2, 1)
		_st(MS_TP + 6, 2, 0)
		_st(MS_TPF, 1, 3)
	else:
		_st(MS_TPF, 1, 0)
	var tab0 := _ld(MS_TAB, 4, false)
	var r: int
	if cheats != null and _on("same_characters"):
		var saved := _hide_team()
		r = super.f_0206cc94()
		_show_team(saved)
	else:
		r = super.f_0206cc94()
	var c := PackedByteArray()
	for i in 5:
		c.append(_ld(MS_CUR + 0x57 + i, 1, false))
	_ms_cur[p] = c
	for i in 4:
		_ms_rep[p][i] = _ld(MS_REP[i], 4, false)
	for i in 3:
		_st(MS_PAD + i * 2, 2, pad[i])
	for i in 4:
		_st(MS_TP + i * 2, 2, tp[i])
	_st(MS_TPF, 1, tpf)
	if _ld(MS_TAB, 4, false) != tab0:          # the tab is shared: the other cursor comes along to the same fighter
		_ms_cur[1 - p] = c.duplicate()
	return r & 0xFFFFFFFF


## player p's B: its own last pick goes (FUN_0206EABC for one side), or -- both teams empty -- the screen is left
func _ms_back(p: int) -> void:
	var a := _ms_picks(p)
	for k in [2, 1, 0]:
		if a[k] == -1:
			continue
		f_02065e90(3 * p + k, 0xFFFFFFFF)
		_ms_side(p)
		match k:
			0: f_02066ca4(0)
			1: f_02066c94(0)
			2: f_02066c84(0)
		if p == 0:
			f_0206f67c(f_020671f4())
		else:
			f_0206f404(f_020671f4())
		f_0206ef54()
		f_0206fa64()
		f_0206d57c(1)
		return
	if _ms_count(1 - p) == 0:
		mp.inject |= QoLMp.B                     # the loop's own B with nothing picked: leave (→ setup page)


## u8 rect {x0, y0, x1, y1} (READY? GO 0x020D05CC / BACK 0x020D05C8, as FUN_0206CC94 tests them)
func _ms_in(rect_addr: int, t: Vector2i) -> bool:
	return t.x >= _ld(rect_addr, 1, false) and t.x <= _ld(rect_addr + 2, 1, false) and t.y >= _ld(rect_addr + 1, 1, false) and t.y <= _ld(rect_addr + 3, 1, false)


func _mp_select() -> int:
	if not _ms_init:
		_ms_init = true
		var c := PackedByteArray()
		for i in 5:
			c.append(_ld(MS_CUR + 0x57 + i, 1, false))
		_ms_cur = [c, c.duplicate()]
		var rep := []
		for i in 4:
			rep.append(_ld(MS_REP[i], 4, false))
		_ms_rep = [rep.duplicate(), rep.duplicate()]
		mp.ready = [false, false]
	var taps := []
	for p in 2:
		var t: Vector2i = mp.sel_tap[p]
		if t.x < 0:
			t = _ms_ptap[p]
		_ms_ptap[p] = Vector2i(-1, -1)
		taps.append(t)
	var result := 0x800
	if f_0206a76c() != 0:
		if not _ms_conf:
			f_0206a748(0)                        # (shown by the game itself: not in an MP select)
		else:
			# the READY? overlay: either player answers (A / B, or a tap on GO / BACK)
			f_02068b18()
			var go := false
			var back := false
			for p in 2:
				var pr: int = mp.pressed[p] | _ms_pend[p]
				_ms_pend[p] = 0
				if (pr & QoLMp.A) != 0 or (taps[p].x >= 0 and _ms_in(MS_GO, taps[p])):
					go = true
				elif (pr & QoLMp.B) != 0 or (taps[p].x >= 0 and _ms_in(MS_BACK, taps[p])):
					back = true
			if go:
				_ms_order()                        # part 28: fighters first (two supports)
				_st(MS_SIDE, 1, 1)                 # GO with side byte 1: the loop leaves for the stage select
				_ms_conf = false
				_mp_ms_debug("GO")
				return 0x8000
			if back:
				f_0206a748(0)
				_ms_conf = false
				mp.ready = [false, false]
				f_0206d57c(1)
				_mp_ms_debug("BACK")
			return 0x800
	var picker := -1
	for p in [1, 0]:
		var pr: int = (mp.pressed[p] | _ms_pend[p]) & 0xFFF
		_ms_pend[p] = 0
		var hd: int = mp.held[p] & 0xFFF
		var tap: Vector2i = taps[p]
		if picker >= 0:                          # one result per frame: this player's input waits a frame
			_ms_pend[p] = pr
			_ms_ptap[p] = tap
			continue
		if mp.ready[p]:
			if (pr & QoLMp.B) != 0:
				mp.ready[p] = false
				f_0206d57c(1)
			continue
		if (pr & QoLMp.START) != 0:
			if _ms_fighters(p) > 0:              # (part 28: a team of supports only cannot fight)
				mp.ready[p] = true
				f_0206d57c(3)
			else:
				f_0206d57c(4)
			continue
		if (pr & QoLMp.B) != 0:
			_ms_back(p)
			continue
		var r := _ms_call(p, pr & ~(QoLMp.B | QoLMp.START | QoLMp.SELECT_BTN), hd, mp.released[p], tap)
		if r >= 26 and r < 0x800 and _ms_fighters(p) == 0 and _ms_count(p) >= 2:
			r = 0xFFFFFFFF                       # part 28: the last free slot is kept for a fighter (buzzer)
		if r == 0xFFFFFFFE or r == 0xFFFFFFF6:    # the CANCEL plate: as B, for this player only
			_ms_back(p)
		elif r != 0x800:
			result = r
			picker = p
			if r < 0x800 and cheats != null:     # BOSS CHARACTERS: the picking player's L
				if _on("boss_characters") and BOSS_LEVELS.has(r) and (hd & QoLMp.L) != 0:
					boss_pending = r
					boss_pending_side = p
				else:
					boss_pending = -1
	for i in 5:                                  # the game's own cursor = PLAYER 1's
		_st(MS_CUR + 0x57 + i, 1, _ms_cur[0][i])
	for i in 4:
		_st(MS_REP[i], 4, _ms_rep[0][i])
	mp.cur = [_ms_cur[0][0], _ms_cur[1][0]]
	mp.tab = _ld(MS_TAB, 4, false)
	if picker >= 0:
		_ms_side(picker)                         # FUN_0206ED18 commits the pick for this side
	else:
		_ms_side(0)
	if result == 0x800 and mp.ready[0] and mp.ready[1]:
		f_0206a748(1)                            # both done: the game's READY? GO / BACK overlay
		_ms_conf = true
		_mp_ms_debug("READY?")
	if result != 0x800:
		_mp_ms_debug("result %x by p%d" % [result, picker + 1])
	return result


func _mp_ms_debug(what: String) -> void:
	if _mp_dbg:
		print("MPS f%d %s cur %d/%d tab %d ready %s picks %s %s" % [_port_frame(), what, _ms_cur[0][0], _ms_cur[1][0],
			_ld(MS_TAB, 4, false), str(mp.ready), str(_ms_picks(0)), str(_ms_picks(1))])


## FUN_0206ED18 (commit a pick for the side byte): in an MP select a full team is that player's "done", never the
## game's own READY? (it returns 1 when the DP total is reached)
func f_0206ed18(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_sel():
		return super.f_0206ed18(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var r := super.f_0206ed18(param_1)
	var p := _ld(MS_SIDE, 1, false) & 1
	if r == 1:
		r = 0
	if r == 0 and _ms_count(p) == 3:
		mp.ready[p] = true
	_mp_ms_debug("pick %d for p%d -> %d" % [param_1, p + 1, r])
	return r


## FUN_0206A3D8: the cursor objects, once per player (outline tinted)
func f_0206a3d8(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_sel() or not _ms_init:
		return super.f_0206a3d8(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var o4 := _ld(MS_CUR + 4, 4, false)
	var o8 := _ld(MS_CUR + 8, 4, false)
	var o28 := _ld(MS_CUR + 0x28, 4, false)
	var keep := [_ld(o4 + 0x3C, 4, false), _ld(o4 + 0x40, 4, false), _ld(o8 + 0x3C, 4, false), _ld(o8 + 0x40, 4, false)]
	var ids := [int(_ms_cur[0][0]), int(_ms_cur[1][0])]
	var ents := [[ids[1], MP_COL[1]], [ids[0], MP_COL[0]]] if ids[0] != ids[1] else [[ids[0], MP_COL[2]]]
	for e in ents:
		var id: int = e[0]
		var hx := _ld(0x020D04F0 + _ld(0x020D04A0 + id, 1, false) * 4, 2, false)
		var hy := _ld(0x020D04F2 + _ld(0x020D04A0 + id, 1, false) * 4, 2, false)
		var x := hx + 0x16
		var y := hy + (0x10 if x < 0x60 else 0xF)
		for o in [o4, o8]:
			_st(o + 0x3C, 4, x << 12)
			_st(o + 0x40, 4, y << 12)
		io_write(0x04000480, 4, e[1])            # the outline and its pulse ring (+8), tinted
		f_0200aebc(o4)
		f_0200aebc(o8)
		io_write(0x04000480, 4, 0x7FFF)
		_st(o28 + 0x3C, 4, x << 12)
		_st(o28 + 0x40, 4, (hy + 0x23) << 12)
		_st(o28 + 0x44, 4, 0x69000)
		_st(o28, 4, _ld(0x020DE9C4 + (_ld(0x020D0478 + id, 1, false) - 1) * 4, 4, false))
		if _ld(0x020DB608 + id, 1, true) != 0:
			f_0200aebc(o28)
	_st(o4 + 0x3C, 4, keep[0])
	_st(o4 + 0x40, 4, keep[1])
	_st(o8 + 0x3C, 4, keep[2])
	_st(o8 + 0x40, 4, keep[3])
	return 0


## ---- stage select
func f_0207215c(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _lan_stg():
		return _lan_stage()                      # part 30 phase 3: LAN stage select (`# ---- LAN SELECT`)
	if not _mp_stg():
		return super.f_0207215c(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	super.f_0207215c()                           # blank input: bar scroll, the game's cursor objects
	var gi := _ld(ST_CUR + 0x20, 2, true) & 15
	if not _st_init:
		_st_init = true
		mp.icon = [gi, gi]
		mp.chosen = [-1, -1]
		mp.winner = -1
		_st_last = 0
	if _st_flick >= 0:                           # the 50/50 roulette, then the battle
		return _st_roulette()
	for p in 2:
		var pr: int = mp.pressed[p]
		var tap: Vector2i = mp.sel_tap[p]
		var ic: int = mp.icon[p]
		if tap.x >= 0:
			var hit := -1
			for i in 16:
				for tb in ST_RECTS:
					var a: int = tb + i * 8
					if tap.x >= _ld(a, 2, false) and tap.x <= _ld(a + 2, 2, false) and tap.y >= _ld(a + 4, 2, false) and tap.y <= _ld(a + 6, 2, false):
						hit = i
			if hit >= 0:
				mp.icon[p] = hit
				mp.chosen[p] = hit
				_st_last = p
				f_0200ff9c(0, 0)
			continue
		if mp.chosen[p] >= 0:
			if (pr & QoLMp.B) != 0:
				mp.chosen[p] = -1
				f_02071054(1)
			continue
		var n := ic
		if (pr & QoLMp.UP) != 0:
			n = posmod(n - 4, 16)
		if (pr & QoLMp.DOWN) != 0:
			n = posmod(n + 4, 16)
		if (pr & QoLMp.RIGHT) != 0:
			n = (n & ~3) | ((n + 1) & 3)
		if (pr & QoLMp.LEFT) != 0:
			n = (n & ~3) | ((n + 3) & 3)
		if n != ic:
			mp.icon[p] = n
			_st_last = p
			f_02071054(0)
		if (pr & QoLMp.A) != 0:
			mp.chosen[p] = mp.icon[p]
			_st_last = p
			f_0200ff9c(0, 0)
		elif (pr & QoLMp.B) != 0 and mp.chosen[0] < 0 and mp.chosen[1] < 0:
			mp.inject |= QoLMp.B                 # nobody chose yet: back to the character select (the loop's B)
	_ms_icon(mp.icon[_st_last])                  # the top screen names the stage of the player who moved last
	if mp.chosen[0] >= 0 and mp.chosen[1] >= 0:
		_st_start(int(mp.chosen[0]) if (mp.chosen[0] == mp.chosen[1] or (mp.rng.randi() & 1) == 0) else int(mp.chosen[1]))
	mp.cand = _st_cand if _st_flick >= 0 else -1
	return 0


## both chose: the 50/50 winner `win` (one of mp.chosen) and the roulette's switch frames
func _st_start(win: int) -> void:
	_st_win = win
	mp.winner = _st_win
	_st_flick = 0
	_st_switch = []
	if mp.chosen[0] != mp.chosen[1]:
		var f := 0
		for s in ST_STEPS:
			f += s
			_st_switch.append(f)
	# the candidate before the last switch: after all switches it is the winner
	var other: int = int(mp.chosen[1]) if _st_win == int(mp.chosen[0]) else int(mp.chosen[0])
	_st_cand = _st_win if _st_switch.size() % 2 == 0 else other
	_ms_icon(_st_cand)
	if _mp_dbg:
		print("MPS f%d stage chosen %s winner %d" % [_port_frame(), str(mp.chosen), _st_win])


## one frame of the roulette (flicker between the two choices), then 0x81 (the loop's confirm -> the battle)
func _st_roulette() -> int:
	if _st_done:                                 # (the loop's exit fade calls this 60 more frames)
		_st(ST_CUR + 0x20, 2, _st_win)
		return 0
	_st_flick += 1
	if _st_switch.has(_st_flick):
		_st_cand = int(mp.chosen[1]) if _st_cand == int(mp.chosen[0]) else int(mp.chosen[0])
		f_02071054(0)
	_ms_icon(_st_cand)
	var end := ST_HOLD + (int(_st_switch[-1]) if not _st_switch.is_empty() else 0)
	if _st_flick >= end:
		_st(ST_CUR + 0x20, 2, _st_win)
		if _mp_dbg:
			print("MPS f%d stage icons %s -> %d" % [_port_frame(), str(mp.chosen), _st_win])
		_st_done = true
		return 0x81                              # the loop's confirm: FUN_02071374 commits the stage, battle next
	return 0


## the game's stage cursor icon (s16 0x020DEB2C); a change also sets the "moved" byte FUN_02071C8C writes, so the
## upper screen (FUN_02072FBC) shows that stage's name and description
func _ms_icon(ic: int) -> void:
	if _ld(ST_CUR + 0x20, 2, true) != ic:
		_st(ST_CUR + 0x20, 2, ic)
		f_02071c8c(1)


## FUN_02071E64 (stage select drawing): the cursor once per player, tinted
func f_02071e64(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_stg() or not _st_init:
		return super.f_02071e64(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	f_0200b244()
	var icons := _ld(0x020DEAE8 + 8, 4, false)
	for i in 16:
		f_0200ab48(_ld(icons + i * 0xC, 4, false))
	f_0200ab48(_ld(0x020DEB30 + 0xC, 4, false))
	f_0200ab48(_ld(0x020DEB30 + 0x10, 4, false))
	var lv: float = clampf(_ld(0x020DC094, 4, true) / 31.0, 0.0, 1.0)   # the game's pulse level (0..31)
	var ents := []
	if _st_flick >= 0:
		# roulette: the candidate in white, the other choice in its player's colour; after the last switch only the winner
		var done := _st_switch.is_empty() or _st_flick >= int(_st_switch[-1])
		for p in 2:
			var ic: int = mp.chosen[p]
			if ents.any(func(e): return e[0] == ic):
				continue
			if ic == _st_cand:
				ents.append([ic, 0x7FFF])
			elif not done:
				ents.append([ic, _mp_pulse(MP_COL[p], 0.0)])
	else:
		var ic0: int = mp.icon[0]
		var ic1: int = mp.icon[1]
		if ic0 == ic1:
			ents.append([ic0, _mp_pulse(MP_COL[2], 0.0 if mp.chosen[0] >= 0 and mp.chosen[1] >= 0 else lv)])
		else:
			ents.append([ic1, _mp_pulse(MP_COL[1], 0.0 if mp.chosen[1] >= 0 else lv)])
			ents.append([ic0, _mp_pulse(MP_COL[0], 0.0 if mp.chosen[0] >= 0 else lv)])
	for e in ents:
		var ic: int = e[0]
		var o := _ld(ST_CUR + (0x10 if (ic & 1) != 0 else 0xC), 4, false)
		var keep := [_ld(o + 0x3C, 4, false), _ld(o + 0x40, 4, false), _ld(o + 0x10, 2, false), _ld(o + 0x12, 2, false)]
		_st(o + 0x3C, 4, _ld(ST_XY + ic * 8, 2, true) << 12)
		_st(o + 0x40, 4, _ld(ST_XY + 2 + ic * 8, 2, true) << 12)
		_st(o + 0x10, 2, 0x47 if ic == 12 or ic == 15 else 0x48)
		_st(o + 0x12, 2, 0x1F if ic == 12 or ic == 15 else 0x20)
		io_write(0x04000480, 4, e[1])
		f_0200ab48(o)
		_st(o + 0x3C, 4, keep[0])
		_st(o + 0x40, 4, keep[1])
		_st(o + 0x10, 2, keep[2])
		_st(o + 0x12, 2, keep[3])
	io_write(0x04000480, 4, 0x7FFF)
	if f_02071c70() == 1:
		f_0200aebc(_ld(_ld(0x020DEAD4, 4, false) + 0xC, 4, false))
		f_0200ab48(_ld(0x020DEAF8 + 0xC, 4, false))
	return f_0200ab18()


## a player colour brightened toward white by `t` (0..1) at most half way: the game's yellow / white pulse
static func _mp_pulse(c: int, t: float) -> int:
	var r := c & 31
	var g := (c >> 5) & 31
	var b := (c >> 10) & 31
	var k := t * 0.5
	r = roundi(r + (31 - r) * k)
	g = roundi(g + (31 - g) * k)
	b = roundi(b + (31 - b) * k)
	return r | (g << 5) | (b << 10)


## FUN_02070718(level): the stage cursor's pulse colour (yellow ↔ white). White in an MP stage select: the players'
## colours come from the GX vertex colour (texture × colour), which a yellow texture would turn dark blue
func f_02070718(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mp_stg():
		return 0x7FFF
	return super.f_02070718(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_02069990 (draws the select; with the current side's team full it opens READY? by itself): in an MP select the
## team is hidden while it draws -- READY? comes only when both players are done (_mp_select)
func f_02069990(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_sel():
		return super.f_02069990(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var saved := _hide_team()
	var r := super.f_02069990()
	_show_team(saved)
	return r


# ---- MP QA (part 27) ------------------------------------------------------------------------------------------------
## MP battle end (DATA_NOTES "part 27 findings (MP QA)"): the game's KnockOut!! / TIME OVER banner names the result
## from the LOCAL side's point of view (u8 G+0x1BCA9, FUN_02012FEC; 0 = PLAYER 1): FUN_0201825C (battle state 0x11,
## KO) sub-state 1, at the end of its 60-frame countdown, spawns FUN_020225C8(P1 active, kind, G+0x1BCB8, …) with
## kind 0 WIN / 5 PERFECT (FUN_02029764(side) != 0: 100 % HP) when the winner (FUN_02029260, teams+0x11D0) is the
## local side, else 2 LOSE; FUN_020163F0 (state 0x0F, time over) sub-state 1: 1 WIN / 3 LOSE / 4 draw. Sub-state 3
## of both pans the camera (FUN_02019104(fighter, 0x1E)) to the winner when it is local, else to the loser.
## In an MP battle there is no "losing" player at the screen: the banner and the camera act as for a local winner
## (WIN / PERFECT for whoever won, camera on the winner's victory pose). Without an MP battle: super only.
var _mp_end := 0                         ## 1 KO banner frame, 2 time-over banner frame, 3 camera frame


func _mp_end_pre(ko: bool) -> void:
	_mp_end = 0
	var sub := f_020010c4() & 0xFFFF
	var cnt := _ld(_ld(0x020DE3A0, 4, false) + 0x1BCA4, 2, false)
	if sub == 1 and cnt == 0:
		_mp_end = 1 if ko else 2
	elif sub == 3:
		_mp_end = 3


func f_0201825c(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_on():
		return super.f_0201825c(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_mp_end_pre(true)
	var r := super.f_0201825c(param_1, param_2, param_3, param_4)
	_mp_end = 0
	return r


func f_020163f0(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_on():
		return super.f_020163f0(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_mp_end_pre(false)
	var r := super.f_020163f0()
	_mp_end = 0
	return r


## FUN_020225C8 hook (called first in the f_020225c8 override): the banner kind of an MP battle end
func _mp_end_kind(kind: int) -> int:
	var w := f_02029260()
	if w == 0:
		return kind
	if _mp_end == 1 and kind == 2:           # LOSE -> WIN, or PERFECT as the game gives a local winner
		kind = 5 if (f_02029764(_ld(w + 0x1A, 1, false)) & 0xFFFFFFFF) != 0 else 0
	elif _mp_end == 2 and kind == 3:         # TIME OVER: LOSE -> WIN
		kind = 1
	if _mp_dbg:
		print("MP f%d battle end banner kind %d winner side %d" % [_port_frame(), kind, _ld(w + 0x1A, 1, false)])
	return kind


## FUN_02019104(fighter, frames): camera pan; at an MP battle end always to the winner
func f_02019104(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mp_end == 3:
		var w := f_02029260()
		if w != 0 and param_1 != w:
			param_1 = w
	return super.f_02019104(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## MP character select grey-outs. FUN_0206ABB0 greys (object +4 frame variant = entry +0x22, else +0x21; entries
## u32 [0x020DE870] + id * 0x28, ids 0..0x25, only the shown tab's / the SP tab's) what the CURRENT side's team
## (0x020DE64C) would refuse: picked already, same family, a second support, DP. In an MP select it runs once per
## player still picking (not READY), and a face stays grey only when every one of them would be refused it -- with
## one player left picking that player's own greys, exactly as in single player.
## Part 28: each pass with that player's own DP slot bytes too (_ms_side; the shared bytes greyed everything for
## the other player once one team reached the 20-DP limit), with SAME CHARACTERS each player's team hidden (as the
## cheat's single-player path), and supports grey for a player whose last free slot is kept for a fighter.
func _mp_grey() -> int:
	var side := _ld(MS_SIDE, 1, false)
	var team := [_ld(SELECT_TEAM, 4, false), _ld(SELECT_TEAM + 4, 4, false), _ld(SELECT_TEAM + 8, 4, false)]
	var dps := [_ld(MS_DPS[0], 1, false), _ld(MS_DPS[1], 1, false), _ld(MS_DPS[2], 1, false)]
	var same: bool = cheats != null and _on("same_characters")
	var base := _ld(0x020DE870, 4, false)
	var sp_tab := _ld(MS_TAB, 4, false) == 7
	var ps := []
	for p in 2:
		if not mp.ready[p]:
			ps.append(p)
	if ps.is_empty():
		ps = [0, 1]
	var normal := []                         # per entry: some player may pick it
	normal.resize(0x26)
	normal.fill(false)
	var r := 0
	for p in ps:
		_ms_side(p)
		var no_sup := _ms_fighters(p) == 0 and _ms_count(p) >= 2
		if same:
			var saved := _hide_team()
			r = super.f_0206abb0()
			_show_team(saved)
		else:
			r = super.f_0206abb0()
		for i in 0x26:
			var e := base + i * 0x28
			var o := _ld(e + 4, 4, false)
			if o != 0 and _ld(o + 4, 1, false) != _ld(e + 0x22, 1, false) and not (no_sup and i >= 26):
				normal[i] = true
	for i in 0x26:
		var e := base + i * 0x28
		var o := _ld(e + 4, 4, false)
		if o == 0:
			continue
		if normal[i] and _ld(o + 4, 1, false) == _ld(e + 0x22, 1, false):
			_st(o + 4, 1, _ld(e + 0x21, 1, false))
		elif not normal[i] and sp_tab and i >= 26:
			_st(o + 4, 1, _ld(e + 0x22, 1, false))
	_st(MS_SIDE, 1, side)
	for k in 3:
		_st(SELECT_TEAM + 4 * k, 4, team[k])
		_st(MS_DPS[k], 1, dps[k])
	return r


# ---- MP SUPPORTS (part 28) ------------------------------------------------------------------------------------------
## Two supports in one team (possible with SAME CHARACTERS, which hides the team from the game's "second support"
## test FUN_02066088): the game's own assist call FUN_02026C00(fighter, touched) wants the touch inside EVERY support
## record's panel rect (+0x2D0..+0x2D6) at once -- never true for two supports -- and the arrival FUN_020277AC puts
## the team's LAST support record in the assist slot. In an MP battle the MP panel shows both supports (one half of
## the support box each, QoLMpPanel) and maps a tap to the touched support's rect centre; here the call is tested
## against that support's rect only (the other supports' rects are set to it for the call) and the arrival takes
## that support (the team's member count +0x8C9 is cut just after it for the call). One support, or no MP battle:
## the game's own functions unchanged.
var _ms2_guard := 0
var _ms2_k := [-1, -1]                   ## per side: party slot of the support whose call is in progress


## FUN_02026C00 hook (MP battle, a touch): returns the call result
func _ms2_call(f: int, touched: int) -> int:
	var side: int = _ld(f + 0x1A, 1, false) & 1
	var team: int = _ld(TEAMS, 4, false) + side * 0x8E8
	var sups := []
	for k in _ld(team + 0x8C9, 1, false):
		if _ld(team + k * 0x2D8 + 5, 1, false) > 0x19:
			sups.append(k)
	_ms2_guard += 1
	if sups.size() < 2:
		var r0 := f_02026c00(f, touched)
		_ms2_guard -= 1
		return r0
	var act: int = team + _ld(team + 0x8C8, 1, false) * 0x2D8
	var tx: int = _ld(act + 0x264, 2, false)
	var ty: int = _ld(act + 0x266, 2, false)
	var hit := -1
	for k in sups:
		var rc: int = team + k * 0x2D8 + 0x2D0
		if tx >= _ld(rc, 2, false) and tx <= _ld(rc + 4, 2, false) and ty >= _ld(rc + 2, 2, false) and ty <= _ld(rc + 6, 2, false):
			hit = k
	var keep := {}
	if hit >= 0:
		for k in sups:
			if k != hit:
				var rc: int = team + k * 0x2D8 + 0x2D0
				keep[k] = [_ld(rc, 4, false), _ld(rc + 4, 4, false)]
				_st(rc, 4, _ld(team + hit * 0x2D8 + 0x2D0, 4, false))
				_st(rc + 4, 4, _ld(team + hit * 0x2D8 + 0x2D4, 4, false))
	var r := f_02026c00(f, touched)
	for k in keep:
		var rc: int = team + k * 0x2D8 + 0x2D0
		_st(rc, 4, keep[k][0])
		_st(rc + 4, 4, keep[k][1])
	_ms2_guard -= 1
	if r != 0 and hit >= 0:
		_ms2_k[side] = hit
		if _mp_dbg:
			print("MP f%d p%d calls support slot %d (id %d)" % [_port_frame(), side + 1, hit, _ld(team + hit * 0x2D8 + 5, 1, false)])
	elif _mp_dbg and hit >= 0:
		print("MP f%d p%d support slot %d refused by the game (assist slot %x, assists %d)" % [_port_frame(), side + 1, hit,
			_ld(_ld(TEAMS, 4, false) + 0x11E0, 4, false), _ld(team + 0x8CA, 1, false)])
	return r


## FUN_020277AC hook (MP battle): the arrival of the support chosen by _ms2_call
func _ms2_arrive(f: int) -> int:
	var side: int = _ld(f + 0x1A, 1, false) & 1
	var team: int = _ld(TEAMS, 4, false) + side * 0x8E8
	var k: int = _ms2_k[side]
	_ms2_k[side] = -1
	var n: int = _ld(team + 0x8C9, 1, false)
	_ms2_guard += 1
	if k >= 0 and k + 1 < n:
		_st(team + 0x8C9, 1, k + 1)
	var r := f_020277ac(f)
	_st(team + 0x8C9, 1, n)
	_ms2_guard -= 1
	if _mp_dbg:
		var s: int = _ld(_ld(TEAMS, 4, false) + 0x11E0, 4, false)
		print("MP f%d p%d support arrives: slot %d, assist record id %d" % [_port_frame(), side + 1, k, _ld(s + 5, 1, false) if s != 0 else -1])
	return r


# ---- MP TEAM ARTS LIGHT (part 29) -----------------------------------------------------------------------------------
## The Touch! plate of a side is lit at 200 % ki when that side's active record has +0x274 & 0x100 ("a Team Arts partner
## is on the team"), set or cleared only by FUN_02026548(active). The game calls FUN_02026548 at the battle loader
## (FUN_0202A40C) for the LOCAL side's active only, on a tag (FUN_020281D8) / KO replacement (FUN_020298D4) of that
## side, and in the Team Arts test FUN_02026E34 itself (the tap) -- so P2's bit stayed 0 from the battle start until
## P2's first tag or Team Arts, while a tap on the "dim" plate did start Team Arts (V r1). In an MP battle the port
## recomputes the bit for each side's active fighter after its update every battle frame, with the Team Arts
## globals teams+0x11E4..+0x11F0 (that FUN_02026548 rewrites) put back. No MP battle: never called.
func _mta_tick(rec: int) -> void:
	var g: int = _ld(TEAMS, 4, false)
	if g == 0 or rec == 0:
		return
	var side: int = _ld(rec + 0x1A, 1, false) & 1
	var team: int = g + side * 0x8E8
	if rec != team + _ld(team + 0x8C8, 1, false) * 0x2D8:
		return                                       # Team Arts members / not the active fighter
	var keep := [_ld(g + 0x11E4, 4, false), _ld(g + 0x11E8, 4, false), _ld(g + 0x11EC, 4, false), _ld(g + 0x11F0, 4, false)]
	var was: int = _ld(rec + 0x274, 4, false) & 0x100
	f_02026548(rec)
	for i in 4:
		_st(g + 0x11E4 + i * 4, 4, keep[i])
	if _mp_dbg and (_ld(rec + 0x274, 4, false) & 0x100) != was:
		print("MP f%d p%d Team Arts partner %s (id %d)" % [_port_frame(), side + 1, "yes" if was == 0 else "no", _ld(rec + 5, 1, false)])


# ---- MP DUAL ASSISTS (part 29) --------------------------------------------------------------------------------------
## The game has ONE assist slot for both sides (u32 teams+0x11E0, DATA_NOTES part 15): FUN_02026C00 refuses a call
## while it is busy or while EITHER active fighter is in its call pose (+0x250 & 0x100), FUN_020277AC puts the
## caller's support record in it, the battle loop runs FUN_020294B8(*slot) once per frame, and FUN_0202B580 hides the
## record and clears the slot (the assist's own end handlers FUN_0202B5D8 / FUN_0202B604, or forced by the Team Arts
## end FUN_020287E8 and the grab / ultimate starts FUN_02028DDC / FUN_0202B698). Shenron's revive FUN_0202759C /
## FUN_0202B4A0 (KO'd fighter, FUN_0203483C) arrives only while the slot is free.
## In an MP battle each side gets its own slot: _mda[side] = the side's real support record on screen. The global
## slot holds one of them (so the game's "an assist is out" tests -- FUN_02015328 waiting for it, the KO state --
## see both), the other one runs right after it with the slot pointing at it (as ASSIST SPAM's copies). Every
## game function that tests or fills the slot for one side sees that side's own slot (_mda_call / _mda_arrive /
## _mda_own); a forced end ends both sides' assists. ASSIST SPAM copies keep working per side (8 each). The records
## are the teams' own (no copy), so both sides may call the same character. No MP battle: none of this runs.
var _mda := [0, 0]
var _mda_guard := 0
var _mda_cur := 0                        ## record being run by _mda_run (its own end in f_0202b580)
var _mda_frame := -1


func _mda_side(rec: int) -> int:
	return _ld(rec + 0x1A, 1, false) & 1


## a slot value no wrapper put there (e.g. an assist out when the session started): give it to its side
func _mda_sync() -> void:
	var s: int = _ld(_slot(), 4, false)
	if s != 0 and s != _mda[0] and s != _mda[1] and not _clones.has(s):
		_mda[_mda_side(s)] = s


## the global slot after a per-side operation: keep the one in it if still out, else either side's (0 = none)
func _mda_apply() -> void:
	var slot := _slot()
	var s: int = _ld(slot, 4, false)
	if s != 0 and (s == _mda[0] or s == _mda[1]):
		return
	_st(slot, 4, _mda[0] if _mda[0] != 0 else _mda[1])


## ASSIST SPAM copies of the caller's side (MP) / all copies (single player: the old limit)
func _mda_clones(f: int) -> int:
	if not _mp_on():
		return _clones.size()
	var n := 0
	for c in _clones:
		if _mda_side(c) == _mda_side(f):
			n += 1
	return n


## FUN_02026C00 (MP): the caller's own slot, the opponent's call pose does not block
func _mda_call(f: int, touched: int) -> int:
	var side := _mda_side(f)
	var slot := _slot()
	_mda_sync()
	var saved: int = _ld(slot, 4, false)
	var ot: int = _ld(TEAMS, 4, false) + (1 - side) * 0x8E8
	var o: int = ot + _ld(ot + 0x8C8, 1, false) * 0x2D8
	var ob: int = _ld(o + 0x250, 4, false)
	_st(slot, 4, _mda[side])
	_st(o + 0x250, 4, ob & ~0x100)
	_mda_guard += 1
	var r := f_02026c00(f, touched)
	_mda_guard -= 1
	_st(o + 0x250, 4, ob)
	_st(slot, 4, saved)
	if _mp_dbg and touched != 0:
		print("MP f%d p%d assist call %s (own assist %x, other %x, clones %d)" % [_port_frame(), side + 1,
			"ok" if r != 0 else "refused", _mda[side], _mda[1 - side], _clones.size()])
	return r


## FUN_020277AC (MP): the support arrives in the caller's own slot (or, slot busy + ASSIST SPAM, as a copy)
func _mda_arrive(f: int) -> int:
	var side := _mda_side(f)
	var slot := _slot()
	_mda_sync()
	var own: int = _mda[side]
	_st(slot, 4, own)
	_mda_guard += 1
	var r := f_020277ac(f)
	_mda_guard -= 1
	var now: int = _ld(slot, 4, false)
	if now != 0 and now != own and not _clones.has(now):
		_mda[side] = now
	_st(slot, 4, now if now != 0 else _mda[1 - side])
	_mda_apply()
	if _mp_dbg:
		print("MP f%d p%d assist arrives: own %x id %d (other %x, clones %d, slot %x)" % [_port_frame(), side + 1, _mda[side],
			_ld(_mda[side] + 5, 1, false) if _mda[side] != 0 else -1, _mda[1 - side], _clones.size(), _ld(slot, 4, false)])
	return r


## FUN_020294B8 (MP): the battle loop's call with the slot's assist runs it, then once per frame the other side's
## assist and the ASSIST SPAM copies, each with the slot pointing at it (its end clears the slot)
func _mda_run(p1: int, p2: int, p3: int, p4: int) -> int:
	var slot := _slot()
	if p1 != _ld(slot, 4, false):                    # Team Arts members (FUN_020287E8): the game's own call
		return super.f_020294b8(p1, p2, p3, p4)
	_mda_sync()
	var r := 0
	if p1 != 0:
		_mda_cur = p1
		r = super.f_020294b8(p1, p2, p3, p4)
		_mda_cur = 0
	var frame: int = _ld(0x020DD4C0, 2, false)
	if frame != _mda_frame:
		_mda_frame = frame
		_in_clones = true
		for s in 2:
			var a: int = _mda[s]
			if a != 0 and a != p1:
				_st(slot, 4, a)
				_mda_cur = a
				super.f_020294b8(a)
				_mda_cur = 0
		for c in _clones.duplicate():
			_st(slot, 4, c)
			_mda_cur = c
			super.f_020294b8(c)
			_mda_cur = 0
			if _ld(slot, 4, false) == 0:                 # its assist ended (the game hid it and freed the slot)
				_clones.erase(c)
				_clone_free.append(c)
		_in_clones = false
		if _mp_dbg and (_mda[0] != 0 or _mda[1] != 0 or not _clones.is_empty()) and _port_frame() % 10 == 0:
			var t := []
			for s in 2:
				var a: int = _mda[s]
				t.append("p%d %s" % [s + 1, "-" if a == 0 else "id %d act %x x %d hp %d" % [_ld(a + 5, 1, false), _ld(a + 6, 1, false),
					_ld(a + 0x38, 4, true) >> 8, _ld(a + 0x24A, 2, true)]])
			print("MDA f%d %s | %s | clones %d" % [_port_frame(), t[0], t[1], _clones.size()])
	_st(slot, 4, p1 if p1 != 0 and (p1 == _mda[0] or p1 == _mda[1]) else 0)
	_mda_apply()
	return r


## FUN_0202B580 (assist end): the running assist's own end ends only it; a forced end (Team Arts end, grab /
## ultimate start) sends both sides' assists away (the game's single assist leaves there too)
func f_0202b580(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _mp_on():
		return super.f_0202b580(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if _mda_cur != 0:
		var r0 := super.f_0202b580()
		for s in 2:
			if _mda[s] == _mda_cur:
				_mda[s] = 0
				if _mp_dbg:
					print("MP f%d p%d assist leaves" % [_port_frame(), s + 1])
		return r0
	_mda_sync()
	var r := 0
	for s in 2:
		if _mda[s] != 0:
			_st(_slot(), 4, _mda[s])
			var x := super.f_0202b580()
			r = x if r == 0 else r
			_mda[s] = 0
			if _mp_dbg:
				print("MP f%d p%d assist sent away (forced end)" % [_port_frame(), s + 1])
	var y := super.f_0202b580()
	return r if r != 0 else y


## FUN_0202759C (KO'd fighter: Shenron's revive arrives while the slot is free) / FUN_0202B4A0 (the same at the end
## of a knock-back flight): in an MP battle the fighter's own slot decides
func f_0202759c(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mda_guard != 0 or _mda_cur != 0 or not _mp_on() or _ld(param_1 + 0x24A, 2, false) != 0:
		return super.f_0202759c(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var slot := _slot()
	_mda_sync()
	_st(slot, 4, _mda[_mda_side(param_1)])
	var r := super.f_0202759c(param_1)
	_mda_apply()
	return r


func f_0202b4a0(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _mda_guard != 0 or _mda_cur != 0 or not _mp_on():
		return super.f_0202b4a0(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var slot := _slot()
	_mda_sync()
	_st(slot, 4, _mda[_mda_side(param_1)])
	var r := super.f_0202b4a0(param_1)
	_mda_apply()
	return r


# ---- LAN CORE (part 30) ---------------------------------------------------------------------------------------------
## LAN battles (docs/LAN_DESIGN.md 1.2 / 1.4 / 6.1; DATA_NOTES "Session 1 part 30 findings (LAN core)"). QoLLan (lan,
## set by QoLController; IDLE = nothing here runs) decides at FUN_020140C8 whether this battle start is a LAN battle
## (session connected, the host's STAGE_RESULT here; `lanbattle=1`: any Free Battle). Then, before the random cheats and
## the MP battle state: battle RNG FUN_020019FC(1) (index 0, no RTC reseed: what the game's own wireless battle does),
## instance-id counter u16 0x020DD7B4 = 0, main-loop frame counter u16 0x020DD4C0 = 0, wireless flags +0x32 / +0x33
## cleared, boss level 0, stage / parties from STAGE_RESULT (when given), the guest swaps the HOST's save copy into
## 0x020DD5B4 (the loader reads options / Team Arts unlocks from it), the port RNGs seeded from the battle seed. P2 is the
## other machine's player through the MP battle path (QoLMp.lan; f_0202dce0 reads the fields QoLLan writes from the
## records). The battle ends at FUN_02001014 from scene 0 on both machines at the same lockstep frame: save copy back,
## RNG mode 0; abort (disconnect / desync): the pause menu's "Mode Select" (f_0201546c returns 4) -> VS menu 0x11.
var lan: QoLLan = null
var _lan_own_save := PackedByteArray()   ## guest: its own save copy while the host's is in RAM for the battle
const LAN_SAVE := 0x020DD5B4
const LAN_SAVE_LEN := 0x1F4


## a LAN battle runs (lockstep or being aborted) — gameplay hooks must not use local state then (e.g. BOMB RAIN's view)
func lan_battle() -> bool:
	return lan != null and lan.in_battle


func _lan_battle_start() -> void:
	if lan == null or not lan.wants_battle(_ld(GAME_MODE, 4, false)):
		return
	var bi: Dictionary = lan.start_info                # (part 31: the STAGE_RESULT copy of this battle's redirect)
	f_020019fc(1)                                      # battle RNG: table index 0, never reseeded from the RTC
	_st(0x020DD7B4, 2, 0)                              # instance-id counter (object +0x22)
	_st(0x020DD4C0, 2, 0)                              # main-loop frame counter (shuffle tick dedupe)
	if _ld(0x020DD54E, 1, false) != 0 or _ld(0x020DD54F, 1, false) != 0:
		f_02002738(0)                                  # wireless flags +0x32 / +0x33 (never 2 = client in a battle)
	_st(0x020DD510, 1, 0)                              # boss level
	var stg := int(bi.get("stage", -1))
	if stg >= 0:
		_st(0x020DD54A, 1, stg)
	var teams = bi.get("teams", [])
	if teams is Array and teams.size() == 2:
		f_0200297c(5)
		for sd in 2:
			var ids: Array = teams[sd]
			var sup := 38
			for k in 3:
				var id := int(ids[k]) if k < ids.size() else 38
				_st(PARTY + sd * 0xC + k * 4, 4, id)
				if id >= 26 and id < 38:
					sup = id
			_st(PARTY_SUPPORT + sd * 4, 4, sup)
			_st(PARTY_COUNT + sd, 1, clampi(ids.size(), 1, 3))
		var bo = bi.get("boss", [])                    # phase 3: BOSS CHARACTERS picks of both players (the loader)
		if bo is Array and bo.size() == 2:
			for sd in 2:
				var tm := []
				for x in teams[sd]:
					tm.append(int(x))
				tm.sort()
				boss_teams[sd] = {"team": tm, "boss": (bo[sd] as Array).duplicate() if bo[sd] is Array else []}
	_lan_own_save = PackedByteArray()
	var sv = bi.get("save", PackedByteArray())
	if lan.role == "guest" and sv is PackedByteArray and sv.size() == LAN_SAVE_LEN:
		_lan_own_save = M.slice(LAN_SAVE - 0x2000000, LAN_SAVE - 0x2000000 + LAN_SAVE_LEN)
		for i in LAN_SAVE_LEN:
			M[LAN_SAVE - 0x2000000 + i] = sv[i]
	var sd0: int = int(bi.get("seed", 1)) & 0xFFFFFFFF  # the port's own RNGs (RANDOM CHARACTERS / STAGE, shuffles)
	rng.seed = sd0
	_shuf_rng.seed = sd0 ^ 0x53480000
	_shuf_seeded = true
	_stg_rng.seed = sd0 ^ 0x53540000
	_stg_seeded = true
	_rz_rng.seed = sd0 ^ 0x525A0000                    # part 39 RANDOMIZER
	_rz_seeded = true
	_shuf_frame = -1
	_stg_frame = -1
	_shuf_p2[1] = -1
	if mp != null:                                     # P2 = the other machine's player (MP battle rules on both)
		mp.clear_inputs()
		mp.lan = true
		mp.stage = QoLMp.BATTLE
	lan.on_battle_init()
	print("LAN battle start (%s): mode %d stage %d party %d %d %d / %d %d %d, save copy %s" % [lan.role,
		_ld(GAME_MODE, 4, false), _ld(0x020DD54A, 1, false), _ld(PARTY, 4, true), _ld(PARTY + 4, 4, true), _ld(PARTY + 8, 4, true),
		_ld(PARTY + 0xC, 4, true), _ld(PARTY + 0x10, 4, true), _ld(PARTY + 0x14, 4, true), "host's" if not _lan_own_save.is_empty() else "own"])


## FUN_02001014 while a LAN battle runs: the scene to go to instead of `param_1`
func _lan_battle_exit(param_1: int) -> int:
	var cur := _ld(0x020DD4C4, 1, false)
	var to := param_1 & 0xFF
	if cur != 0:
		return param_1
	var nto := to
	if lan.aborting or to == 6:                        # left alone / pause "Mode Select": the VS menu (lobby)
		f_02002738(0)
		f_0200297c(2)
		nto = MP_VS_SCENE_ID
	elif not lan.debug_battle and to in [0x14, 10, 3, 0xD]:   # the session's own flow: the team select (scene 4, mode 2)
		f_0200297c(2)
		f_02002738(1)
		f_020026e4(1)
		nto = 4
	if not _lan_own_save.is_empty():                   # the guest's own save copy again
		for i in LAN_SAVE_LEN:
			M[LAN_SAVE - 0x2000000 + i] = _lan_own_save[i]
		_lan_own_save = PackedByteArray()
	f_020019fc(0)
	if mp != null:
		mp.lan = false
		mp.stage = QoLMp.NONE if not mp.active else mp.stage
		mp.clear_inputs()
	lan.on_battle_exit(to)
	print("LAN battle exit: scene asked %x -> %x%s" % [to, nto, " (abort)" if lan.aborting else ""])
	return nto


## the battle pause menu (FUN_0201546C, state 9): while a LAN battle is being left alone (6.1) its "Mode Select" item
## (result 4 -> next scene 6) is chosen as soon as the menu takes input (sub-state 1)
func f_0201546c(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if lan == null or not lan.aborting:
		return super.f_0201546c(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var sub := f_020010c4()
	var r := super.f_0201546c(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if sub == 1 and r == 0:
		return 4
	return r


# ---- LAN SELECT (part 30, phase 3) -----------------------------------------------------------------------------------
## docs/LAN_DESIGN.md 4: the LAN team select and stage select on the game thread (QoLLan `# ---- LAN SELECT` sends and
## receives). With no LAN session (QoLLan.sel_on() false) nothing here runs.
## - FUN_0206CC94 in scene 4 (mode 2: the Z-Battle style single-team select, each machine its own team): the game's own
##   single-player select (SAME CHARACTERS / BOSS CHARACTERS as in single player). Its GO (READY? overlay: A / GO tap,
##   result 0x8000) is held: the team (fighters first, FUN_02066558's exit rules) goes to QoLLan (SELECT_READY), the
##   overlay stays up and 0x800 is returned every frame until QoLLan.sel_go() (host: the guest is ready too; guest: the
##   host's GO); B (the loop pops a pick and closes the overlay) or BACK = not ready any more. force_leave: the team is
##   emptied and B pressed (the loop's own exit with no picks: mode 2 -> FUN_02002738(0) + scene 0x11 = the room).
## - FUN_0207215C in scene 5: the LOCAL two-outline code with index me() driven by this machine's buttons (QoLLan.sel_filter
##   puts them into QoLMp) and the other index by the network (STAGE_CURSOR); the host decides the 50/50 (and resolves
##   the random icon to a stage id), the guest takes it from STAGE_RESULT; both run the same roulette -> 0x81.
## - FUN_02001014: 5 -> 7 (mode 2 battle request) => scene 0, mode 5, flags cleared, QoLLan.battle_pending (the battle
##   start sync `_lan_battle_start` then writes both teams / stage / seeds); 4 -> 0x11 by this machine's B = LEAVE_SELECT.
var _lan_sel_seen := ""                  ## the select round the hook last saw (a new round: per-round state reset; part 31:
										 ## session id + flow + round, so round 1 of a new session / flow is a new round too)
var _lan_wait := false                   ## GO pressed, waiting for the other player
var _lan_sel_n := 0                      ## frames of this team select (debug lanpicks)
var _lan_pick_i := 0
var _lan_stg_n := 0
var _lan_rem_icon := -1
var _lan_from := -1                      ## the scene before the teardown's FUN_02001014(2)


func _lan_stg() -> bool:
	return lan != null and mp != null and lan.sel_on() and _ld(0x020DD4C4, 1, false) == 5


func _lan_dbg(s: String) -> void:
	if Game.args.has("landbg"):
		print("LANS f%d %s" % [_port_frame(), s])


## the game's single-player select input (as f_0206cc94 without a session)
func _lan_sel_call() -> int:
	if cheats == null or not _on("same_characters") or f_0206a76c() != 0:
		var r0 := super.f_0206cc94()
		_note_pick(r0)
		return r0
	var saved := _hide_fighters()
	var r := super.f_0206cc94()
	_show_team(saved)
	_note_pick(r)
	return r


## the team as the battle gets it: FUN_02066558's exit order (a support in slot 0 / 1 moved back) and pair rule (id 7 ->
## 0x15 when the team holds 0x1E), empty slots dropped
func _lan_team() -> Array:
	var t := []
	for k in 3:
		t.append(_ld(SELECT_TEAM + 4 * k, 4, true))
	if t[0] > 0x19:
		var x = t[0]
		t[0] = t[1]
		t[1] = x
	if t[1] > 0x19 and t[2] < 0x1A:
		var x = t[1]
		t[1] = t[2]
		t[2] = x
	if 0x1E in t:
		for k in 3:
			if t[k] == 7:
				t[k] = 0x15
	var out := []
	for v in t:
		if v >= 0 and v < 38:
			out.append(v)
	return out


func _lan_ready() -> void:
	var team := _lan_team()
	var boss := []
	if cheats != null and _on("boss_characters"):
		var bt: Dictionary = boss_teams[0]
		if not bt.is_empty():
			boss = (bt.get("boss", []) as Array).duplicate()
	lan.local_ready(team, boss)
	_lan_wait = true
	_lan_dbg("READY team %s boss %s" % [team, boss])


func _lan_select() -> int:
	var tok := "%x/%d/%d" % [lan.session_id, lan.flow, lan.sel_round]
	if _lan_sel_seen != tok:
		_lan_sel_seen = tok
		_lan_wait = false
		_lan_sel_n = 0
		_lan_pick_i = 0
	_lan_sel_n += 1
	if lan.force_leave:                              # back to the room: no picks, the loop's own B exit
		for k in 3:
			_st(SELECT_TEAM + 4 * k, 4, 0xFFFFFFFF)
		if f_0206a76c() != 0:
			f_0206a748(0)
		lan.press_b = true
		return 0x800
	if _lan_wait:
		if lan.sel_go():
			_lan_wait = false
			_lan_dbg("GO (both ready)")
			return 0x8000
		if f_0206a76c() == 0:                        # the overlay was closed (B): not ready any more
			_lan_wait = false
			lan.local_unready()
			_lan_dbg("not ready any more")
		else:
			var rw := _lan_sel_call()
			if rw == 0x8000:
				return 0x800                         # (GO again: still waiting)
			if f_0206a76c() == 0:
				_lan_wait = false
				lan.local_unready()
				_lan_dbg("not ready any more (BACK)")
			return rw
	var sp := lan.script_picks()
	if not sp.is_empty():
		return _lan_script(sp)
	var r := _lan_sel_call()
	if r == 0x8000:
		_lan_ready()
		if lan.sel_go():
			_lan_wait = false
			_lan_dbg("GO (the other player was ready)")
			return 0x8000
		return 0x800
	return r


## debug lanpicks: picks one per 20 frames from `picks_delay`, then READY? + GO ([-1]: B with no picks = the room)
func _lan_script(sp: Array) -> int:
	var t0: int = lan.picks_delay
	if sp == [-1]:
		if _lan_sel_n == t0:
			_lan_dbg("lanrounds: B with no picks")
			lan.press_b = true
		return 0x800
	if _lan_pick_i < sp.size():
		if _lan_sel_n >= t0 + 20 * _lan_pick_i:
			_lan_pick_i += 1
			if (_lan_pick_i - 1) in lan.boss_dbg and cheats != null and _on("boss_characters"):
				boss_pending = int(sp[_lan_pick_i - 1])  # (as a pick with L held: QoLController's boss bookkeeping)
				boss_pending_side = 0
			return int(sp[_lan_pick_i - 1])
		return 0x800
	var t1 := t0 + 20 * sp.size()
	if f_0206a76c() == 0:
		if _lan_sel_n >= t1:
			f_0206a748(1)                            # the game's READY? GO / BACK overlay
		return 0x800
	if _lan_sel_n == t1 + 20:
		_lan_ready()
		if lan.sel_go():
			_lan_wait = false
			return 0x8000
	return 0x800


func _lan_sel_redirect(param_1: int) -> int:
	var cur := _ld(0x020DD4C4, 1, false)
	var to := param_1 & 0xFF
	if to == 2 and cur != 2:                         # the team select's teardown (FUN_02066230) calls FUN_02001014(2)
		_lan_from = cur                              # first: the real exit then sees scene 2
		return param_1
	if cur == 2 and _lan_from >= 0:
		cur = _lan_from
	_lan_from = -1
	var nto := to
	if cur == 4:
		_lan_sel_seen = ""                           # (the next team select starts over, also round 1 after the room)
	if cur == 4 and to == 0x11:
		if not lan.force_leave:
			lan.left_select()                        # B with no picks: the other player follows to the room
	elif cur == 5 and to == 7:
		if lan.force_leave or not lan.connected() or not lan.battle_fresh():
			if lan.connected() and not lan.force_leave:   # part 31: no STAGE_RESULT of this session / flow / round:
				lan.request_room("OUT OF STEP")      # never a battle without one (both back to the room)
			f_02002738(0)
			f_0200297c(2)
			nto = MP_VS_SCENE_ID
		else:
			f_0200297c(5)                            # Free Battle rules; the battle start sync writes teams / stage
			f_02002738(0)
			lan.battle_redirect()                    # (part 31: battle_pending + a copy of this round's STAGE_RESULT)
			nto = 0
	if nto == 5 or nto == 4:
		mp_sel_reset()
		if mp != null:
			mp.cand = -1                             # (part 31: no roulette mark of the last round at the next stage select)
	var mem := ""
	if Game.args.has("mpdbg"):                       # phase 4 QA: heap / file cache per round (as part 27's MP lines)
		var fm := _ld(0x020DD7B8, 4, false)
		var cache := 0
		for i in 48:
			if _ld(fm + 0x200 + i * 8 + 4, 4, false) != 0:
				cache += 1
		mem = " heap free %s archives %d cache %d" % [str(_heap_free()), _ld(fm + 0x380, 4, false), cache]
	_lan_dbg("scene %x -> %x (asked %x) mode %d%s" % [cur, nto, to, _ld(GAME_MODE, 4, false), mem])
	return nto


## the stage id of stage-select icon `ic` (FUN_02071374's table, u32 [0x020715FC]); the random icon (15) is resolved here
func _lan_stage_id(ic: int) -> int:
	var tab := _ld(0x020715FC, 4, false)
	var id := _ld(tab + ic, 1, false) if tab >= 0x02000000 and tab < 0x02400000 else ic
	if id == 15 or id > 14:
		id = randi_range(0, 14)
	return id


func _lan_stage() -> int:
	super.f_0207215c()                               # blank input: bar scroll, the game's cursor objects
	var me: int = lan.me()
	var gi := _ld(ST_CUR + 0x20, 2, true) & 15
	if not _st_init:
		_st_init = true
		mp.icon = [gi, gi]
		mp.chosen = [-1, -1]
		mp.winner = -1
		mp.cand = -1
		_st_last = me
		_lan_stg_n = 0
		_lan_rem_icon = -1
	_lan_stg_n += 1
	if (lan.force_leave or lan.stage_back) and _st_flick < 0:
		lan.press_b = true                           # the loop's own B: back to the team select
		return 0
	if _st_flick >= 0:
		return _st_roulette()
	var rc: Array = lan.remote_cursor()              # the other player's cursor (network)
	if int(rc[0]) >= 0:
		mp.icon[1 - me] = int(rc[0])
		if int(rc[0]) != _lan_rem_icon:
			_lan_rem_icon = int(rc[0])
			_st_last = 1 - me
	mp.chosen[1 - me] = int(rc[1]) if int(rc[0]) >= 0 else -1
	var pr: int = mp.pressed[me]
	var tap: Vector2i = mp.sel_tap[me]
	var ic: int = mp.icon[me]
	if tap.x >= 0:
		var hit := -1
		for i in 16:
			for tb in ST_RECTS:
				var a: int = tb + i * 8
				if tap.x >= _ld(a, 2, false) and tap.x <= _ld(a + 2, 2, false) and tap.y >= _ld(a + 4, 2, false) and tap.y <= _ld(a + 6, 2, false):
					hit = i
		if hit >= 0:
			mp.icon[me] = hit
			mp.chosen[me] = hit
			_st_last = me
			f_0200ff9c(0, 0)
	elif mp.chosen[me] >= 0:
		if (pr & QoLMp.B) != 0:
			mp.chosen[me] = -1
			f_02071054(1)
	else:
		var n := ic
		if (pr & QoLMp.UP) != 0:
			n = posmod(n - 4, 16)
		if (pr & QoLMp.DOWN) != 0:
			n = posmod(n + 4, 16)
		if (pr & QoLMp.RIGHT) != 0:
			n = (n & ~3) | ((n + 1) & 3)
		if (pr & QoLMp.LEFT) != 0:
			n = (n & ~3) | ((n + 3) & 3)
		if n != ic:
			mp.icon[me] = n
			_st_last = me
			f_02071054(0)
		if (pr & QoLMp.A) != 0:
			mp.chosen[me] = mp.icon[me]
			_st_last = me
			f_0200ff9c(0, 0)
		elif (pr & QoLMp.B) != 0:
			lan.back_req = true                      # nothing chosen: both back to the team select (host decides)
	if lan.stage_dbg >= 0 and _lan_stg_n == lan.stage_delay and mp.chosen[me] < 0:   # debug lanstage=ICON
		mp.icon[me] = lan.stage_dbg & 15
		mp.chosen[me] = lan.stage_dbg & 15
		_st_last = me
		f_0200ff9c(0, 0)
	lan.loc_icon = mp.icon[me]
	lan.loc_chosen = mp.chosen[me]
	_ms_icon(mp.icon[_st_last])
	if lan.role == "host":
		if mp.chosen[0] >= 0 and mp.chosen[1] >= 0:   # the host's 50/50 (and the random icon's stage)
			var win := int(mp.chosen[0]) if (mp.chosen[0] == mp.chosen[1] or (randi() & 1) == 0) else int(mp.chosen[1])
			var stg := _lan_stage_id(win)
			lan.stage_decided = {"round": lan.sel_round, "icons": [int(mp.chosen[0]), int(mp.chosen[1])], "winner": win, "stage": stg}
			_lan_dbg("stage chosen %s winner %d stage %d" % [str(mp.chosen), win, stg])
			_st_start(win)
	else:
		var res: Dictionary = lan.stage_result()
		if not res.is_empty():
			var ics: Array = res.get("icons", [mp.chosen[0], mp.chosen[1]])
			mp.chosen = [int(ics[0]), int(ics[1])]
			mp.icon = [int(ics[0]), int(ics[1])]
			_lan_dbg("stage result %s winner %d stage %d" % [str(mp.chosen), int(res.get("winner", -1)), int(res.get("stage", -1))])
			_st_start(int(res.get("winner", ics[0])))
	mp.cand = _st_cand if _st_flick >= 0 else -1
	return 0


# ---- ALLSTAR BATTLE (part 34) ---------------------------------------------------------------------------------------
## ALL-STAR phase 2 (docs/ALLSTAR_DESIGN.md 1.5 / 1.6 / 1.9; DATA_NOTES "part 34 findings (All-Star battle)"). Only
## while QoLAllStar.active and the battle runs in mode 5 (`_asb_on`, decided at FUN_020140C8): otherwise every hook is
## super only.
## - Battle start (FUN_020140C8, after RANDOM CHARACTERS / RANDOM STAGE): P2 = a rolling 2-member CPU team
##   [order[i], order[i+1]] (1 member for the last one), no support, stage 4 (Time Chamber), boss level 0; after super
##   the timer G+0x1BCA6 = 0xFFFF (no time-up).
## - Per frame (FUN_020010F4 = NitroMain's scene update, once per game frame): side-1 KOs counted (HP 0 seen once per
##   record), the clock (frames in battle states 7, 8, 0xA-0xE = fight + in-fight events, not 9 = pause, from FIGHT
##   until the last enemy's KO; cap 99:59), the swap (state 7 again after the game's own KO replacement, state 0xC:
##   the KO'd, hidden bench record is reloaded as the enemy after next with the CHARACTER SHUFFLE loader
##   `_shuffle_load` inside `_shuf_loading` (card-DMA gate), mirror palette when P1's team has that character, full
##   HP of the new character, face icon into its own per-side buffer), hearts (QoLAllStar.heart_req), HUD (MM:SS +
##   "n/26" in BG1 cells drawn from the game's own digit tiles), the result ("win" / "lose" once the battle ends).
## - FUN_02027164 (tag) refused for side 1 when touched (param_2 != 0; the KO path uses 0 and keeps working);
##   FUN_02026E34 (Team Arts) = 0 for side 1.
## Debug: `asdbg` (AS lines), `asp1=a,b,c` (P1's party for the battle, e.g. 3 members for heart tests),
## `asheart=F[:i],...` (use heart i at port frame F), `asclock=S` (start the clock at S seconds: cap test),
## `ashp=F:k:HP,...` (P1 record k's HP at port frame F: heart / lose tests).
const ASB_G := 0x020DE3A0                 ## u32 -> battle globals (timer u16 +0x1BCA6)
const ASB_FPS := 59.8261
const ASB_CAP := 5999                     ## seconds shown at most (99:59)
const ASB_SCRATCH := 0x027C8000           ## port-only RAM (unused): HUD tile composition
var _asb_on := false                      ## this battle is an All-Star battle
var _asb_next := 0                        ## order index of the next enemy to load into the KO'd bench record
var _asb_ko := [false, false, false]      ## side-1 records counted as KO'd (until reloaded)
var _asb_dbg := Game.args.has("asdbg")
var _asb_prev_state := -1
var _asb_swaps := 0
var _asb_heart_at: Array = []             ## debug `asheart=`: [port frame, heart]
var _asb_hp_at: Array = []               ## debug `ashp=F:k:HP`: [port frame, P1 record, HP]


func _asb_session() -> bool:
	return allstar != null and allstar.active and _ld(GAME_MODE, 4, false) == 5 and (mp == null or not mp.active) \
		and (lan == null or not lan.in_battle)


func _asb_log(s: String) -> void:
	if _asb_dbg:
		print("AS f%d %s" % [_port_frame(), s])


## FUN_020140C8 pre-super (the last step before the party is read): the All-Star battle setup
func _asb_battle_setup() -> void:
	_asb_on = false
	if not _asb_session():
		return
	_asb_on = true
	allstar.battle_reset()
	allstar.hearts = [true, true, true]
	allstar.heart_req = -1
	allstar.done = false
	allstar.done_frame = -1
	if Game.args.has("asp1"):                          # debug: P1's party for this battle
		var ids := Game.flag("asp1").split(",", false)
		for k in 3:
			_st(PARTY + k * 4, 4, int(ids[k]) if k < ids.size() else 38)
		_st(PARTY_SUPPORT, 4, 38)
		_st(PARTY_COUNT, 1, clampi(ids.size(), 1, 3))
	allstar.p1_ids = []
	for k in _ld(PARTY_COUNT, 1, false):
		allstar.p1_ids.append(_ld(PARTY + k * 4, 4, false))
	var a: int = allstar.enemy(0)
	var b: int = allstar.enemy(1)
	_st(PARTY + 0xC, 4, a)
	_st(PARTY + 0x10, 4, b)
	_st(PARTY + 0x14, 4, 38)
	_st(PARTY_SUPPORT + 4, 4, 38)                     # the enemy never calls a support
	_st(PARTY_COUNT + 1, 1, 2 if b != 38 else 1)
	_st(0x020DD54A, 1, QoLAllStar.STAGE_ID)            # Time Chamber
	_st(0x020DD510, 1, 0)                              # boss level 0
	boss_teams[1] = {}
	_asb_next = allstar.index + 2
	_asb_ko = [false, false, false]
	_asb_prev_state = -1
	_asb_swaps = 0
	_asb_refusals = {}
	_asb_heart_at = []
	_asb_hp_at = []
	if Game.args.has("ashp"):
		for e in Game.flag("ashp").split(",", false):
			_asb_hp_at.append(Array(e.split(":")).map(func(v): return int(v)))
	if Game.args.has("asheart"):
		for e in Game.flag("asheart").split(",", false):
			var q := e.split(":")
			_asb_heart_at.append([int(q[0]), int(q[1]) if q.size() > 1 else -1])
	_asb_hud_reset()
	_ass_reset()                                       # part 34 phase 3 (`# ---- ALLSTAR STAGE`)
	_asb_log("battle start%s: enemies %d, %d (index %d of %d) P1 %s heap %s" % [" (ENDLESS)" if allstar.endless else "", a, b,
		allstar.index, allstar.total(), str(allstar.p1_ids), str(_heap_free())])


## FUN_020140C8 post-super: no time limit
func _asb_battle_started() -> void:
	if _asb_on:
		_st(_ld(ASB_G, 4, false) + 0x1BCA6, 2, 0xFFFF)
		if Game.args.has("asclock"):                   # debug: the clock starts at S seconds (cap test)
			allstar.elapsed_frames = int(float(Game.flag("asclock")) * ASB_FPS)


## FUN_020010F4: NitroMain's scene update (once per game frame); the All-Star battle tick after it
func f_020010f4(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_020010f4(param_1, param_2, param_3, param_4, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if _asb_on:
		_asb_tick()
		if _asb_on:
			_ass_tick()                                 # part 34 phase 3: space sky + music (`# ---- ALLSTAR STAGE`)
	return r


func _asb_tick() -> void:
	if _ld(0x020DD4C4, 1, false) != 0 or allstar == null or not allstar.active:
		_asb_on = false                                 # the battle scene was left
		return
	var st: int = _ld(BATTLE_STATE, 1, false)
	var g: int = _ld(TEAMS, 4, false)
	if st < 4 or g < 0x02000000 or g >= 0x02400000:
		return
	var t1 := g + 0x8E8
	var cnt: int = clampi(_ld(t1 + 0x8C9, 1, false), 0, 3)
	var total: int = allstar.total()
	for k in cnt:                                      # side-1 KOs
		var r := t1 + k * 0x2D8
		if _ld(r + 5, 1, false) < 26 and _ld(r + 0x24A, 2, true) <= 0 and not _asb_ko[k]:
			_asb_ko[k] = true
			allstar.beaten += 1
			if allstar.start_index + allstar.beaten >= total and not allstar.done:
				allstar.done = true
				allstar.done_frame = _port_frame()
			_asb_log("enemy KO: id %d (record %d) beaten %d -> %d/%d clock %s%s" % [_ld(r + 5, 1, false), k, allstar.beaten,
				allstar.start_index + allstar.beaten, total, _asb_clock_text(), " LAST: clock stops" if allstar.done else ""])
	allstar.index = mini(allstar.start_index + allstar.beaten, total - 1)
	if not allstar.done and st in [7, 8, 0xA, 0xB, 0xC, 0xD, 0xE] and allstar.elapsed_frames < int((ASB_CAP + 1) * ASB_FPS) - 1:
		allstar.elapsed_frames += 1
	if st == 7:
		_asb_swap(t1, cnt)
	while not _asb_hp_at.is_empty() and _port_frame() >= _asb_hp_at[0][0]:   # debug `ashp=F:k:HP`
		var e: Array = _asb_hp_at.pop_front()
		_st(g + int(e[1]) * 0x2D8 + 0x24A, 2, int(e[2]))
		_asb_log("P1 record %d HP set to %d (ashp)" % [e[1], e[2]])
	if not _asb_heart_at.is_empty() and _port_frame() >= _asb_heart_at[0][0] and allstar.heart_req < 0:
		var h: int = _asb_heart_at.pop_front()[1]
		if h < 0:
			h = allstar.hearts.find(true)
		allstar.heart_req = h
		_asb_log("heart %d requested (asheart)" % h)
	if allstar.heart_req >= 0:
		_asb_heart(st)
	if st >= 0xF and st <= 0x11 and allstar.result == "":
		allstar.result = "win" if allstar.done else "lose"
		_asb_log("battle end (state %x): result %s, clock %s, beaten %d/%d, hearts used %d" % [st, allstar.result,
			_asb_clock_text(), allstar.start_index + allstar.beaten, total, allstar.hearts_used])
	if st != _asb_prev_state:
		if _asb_dbg:
			_asb_log("state %x -> %x (P2 active %d id %d)" % [_asb_prev_state, st, _ld(t1 + 0x8C8, 1, false),
				_ld(t1 + _ld(t1 + 0x8C8, 1, false) * 0x2D8 + 5, 1, false)])
		_asb_prev_state = st
	_asb_hud(st)


## seconds shown (capped)
func _asb_secs() -> int:
	return mini(int(allstar.elapsed_frames / ASB_FPS), ASB_CAP)


func _asb_clock_text() -> String:
	var s := _asb_secs()
	return "%02d:%02d" % [s / 60, s % 60]


## the KO'd, hidden bench record of side 1 becomes the enemy after next (state 7, after the game's replacement)
func _asb_swap(t1: int, cnt: int) -> void:
	if _asb_next >= allstar.total():
		return
	var act: int = _ld(t1 + 0x8C8, 1, false)
	for k in cnt:
		var r := t1 + k * 0x2D8
		if k == act or not _asb_ko[k] or _ld(r + 0x24A, 2, true) > 0:
			continue
		if f_02012fd4() != 0 or _ld(_ld(TEAMS, 4, false) + 0x11DC, 4, false) != 0 or _ld(SUBFILES, 1, false) != 0:
			return                                     # cut-in / pause / tag running / packed-file read busy
		if _shuffle_objects(r) > 0:
			return                                     # its KO effects still point into its chunks
		_asb_load(r, k)
		return


## load order[_asb_next] into side-1 record r (slot k), like a CHARACTER SHUFFLE swap of a bench record
func _asb_load(r: int, k: int) -> void:
	var n: int = allstar.at(_asb_next)                 # (part 38 ENDLESS: the next random fighter)
	var old: int = _ld(r + 5, 1, false)
	var h0 := _heap_free()
	_shuf_loading = true                               # part 18: no VBlank texture / BG uploads while loading
	var ok := _shuffle_load(r, n)
	if not ok:
		print("AS: loading character %d failed (heap %s); reloading %d" % [n, str(_heap_free()), old])
		n = old
		_shuffle_load(r, old)
	# the battle loader's mirror rule (FUN_0202A094): P2 takes the mirror palette when any P1 fighter is this character
	var pal: int = _ld(r + 0xFC, 4, false)
	if _cache_index(pal, true) >= 0:
		var g: int = _ld(TEAMS, 4, false)
		for j in 3:
			if _ld(g + j * 0x2D8 + 5, 1, false) == n:
				_st(r + 0xFC, 4, pal + 0x100)
				f_02010ae0(_ld(r + 0x10A, 2, false), pal + 0x100, 0x100)
				break
	var mx: int = _ld(_ld(r + 0x50, 4, false), 2, false)   # the new character's own max HP (as FUN_0202A094)
	_st(r + 0x24C, 2, mx)
	_st(r + 0x24A, 2, mx)
	_st(r + 0x254, 2, _ld(r + 0x254, 2, false) & 0xF7FF)   # as the game's revive FUN_020298D4
	_st(r + 0x250, 4, 0)
	f_02021b4c(r, 0)                                   # the action script of the new character
	_shuffle_icon(r, n)                                # life-bar face icon (per-side buffer)
	_asb_bar_paint(1, k, mx, mx, false)                # part 35: its bar buffer full again (was drained at the KO)
	_shuf_loading = false
	_asb_ko[k] = false
	_asb_next += 1
	_asb_swaps += 1
	if _asb_dbg:
		var m: int = _ld(FS_MGR, 4, false)
		var used := 0
		for i in 48:
			if _ld(m + 0x200 + i * 8 + 4, 4, false) != 0:
				used += 1
		_asb_log("swap #%d: record %d id %d -> %d ok %s hp %d/%d mirror %s next %d heap free %d/%d -> %s archives %d cache %d" % [
			_asb_swaps, k, old, n, ok, _ld(r + 0x24A, 2, true), mx, _cache_index(_ld(r + 0xFC, 4, false), true) < 0, _asb_next,
			h0[0], h0[1], str(_heap_free()), _ld(m + 0x380, 4, false), used])


## safety net (the KO path FUN_02027164(rec, 0, 0)): a side-1 KO while the other record is still waiting for its
## reload -> reload it now (its effect objects ended), so the game's replacement finds it alive
func _asb_ko_reload(f: int) -> void:
	if _asb_next >= allstar.total():
		return
	var t1: int = _ld(TEAMS, 4, false) + 0x8E8
	for k in clampi(_ld(t1 + 0x8C9, 1, false), 0, 3):
		var r := t1 + k * 0x2D8
		if r != f and _asb_ko[k] and _ld(r + 0x24A, 2, true) <= 0:
			_asb_log("KO before the bench was reloaded: reloading record %d now" % k)
			_chaos_prepare(r)
			_asb_load(r, k)
			return


## a heart: revive every KO'd P1 fighter (the game's own FUN_020298D4), heal all to max (FUN_02029428). Waits for
## the fight (state 7, no cut-in / pause, no Team Arts running, P1's active alive); dropped when nobody is hurt.
func _asb_heart(st: int) -> void:
	var i: int = allstar.heart_req
	if i < 0 or i > 2 or not allstar.hearts[i] or st >= 0xF:
		allstar.heart_req = -1
		return
	var g: int = _ld(TEAMS, 4, false)
	if st != 7 or f_02012fd4() != 0 or _ld(g + 0x11E4, 4, false) != 0 or _ld(g + 0x11DC, 4, false) != 0:
		return
	var act := f_02027c00(0)
	if act == 0 or _ld(act + 0x24A, 2, true) <= 0:
		return
	var cnt: int = clampi(_ld(g + 0x8C9, 1, false), 0, 3)
	var hurt := 0
	var dead := 0
	for k in cnt:
		var r := g + k * 0x2D8
		if _ld(r + 5, 1, false) < 26:
			var hp: int = _ld(r + 0x24A, 2, true)
			if hp < _ld(r + 0x24C, 2, true):
				hurt += 1
			if hp <= 0:
				dead += 1
	allstar.heart_req = -1
	if hurt == 0:
		_asb_log("heart %d: nobody hurt, nothing done" % i)
		return
	var before := _asb_p1_hp(g, cnt)
	for _n in dead:
		f_020298d4(0)                                  # the first KO'd member each time
	for k in cnt:
		var r := g + k * 0x2D8
		if _ld(r + 5, 1, false) < 26:
			f_02029428(r, _ld(r + 0x24C, 2, true))
	_asb_bars(0)                                       # part 35: every P1 bar from its HP (benched ones too)
	allstar.hearts[i] = false
	allstar.hearts_used += 1
	f_0200ff9c(0, 2)
	_asb_log("heart %d used: revived %d, HP %s -> %s" % [i, dead, before, _asb_p1_hp(g, cnt)])


var _asb_refusals := {}


## debug (asdbg): the CPU's tag / Team Arts attempts that were refused (first one and every 20th of each kind)
func _asb_refused(what: String) -> void:
	_asb_refusals[what] = int(_asb_refusals.get(what, 0)) + 1
	if _asb_dbg and int(_asb_refusals[what]) % 20 == 1:
		_asb_log("CPU %s refused (%d so far)" % [what, _asb_refusals[what]])


func _asb_p1_hp(g: int, cnt: int) -> String:
	var s := []
	for k in cnt:
		var r := g + k * 0x2D8
		s.append("%d:%d/%d" % [_ld(r + 5, 1, false), _ld(r + 0x24A, 2, true), _ld(r + 0x24C, 2, true)])
	return ",".join(s)


## FUN_02027164(fighter, touched, ki %): a tag request. All-Star: the enemy never tags (its KO path, param_2 = 0, works)
func f_02027164(param_1: int = 0, param_2: int = 0, param_3: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _asb_on and (_ld(param_1 + 0x1A, 1, false) & 1) == 1:
		if param_2 != 0:
			_asb_refused("tag")
			return 0
		_asb_ko_reload(param_1)
	return super.f_02027164(param_1, param_2, param_3, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## FUN_02026E34(fighter): the Team Arts touch test. All-Star: never for the enemy
func f_02026e34(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _asb_on and (_ld(param_1 + 0x1A, 1, false) & 1) == 1:
		_asb_refused("Team Arts")
		return 0
	return super.f_02026e34(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## ---- life bars (part 35; DATA_NOTES "part 35 findings (All-Star life bars)") ----
## The top-screen life bar is one 3D quad whose 74 columns are palette entries: per side a block B = *(0x020DE3BC) +
## side * 0x258 holds 3 colour buffers (pointers B+0xF3C, 0xA0 bytes = u16[80]: [0..0x49] the column colours,
## [0x4B] lost, [0x4C] full, [0x4D] damage flash, [0x4E] low, [0x4F] low flash), B+0xF4D[slot] = the buffer of team
## member `slot` (the active one's is buffer 0 = the shown one), B+0xF4A / +0xF4B shown / target columns, +0xF4C drain
## timer, B+0xF48 the palette handle, B+0xD3C the palette uploaded by FUN_02010AE0. The game only repaints columns of
## the ACTIVE member's buffer when its HP changes (FUN_0201D2xx per-frame update: up = fill 0..v full, down = drain),
## and the tag swap FUN_0201CBBC only exchanges buffers and sets +0xF4A/+0xF4B, so a member whose HP went UP while
## benched (heart heal / revive, All-Star's reloaded enemy) came back with its old "lost" columns = an empty-looking
## bar. FUN_020298D4 (revive) also writes the REVIVED member's columns into +0xF4A / +0xF4B even when another member
## is active. All-Star fix: repaint a member's buffer from its HP whenever it changes off-screen.
func _asb_bar_paint(side: int, slot: int, hp: int, mx: int, active: bool) -> void:
	var b: int = _ld(0x020DE3BC, 4, false) + side * 0x258
	if mx <= 0 or slot < 0 or slot > 2:
		return
	var idx: int = _ld(b + 0xF4D + slot, 1, false)
	if idx > 2:
		return
	var buf: int = _ld(b + 0xF3C + idx * 4, 4, false)
	if buf < 0x02000000 or buf >= 0x02400000:
		return
	var cols: int = clampi(hp * 0x4A / mx, 0, 0x4A)
	var on: int = _ld(buf + (0x4E if cols < 0x17 else 0x4C) * 2, 2, false)
	var off: int = _ld(buf + 0x4B * 2, 2, false)
	if _asb_dbg:
		var d := []
		for j in 3:
			var bj: int = _ld(b + 0xF3C + j * 4, 4, false)
			var c := []
			for e in [0, 1, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F]:
				c.append("%04x" % _ld(bj + e * 2, 2, false))
			d.append("%x:%s" % [bj, " ".join(c)])
		_asb_log("bar dump side %d slot %d idx %d F4D %d %d %d F4A %d: %s" % [side, slot, idx, _ld(b + 0xF4D, 1, false),
			_ld(b + 0xF4E, 1, false), _ld(b + 0xF4F, 1, false), _ld(b + 0xF4A, 1, false), " | ".join(d)])
	for i in 0x4A:
		_st(buf + i * 2, 2, on if i < cols else off)
	if active:
		_st(b + 0xF4A, 1, cols)
		_st(b + 0xF4B, 1, cols)
		_st(b + 0xF4C, 1, 0)
	f_02010ae0(_ld(b + 0xF48, 2, false), b + 0xD3C, 0x200)


## repaint every member of one side from its HP (after a heart)
func _asb_bars(side: int) -> void:
	var t: int = _ld(TEAMS, 4, false) + side * 0x8E8
	var act: int = _ld(t + 0x8C8, 1, false)
	for k in clampi(_ld(t + 0x8C9, 1, false), 0, 3):
		var r := t + k * 0x2D8
		if _ld(r + 5, 1, false) < 26:
			_asb_bar_paint(side, k, maxi(_ld(r + 0x24A, 2, true), 0), _ld(r + 0x24C, 2, true), k == act)


## FUN_0201CBBC(side, out slot, in slot, HP, max HP): the life bar at a tag / the KO replacement. All-Star: the incoming
## member's buffer is repainted from its HP first (it may have been healed, revived or reloaded while benched)
func f_0201cbbc(param_1: int = 0, param_2: int = 0, param_3: int = 0, param_4: int = 0, param_5: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _asb_on and param_1 >= 0 and param_1 <= 1:
		_asb_bar_paint(param_1, param_3, param_4 & 0xFFFF, param_5 & 0xFFFF, false)
		_asb_log("life bar: side %d slot %d -> %d, HP %d/%d repainted" % [param_1, param_2, param_3, param_4 & 0xFFFF, param_5 & 0xFFFF])
	return super.f_0201cbbc(param_1, param_2, param_3, param_4, param_5, _x5, _x6, _x7, _x8, _x9, _x10, _x11)


## HUD (design 1.6): the timer plate's cells (BG1, cols 13-18 rows 0-1 = x 104-151, y 0-15; the game's own ∞ in cols
## 14-17) and a new plate under it (cols 13-18 rows 3-4, y 24-39) show "MM:SS" and "n/26". Their pixels are composed
## from the game's own timer digit tiles (glyph library in the BG1 map buffer S = *(0x020DE3BC): S+0x1D9E + 2d =
## upper half of digit d, +0x40 the lower half; 8x16, 7 px ink rows 4-12 in BG palette row 15: 1 white, 4 yellow,
## 0xE black, 5 / 6 shades) plus a drawn colon / slash, into free BG1 character slots (ASB_TILE.., 4-bit, char base
## 0: the HUD uses tiles 0-0x5C, BG2's 256-colour chars start at 0x4000 = tile 0x200; V: tiles 0x100-0x1FF all zero
## in battle), written straight into VRAM (bank D) when the text changes. The map cells are pointed at them in the BG
## manager's map buffer (S + 0x1774) and in VRAM (map 0x1C800), and put back whenever the game restored its own
## entry there (never over something else, e.g. a pause screen).
const ASB_TILE := 0x180                    ## first BG1 tile used (24 tiles: 12 timer, 12 tracker)
const ASB_BGMAP := 0x0601C800              ## BG1 map in engine A BG VRAM (DISPCNT map base 0x10000 + BG1CNT 0x19 * 0x800)
const ASB_SLASH := ["....ee", "....ee", "...ee.", "...ee.", "..ee..", "..ee..", ".ee...", ".ee...", "ee...."]
var _asb_glyph: Array = []                 ## digit d -> PackedByteArray 8 x 16 palette indices
var _asb_base := PackedByteArray()         ## the timer plate cols 13-18 rows 0-1 (48 x 16), ∞ erased
var _asb_orig: Array = []                  ## [map index, the game's entry, our entry] per cell
var _asb_shown := ["", ""]                 ## texts in the tiles now
var _asb_hud_ok := false


func _asb_hud_reset() -> void:
	_asb_glyph = []
	_asb_orig = []
	_asb_shown = ["", ""]
	_asb_hud_ok = false


## 8x8 4-bit tile at VRAM char index t of BG1 into px (w wide) at (ox, oy), with the map entry's flips
func _asb_tile_px(e: int, px: PackedByteArray, w: int, ox: int, oy: int) -> void:
	var t := 0x06000000 + (e & 0x3FF) * 32
	for y in 8:
		var row: int = _ld(t + y * 4, 4, false)
		for x in 8:
			var v := (row >> (x * 4)) & 15
			var dx := 7 - x if (e & 0x400) != 0 else x
			var dy := 7 - y if (e & 0x800) != 0 else y
			px[(oy + dy) * w + ox + dx] = v


func _asb_hud_init() -> bool:
	var s: int = _ld(0x020DE3BC, 4, false)
	if s < 0x02000000 or s >= 0x02400000:
		return false
	var mb := s + 0x1774
	for d in 10:
		var px := PackedByteArray()
		px.resize(128)
		_asb_tile_px(_ld(s + 0x1D9E + d * 2, 2, false), px, 8, 0, 0)
		_asb_tile_px(_ld(s + 0x1D9E + d * 2 + 0x40, 2, false), px, 8, 0, 8)
		_asb_glyph.append(px)
	if _asb_glyph[0][4 * 8] == 0 or _ld(mb + 14 * 2, 2, false) == 0:
		_asb_glyph = []
		return false                                   # the HUD is not built yet
	_asb_base = PackedByteArray()
	_asb_base.resize(48 * 16)
	for r in 2:
		for c in 6:
			_asb_tile_px(_ld(mb + (r * 32 + 13 + c) * 2, 2, false), _asb_base, 48, c * 8, r * 8)
	for y in range(2, 16):                             # the ∞ is gone: plain plate inside cols 14-17
		for x in range(8, 40):
			_asb_base[y * 48 + x] = 4
	for r in 5:
		if r == 2:
			continue
		for c in 6:
			var i := r * 32 + 13 + c
			_asb_orig.append([i, _ld(mb + i * 2, 2, false), 0xF000 | (ASB_TILE + (r if r < 2 else r - 1) * 6 + c)])
	_asb_hud_ok = true
	_asb_log("HUD: glyphs read, timer plate cells %s" % str(_asb_orig.map(func(o): return "%x" % o[1])))
	return true


## text into a 48 x 16 picture (index 0 = transparent), centred on x 24 (`x0` < 0) or from x0
func _asb_text(px: PackedByteArray, t: String, x0: int) -> void:
	var w := 0
	for ch in t:
		w += (7 if ch.is_valid_int() else (2 if ch == ":" else 6)) + 1
	w -= 1
	var x := x0 if x0 >= 0 else 24 - (w + 1) / 2
	for ch in t:
		if ch.is_valid_int():
			var g: PackedByteArray = _asb_glyph[int(ch)]
			for y in range(4, 13):
				for gx in 7:
					var v := g[y * 8 + gx]
					if v != 4 and v != 0:
						px[y * 48 + x + gx] = v
			x += 8
		elif ch == ":":
			for y in [6, 7, 10, 11]:
				px[y * 48 + x] = 0xE
				px[y * 48 + x + 1] = 0xE
			x += 3
		else:
			for y in 9:
				for gx in 6:
					if ASB_SLASH[y][gx] == "e":
						px[(y + 4) * 48 + x + gx] = 0xE
			x += 7


## the tracker's own plate: the timer plate's style (white / black outline, yellow inside), slanted ends
func _asb_plate() -> PackedByteArray:
	var px := PackedByteArray()
	px.resize(48 * 16)
	for y in 16:
		var d := mini(y, 15 - y)
		var lx := maxi(0, 3 - d)
		var rx := 47 - lx
		for x in range(lx, rx + 1):
			var v := 4
			if d == 0 or x == lx or x == rx:
				v = 1
			elif d == 1 or x == lx + 1 or x == rx - 1:
				v = 0xE
			px[y * 48 + x] = v
	return px


func _asb_put(px: PackedByteArray, first: int) -> void:
	for r in 2:
		for c in 6:
			var t := 0x06000000 + (first + r * 6 + c) * 32
			for y in 8:
				var row := 0
				for x in 8:
					row |= px[(r * 8 + y) * 48 + c * 8 + x] << (x * 4)
				_st(t + y * 4, 4, row)


func _asb_hud(st: int) -> void:
	if st == 9 and _asb_hud_ok:                        # pause: the menu window opens under the tracker -> the game's cells
		var mb9: int = _ld(0x020DE3BC, 4, false) + 0x1774
		for o in _asb_orig:
			if o[0] >= 3 * 32:
				if _ld(mb9 + o[0] * 2, 2, false) == o[2]:
					_st(mb9 + o[0] * 2, 2, o[1])
				if _ld(ASB_BGMAP + o[0] * 2, 2, false) == o[2]:
					_st(ASB_BGMAP + o[0] * 2, 2, o[1])
		return
	if st < 6:
		return
	if not _asb_hud_ok and not _asb_hud_init():
		return
	var clock := _asb_clock_text()
	if clock != _asb_shown[0]:
		_asb_shown[0] = clock
		var px := _asb_base.duplicate()
		_asb_text(px, clock, 7)
		_asb_put(px, ASB_TILE)
	var n := "%d/%d" % [allstar.start_index + allstar.beaten, allstar.total()]
	if allstar.endless:                                # part 38 ENDLESS: enemies beaten so far, no total
		n = str(mini(allstar.beaten, 99999))
	if n != _asb_shown[1]:
		_asb_shown[1] = n
		var px := _asb_plate()
		_asb_text(px, n, -1)
		_asb_put(px, ASB_TILE + 12)
	var mb: int = _ld(0x020DE3BC, 4, false) + 0x1774
	for o in _asb_orig:
		var cur: int = _ld(mb + o[0] * 2, 2, false)
		if cur == o[1] and cur != o[2]:
			_st(mb + o[0] * 2, 2, o[2])
		if _ld(ASB_BGMAP + o[0] * 2, 2, false) == o[1]:
			_st(ASB_BGMAP + o[0] * 2, 2, o[2])


# ---- ALLSTAR STAGE (part 34) ----------------------------------------------------------------------------------------
## ALL-STAR phase 3: the space sky (BG3 night sky: gradient, nebula, twinkling stars; part 35) and the music rotation of an All-Star battle, in
## QoLAllStarStage (scripts/qol/qol_allstar_stage.gd). Ticked from f_020010f4 only while `_asb_on`; nothing at all
## outside an All-Star battle. Track lengths come from QoLSound (STRM HEAD) via `as_strm_info`.
var as_strm_info := {}                    ## STRM id -> [samples, loop start, rate] (set by QoLSound.setup)
var _ass: QoLAllStarStage = null


func _ass_reset() -> void:
	if _ass == null:
		_ass = QoLAllStarStage.new(self)
	_ass.reset()


func _ass_tick() -> void:
	if _ass == null:
		_ass_reset()
	_ass.tick(_ld(BATTLE_STATE, 1, false))


# ---- ALLSTAR MENU (part 34) -----------------------------------------------------------------------------------------
## NEW GAMEMODES / ALL-STAR phase 1 (docs/ALLSTAR_DESIGN.md 1.1-1.3): GAMEMODE tile -> Gamemode menu (scene 0xB with 4
## slots) -> All-Star team select (scene 4, mode 5) -> battle; routing in f_02001014. Session state: QoLAllStar.
## With NEW GAMEMODES off / no session every override here is super only.
var allstar: QoLAllStar = null           ## set by QoLController (shared session; `active` only during a session)
const GM_SCENE := 0x020DD4C4             ## u8 current scene
const GM_STATE := 0x020DE554             ## u8 scene 0xB state (FUN_0204DB0C): 6 = input
const GM_EXIT := 0x020DE560              ## u8 scene 0xB exit code: 3 -> scene 4, 4 -> scene 6 (FUN_0204DB60)
const GM_TASK := 0x020DE5A0              ## u32 -> scene 0xB draw task; +0x30 = module state q (bars +0x14.., cursor +0x24)
## the 4 slots of the Gamemode menu: bar object position (x, y; the game's 3 courses are at (175,46) (160,100)
## (146,154)), all drawn with the HARD bar's shape (the game's texture, relabelled by QoLAllStarMenu); the cursor
## frame sits 15 px right of a bar of that shape (the game's own (160,100) -> (175,100))
const GM_SLOTS := [Vector2i(160, 44), Vector2i(149, 85), Vector2i(138, 126), Vector2i(127, 167)]
const GM_CURSOR_DX := 15
var _gm_from := -1                       ## the scene before a teardown's FUN_02001014(2)


## the Gamemode menu runs: scene 0xB entered from the GAMEMODE tile (QoLAllStar.MENU), NEW GAMEMODES on
func _gm_menu() -> bool:
	return allstar != null and allstar.stage == QoLAllStar.MENU and cheats != null and cheats.new_gamemodes \
		and _ld(GM_SCENE, 1, false) == 0xB


## FUN_02075738: Mode Select's chosen tile -> next scene (+ game mode = tile index). NEW GAMEMODES: tile 5 (GAMEMODE,
## the game's FREE BATTLE) -> scene 0xB = the Gamemode menu (MAXIMUM's course select with 4 slots). The scene's state
## and exit code are cleared so a Maximum battle quit earlier (state 1 = back from a battle) cannot take its map path.
func f_02075738(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var r := super.f_02075738(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if allstar == null or cheats == null or not cheats.new_gamemodes or r != 3 or _ld(GAME_MODE, 4, false) != 5 \
			or (mp != null and mp.active) or (lan != null and lan.state != QoLLan.IDLE):
		return r
	allstar.end()
	allstar.stage = QoLAllStar.MENU
	_st(GM_STATE, 1, 0)
	_st(GM_EXIT, 1, 0)
	allstar._log("GAMEMODE tile -> Gamemode menu (scene 0xB)")
	return 0xB


## FUN_0205495C: scene 0xB's draw task (3 bars, header, cursor). Gamemode menu: 4 bars — slot 0 = the first bar object
## (texture +0x2000, relabelled ALL-STAR), slot 1 = the third bar object (texture +0x6000, relabelled ENDLESS; part 38),
## slots 2-3 = the second bar object (texture +0x4000, EMPTY) drawn twice at its slots (FUN_0200AEBC draws at once: GX
## commands), all with the first bar's palette; then header and cursor.
func f_0205495c(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _gm_menu():
		return super.f_0205495c(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var q := _ld(param_1 + 0x30, 4, false)
	var keep_a := f_0200b420()
	var keep_b := f_0200b408()
	f_0200b480(1)
	f_0200b468(2)
	var o0 := _ld(q + 0x14, 4, false)
	var o1 := _ld(q + 0x18, 4, false)
	var o2 := _ld(q + 0x1C, 4, false)                 # part 38: the third bar (texture +0x6000, relabelled ENDLESS)
	var pal1 := _ld(o1 + 4, 1, false)
	var pal2 := _ld(o2 + 4, 1, false)
	_st(o1 + 4, 1, _ld(o0 + 4, 1, false))             # (a closed course's bar may use another palette)
	_st(o2 + 4, 1, _ld(o0 + 4, 1, false))
	for i in 4:
		var o := o0 if i == 0 else (o2 if i == 1 else o1)
		_gm_pos(o, GM_SLOTS[i].x, GM_SLOTS[i].y, 20)
		f_0200aebc(o)
	_st(o1 + 4, 1, pal1)
	_st(o2 + 4, 1, pal2)
	f_0200aebc(_ld(q + 0x20, 4, false))
	var c: int = clampi(allstar.menu_cursor, 0, 3)
	var cur := _ld(q + 0x24, 4, false)
	_gm_pos(cur, GM_SLOTS[c].x + GM_CURSOR_DX, GM_SLOTS[c].y, 30)
	f_0200aebc(cur)
	f_0200b480(keep_a)
	return f_0200b468(keep_b)


func _gm_pos(o: int, x: int, y: int, z: int) -> void:
	_st(o + 0x3C, 4, x << 12)
	_st(o + 0x40, 4, y << 12)
	_st(o + 0x44, 4, z << 12)


## touch rect of slot i (like the game's: the bar's width, 32 px high around its centre)
func _gm_rect(i: int) -> Array:
	var s: Vector2i = GM_SLOTS[i]
	return [maxi(0, s.x - 82), mini(255, s.x + 82), s.y - 16, s.y + 16]


## FUN_0204DD8C: scene 0xB's input (state 6; 0 = leave). Gamemode menu: own cursor 0..3 with the game's own rules and
## sounds (tap a slot = move there, tap it again / A = choose; Up / Down with the game's key repeat; SE 8 move, 2
## decide, 4 back, 0xD buzzer). ALL-STAR / ENDLESS (part 38) -> exit 3 (scene 4, redirected to the All-Star select in
## f_02001014; the cursor tells which session starts); EMPTY -> buzzer, nothing else; B -> exit 4 (scene 6 = Mode Select).
func f_0204dd8c(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if not _gm_menu():
		return super.f_0204dd8c(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	for i in 4:
		var rc := _gm_rect(i)
		if f_02009844(1, rc[0], rc[1], rc[2], rc[3]) != 0:
			if i == allstar.menu_cursor:
				return _gm_decide()
			allstar.menu_cursor = i
			f_0200ff9c(0, 8)
	if f_02001230(1) != 0:
		return _gm_decide()
	if f_02001230(2) != 0:
		f_0200ff9c(0, 4)
		_st(GM_EXIT, 1, 4)
		allstar._log("Gamemode menu: B -> Mode Select")
		return 0
	for k in 2:                                        # trigger, then the game's key repeat (as FUN_0204DD8C)
		if (f_02001230(0x40) if k == 0 else f_020011dc(0x40)) != 0:
			allstar.menu_cursor = (allstar.menu_cursor + 3) % 4
			f_0200ff9c(0, 8)
		if (f_02001230(0x80) if k == 0 else f_020011dc(0x80)) != 0:
			allstar.menu_cursor = (allstar.menu_cursor + 1) % 4
			f_0200ff9c(0, 8)
	return 1


func _gm_decide() -> int:
	if allstar.menu_cursor > 1:                        # EMPTY: nothing here yet
		f_0200ff9c(0, 0xD)
		return 1
	f_0200ff9c(0, 2)
	_st(GM_EXIT, 1, 3)
	allstar._log("Gamemode menu: %s" % ("ENDLESS" if allstar.menu_cursor == 1 else "ALL-STAR"))
	return 0


## scene changes while the Gamemode menu / an All-Star session runs (design 1.3; cur -> asked => new):
## 0xB -> 4 (ALL-STAR) => 4, mode 5, session starts; 0xB -> 6 (B) => 6; 4 -> 6 (B, nothing picked) => 0xB (Gamemode
## menu); 4 -> 0 => 0 (battle); battle 0 -> 0x14 (P1 lost) / 10 (P1 won; phase 4: records page) / 3 / 0xD (pause:
## character / stage select) => 4, mode 5 (All-Star select); 0 -> 6 (pause: Mode Select) => 6, session ends.
## `allstar=1` (debug): the Free Battle path's battle start (5 -> 0x13 / -> 0 in mode 5) starts a session.
## Returns the scene to ask for (param unchanged when nothing applies).
func _gm_route(param_1: int) -> int:
	if allstar == null:
		return param_1
	var cur := _ld(GM_SCENE, 1, false)
	var to := param_1 & 0xFF
	if allstar.debug_battle and not allstar.active and (to == 0 or to == 0x13) and _ld(GAME_MODE, 4, false) == 5 \
			and (mp == null or not mp.active) and (lan == null or lan.state == QoLLan.IDLE):
		allstar.start(allstar.debug_endless)           # allstar=1: this Free Battle is an All-Star (endless=1: ENDLESS) battle
	if not allstar.active and allstar.stage != QoLAllStar.MENU:
		return param_1
	if to == 2 and cur != 2:                           # the team select's teardown (FUN_02066230) asks for scene 2
		_gm_from = cur                                 # first; the real exit then sees scene 2 (as `_lan_from`)
		return param_1
	if cur == 2 and _gm_from >= 0:
		cur = _gm_from
	_gm_from = -1
	if allstar.stage == QoLAllStar.MENU and not cur in [6, 0xB]:
		allstar.end()                                  # (left some other way, e.g. a soft reset: never a stale menu)
		return param_1
	var nto := to
	match cur:
		0xB:
			if allstar.stage == QoLAllStar.MENU:
				if to == 4:
					f_0200297c(QoLAllStar.GAME_MODE)
					allstar.start(allstar.menu_cursor == 1)   # part 38: slot 1 = ENDLESS
				else:
					allstar.end()
		4:
			if to == 6:                                # B with nothing picked: the Gamemode menu again
				var mc: int = 1 if allstar.endless else 0  # (part 38: the cursor back on the mode left)
				allstar.end()
				if cheats != null and cheats.new_gamemodes:
					allstar.menu_cursor = mc
					allstar.stage = QoLAllStar.MENU
					_st(GM_STATE, 1, 0)
					_st(GM_EXIT, 1, 0)
					nto = 0xB
			elif to != 0:
				allstar.end()
		0:
			if to in [0x14, 10, 3, 0xD]:
				if allstar.result == "":
					allstar.result = "lose" if to == 0x14 else ("win" if to == 10 else "quit")
				_asr_win(to)                           # part 34 phase 4: a win -> records page (`# ---- ALLSTAR RECORDS`)
				f_0200297c(QoLAllStar.GAME_MODE)
				allstar.stage = QoLAllStar.SELECT
				nto = 4
			else:
				if allstar.result == "":
					allstar.result = "quit"
				allstar.end()
	if allstar.dbg:
		print("AS scene %x -> %x (asked %x) mode %d stage %d active %s result %s" % [cur, nto, to, _ld(GAME_MODE, 4, false),
			allstar.stage, allstar.active, allstar.result])
	return (param_1 & ~0xFF) | nto if nto != to else param_1


# ---- ALLSTAR RECORDS (part 34) --------------------------------------------------------------------------------------
## ALL-STAR phase 4 (docs/ALLSTAR_DESIGN.md 1.10): a won All-Star battle asks for its results (scene 10; `_gm_route`
## sends it to the All-Star select instead): QoLController's records page (QoLAllStarRecords) opens over the select
## loading behind it. Only the request and P1's support (still in the party block here; the select clears it) are
## taken on the game thread; the page, the file and the input are the main thread's.
## Part 38 ENDLESS: the battle ends only when player 1's team is out (Game Over, scene 0x14, rerouted the same way):
## that asks for the ENDLESS RECORDS page (a pause exit, 3 / 0xD, does not: nothing recorded).
func _asr_win(to: int) -> void:
	if allstar.endless:
		if to != 0x14 or allstar.result != "lose":
			return
	elif to != 10 or allstar.result != "win":
		return
	allstar.p1_support = _ld(PARTY_SUPPORT, 4, false)
	allstar.records_req = true
	allstar._log("%s -> records page (support %d)" % [allstar.result, allstar.p1_support])


# ---- FLIGHTLESS (part 39) -------------------------------------------------------------------------------------------
## Cheat FLIGHTLESS (page 10 CHALLENGES, `cheats=flightless`): every active fighter (both teams) that is above the
## floor falls: its own fall speed grows by FL_G per battle frame up to FL_MAX and is added straight to y (+0x3C, 24.8
## px, y down). The game's ground test FUN_020214C4 (camera update, later in the same frame) clamps the feet to the
## floor line (effect pool +0x4DEE, s16 px; feet = (y >> 8) - u8 +0x24F) and lands the fighter its own way (landing
## sound 0xF, ground neutral 5), so Up only gives a hop. No pull during supers / ultimates / charging into a super
## (actions 0x26-0x30), character actions >= 0x85 (specials, super parts, throws), victim states 0x34-0x66, KO 0x33,
## intro / win poses 0x13-0x15, sequences (+0x250 & 0x420), frozen (+0x800), pause / cut-in, super / Team Arts camera,
## or before the fight runs (battle state 7). Supports never fall (only the two active records). LAN: integers from
## battle RAM only. DATA_NOTES "part 39 findings".
const FL_G := 0x60                       ## fall speed gained per frame (24.8 px: 0.375 px)
const FL_MAX := 0x700                    ## fastest fall (7 px / frame; flying is ~2.3)
## part 40: a real jump (the user: 3x higher). The game's takeoff from the ground (Up: FUN_020213A8(0x400, -0x40, 0,
## 0x40), ~4 px / frame slowing by 0.25) alone peaked at ~13 px under FL_G; on a takeoff (grounded last frame, now in
## the air going up in action 0 / 1) the fall speed starts at -FL_JUMP (an extra lift) and grows by only FL_GU while
## the fighter still rises, FL_G again from the top: ~35 px high (the old hop: ~9), ~30 frames in the air (`fldbg` traces it).
const FL_JUMP := 0xC0                    ## 0.75 px / frame of extra lift at the takeoff
const FL_GU := 0x20                      ## 0.125 px / frame² while rising
var _fl_v := {}                          ## fighter -> its fall speed (24.8 px / frame)
var _fl_gnd := {}                        ## fighter -> standing at its last tick
var _fl_up := {}                         ## fighter -> in a jump's rising part
var _fl_dbg := Game.args.has("fldbg")


func _fl_tick(f: int) -> void:
	var y: int = _ld(f + 0x3C, 4, true)
	var floor_y: int = _ld(_ld(0x020DE3CC, 4, false) + 0x4DEE, 2, true)
	if (y >> 8) - _ld(f + 0x24F, 1, false) >= floor_y:
		_fl_v.erase(f)                                 # standing (or the floor clamp's frame)
		_fl_up.erase(f)
		_fl_gnd[f] = true
		return
	var was_gnd: bool = _fl_gnd.get(f, false)
	_fl_gnd[f] = false
	var act: int = _ld(f + 6, 1, false)
	var keep := _ld(f + 0x24A, 2, true) <= 0 or act == 0x33 or (act >= 0x13 and act <= 0x15) \
		or (act >= 0x26 and act <= 0x30) or act >= 0x85 or (act >= 0x34 and act <= 0x66) \
		or (_ld(f + 0x250, 4, false) & 0xC20) != 0 or _ld(BATTLE_STATE, 1, false) != 7 or f_02012fd4() != 0
	var cam: int = _ld(CAMERA, 4, false)
	if keep or (cam != 0 and _ld(cam, 2, false) != 0):
		_fl_v.erase(f)                                 # hovers (and starts falling slowly again afterwards)
		_fl_up.erase(f)
		return
	var vy: int = _ld(f + 0x2A, 2, true)               # the game's own vertical speed (y down)
	var v: int
	if was_gnd and vy < 0 and (act == 0 or act == 1):
		v = -FL_JUMP                                   # a takeoff: jump
		_fl_up[f] = true
	elif _fl_up.has(f):
		v = int(_fl_v.get(f, 0)) + FL_GU
		if v + vy >= 0:
			_fl_up.erase(f)                            # the top: falling from here on
	else:
		v = mini(int(_fl_v.get(f, 0)) + FL_G, FL_MAX)
	_fl_v[f] = v
	_st(f + 0x3C, 4, (y + v) & 0xFFFFFFFF)
	if _fl_dbg:
		print("FL f%d fighter %x act %x height %d v %d game vy %d%s" % [_port_frame(), f, act, floor_y + _ld(f + 0x24F, 1, false) - ((y + v) >> 8),
			v, vy, " up" if _fl_up.has(f) else ""])


# ---- SMASH KNOCKBACK (part 39, part 40) -----------------------------------------------------------------------------
## Cheat SMASH KNOCKBACK (page 10 CHALLENGES, `cheats=smash_knockback`): after the game's collision pass FUN_0201E5BC,
## every fighter that lost HP in it (FUN_020293A4, noted in `_kb_hit`) and was knocked back (hit reaction 0xF-0x12 or
## KO 0x33, moving) gets its push multiplied by k = 1 + KB_K * (HP lost / max HP), so at full HP nothing changes and
## near a KO it flies about KB_K + 1 times as far: the push is FUN_020213A8(victim, s, -0x40, 0, dir) (velocity
## +0x28 / +0x2A, deceleration +0x30 / +0x32, speed +0x22, accel +0x26; FUN_02021264 adds velocity to the position,
## then the deceleration, until the velocity reaches 0): velocity AND deceleration x k = same duration, k x the
## distance. Both teams. LAN: integers from battle RAM only.
## Part 40 (the user: "too dull"): KB_K 2 -> 1.4, and fighters can be knocked OUT OF THE CAMERA. The game's camera
## (mode 0, FUN_02019594) zooms out to 0x80 at most and then pulls both active fighters back along their line (the
## tether: they never leave the picture). A knocked-back fighter is LAUNCHED (`_kb_free`): while one is, the tether's
## pull is undone (positions saved / put back around FUN_02019594) and the camera centre (+0xC / +0x10) is kept within
## KB_EDGE_X / KB_EDGE_Y px of the other fighter (it stays in the picture); a launch ends once the game needs no pull
## and the fighter is out of its hit reaction. A fighter whose centre is off the camera (screen = 128 / 96 + zoom x
## (pos - centre) / 256, beyond KB_OFF px) loses KB_DMG of its max HP every KB_TICK running battle frames
## (FUN_020293A4, the scale +0x1676 undone; a KO the game's way: reaction 0x11); a marker at the screen edge shows where
## it is: its own life-bar face icon (sprite rec+0x290) in a dark orange-trimmed box with an arrow, flashing red on
## each tick (drawn in `_fx_draw`). Bounded stages keep their walls. Debug: `kbdbg`.
const KB_K := 1.4
const KB_EDGE_X := 160                   ## world px from the anchor fighter to the camera centre (at zoom 0x80: 256 = edge)
const KB_EDGE_Y := 100                   ## (192 = edge)
const KB_OFF := 12                       ## screen px beyond the edge: off the camera
const KB_TICK := 20                      ## running battle frames between damage ticks
const KB_DMG := 0.01                     ## of max HP per tick (3 % a second)
var _kb_on := false                      ## inside the collision pass with the cheat on
var _kb_hit := {}                        ## fighter -> true: lost HP in this pass
var _kb_free := {}                       ## fighter -> true: launched (the tether does not pull)
var _kb_off := {}                        ## fighter -> running frames off the camera
var _kb_flash := {}                      ## fighter -> frames of the marker's red flash left
var _kb_dbg := Game.args.has("kbdbg")


func _kb_apply() -> void:
	for v in _kb_hit:
		var hp: int = maxi(_ld(v + 0x24A, 2, true), 0)
		var mx: int = _ld(v + 0x24C, 2, false)
		var act: int = _ld(v + 6, 1, false)
		if mx <= 0 or not (act in [0xF, 0x10, 0x11, 0x12, 0x33]):
			continue
		if _ld(v + 0x28, 2, true) == 0 and _ld(v + 0x2A, 2, true) == 0:
			continue
		_kb_free[v] = true                             # part 40: it may fly out of the picture
		var k := 1.0 + KB_K * clampf(1.0 - float(hp) / mx, 0.0, 1.0)
		var kk := int(k * 256.0)
		if kk <= 256:
			continue
		for off in [0x22, 0x26, 0x28, 0x2A, 0x30, 0x32]:
			_st(v + off, 2, clampi((_ld(v + off, 2, true) * kk) >> 8, -0x7FFF, 0x7FFF) & 0xFFFF)
		if Game.args.has("cheatdbg"):
			print("CHT knockback f%d fighter %x hp %d/%d x%.2f velocity %d,%d" % [_port_frame(), v, hp, mx, k,
				_ld(v + 0x28, 2, true), _ld(v + 0x2A, 2, true)])
	_kb_hit.clear()


## FUN_02019594(a, b): camera mode 0 (centre, zoom, tether pull). Part 40: with a launched fighter the pull is undone
## and the centre stays near the other fighter.
func f_02019594(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _ts != null and _ts.active():                   # part 41 TIME SKIP: the tether cannot move the frozen fighter
		var h: Array = _ts.hold_before()
		var rt := super.f_02019594(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
		_ts.hold_after(h)
		return rt
	if cheats == null or _kb_free.is_empty() or not _on("smash_knockback"):
		return super.f_02019594(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var pos := [_ld(param_1 + 0x38, 4, true), _ld(param_1 + 0x3C, 4, true), _ld(param_2 + 0x38, 4, true), _ld(param_2 + 0x3C, 4, true)]
	var r := super.f_02019594(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var pulled: bool = pos != [_ld(param_1 + 0x38, 4, true), _ld(param_1 + 0x3C, 4, true), _ld(param_2 + 0x38, 4, true), _ld(param_2 + 0x3C, 4, true)]
	for f in _kb_free.keys():                          # launches end: back in range and out of the hit reaction
		var a: int = _ld(f + 6, 1, false)
		if not pulled and not (a in [0xF, 0x10, 0x11, 0x12]) or not (f == param_1 or f == param_2):
			_kb_free.erase(f)
	if not pulled:
		return r
	_st(param_1 + 0x38, 4, pos[0] & 0xFFFFFFFF)
	_st(param_1 + 0x3C, 4, pos[1] & 0xFFFFFFFF)
	_st(param_2 + 0x38, 4, pos[2] & 0xFFFFFFFF)
	_st(param_2 + 0x3C, 4, pos[3] & 0xFFFFFFFF)
	var cam: int = _ld(CAMERA, 4, false)
	var anchor := 0
	if _kb_free.has(param_1) and not _kb_free.has(param_2):
		anchor = param_2
	elif _kb_free.has(param_2) and not _kb_free.has(param_1):
		anchor = param_1
	if anchor != 0:
		var ax: int = _ld(anchor + 0x38, 4, true) >> 8
		var ay: int = _ld(anchor + 0x3C, 4, true) >> 8
		_st(cam + 0xC, 4, clampi(_ld(cam + 0xC, 4, true), ax - KB_EDGE_X, ax + KB_EDGE_X) & 0xFFFFFFFF)
		_st(cam + 0x10, 4, clampi(_ld(cam + 0x10, 4, true), ay - KB_EDGE_Y, ay + KB_EDGE_Y) & 0xFFFFFFFF)
	if _kb_dbg:
		print("KB f%d free %s centre %d,%d zoom %x" % [_port_frame(), str(_kb_free.keys()), _ld(cam + 0xC, 4, true), _ld(cam + 0x10, 4, true), _ld(cam + 6, 2, false)])
	return r


## [screen x, screen y] of fighter f's centre through the game's camera (its own zoom, as FUN_02019180)
func _kb_screen(f: int) -> Vector2:
	var cam: int = _ld(CAMERA, 4, false)
	var z: int = _ld(cam + 6, 2, false)
	var x: int = _ld(cam + 0x30, 4, true) + z * ((_ld(f + 0x38, 4, true) >> 8) - _ld(cam + 0xC, 4, true)) / 256
	var y: int = _ld(cam + 0x34, 4, true) + z * ((_ld(f + 0x3C, 4, true) >> 8) - _ld(cam + 0x10, 4, true)) / 256
	return Vector2(x, y)


## once per battle frame per active fighter (`_c39_tick`): off the camera -> damage ticks
func _kb_tick(f: int) -> void:
	if _kb_flash.has(f):
		_kb_flash[f] -= 1
		if _kb_flash[f] <= 0:
			_kb_flash.erase(f)
	var cam: int = _ld(CAMERA, 4, false)
	var act: int = _ld(f + 6, 1, false)
	if cam == 0 or _ld(cam, 2, false) != 0 or _ld(BATTLE_STATE, 1, false) != 7 or f_02012fd4() != 0 \
			or _ld(f + 0x24A, 2, true) <= 0 or act == 0x33 or (_ld(f + 0x250, 4, false) & 0xC20) != 0:
		return                                         # super / Team Arts camera, pause, KO, sequences: no ticks
	var s := _kb_screen(f)
	if s.x >= -KB_OFF and s.x <= 256 + KB_OFF and s.y >= -KB_OFF and s.y <= 192 + KB_OFF:
		_kb_off.erase(f)
		return
	var n: int = int(_kb_off.get(f, 0)) + 1
	_kb_off[f] = n
	if n % KB_TICK != 0:
		return
	var mx: int = _ld(f + 0x24C, 2, false)
	var sc: int = _ld(_ld(TEAMS, 4, false) + 0x1676, 2, false)
	var want: int = maxi(1, int(mx * KB_DMG))
	if sc > 0:
		f_020293a4(f, (want * 256 + sc - 1) / sc, 0)
	_kb_flash[f] = 8
	if _ld(f + 0x24A, 2, true) <= 0 and _ld(f + 6, 1, false) != 0x33:
		_st(f + 0x250, 4, 0)                           # a KO off the camera: the game's KO follows (as GREEN DEMON)
		_st(f + 0x25D, 1, _ld(f + 0x1A, 1, false))
		f_02021b4c(f, 0x11)
		_st(f + 0x25E, 2, 10)
		_st(f + 0x250, 4, _ld(f + 0x250, 4, false) | 2)
	if _kb_dbg:
		print("KB f%d fighter %x off camera at %d,%d: -%d HP -> %d" % [_port_frame(), f, int(s.x), int(s.y), want, _ld(f + 0x24A, 2, true)])


## the edge markers (after the game's sprite list): for each active fighter off the camera, its face icon at the
## nearest screen edge in a dark box with an orange rim and an arrow toward it; red flash on a damage tick
func _kb_draw() -> bool:
	var drew := false
	for f in _kb_off:
		var p: int = f + 0x290
		if _ld(f + 0x24A, 2, true) <= 0 or _ld(p, 4, false) == 0 or f != f_02027c00(_ld(f + 0x1A, 1, false) & 1):
			continue
		var s := _kb_screen(f)
		var mx := clampf(s.x, 18.0, 238.0)
		var my := clampf(s.y, 71.0, 174.0)               # (below the HUD and the RUSH counter, y 32-56)
		var d := (s - Vector2(mx, my)).normalized()
		var red: bool = _kb_flash.has(f)
		mx = floorf(mx)
		my = floorf(my)
		_fx_box(mx - 14, my - 14, 28, 28, 0x0D9F if red else 0x02DF, 0x80C0 | (31 << 16) | (0x21 << 24), 44, 0x0E00)   # rim
		_fx_box(mx - 13, my - 13, 26, 26, 0x0006 if red else 0x0842, 0x80C0 | (31 << 16) | (0x21 << 24), 45, 0x0E01)   # box
		# part 41: the icon 1:1 (its texture is 32x32 with the 24x24 face at the top left: the quad's centre +4, +4)
		var m := [32.0, 0.0, 0.0, 0.0, 32.0, 0.0, 0.0, 0.0, 1.0, mx + 4.0, my + 4.0, 46.0]
		_spr_emit(p, m, 0x80C0 | (31 << 16) | (0x21 << 24), 0x7FFF if not red else 0x4E7F)
		for k in 3:                                    # the arrow: three shrinking squares outward
			var c := Vector2(mx, my) + d * (18.0 + k * 3.0)
			var w := 5 - k * 2
			_fx_box(floorf(c.x - w * 0.5), floorf(c.y - w * 0.5), w, w, 0x02DF, 0x80C0 | (31 << 16) | (0x21 << 24), 46, 0x0E02 + k)
		drew = true
	return drew

# ---- ULTRA INSTINCT (part 39) ---------------------------------------------------------------------------------------
## Cheat ULTRA INSTINCT (page 9 POWERS since part 41, page 5 before; `cheats=ultra_instinct`): the parry; everything is in
## scripts/qol/qol_ultra.gd. Hooks here: f_0202954C (tick for player 1's active fighter, both players' in MP),
## f_0201E5BC (before / after the collision pass), f_0202A40C (reset), _fx_any / _fx_draw (its flashes).
const _ULTRA_GD := preload("res://scripts/qol/qol_ultra.gd")
var _ui = null                           ## created the first time a battle frame runs with the cheat on


## FUN_0201E5BC: the battle's collision pass (attack boxes against hurt boxes -> the attackers' hit handlers)
func f_0201e5bc(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats == null:
		return super.f_0201e5bc(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var ui: bool = _ui != null and _on("ultra_instinct") and _ui.busy()
	var kb := _on("smash_knockback")
	var hp: bool = _hp != null and _on("hot_potato") and _hp.any()
	var vp := _on("vampire")
	var db: bool = _db != null and _on("dragon_balls")
	if not ui and not kb and not hp and not vp and not db:
		return super.f_0201e5bc(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	if ui:
		_ui.before()
	_kb_hit.clear()
	_kb_on = kb
	_hp_coll = hp
	if vp and _vp == null:
		_vp = _VAMP_GD.new(self)
	_vp_coll = vp
	_db_coll = db
	var r := super.f_0201e5bc(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_kb_on = false
	_hp_coll = false
	_vp_coll = false
	_db_coll = false
	if ui:
		_ui.after()
	if kb:
		_kb_apply()
	return r


var _rzult := Game.args.has("rzult")
var _p2hp_at := int(Game.flag("p2hp", "-1:0").split(":")[0])
var _p2hp_v := int((Game.flag("p2hp", "-1:0") + ":0").split(":")[1])
var _p1hp_at := int(Game.flag("p1hp", "-1:0").split(":")[0])
var _p1hp_v := int((Game.flag("p1hp", "-1:0") + ":0").split(":")[1])


## once per battle frame per fighter (f_0202954C, before its action handler): the part 39 cheats
func _c39_tick(f: int) -> void:
	var side: int = _ld(f + 0x1A, 1, false) & 1
	if f != f_02027c00(side):
		return
	if _p2hp_at >= 0 and side == 1 and _port_frame() == _p2hp_at:
		_st(f + 0x24A, 2, _p2hp_v)                     # part 40 debug `p2hp=F:HP`
	if _p1hp_at >= 0 and side == 0 and _port_frame() == _p1hp_at:
		_st(f + 0x24A, 2, _p1hp_v)                     # part 40 debug `p1hp=F:HP` (red-HP ultimates)
	if _rzult and side == 0:
		_st(f + 0x24E, 1, 0)                           # part 40 debug `rzult`: the once-a-battle ultimate flag cleared
	if _on("flightless"):
		_fl_tick(f)
	if _on("smash_knockback"):
		_kb_tick(f)                                    # part 40: off the camera -> damage
	if not _helped(f):
		return
	if _on("ultra_instinct"):
		if _ui == null:
			_ui = _ULTRA_GD.new(self)
		_ui.tick(f)
	if not _rz.is_empty():
		for r in _rz.keys():                           # a transformed fighter benched after its KO: back now
			if r != f and r != f_02027c00(_ld(r + 0x1A, 1, false) & 1):
				_rz_back(r)
		if _rz.has(f):
			_rz_tick(f)


# ---- RANDOMIZER (part 39) -------------------------------------------------------------------------------------------
## Cheat RANDOMIZER (page 7 CHARACTERS, `cheats=randomizer`): player 1's super attacks (both players' in MP) are done
## by a random fighter. The action dispatcher FUN_0202AEB4 (neutral / move handlers) starts a super (0x2C) or an
## ultimate (0x2E) for X+A held; when it did, the record is put back as it was before the call (a byte copy of the
## 0x2D8-byte record, the common effects the call spawned are killed), the record is reloaded as a random other
## fighter (0-25) with CHARACTER SHUFFLE's loader (`_shuffle_load`: chunks, images, palettes, voices, face icon,
## lower-screen portrait; HP and max HP kept) and the dispatcher runs again: the new character starts ITS super
## (its own cost, script, direction variant; ultimate if it has one and the ki is there). If it starts none, the
## original comes back at once and does its own. `_rz_tick` (every battle frame while transformed) turns the fighter
## back with the same loader: at once when it is hit (generic hit reactions 0xE-0x12, restarted for the original as
## CHAOS SHUFFLE does), else when the super, its sequence / camera and the objects made from the random fighter's
## chunks are over (at most RZ_WAIT frames after the super, then the objects are killed). A KO waits until the KO
## sequence lets go of the record. A super started while still transformed picks another fighter. Boss picks
## (BOSS CHARACTERS) are no boss while transformed and get their boss level back. CHARACTER / CHAOS SHUFFLE wait while
## transformed. LAN: the seeded `_rz_rng` (battle seed). Debug: `rzseed=N`, `rzto=ID` (always that fighter), `cheatdbg`.
const RZ_SUPERS := [0x2C, 0x2E]
const RZ_HIT := [0x0E, 0x0F, 0x10, 0x11, 0x12]
const RZ_WAIT := 240
var _rz := {}                            ## fighter -> {"orig": id, "boss": level (0 none), "t": frames, "wait": frames}
var _rz_rng := RandomNumberGenerator.new()
var _rz_seeded := false
var _rz_busy := false


func f_0202aeb4(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	var nd := -1
	if cheats != null and not _rz_busy and _on("nondirectional") and _helped(param_1):
		nd = _nd_pick(param_1)                         # part 42 NONDIRECTIONAL: the held direction's angle, or -1
	if nd < 0:
		return _aeb(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var real7: int = _ld(param_1 + 7, 1, false)
	_st(param_1 + 7, 1, nd)                            # the dispatcher (and RANDOMIZER's calls) see the chosen angle;
	var rn := _aeb(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)   # the VM keeps +0x20 = it
	if _nd_dbg:
		print("ND f%d fighter %x angle %x -> %x: act %x" % [_port_frame(), param_1, real7, nd, _ld(param_1 + 6, 1, false)])
	_st(param_1 + 7, 1, real7)                         # (the game rewrites +7 after the handler anyway)
	return rn


## the dispatcher with RANDOMIZER's handling (part 39); NONDIRECTIONAL wraps it (f_0202aeb4)
func _aeb(param_1: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if cheats == null or _rz_busy or not _on("randomizer") or not _helped(param_1):
		return super.f_0202aeb4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var held: int = _ld(param_1 + 0x270, 2, false)
	if (held & 0x401) != 0x401 or (held & 0x100) != 0 or (held & 0x802) == 0x802 \
			or param_1 != f_02027c00(_ld(param_1 + 0x1A, 1, false) & 1) or _ld(param_1 + 5, 1, false) > 25:
		return super.f_0202aeb4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var team: int = _ld(TEAMS, 4, false) + (_ld(param_1 + 0x1A, 1, false) & 1) * 0x8E8
	var snap := _rz_snap(param_1, team)
	var alive := _rz_alive()
	var act0: int = _ld(param_1 + 6, 1, false)
	var r := super.f_0202aeb4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var act: int = _ld(param_1 + 6, 1, false)
	if not act in RZ_SUPERS:
		return r
	_rz_busy = true
	var cur: int = _ld(param_1 + 5, 1, false)
	var st: Dictionary = _rz.get(param_1, {})
	var orig: int = st.get("orig", cur)
	_rz_kill_new(alive)                                # the super's start effects (common effects 0xD / 0xF)
	_rz_restore(param_1, team, snap)                   # record AND team ki as before the call (part 40: the
	var n := _rz_pick(cur, orig)                       # ultimate check FUN_02026A8C spends its 150 % itself)
	if st.is_empty():
		st = {"orig": orig, "boss": _rz_unboss(param_1), "t": 0, "wait": 0}
	_rz_load(param_1, n, act0, false)
	_rz[param_1] = st
	st["t"] = 0
	st["wait"] = 0
	alive = _rz_alive()
	snap = _rz_snap(param_1, team)
	r = super.f_0202aeb4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var act2: int = _ld(param_1 + 6, 1, false)
	var forced := false
	if act == 0x2E and act2 != 0x2E:                   # part 40: an ultimate was asked for; this fighter's own test
		_rz_kill_new(alive)                            # refused it (its ultimate wants another direction / is
		_rz_restore(param_1, team, snap)               # locked): it starts its ultimate the dispatcher's way
		_rz_ultimate(param_1)
		act2 = 0x2E
		forced = true
		r = 1
	if Game.args.has("cheatdbg"):
		print("CHT randomizer f%d fighter %x: super %x as %d -> %d starts %x%s (original %d) ki %d" % [_port_frame(), param_1, act, cur, n, act2,
			" (forced)" if forced else "", orig, _ld(team + 0x8D0, 2, false)])
	if not act2 in RZ_SUPERS:                         # this fighter has no super here: the original does its own
		_rz_kill_new(alive)
		_rz_restore(param_1, team, snap, false)        # (the ki only: the record is reloaded)
		_rz_back(param_1, false)
		r = super.f_0202aeb4(param_1, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_rz_busy = false
	return r


# ---- NONDIRECTIONAL (part 42) --------------------------------------------------------------------------------------
## Cheat NONDIRECTIONAL (page 5 FIGHTING, `cheats=nondirectional`): X+A with a direction held picks the super variant
## by that direction instead of the angle to the enemy. The dispatcher FUN_0202AEB4 (X+A held, R not, not Y+B) tests the
## ultimate (FUN_02026A8C: direction rule u8 blk+0x23 = 0 level / 1 up / 3 down / 4 any, blk = [f+0x50]) and then the
## super with q = ((+7 + 0x20) & 0xFF) >> 6 (cost u8 blk+0x1F+q, unlock bit q of +0x274); on a start +0x20 = +7 and VM op
## 4 jumps to the up / level / down script by +0x20 (DATA_NOTES part 42). Here: when the super (or the ultimate) WOULD
## start with the held direction's angle (_nd_pick, pure reads), +7 = that angle for the dispatcher call (and
## RANDOMIZER's calls inside it). Up = 0x3C / 0x44, Down = 0xC4 / 0xBC (not 0x40 / 0xC0: the VM's mirror boundary would
## turn the fighter round), Left / Right = level TOWARD the enemy (0 / 0x80; a literal Left turned away from it). When
## the red-HP ultimate is possible but its rule refuses the real angle, any held direction fires it (the rule's own
## direction). No direction held / the precheck fails: the game's own behaviour. Player 1 (both humans in MP); never the
## CPU. LAN: the held word (lockstep input) and battle RAM only. Debug: `nddbg`.
var _nd_dbg := Game.args.has("nddbg")


func _nd_pick(f: int) -> int:
	var held: int = _ld(f + 0x270, 2, false)
	if (held & 0x401) != 0x401 or (held & 0x100) != 0 or (held & 0x802) == 0x802 or (held & 0xF0) == 0:
		return -1
	var right: bool = ((_ld(f + 7, 1, false) + 0x40) & 0xFF) < 0x80   # the enemy is to the right (the VM's mirror rule)
	var side: int = _ld(f + 0x1A, 1, false) & 1
	var teams: int = _ld(TEAMS, 4, false)
	var ki: int = _ld(teams + side * 0x8E8 + 0x8D0, 2, false) >> 8   # (unsigned: 200 % = 0xC800)
	var blk: int = _ld(f + 0x50, 4, false)
	var unl: int = _ld(f + 0x274, 4, false)
	var d: int
	if (held & 0x40) != 0:
		d = 0x3C if right else 0x44
	elif (held & 0x80) != 0:
		d = 0xC4 if right else 0xBC
	else:
		d = 0 if right else 0x80
	var opp := f_02027bd0(side)
	if (unl & 0x40) != 0 and _ld(f + 0x24E, 1, true) == 0 and ki > 0x95 and opp != 0 \
			and (_ld(opp + 0x250, 4, false) & 0x400) == 0 and ((_ld(opp + 6, 1, false) - 0x2E) & 0xFF) > 1 \
			and _ld(teams + 0x1675, 1, true) == 0 and f_0201c594(side) != 0:
		match _ld(blk + 0x23, 1, false):                # the ultimate is possible: its own direction
			0:
				return 0 if right else 0x80
			1:
				return 0x3C if right else 0x44
			3:
				return 0xC4 if right else 0xBC
			_:
				return d
	var q: int = ((d + 0x20) & 0xFF) >> 6
	if _ld(blk + 0x1F + q, 1, false) <= ki and (unl & (1 << q)) != 0:
		return d
	return -1


## [record bytes, team block tail +0x8C8..+0x8E8 (active member, assists, ki, Team Arts counters)]
func _rz_snap(f: int, team: int) -> Array:
	return [M.slice(f - BASE, f - BASE + 0x2D8), M.slice(team + 0x8C8 - BASE, team + 0x8E8 - BASE)]


func _rz_restore(f: int, team: int, snap: Array, rec := true) -> void:
	if rec:
		_put(f, snap[0])
	_put(team + 0x8C8, snap[1])


## the dispatcher FUN_0202AEB4's ultimate branch (after FUN_02026A8C said yes: +0x24E = 1, 150 % ki spent)
func _rz_ultimate(f: int) -> void:
	_st(f + 0x24E, 1, 1)
	f_02027950(f, 0x9600, 0)
	_st(f + 0x250, 4, 0)
	_st(f + 0x25D, 1, _ld(f + 0x1A, 1, false))
	f_02021b4c(f, 0x2E)
	_st(f + 0x250, 4, _ld(f + 0x250, 4, false) | 0x40400)
	_st(f + 0x20, 1, _ld(f + 7, 1, false))
	_st(f + 0xE, 2, _ld(f + 0xE, 2, false) | 8)
	f_02029e3c(f, 0x20)
	var o := f_0202247c(f, 0xF)
	if o != 0:
		f_0202216c(o, 0, 4)
	f_020213a8(f, 0, 0, 0, 0)

## a random fighter id 0-25, not the current one, nor the original (`rzto=ID`: that one)
func _rz_pick(cur: int, orig: int) -> int:
	if Game.args.has("rzto"):
		return clampi(int(Game.flag("rzto")), 0, 25)
	if not _rz_seeded:
		_rz_seeded = true
		if Game.args.has("rzseed"):
			_rz_rng.seed = int(Game.flag("rzseed"))
		else:
			_rz_rng.randomize()
	var n := cur
	while n == cur or n == orig:
		n = _rz_rng.randi_range(0, 25)
	return n


## status bytes (+4) of the effect pool's 56 slots
func _rz_alive() -> PackedByteArray:
	var pool: int = _ld(0x020DE3CC, 4, false)
	var a := PackedByteArray()
	a.resize(56)
	for i in 56:
		a[i] = _ld(pool + i * 0x164 + 4, 1, false)
	return a


## kill the objects spawned since `alive` was taken (the game's way: +4 = 2)
func _rz_kill_new(alive: PackedByteArray) -> void:
	var pool: int = _ld(0x020DE3CC, 4, false)
	for i in 56:
		var o := pool + i * 0x164
		if alive[i] == 0 and (_ld(o + 4, 1, false) & 1) != 0:
			_st(o + 4, 1, 2)


## a BOSS CHARACTERS boss stops being one while transformed: its level (0 = not a boss)
func _rz_unboss(f: int) -> int:
	for i in battle_bosses.size():
		if battle_bosses[i][0] == f:
			var lv: int = battle_bosses[i][1]
			battle_bosses.remove_at(i)
			return lv
	return 0


## reload record f as character n (CHARACTER SHUFFLE's loader), HP kept; then action `act` restarts with the new
## script (chaos: CHAOS SHUFFLE's rule, which keeps reactions and ends attacks)
func _rz_load(f: int, n: int, act: int, chaos: bool) -> void:
	var old: int = _ld(f + 5, 1, false)
	var hp: int = _ld(f + 0x24A, 2, true)
	var mx: int = _ld(f + 0x24C, 2, false)
	_shuf_loading = true
	_chaos_prepare(f)
	if not _shuffle_load(f, n):
		print("CHT randomizer: loading character %d failed (heap %s); reloading %d" % [n, str(_heap_free()), old])
		n = old
		_shuffle_load(f, old)
	_st(f + 0x24A, 2, hp)
	_st(f + 0x24C, 2, mx)
	if chaos:
		_chaos_again = -1
		_chaos_restart(f, act)
	else:
		f_02021b4c(f, act)
	f_02026548(f)
	_shuffle_voices(f_02027c00(_ld(f + 0x1A, 1, false) & 1))   # (the side's ACTIVE fighter: f may be benched)
	_shuffle_icon(f, n)
	_shuffle_panel(f)
	_shuf_loading = false


## back to the original character (boss level back), the current action kept the CHAOS SHUFFLE way
func _rz_back(f: int, chaos := true) -> void:
	var st: Dictionary = _rz.get(f, {})
	if st.is_empty():
		return
	_rz.erase(f)
	var was_busy := _rz_busy
	_rz_busy = true
	_rz_load(f, st["orig"], _ld(f + 6, 1, false), chaos)
	if st["boss"] > 0:
		var hp: int = _ld(f + 0x24A, 2, true)
		var mx: int = _ld(f + 0x24C, 2, false)
		_make_boss(f, st["boss"])
		battle_bosses.append([f, st["boss"]])
		_st(f + 0x24A, 2, hp)
		_st(f + 0x24C, 2, mx)
	_rz_busy = was_busy
	if Game.args.has("cheatdbg"):
		print("CHT randomizer f%d fighter %x back to %d (act %x, %d frames)" % [_port_frame(), f, st["orig"], _ld(f + 6, 1, false), st["t"]])


## every battle frame while transformed: back when hit, or when the super and what it left are over
func _rz_tick(f: int) -> void:
	var st: Dictionary = _rz[f]
	st["t"] += 1
	if _ld(f + 6, 1, false) >= 0x13 and _ld(f + 6, 1, false) <= 0x15:
		_rz_back(f)                                    # the fight is won: the win pose is the original's
		return
	if f_02012fd4() != 0 or _ld(_ld(TEAMS, 4, false) + 0x11DC, 4, false) != 0 or (_ld(f + 0x250, 4, false) & 0x800) != 0:
		return                                         # pause / cut-in, tag, frozen: later
	var act: int = _ld(f + 6, 1, false)
	if _ld(f + 0x24A, 2, true) <= 0 or act == 0x33:
		if act != 0x33 and (_ld(f + 0x250, 4, false) & 0x420) == 0:
			_rz_back(f)                                # KO over (benched / the next member is in)
		return
	if (_ld(f + 0x250, 4, false) & 0x420) != 0 or act >= 0x85 or (act >= 0x26 and act <= 0x30) or (act >= 0x34 and act <= 0x66):
		return                                         # the super / a throw / a sequence still runs
	if act in RZ_HIT:
		_rz_back(f)                                    # hit during (or after) the super: back at once
		return
	var cam: int = _ld(CAMERA, 4, false)
	if cam != 0 and _ld(cam, 2, false) != 0:
		return
	if _shuffle_objects(f) > 0 and st["wait"] < RZ_WAIT:
		st["wait"] += 1                                # its shots / summons are still out
		return
	_rz_back(f)


## part 39 debug `setest` (choosing ULTRA INSTINCT's sound): from port frame 4150 the fight is held in hit stop
## (silent), and from 4200 every 60 frames battle sound k = 0, 1, ... 0x31 plays (FUN_02029E3C on P1's fighter);
## `setest=A,B,...` plays only those. The capture's audio.wav is cut into 60-frame windows by the analysis script.
var _setest := Game.args.has("setest")
var _setest_ids: Array = []


func _se_test() -> void:
	var fr := _port_frame()
	if fr < 4150 or _ld(BATTLE_STATE, 1, false) != 7:
		return
	if _setest_ids.is_empty():
		var s: String = Game.flag("setest")
		if s == "" or s == "1":
			_setest_ids = range(0, 0x32)
		else:
			for v in s.split(",", false):
				_setest_ids.append(v.hex_to_int() if v.begins_with("0x") else int(v))
	f_02012f9c(4)
	if fr >= 4200 and (fr - 4200) % 60 == 0:
		var k := (fr - 4200) / 60
		if k < _setest_ids.size():
			f_02029e3c(f_02027c00(0), _setest_ids[k])
			print("SETEST f%d se %x" % [fr, _setest_ids[k]])


# ---- HOT POTATO (part 40) -------------------------------------------------------------------------------------------
## Cheat HOT POTATO (page 10 CHALLENGES, `cheats=hot_potato`): everything is in scripts/qol/qol_potato.gd; hooks here:
## f_0202954C (tick once per battle frame), f_0201E5BC (`_hp_coll` while the collision pass runs) + f_020293A4 (hit():
## a hit inside the pass may pass the bomb), f_0202A40C (reset), _fx_any / _fx_draw (the bomb + countdown). The art is
## BOMB RAIN's (`_bomb_img`, the shared texture block).
const _POTATO_GD := preload("res://scripts/qol/qol_potato.gd")
var _hp = null                           ## created the first time a battle frame runs with the cheat on
var _hp_coll := false                    ## inside the collision pass with a bomb lit


# ---- VAMPIRE (part 41) ---------------------------------------------------------------------------------------------
## Cheat VAMPIRE (page 5 FIGHTING, `cheats=vampire`): everything is in scripts/qol/qol_vampire.gd; hooks here:
## f_0201E5BC (`_vp_coll` while the collision pass runs) + f_020293A4 (hit(): the HP a fighter really lost in the pass,
## measured around the whole damage call incl. the other damage cheats), f_0202A40C (reset), _fx_any / _fx_draw.
const _VAMP_GD := preload("res://scripts/qol/qol_vampire.gd")
var _vp = null                           ## created the first time a collision pass runs with the cheat on
var _vp_coll := false                    ## inside the collision pass with the cheat on
var _vp_in := false                      ## inside the measured damage call (also DRAGON BALL HUNT's)


# ---- TIME SKIP (part 41) -------------------------------------------------------------------------------------------
## Cheat TIME SKIP (page 9 POWERS, `cheats=time_skip`): everything is in scripts/qol/qol_timeskip.gd; hooks here:
## f_0202954C (tick once per battle frame; the frozen side's fighter runs freeze_step instead), f_020294B8 (its support
## only drawn), f_02021F54 (its objects frozen around the effect loop), f_0201E224 / f_02019594 (body push / tether
## cannot move it), f_0202A40C (reset), _fx_any / _fx_draw (tint, skipper copy, rings).
const _TS_GD := preload("res://scripts/qol/qol_timeskip.gd")
var _ts = null                           ## created the first time a battle frame runs with the cheat on


## FUN_02021F54: the effect loop (48 object slots + 8 aura slots: handler, VM, attach, life, draw)
func f_02021f54(_x0: int = 0, _x1: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _ts == null or not _ts.active():
		return super.f_02021f54(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_ts.objects_before()
	var r := super.f_02021f54(_x0, _x1, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_ts.objects_after()
	return r


## FUN_0201E224(p1, p2): the active fighters' body push-apart
func f_0201e224(param_1: int = 0, param_2: int = 0, _x2: int = 0, _x3: int = 0, _x4: int = 0, _x5: int = 0, _x6: int = 0, _x7: int = 0, _x8: int = 0, _x9: int = 0, _x10: int = 0, _x11: int = 0) -> int:
	if _ts == null or not _ts.active():
		return super.f_0201e224(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	var h: Array = _ts.hold_before()
	var r := super.f_0201e224(param_1, param_2, _x2, _x3, _x4, _x5, _x6, _x7, _x8, _x9, _x10, _x11)
	_ts.hold_after(h)
	return r


# ---- Z-VANISH (part 42) --------------------------------------------------------------------------------------------
## Cheat Z-VANISH (page 9 POWERS, `cheats=z_vanish`): everything is in scripts/qol/qol_zvanish.gd; hooks here:
## f_0202954C (tick for each active fighter before it runs), f_0202A40C (reset), _fx_any / _fx_draw (afterimages).
const _ZV_GD := preload("res://scripts/qol/qol_zvanish.gd")
var _zv = null                           ## created the first time a battle frame runs with the cheat on


# ---- BODY CHANGE (part 42) ---------------------------------------------------------------------------------------
## Cheat BODY CHANGE (page 9 POWERS, `cheats=body_change`): everything is in scripts/qol/qol_bodychange.gd; hooks here:
## f_0202954C (tick once per battle frame), f_0202A40C (reset), _fx_any / _fx_draw (countdown, ray, glow).
const _BC_GD := preload("res://scripts/qol/qol_bodychange.gd")
var _bc = null                           ## created the first time a battle frame runs with the cheat on


# ---- DRAGON BALL HUNT (part 41) -------------------------------------------------------------------------------------
## Cheat DRAGON BALL HUNT (page 10 CHALLENGES, `cheats=dragon_balls`): everything is in scripts/qol/qol_dragonballs.gd;
## hooks here: f_0202954C (tick once per battle frame), f_0201E5BC (`_db_coll`) + f_020293A4 (hit(): the HP lost, as
## VAMPIRE measures it: a big hit drops a ball), f_0202A40C (reset), _fx_any / _fx_draw. The art is the game's own
## (read from the player's ROM), kept in the shared texture block (qol_texblock.gd, part 41: 12 KiB).
const _DB_GD := preload("res://scripts/qol/qol_dragonballs.gd")
var _db = null                           ## created the first time a battle frame runs with the cheat on
var _db_coll := false                    ## inside the collision pass with the cheat on


# ---- RICOCHET KI (part 40) ------------------------------------------------------------------------------------------
## Cheat RICOCHET KI (page 6 KI & ASSISTS, `cheats=ricochet_ki`): player 1's plain shots (handler FUN_020209E0: ki
## blasts and the plain-projectile specials; both players' in MP) bounce off the edges of the camera's picture and off
## the floor, up to RC_MAX times each, instead of flying away. Right after the handler moved the shot (f_020209E0
## override): its screen position through the game's camera (its own zoom, as FUN_02019180) beyond an edge (RC_PAD px
## inside) while moving out -> that velocity component (velocity +0x28 / +0x2A, target +0x2C / +0x2E, accel +0x30 /
## +0x32) is mirrored, and the direction +0x21 / +7 and the sprite rotation (FUN_02011F74, as the handler and the
## game's dash-attack reflection set it) follow. The floor: y beyond the floor line (effect pool +0x4DEE) + RC_FLOOR.
## Counts per object slot, forgotten when the slot is reused (f_020225C8). LAN: battle RAM and the game's camera.
## Debug: `rcdbg`.
const RC_MAX := 3
const RC_PAD := 4                        ## screen px inside the edge
const RC_TOP := 24                       ## the top edge sits below the HUD bars
const RC_FLOOR := 56                     ## world px below the floor line (the feet line is ~+64)
var _rc := {}                            ## shot object -> bounces so far
var _rc_dbg := Game.args.has("rcdbg")


func _rc_bounce(o: int) -> void:
	if (_ld(o + 4, 1, false) & 1) == 0 or int(_rc.get(o, 0)) >= RC_MAX:
		return
	var cam: int = _ld(CAMERA, 4, false)
	if cam == 0 or _ld(BATTLE_STATE, 1, false) != 7:
		return                                         # (the fight only: other scenes run the handler too)
	var z: int = _ld(cam + 6, 2, false)
	var wx: int = _ld(o + 0x38, 4, true) >> 8
	var wy: int = _ld(o + 0x3C, 4, true) >> 8
	var sx: int = _ld(cam + 0x30, 4, true) + z * (wx - _ld(cam + 0xC, 4, true)) / 256
	var sy: int = _ld(cam + 0x34, 4, true) + z * (wy - _ld(cam + 0x10, 4, true)) / 256
	var vx: int = _ld(o + 0x28, 2, true)
	var vy: int = _ld(o + 0x2A, 2, true)
	var floor_y: int = _ld(_ld(0x020DE3CC, 4, false) + 0x4DEE, 2, true) + RC_FLOOR
	var bx := (sx <= RC_PAD and vx < 0) or (sx >= 256 - RC_PAD and vx > 0)
	var by := (sy <= RC_TOP and vy < 0) or (wy >= floor_y and vy > 0)
	if not bx and not by:
		return
	var d: int = _ld(o + 0x21, 1, false)
	for off in ([0x28, 0x2C, 0x30] if bx else []) + ([0x2A, 0x2E, 0x32] if by else []):
		_st(o + off, 2, (-_ld(o + off, 2, true)) & 0xFFFF)
	if bx:
		d = (0x80 - d) & 0xFF
	if by:
		d = (0x100 - d) & 0xFF
	_st(o + 0x21, 1, d)
	_st(o + 7, 1, d)
	f_02011f74(o + 0x124, 0, 0, (0x100 - d) & 0xFF)
	_rc[o] = int(_rc.get(o, 0)) + 1
	if _rc_dbg:
		print("RC f%d shot %x bounce %d at screen %d,%d (%s) dir %x" % [_port_frame(), o, _rc[o], sx, sy, "x" if bx else "y", d])
