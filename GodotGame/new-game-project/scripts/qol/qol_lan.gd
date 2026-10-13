class_name QoLLan
extends RefCounted
# ---- LAN CORE (part 30)
## LAN MULTIPLAYER session + deterministic lockstep (docs/LAN_DESIGN.md 1, 2, 5, 6.1; DATA_NOTES "Session 1 part 30
## findings (LAN core)"). One instance lives in QoLController (`lan`, always created; IDLE = inert) and is shared with
## QoLGame (`lan`). Transport: QoLLanNet (ENet). Everything runs on the main thread except the few flags QoLGame's
## battle hooks set on the game thread (`_init_flag`, `_exit_flag`, `in_battle`), which the main thread acts on in
## after_step (the game thread is parked then).
##
## PUBLIC API (used by QoLLanMenu; keep stable): `state` (IDLE..BATTLE) + `state_name()`, `role` ("host" / "guest" / ""),
## `my_name`, `peer_name`, `ping_ms` (-1 unknown), `port`, `reason` (last failure), `target` ("ip:port" being joined),
## `settings`, `local_addresses()`, `host(name, port)`, `join(name, ip, port)`, `leave()`, `propose_select()`,
## `accept_select()`, `deny_select()`, `poll()`, `pop_event()` ({} = none) with "type": "connected", "connect_failed"
## (+"reason"), "rejected" (+"reason": "VERSION …" / "ROM" / "FULL"), "peer_joined", "peer_left", "proposal",
## "proposal_denied", "proposal_accepted" (host), "desync" (+"frame"), "lost"; plus `active()`, `connected()`,
## `waiting()` (a lockstep stall over 0.5 s: "WAITING FOR PLAYER"), `connect_left()` (seconds), `in_battle`, `lockstep`.
##
## Lockstep (2.2 / 2.3): lockstep frame L = 1 is the first game frame after the battle init FUN_020140C8 (QoLGame
## `# ---- LAN CORE`). Each machine's input sampled when frame L starts is its record for L + delay; frames 1..delay
## are neutral on both. GameDS._tick_begin refuses to start frame L until the remote record L is here (can_step), then
## frame() turns the two records into the DS pad / touch (host = P1) and QoLMp's P2 fields (guest = P2, read by
## QoLGame.f_0202dce0) — the same code and the same records on both machines.
## Debug flags (inert without them): lan=host|join:IP[:PORT] lanport lanname lanauto lanbattle=1 laninputs= landelay=N
## lanlag / lanjitter / lanloss / lanimpseed (QoLLanNet) landbg lanhash=FILE lanquit=L landesync=L lanbuild=S lanrom=S
## lanteams=a.b.c/d.e.f lanbstage=HEX (the `lanbattle=1` STAGE_RESULT).

enum { IDLE, HOSTING, CONNECTING, LOBBY, SELECT, STAGE, BATTLE }
const STATE_NAMES := ["IDLE", "HOSTING", "CONNECTING", "LOBBY", "SELECT", "STAGE", "BATTLE"]
const MAGIC := "DBZ-SSW2-LAN"
const PROTO := 1
const DEFAULT_PORT := 8082
const CONNECT_TIMEOUT_MS := 15000
const LOST_MS := 10000                   ## no packet for this long = connection lost
const PING_MS := 500
const WAIT_SHOW_MS := 500                ## stall longer than this: "WAITING FOR PLAYER"
const SAVE_COPY := 0x020DD5B4            ## the game's save copy in RAM (0x1F4 bytes, read by the battle loader)
const SAVE_COPY_LEN := 0x1F4
const REC_LEN := 7                       ## u16 held, u16 tapped, u8 flags (1 touching, 2 new touch), u8 x, u8 y
const MAX_SEND := 16                     ## records per input packet (redundancy against loss)
const PERIOD_MS := 1000.0 / 59.8261
const RESEND_MS := 15                    ## input packets are resent at most this often (besides one per new record)
const SCENE := 0x020DD4C4                ## u8 scene, u8 state (+1), u16 sub-state (+2)
const SOFT_RESET := 0x30C                ## L + R + Select + Start: the game's soft reset (masked in LAN battles)
const START := 0x008
const A := 0x001
const PKT_INPUT := 1
const PKT_PING := 2                      ## (ping / pong: QoLLanNet)
const PKT_PONG := 3

## ---- public state (read by the menus)
var state := IDLE
var role := ""
var my_name := ""
var peer_name := ""
var ping_ms := -1
var port := 0
var reason := ""                         ## why the last connect / session failed
var target := ""                         ## guest: "ip:port"
var settings: QoLSettings
## ---- battle (lockstep)
var battle_info: Dictionary = {}         ## STAGE_RESULT: seed, delay, save (host's save copy), stage, teams, debug
var battle_pending := false              ## phase 3: the 5 -> 7 redirect asked for a LAN battle (consumed at the init)
var debug_battle := false                ## `lanbattle=1`: every Free Battle (mode 5) is a LAN battle
var in_battle := false                   ## a LAN battle runs (set / cleared on the game thread by QoLGame's hooks)
var lockstep := false                    ## frames wait for the remote's records (main thread)
var aborting := false                    ## leaving the battle alone after a disconnect / desync (6.1)
var abort_reason := ""
var delay := 2
var battle_side := -1                    ## part 32: this machine's side in the running / last LAN battle (0 host, 1 guest):
                                         ## `role` is cleared when the session ends, the battle may still be on screen
var battle_no := 0                       ## LAN battles started in this session (id in the input packets)
var stalls := 0
var stall_ms := 0
var _stall_info := ""

var qol                                  ## QoLController
var net := QoLLanNet.new()
var _rom: PackedByteArray
var _events: Array = []
var _dbg := false
var _t_connect := 0
var _t_ping := 0
var _t_send := 0
var _last_rx := 0
var _rtts: Array = []                    ## [t_ms, rtt] of the last pings (delay choice)
var _rtt_ema := -1.0
var _join_t := 0                         ## host: when the guest joined (debug_battle sends STAGE_RESULT 2 s later)
var _info_sent := false
var _rom_md5 := ""
var _build := ""
var _proposed := false
var _auto := false
var _start_req := ""                     ## `lan=` debug start waiting for scene 0x11 (no lanbattle)
## lockstep buffers
var _base := 0                           ## port frame (completed) of the battle init
var _cur_L := 0
var _loc := {}                           ## L -> PackedByteArray record (this machine)
var _loc_new := 0
var _rem := {}                           ## L -> record (the other machine)
var _rem_bid := -1
var _rem_contig := 0
var _rem_acked := 0                      ## newest of our frames the other machine has (its ack)
var _rem_cur := 0                        ## the other machine's current frame (time sync)
var _crc := {}                           ## L -> gameplay checksum (this machine)
var _rcrc := {}                          ## L -> the other machine's checksum
var _crc_new := 0
var _desynced := false
var _stall_t0 := 0
var _wait_until := 0                     ## phase 3: the WAITING FOR PLAYER band stays up until then (ms)
var _adv := 0.0                          ## smoothed frame advantage (time sync)
var _prev_touch := false
var _linger_until := 0                   ## after the battle: keep resending unacked records until then (ms)
var _exit_L := 0
var _init_flag := false                  ## game thread -> main: the battle init ran in this frame
var _loaded := false                     ## phase 4: the battle loader ran (the checksum's pointers are this battle's)
var _loaded_L := -1
var _exit_flag := -1                     ## game thread -> main: FUN_02001014 left the battle (asked scene)
var _abort_n := 0
var _ended_at := -1                      ## port frame the last LAN battle ended (lanquit)
var _script: Array = []                  ## laninputs=
var _hash_f: FileAccess = null
var _quit_L := -1
var _desync_L := -1
## part 32 debug `lanpace`: one "LANP" line per 60 lockstep frames (real time, stalls, packets, ping, CPU time)
var _pace := false
var _pc := {}
var rx_inputs := 0                       ## input packets received (statistics)
var _step_us := 0
var _step_max := 0
var _t_frame := 0
var _polls := 0


func setup(q, rom: PackedByteArray) -> void:
	qol = q
	settings = q.settings
	_rom = rom
	_dbg = Game.args.has("landbg")
	_pace = Game.args.has("lanpace")
	debug_battle = Game.flag("lanbattle", "0") != "0"
	_auto = Game.args.has("lanauto")
	_quit_L = int(Game.flag("lanquit", "-1"))
	_desync_L = int(Game.flag("landesync", "-1"))
	for e in Game.flag("laninputs").split(",", false):
		var p := e.split(":")
		_script.append([int(p[0]), p[1].split("+"), int(p[2]) if p.size() > 2 else 4])
	_sel_setup()                                     # phase 3 debug flags (lanpicks, lanstage, lanrounds, lanleave)
	if Game.args.has("lan"):
		_start_req = Game.flag("lan")
		if debug_battle:
			_debug_start()


# ================================================================================================ public API
func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else "?"


func active() -> bool:
	return state != IDLE


## anything to do after a game frame (QoLController skips after_step otherwise)
func busy() -> bool:
	return state != IDLE or in_battle or lockstep or aborting or _init_flag or _exit_flag >= 0 or _start_req != "" \
		or (_quit_L > 0 and _ended_at >= 0) or force_leave or not notice.is_empty() or _rejoin_at >= 0 or _rejoin_dbg > 0 \
		or _qa_what != ""


## the other player is here (lobby, select, stage, battle)
func connected() -> bool:
	return state >= LOBBY and net.peer != null


func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in QoLLanNet.local_addresses(3):
		out.append(a)
	return out


## open a room on `p` (8082: 8083..8091 when it is in use). false = no port could be bound
func host(name: String, p := DEFAULT_PORT) -> bool:
	_end_session()
	my_name = _clean_name(name, "HOST")
	_ids()
	var err := net.host(p)
	if err != OK:
		reason = "PORT IN USE"
		_log("host: no port from %d (%s)" % [p, error_string(err)])
		return false
	role = "host"
	port = net.port
	state = HOSTING
	_proposed = false
	_log("hosting on UDP %d as %s, addresses %s" % [port, my_name, local_addresses()])
	return true


## connect to a host (async: CONNECTING until "connected", "connect_failed" or "rejected"). `ip` may carry ":port".
func join(name: String, ip: String, p := DEFAULT_PORT) -> bool:
	_end_session()
	my_name = _clean_name(name, "GUEST")
	var a := QoLLanNet.parse_address(ip if ":" in ip else "%s:%d" % [ip, p])
	if a.is_empty():
		reason = "BAD ADDRESS"
		_event({"type": "connect_failed", "reason": reason})
		return false
	_ids()
	target = "%s:%d" % [a[0], a[1]]
	var err := net.join(a[0], a[1])
	if err != OK:
		reason = "NETWORK ERROR"
		_event({"type": "connect_failed", "reason": reason})
		return false
	role = "guest"
	port = int(a[1])
	state = CONNECTING
	_t_connect = Time.get_ticks_msec()
	_log("joining %s as %s" % [target, my_name])
	return true


## leave the room / session (BYE to the other player); a running LAN battle is left through the pause menu (6.1)
func leave() -> void:
	if state == IDLE:
		return
	if net.peer != null and state >= LOBBY:
		_send_msg({"t": "BYE", "reason": "LEFT"})
	_log("leave (%s)" % state_name())
	if in_battle and not aborting:
		_abort("LEFT")
	_end_session(true)                               # (phase 3: BYE delivered before the disconnect)


## host, in the lobby: ask the guest to go to the character select
func propose_select() -> void:
	if role == "host" and state == LOBBY and net.peer != null:
		_proposed = true
		_flow_n += 1                                 # part 31: every proposal starts a new flow id
		_send_msg({"t": "PROPOSE_SELECT", "flow": _flow_n})


## guest: answer the host's proposal (part 31: the flow id of the LAST proposal; a stale popup cannot start an old one)
func accept_select() -> void:
	if role == "guest" and state == LOBBY and _prop_flow > 0:
		prop_pending = false
		_reset_flow()
		flow = _prop_flow
		_send_msg({"t": "ACCEPT", "flow": flow})
		state = SELECT
		in_flow = true
		_where_p = 0


func deny_select() -> void:
	if role == "guest" and state == LOBBY:
		prop_pending = false
		_send_msg({"t": "DENY", "flow": _prop_flow})


## seconds left of the 15 s connect timeout (guest, CONNECTING)
func connect_left() -> float:
	if state != CONNECTING:
		return 0.0
	return maxf(0.0, (CONNECT_TIMEOUT_MS - (Time.get_ticks_msec() - _t_connect)) / 1000.0)


## a lockstep stall longer than 0.5 s ("WAITING FOR PLAYER")
func waiting() -> bool:
	if not lockstep:
		return false
	var now := Time.get_ticks_msec()
	return (_stall_t0 != 0 and now - _stall_t0 > WAIT_SHOW_MS) or now < _wait_until   # (phase 3: shown 0.4 s longer: no flicker)


func pop_event() -> Dictionary:
	return {} if _events.is_empty() else _events.pop_front()


## network + timers; called every Godot frame (QoLController.lan_poll from GameDS._process, the menus) and before a
## stalled game frame. Safe to call several times per frame.
func poll() -> void:
	_polls += 1
	if net.con == null:
		net.service_closing()                        # phase 3: a left session's BYE still being delivered
		return
	for ev in net.service():
		_on_net(ev)
	if net.con == null:
		return
	var now := Time.get_ticks_msec()
	if state == CONNECTING and now - _t_connect > CONNECT_TIMEOUT_MS:
		_fail_connect("TIMEOUT")
		return
	if net.peer != null and state >= LOBBY:
		if now - _t_ping >= PING_MS:
			_t_ping = now
			net.send_ping()                              # (phase 4: answered and timed by QoLLanNet's thread)
		if now - _last_rx > LOST_MS:
			_peer_gone("lost", "TIMEOUT")
			return
		if role == "host" and debug_battle and not _info_sent and now - _join_t > 2000:
			_info_sent = true
			send_stage_result(_debug_info())
	if net.peer != null and state >= LOBBY:
		_where_tick(now)                             # part 31: where both machines are (WHERE) + the out-of-step watchdog
	if (lockstep or (now < _linger_until and _rem_acked < _exit_L)) and now - _t_send >= RESEND_MS:
		_send_inputs()                               # resend (unacked records, ack, checksum): at most every 15 ms


## host: everything a battle start needs (design 4.2), sent once, reliably; kept here for its own battle start.
## info: {"stage": id or -1 (keep), "teams": [[ids...], [ids...]] or [] (keep), ...}; seed / delay / save are added.
func send_stage_result(info: Dictionary) -> void:
	if role != "host":
		return
	var bi := info.duplicate()
	bi["t"] = "STAGE_RESULT"
	bi["seed"] = randi()
	bi["delay"] = _choose_delay()
	bi["save"] = qol.machine.core.M.slice(SAVE_COPY - 0x02000000, SAVE_COPY - 0x02000000 + SAVE_COPY_LEN)
	bi["sid"] = session_id                           # part 31: this session / flow (the round comes with `info`)
	_result_n += 1
	bi["battle"] = _result_n                         # part 31: the battle's id on both machines (input packets)
	bi["flow"] = flow
	battle_info = bi
	_send_msg(bi)
	_log("STAGE_RESULT sent: seed %x delay %d stage %d teams %s" % [bi["seed"], bi["delay"], int(bi.get("stage", -1)), bi.get("teams", [])])


# ================================================================================================ QoLGame hooks (game thread)
## FUN_020140C8: is this battle start a LAN battle? (mode: party u32 0x020DD514)
## part 31: the battle runs on `start_info` (a copy taken at the 5 -> 7 redirect, so a session that ends during the scene
## load cannot leave an unsynced plain Free Battle behind: it starts as a LAN battle and is left at once, `_start_abort`)
func wants_battle(mode: int) -> bool:
	if in_battle:
		return false
	if debug_battle:
		if not connected() or battle_info.is_empty() or mode != 5:
			return false
		start_info = battle_info
		_start_abort = ""
		return true
	if not battle_pending:
		return false
	battle_pending = false
	start_info = _pending_info
	_pending_info = {}
	if start_info.is_empty():
		return false
	_start_abort = "" if connected() and battle_fresh(start_info) else ("LOST" if not connected() else "OUT OF STEP")
	return true


## part 31: `info` is this session's STAGE_RESULT of this flow and round (both machines: the host's own copy / the guest's)
func battle_fresh(info_in = null) -> bool:
	var info: Dictionary = battle_info if info_in == null else info_in
	return not info.is_empty() and int(info.get("sid", -1)) == session_id and session_id != 0 \
		and int(info.get("flow", -1)) == flow and int(info.get("round", -1)) == sel_round


## part 31, game thread (QoLGame 5 -> 7 redirect): the battle will start on a copy of this round's STAGE_RESULT
func battle_redirect() -> void:
	_pending_info = battle_info.duplicate()
	battle_pending = true


## part 31, game thread: the battle cannot start (no STAGE_RESULT of this round): both back to the room (main thread)
func request_room(why: String) -> void:
	_room_req = why


## FUN_020140C8 synced the battle (game thread): lockstep starts with the next frame
func on_battle_init() -> void:
	battle_pending = false
	in_battle = true
	_init_flag = true
	_loaded = false


## phase 4 QA: FUN_0202A40C (the battle loader) ran in this LAN battle (game thread). Until then the team / effect-pool /
## camera pointers the checksum reads still point at the PREVIOUS battle's (freed) blocks, so a machine with another
## history (a fresh guest vs a host that already played, or local battles before the session) hashed stale memory and
## both reported a DESYNC at L1-L4 (/tmp/ssw2/lanqa/rj_after): no checksum before the loader.
func on_battle_loaded() -> void:
	_loaded = true
	_loaded_L = qol.game.frames + 1 - _base if qol != null and lockstep else -1


## FUN_02001014 from scene 0 during a LAN battle (game thread): the battle is over at the end of this frame
func on_battle_exit(to: int) -> void:
	in_battle = false
	_exit_flag = to


# ================================================================================================ GameDS / QoLController hooks (main thread)
## GameDS._tick_begin: may lockstep frame `frames + 1` start? (false = no game frame now)
func can_step(next_frame: int) -> bool:
	var L := next_frame - _base
	_cur_L = L
	if L <= delay or L <= _rem_contig:
		_stall_end()
		return true
	poll()                                           # maybe it just arrived
	if L <= _rem_contig:
		_stall_end()
		return true
	if not lockstep:                                 # (aborted inside poll)
		return true
	if _stall_t0 == 0:
		_stall_t0 = Time.get_ticks_msec()
		_stall_info = "have %d, remote at %d, acked %d" % [_rem_contig, _rem_cur, _rem_acked]
	elif Time.get_ticks_msec() - _stall_t0 > STALL_ABORT_MS * _wd_scale():   # part 31: never wait forever (the peer answers pings
		print("LAN battle %d: no input from the other machine for %d s at L%d (%s)" % [battle_no, STALL_ABORT_MS / 1000,
			L, _stall_info])                         # but sends no records: both machines back to the room)
		_room_both("NO INPUT")
		return true
	return false


## GameDS._tick_begin, after the local input path (filter_input, MIRROR): lockstep -> sample the local record for
## L + delay, send, return [keys, ext, touch] for frame L from the records; aborting -> the pause-menu exit inputs
func frame(keys: int, ext: int, touch: Vector2i) -> Array:
	if aborting:
		return _abort_input()
	if not lockstep:
		return [keys, ext, touch]
	var L := _cur_L
	var t := L + delay
	var w := (~keys & 0x3FF) | (~ext & 0xC00)
	for e in _script:                                # laninputs=: frames relative to the frame they act in
		if t >= e[0] and t < e[0] + e[2]:
			for b in e[1]:
				if b.begins_with("T"):
					var xy: PackedStringArray = b.substr(1).split("/")
					touch = Vector2i(int(xy[0]), int(xy[1]))
				else:
					w |= _btn(b)
	var touching := touch.x >= 0 and touch.y >= 0
	var fl := (1 if touching else 0) | (2 if touching and not _prev_touch else 0)
	_prev_touch = touching
	var r := PackedByteArray()
	r.resize(REC_LEN)
	r.encode_u16(0, w & 0xFFF)
	r.encode_u16(2, 0)
	r[4] = fl
	r[5] = clampi(touch.x, 0, 255) if touching else 0
	r[6] = clampi(touch.y, 0, 191) if touching else 0
	if t > _loc_new:
		_loc[t] = r
		_loc_new = t
	_send_inputs()
	if L == _desync_L:                               # debug landesync=L: corrupt P1's HP on this side only
		var c = qol.machine.core
		var tb: int = c.r32(0x020DE3D0)
		if tb >= 0x02000000 and tb < 0x02400000:
			var p1: int = tb + c.r8(tb + 0x8C8) * 0x2D8
			c.M.encode_u16(p1 + 0x24A - 0x02000000, (c.r16(p1 + 0x24A) - 7) & 0xFFFF)
			print("LAN L%d landesync: P1 HP changed on this side only" % L)
	if _pace:
		_t_frame = Time.get_ticks_usec()
	return _apply(L)


## time sync (2.1): the machine that is ahead runs up to 1 % slower (GameDS free-run pacing)
func time_scale() -> float:
	if not lockstep or _rem_cur <= 0:
		return 1.0
	var adv := float(_cur_L) - (float(_rem_cur) + maxf(float(ping_ms), 0.0) * 0.5 / PERIOD_MS)
	_adv = lerpf(_adv, adv, 0.02)
	return 0.99 if _adv > 0.75 else 1.0


## after every game frame (QoLController.after_step, game thread parked)
func after_step(core) -> void:
	var gf: int = qol.game.frames
	_sel_step(core)                                  # phase 3: select / stage / lobby flow (`# ---- LAN SELECT`)
	if _dbg or _qa_what != "":                       # part 31 debug: POINT lines (kill tests) / lanquitat
		_point_tick(core)
	if _rejoin_dbg > 0:                              # part 31 debug lanrejoin: a session of this process ended -> again
		if state >= LOBBY:
			_rj_lobby = true
		if state != IDLE:
			_rj_active = true
		elif _rj_active and _rejoin_at < 0:
			_rj_active = false
			if _rj_lobby:                            # (a failed connect is retried without counting)
				_rj_lobby = false
				_rejoin_n -= 1
			if _rejoin_n >= 0:
				_rejoin_at = _rejoin_dbg
	if _rejoin_at >= 0 and state == IDLE:            # part 31 debug lanrejoin
		_rejoin_at -= 1
		if _rejoin_at <= 0:
			_rejoin_at = -1
			_start_req = Game.flag("lan")
			if _rejoin_n > 0:
				_leave_dbg = _leave_dbg0
			print("LAN lanrejoin: starting again (%s)" % _start_req)
	if _start_req != "" and not debug_battle and core.r8(SCENE) == 0x11 and core.r8(SCENE + 1) >= 2:
		_debug_start()
	if _room_req != "":                              # part 31: the game thread found no STAGE_RESULT of this round
		var w := _room_req
		_room_req = ""
		_room_both(w)
	if _init_flag:
		_init_flag = false
		_start_lockstep(gf)
		if _start_abort == "" and force_leave:
			_start_abort = "LEFT"
		if _start_abort != "":                       # part 31: the session ended / went out of step during the load
			print("LAN battle %d started without its session (%s): left at once" % [battle_no, _start_abort])
			if _start_abort == "OUT OF STEP":
				_room_both("OUT OF STEP")
			else:
				lockstep = false
				_abort(_start_abort)
			_start_abort = ""
	if lockstep:
		var L := gf - _base
		if _pace and _t_frame > 0:
			var us := Time.get_ticks_usec() - _t_frame
			_step_us += us
			_step_max = maxi(_step_max, us)
			_t_frame = 0
		if L >= 1 and _exit_flag < 0:                # (the exit frame: FUN_02001014 already reseeded the RNG from the RTC)
			var h := _gameplay_hash(core) if _loaded else "000000000000"   # (phase 4: not before the loader)
			if _loaded_L > 0 and L == _loaded_L:
				_log("battle loaded at L%d: teams %08x pool %08x" % [L, core.r32(0x020DE3D0), core.r32(0x020DE3CC)])
			var crc := h.substr(0, 8).hex_to_int()
			_crc[L] = crc
			_crc_new = L
			_crc.erase(L - 300)
			_rcrc.erase(L - 300)
			_check_crc(L)
			if _hash_f != null:
				_hash_f.store_line("LANH B%d L%d f%d sc %04x st %02x rng %08x/%02x/%02x gp %s G %s" % [battle_no, L, gf,
					core.r16(SCENE), core.r8(SCENE + 1), core.r32(0x020DD4E4), core.r8(0x020DD4E8), core.r8(0x020DD4E9),
					h, _g_hash(core)])
			if _dbg and L % 300 == 0:
				print("LAN f%d L%d remote %d acked %d ping %d stalls %d (%d ms) adv %.2f sent %d dropped %d" % [gf, L,
					_rem_contig, _rem_acked, ping_ms, stalls, stall_ms, _adv, net.sent, net.dropped])
			if _pace and L % 60 == 0:
				_pace_line(core, L)
			if _quit_L > 0 and L >= _quit_L:
				_quit("lanquit L%d" % L)
	if _exit_flag >= 0:
		var to := _exit_flag
		_exit_flag = -1
		_end_battle(gf, to)
	if _quit_L > 0 and _ended_at >= 0 and gf - _ended_at >= 120:
		_quit("lanquit: battle over")


# ================================================================================================ internals
## part 32 debug `lanpace`: the last 60 lockstep frames: real ms, frames/s, stall ms (count), input packets sent /
## received, pings (min / avg / max of the rtts that arrived), process CPU ms (Linux /proc/self/stat: user + system)
func _pace_line(core, L: int) -> void:
	var now := Time.get_ticks_usec()
	var cpu := -1.0
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f != null:
		var q := f.get_line().split(") ")[-1].split(" ")   # (get_line: /proc files have no length)
		if q.size() > 12:
			cpu = (float(q[11]) + float(q[12])) * 10.0   # (utime + stime in clock ticks of 10 ms)
	var rt: Array = []
	for e in _rtts:
		if int(e[0]) * 1000 > int(_pc.get("t", 0)):
			rt.append(float(e[1]))
	var rs := "-"
	if not rt.is_empty():
		var sum := 0.0
		for x in rt:
			sum += x
		rs = "%.1f/%.1f/%.1f" % [rt.min(), sum / rt.size(), rt.max()]
	if not _pc.is_empty():
		var ms := (now - int(_pc["t"])) / 1000.0
		print("LANP L%d st %02x real %.0f ms (%.1f f/s) stalls %d ms (%d) sent %d rx %d rtt %s cpu %.0f ms" % [L,
			core.r8(SCENE + 1), ms, 60000.0 / maxf(ms, 1.0), stall_ms - int(_pc["sm"]), stalls - int(_pc["sn"]),
			net.sent - int(_pc["tx"]), rx_inputs - int(_pc["rx"]), rs, cpu - float(_pc["cpu"])])
	if not _pc.is_empty():
		var r3 = qol.game.display.r3d
		var ns := 0
		var nt := 0
		for sf in r3._surfaces:
			ns += 1
			if sf[1] == 1:
				nt += 1
		var lp = qol.lan_panel
		print("LANP L%d   step avg %.2f ms max %.1f, net loops %d, polls %d, 3D surfaces %d (translucent %d), panel %s composes %d (%.1f ms)" % [L,
			_step_us / 60000.0, _step_max / 1000.0, net.loops - int(_pc["nl"]), _polls - int(_pc["po"]), ns, nt,
			"shown" if lp.shown else "hidden", lp.composes - int(_pc["pc"]), (lp.compose_us - int(_pc["pu"])) / 1000.0])
	_step_us = 0
	_step_max = 0
	_pc = {"t": now, "sm": stall_ms, "sn": stalls, "tx": net.sent, "rx": rx_inputs, "cpu": cpu, "nl": net.loops, "po": _polls, "pc": qol.lan_panel.composes, "pu": qol.lan_panel.compose_us}


func _debug_start() -> void:
	var v := _start_req
	_start_req = ""
	var nm := Game.flag("lanname", str(settings.get("lan_name")) if settings.get("lan_name") != null else "")
	var p := int(Game.flag("lanport", str(DEFAULT_PORT)))
	if v == "host":
		host(nm if nm != "" else "HOST", p)
	elif v.begins_with("join:"):
		var a := v.substr(5)
		join(nm if nm != "" else "GUEST", a, p)


## `lanbattle=1` STAGE_RESULT: the battle as the menus set it, or `lanbstage=HEX` (stage id) / `lanteams=a.b.c/d.e.f`
func _debug_info() -> Dictionary:
	var teams := []
	if Game.args.has("lanteams"):
		for side: String in Game.flag("lanteams").split("/"):
			var ids := []
			for x in side.split(".", false):
				ids.append(int(x))
			teams.append(ids)
	if not Game.args.has("lanbstage"):   # part 32: the usual harness trap (each machine resolves its own random stage)
		print("LAN WARNING: lanbattle=1 without lanbstage=HEX: each machine keeps its own menu's stage (Free Battle's " +
			"random stage differs with the RTC) - the gameplay hash will differ from the battle load on (DESYNC)")
	return {"stage": Game.flag("lanbstage").hex_to_int() if Game.args.has("lanbstage") else -1,
		"teams": teams if teams.size() == 2 else [], "debug": true}


func _ids() -> void:
	if _build == "":
		_build = Game.flag("lanbuild", "")
		if _build == "":
			_build = build_id()
	if _rom_md5 == "" and Game.args.has("lanrom"):      # debug: fake another ROM (REJECT "ROM" tests)
		_rom_md5 = Game.flag("lanrom")
	if _rom_md5 == "" and not _rom.is_empty():
		var h := HashingContext.new()
		h.start(HashingContext.HASH_MD5)
		h.update(_rom)
		_rom_md5 = h.finish().hex_encode()


## the port build: res://data/build_id.txt if present, else the MD5 of the translated game, the DS runtime, the QoL layer
## and GameDS — their source text in editor / dev runs, the binary-token scripts (.gdc) in exported builds (which carry no
## source text): two copies of the same build agree, different builds (or an editor run vs an export) do not
static func build_id() -> String:
	if FileAccess.file_exists("res://data/build_id.txt"):
		var s := FileAccess.get_file_as_string("res://data/build_id.txt").strip_edges()
		if s != "":
			return s
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	var n := 0
	var paths: Array = []
	for dir in ["res://scripts/gen", "res://scripts/core", "res://scripts/qol"]:
		var bases := {}
		for f: String in DirAccess.get_files_at(dir):
			for suf in [".gd.remap", ".gdc", ".gd"]:
				if f.ends_with(suf):
					bases[f.substr(0, f.length() - suf.length())] = true
					break
		var names := bases.keys()
		names.sort()
		for b in names:
			paths.append(dir.path_join(b))
	paths.append("res://scripts/game/game_ds")
	for pth: String in paths:
		var b := FileAccess.get_file_as_bytes(pth + ".gd")
		if b.is_empty():
			b = FileAccess.get_file_as_bytes(pth + ".gdc")
		h.update(b)
		n += b.size()
	if n == 0:
		return "unknown"
	return h.finish().hex_encode().substr(0, 16)


static func _clean_name(s: String, def: String) -> String:
	var out := ""
	for ch in s.strip_edges().to_upper():
		if ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-_ ":
			out += ch
	out = out.strip_edges().left(10)
	return out if out != "" else def


func _event(e: Dictionary) -> void:
	_events.append(e)
	if _dbg:
		print("LAN f%d event %s" % [qol.game.frames if qol != null else -1, e])


func _log(s: String) -> void:
	if _dbg:
		print("LAN f%d %s" % [qol.game.frames if qol != null and qol.game != null else -1, s])


func _send_msg(d: Dictionary, to: ENetPacketPeer = null) -> void:
	if not d.has("sid"):                             # part 31: every message carries the session id + the flow id
		d["sid"] = session_id
	if not d.has("flow"):
		d["flow"] = flow
	net.send(QoLLanNet.CH_SESSION, var_to_bytes(d), to)


func _on_net(ev: Dictionary) -> void:
	var p: ENetPacketPeer = ev["peer"]
	match ev["type"]:
		"connect":
			if role == "guest" and state == CONNECTING:
				_send_msg({"t": "HELLO", "magic": MAGIC, "proto": PROTO, "build": _build, "rom": _rom_md5, "name": my_name})
				_log("connected to %s, HELLO sent" % target)
		"disconnect":
			if role == "guest" and state == CONNECTING:
				_fail_connect("NO ANSWER")
			elif p == net.peer and net.peer != null:
				_peer_gone("lost", "DISCONNECTED")
		"rtt":                                           # phase 4: a pong, timed in QoLLanNet's thread (µs)
			if p == net.peer and net.peer != null:
				_last_rx = Time.get_ticks_msec()
				_on_rtt(float(ev["us"]) / 1000.0)
		"receive":
			var ch: int = ev["ch"]
			var data: PackedByteArray = ev["data"]
			if ch == QoLLanNet.CH_SESSION:
				var v = bytes_to_var(data) if data.size() > 0 else null
				if v is Dictionary and v.has("t"):
					_on_msg(p, v)
				return
			if p != net.peer or data.is_empty():
				return
			_last_rx = Time.get_ticks_msec()
			if ch == QoLLanNet.CH_INPUT and data[0] == PKT_INPUT:
				_on_input(data)


func _on_msg(p: ENetPacketPeer, m: Dictionary) -> void:
	var t := str(m["t"])
	if role == "host" and t == "HELLO":
		_on_hello(p, m)
		return
	if p != net.peer:
		return
	_last_rx = Time.get_ticks_msec()
	_log("msg %s" % t)
	# part 31: a message of another session, or (select / stage / battle messages) of another flow, is dropped
	if not (t in ["WELCOME", "REJECT", "BYE"]) and int(m.get("sid", -1)) != session_id:
		print("LAN f%d STALE %s dropped: session %x, this session %x" % [qol.game.frames if qol != null else -1, t,
			int(m.get("sid", -1)), session_id])
		return
	if t in FLOW_MSGS and int(m.get("flow", -1)) != flow:
		print("LAN f%d STALE %s dropped: flow %d round %d, this flow %d round %d" % [qol.game.frames if qol != null else -1,
			t, int(m.get("flow", -1)), int(m.get("round", -1)), flow, sel_round])
		return
	match t:
		"WELCOME":
			if role == "guest" and state == CONNECTING:
				_on_welcome(m)
		"REJECT":
			if role == "guest":
				reason = str(m.get("reason", "REFUSED"))
				_event({"type": "rejected", "reason": reason})
				_end_session()
		"BYE":
			_peer_gone("left", str(m.get("reason", "LEFT")))
		"PROPOSE_SELECT":
			if role == "guest" and state == LOBBY:
				_prop_flow = int(m.get("flow", 0))
				prop_pending = true
				_event({"type": "proposal"})
				if _auto and not (_leave_dbg > 0 and lobby_n >= _leave_dbg):   # (debug lanleave: this room is left)
					accept_select()
		"ACCEPT":
			if role == "host" and state == LOBBY and _proposed and int(m.get("flow", -1)) == _flow_n:
				_reset_flow()                        # part 31: a clean flow on both machines
				flow = _flow_n
				state = SELECT
				in_flow = true
				_where_p = 0
				_proposed = false
				_event({"type": "proposal_accepted"})
			else:
				print("LAN STALE ACCEPT dropped: flow %d, last proposal %d (proposed %s, state %s)" % [int(m.get("flow", -1)),
					_flow_n, _proposed, state_name()])
		"DENY":
			if role == "host" and int(m.get("flow", -1)) == _flow_n:
				_proposed = false
				_event({"type": "proposal_denied"})
		"STAGE_RESULT":
			if _oos_dbg == "noresult":               # part 31 debug: the result never arrives
				_oos_dbg = ""
				print("LAN lanoos noresult: STAGE_RESULT ignored")
				return
			if role == "guest":
				battle_info = m
				stage_res = m                        # phase 3: the host's 50/50 (stage select roulette)
				_log("STAGE_RESULT: flow %d round %d seed %x delay %d stage %d" % [int(m.get("flow", -1)), int(m.get("round", -1)),
					int(m.get("seed", 0)), int(m.get("delay", 2)), int(m.get("stage", -1))])
		"SELECT_READY", "SELECT_UNREADY", "SELECT_GO", "LEAVE_SELECT", "STAGE_CURSOR", "STAGE_BACK", "STAGE_BACK_REQ":
			_on_sel_msg(t, m)                        # phase 3 (`# ---- LAN SELECT`)
		"WHERE":                                     # part 31: where the other machine is (flow, step)
			rem_where = {"flow": int(m.get("flow", -1)), "p": int(m.get("p", -1)), "battle": int(m.get("battle", 0))}
		"BACK_TO_ROOM":                              # part 31: the other machine found the two out of step
			_log("BACK_TO_ROOM received: %s" % str(m.get("reason", "")))
			_go_room(str(m.get("reason", "OUT OF STEP")), true)
		"DESYNC":
			if int(m.get("battle", battle_no)) != battle_no:
				return
			if in_battle and not aborting:
				print("LAN DESYNC reported by the other machine at L%d (its crc %08x)" % [int(m.get("frame", 0)), int(m.get("crc", 0))])
				_event({"type": "desync", "frame": int(m.get("frame", 0))})
				_desynced = true
				_abort("DESYNC")
		"BATTLE_ABORT":
			if in_battle and not aborting and int(m.get("battle", battle_no)) == battle_no:
				_abort(str(m.get("reason", "ABORT")))


func _on_hello(p: ENetPacketPeer, m: Dictionary) -> void:
	var why := ""
	if net.peer != null and p != net.peer:
		why = "FULL"
	elif str(m.get("magic", "")) != MAGIC:
		why = "NOT THIS GAME"
	elif int(m.get("proto", -1)) != PROTO or str(m.get("build", "")) != _build:
		why = "VERSION host %d/%s guest %d/%s" % [PROTO, _build, int(m.get("proto", -1)), str(m.get("build", ""))]
	elif str(m.get("rom", "")) != _rom_md5:
		why = "ROM"
	elif state != HOSTING:
		why = "FULL"
	elif not debug_battle and (in_battle or aborting or lockstep or force_leave or _init_flag or _exit_flag >= 0 \
		or (qol != null and qol.machine.core.r8(SCENE) != 0x11)):
		why = "HOST NOT IN ITS ROOM - TRY AGAIN"     # part 31: still on its way back from a select / battle
	if why != "":
		_send_msg({"t": "REJECT", "reason": why}, p)
		net.disconnect_peer(p, true)
		_log("HELLO from %s rejected: %s" % [str(m.get("name", "?")), why])
		return
	net.peer = p
	peer_name = _clean_name(str(m.get("name", "")), "GUEST")
	state = LOBBY
	_last_rx = Time.get_ticks_msec()
	_join_t = _last_rx
	_info_sent = false
	_proposed = false
	_rtts.clear()
	_rtt_ema = -1.0
	ping_ms = -1
	session_id = (randi() & 0x7FFFFFFF) | 1          # part 31: this connection's id (in every later message)
	_sel_reset_session()
	_reset_battle_ids()
	_log("session %x with %s" % [session_id, peer_name])
	_send_msg({"t": "WELCOME", "proto": PROTO, "build": _build, "rom": _rom_md5, "name": my_name,
		"session": session_id, "snapshot": settings.snapshot()})
	_event({"type": "peer_joined", "name": peer_name})


func _on_welcome(m: Dictionary) -> void:
	if int(m.get("proto", -1)) != PROTO or str(m.get("build", "")) != _build:
		reason = "VERSION host %d/%s guest %d/%s" % [int(m.get("proto", -1)), str(m.get("build", "")), PROTO, _build]
		_event({"type": "rejected", "reason": reason})
		_end_session()
		return
	if str(m.get("rom", "")) != _rom_md5:
		reason = "ROM"
		_event({"type": "rejected", "reason": reason})
		_end_session()
		return
	peer_name = _clean_name(str(m.get("name", "")), "HOST")
	var snap = m.get("snapshot", {})
	if snap is Dictionary:
		settings.begin_override(snap)               # the host's cheats / weird options (never saved: 5.4)
		_log("settings: host's snapshot on: %s" % _on_list())
		if qol != null:
			qol.apply_session_settings()
	state = LOBBY
	_last_rx = Time.get_ticks_msec()
	_rtts.clear()
	_rtt_ema = -1.0
	ping_ms = -1
	session_id = int(m.get("session", 0))           # part 31: the host's id for this connection
	_sel_reset_session()
	_reset_battle_ids()
	_log("session %x with %s" % [session_id, peer_name])
	if settings.get("lan_ip") != null:              # the player's own settings: allowed (save_file keeps its cheats)
		settings.set("lan_ip", target)
	if settings.get("lan_name") != null:
		settings.set("lan_name", my_name)
	settings.save_file()
	_event({"type": "connected", "name": peer_name})


## a round trip (ms, measured by QoLLanNet's thread: the network's own, not the frame times of the two machines)
func _on_rtt(rtt: float) -> void:
	var now := Time.get_ticks_msec()
	_rtts.append([now, rtt])
	while _rtts.size() > 0 and now - int(_rtts[0][0]) > 5000:
		_rtts.pop_front()
	_rtt_ema = rtt if _rtt_ema < 0.0 else lerpf(_rtt_ema, rtt, 0.25)
	ping_ms = maxi(1, int(round(_rtt_ema)))          # (localhost: well under 1 ms -> "1 ms")
	if Game.args.has("pingdbg"):
		print("LAN f%d rtt %.3f ms (enet %d ms) ping %d" % [qol.game.frames if qol != null else -1, rtt, net.enet_rtt(), ping_ms])


## D = clamp(ceil((RTT_avg + 2 jitter) / 2 / 16.71 ms) + 1, 2, 8) from the last 5 s of pings (2.2); `landelay=N`
func _choose_delay() -> int:
	if Game.args.has("landelay"):
		return clampi(int(Game.flag("landelay")), 1, 30)
	if _rtts.is_empty():
		return 2
	var s := 0.0
	for r in _rtts:
		s += float(r[1])
	var avg := s / _rtts.size()
	var j := 0.0
	for r in _rtts:
		j += absf(float(r[1]) - avg)
	j /= _rtts.size()
	return clampi(int(ceil((avg + 2.0 * j) / 2.0 / PERIOD_MS)) + 1, 2, 8)


func _fail_connect(why: String) -> void:
	reason = why
	_log("connect failed: %s" % why)
	_event({"type": "connect_failed", "reason": why})
	_end_session()


## the other player left (BYE) or the connection is gone: host -> HOSTING (room open again), guest -> IDLE
func _peer_gone(kind: String, why: String) -> void:
	reason = why
	last_peer = peer_name
	_log("peer gone: %s (%s)" % [kind, why])
	var away := _away_notice(kind)                   # phase 3: in a select / stage / battle: back to the room + notice
	if in_battle and not aborting:
		_abort("LOST" if kind == "lost" else "LEFT")
	_event({"type": "peer_left" if kind == "left" else "lost", "reason": why})
	if role == "host":
		var p := net.peer
		net.peer = null
		net.disconnect_peer(p, false)
		peer_name = ""
		ping_ms = -1
		_proposed = false
		state = HOSTING
		session_id = 0                               # part 31: everything of that guest's session goes
		_reset_flow()
	else:
		_end_session()
	if away:
		force_leave = _scene == 4 or _scene == 5


func _end_session(graceful := false) -> void:
	if net.con != null:
		if graceful:
			net.close_graceful()
		else:
			net.close()
	if settings != null:
		var was: bool = settings.override_active
		settings.end_override()                     # the guest's own cheats / weird options again
		if was:
			_log("settings: own values back: %s" % _on_list())
		if qol != null and role == "guest":
			qol.apply_session_settings()
	state = IDLE
	role = ""
	peer_name = ""
	ping_ms = -1
	_proposed = false
	session_id = 0                                   # part 31: a full reset of the session's flow state (a battle
	_reset_flow()                                    # already redirected starts from its copy and is left at once)
	if lockstep:
		lockstep = false
		if in_battle and not aborting:
			_abort("LEFT")


# ---- lockstep
## phase 4 QA: a new session counts its battles from 1 on both machines. The id is in every input packet and records of
## another battle are ignored, so a host that had played with an earlier guest (its battle 2 vs the new guest's battle 1)
## waited forever for records it threw away (both stuck on WAITING FOR PLAYER; /tmp/ssw2/lanqa/rj_before).
func _reset_battle_ids() -> void:
	battle_no = 0
	_result_n = 0
	_rem_bid = -1
	_rem = {}
	_rcrc = {}
	_rem_contig = 0
	_rem_acked = 0
	_linger_until = 0
	_exit_L = 0


func _start_lockstep(gf: int) -> void:
	var bn := int(start_info.get("battle", 0))     # part 31: the HOST's number of this battle (STAGE_RESULT), not a
	battle_no = bn if bn > battle_no else battle_no + 1   # local count: a battle only one machine started (aborted
	_base = gf                                       # at its start) made every later one wait for records it dropped
	delay = clampi(int(start_info.get("delay", 2)), 1, 30)
	battle_side = 1 if role == "guest" else 0
	lockstep = true
	aborting = false
	abort_reason = ""
	_desynced = false
	_abort_n = 0
	if connected():                                  # (part 31: a battle started after the session ended stays out)
		state = BATTLE
	_loc = {}
	_loc_new = delay
	_rem_acked = delay
	_cur_L = 0
	_crc = {}
	_crc_new = 0
	_prev_touch = false
	_stall_t0 = 0
	_adv = 0.0
	_rem_cur = 0
	_linger_until = 0
	if _rem_bid != battle_no:                        # records of this battle that came before its init are kept
		_rem = {}
		_rcrc = {}
		_rem_bid = battle_no
	_rem_contig = delay
	while _rem.has(_rem_contig + 1):
		_rem_contig += 1
	if Game.args.has("lanhash") and _hash_f == null:
		_hash_f = FileAccess.open(Game.flag("lanhash"), FileAccess.WRITE)
	print("LAN battle %d: lockstep from f%d (L1 = f%d), delay %d, %s %s vs %s" % [battle_no, gf, gf + 1, delay, role,
		my_name, peer_name])


func _end_battle(gf: int, to: int) -> void:
	var L := gf - _base
	print("LAN battle %d over at L%d (f%d), scene asked %x%s, stalls %d" % [battle_no, L, gf, to,
		(" (aborted: %s)" % abort_reason) if aborting else "", stalls])
	if lockstep:
		_exit_L = L
		_linger_until = Time.get_ticks_msec() + 5000
	lockstep = false
	aborting = false
	_stall_t0 = 0
	_ended_at = gf
	if _hash_f != null:
		_hash_f.flush()
	if state == BATTLE:
		state = LOBBY if connected() else (HOSTING if role == "host" and net.con != null else IDLE)


## leave the battle alone (6.1): lockstep ends now, P2 stands still, the pause menu's "Mode Select" is chosen by
## injected input (QoLGame.f_0201546c returns 4 while aborting), FUN_02001014 is redirected to the VS menu (0x11)
func _abort(why: String) -> void:
	if not in_battle or aborting:
		return
	print("LAN battle %d abort at L%d: %s" % [battle_no, _cur_L, why])
	aborting = true
	abort_reason = why
	if why == "DESYNC":                              # phase 3: told when the room's page opens again
		notice = {"title": "DESYNC", "lines": ["THE TWO GAMES DIFFERED (SEE THE", "LOG). THE BATTLE WAS STOPPED."], "then": "lobby"}
	lockstep = false
	_stall_t0 = 0
	_abort_n = 0
	if qol != null and qol.mp != null:
		qol.mp.clear_inputs()


func _abort_input() -> Array:
	var c = qol.machine.core
	_abort_n += 1
	var w := 0
	if c.r8(SCENE) == 0:
		var st: int = c.r8(SCENE + 1)
		if st == 7 and _abort_n % 4 < 2:
			w = START                                    # pause (state 9); QoLGame then picks "Mode Select"
		elif st >= 0x0F and st != 0x11 and _abort_n % 4 < 2:
			w = A                                        # battle end screens: on
	return [0x3FF & ~w, 0x2C00, Vector2i(-1, -1)]


func _stall_end() -> void:
	if _stall_t0 != 0:
		var ms := Time.get_ticks_msec() - _stall_t0
		if ms > WAIT_SHOW_MS:
			_wait_until = Time.get_ticks_msec() + 400
		stalls += 1
		stall_ms += ms
		if _dbg and ms >= 20:
			print("LAN f%d L%d stall %d ms (waited for the remote record: %s)" % [qol.game.frames, _cur_L, ms, _stall_info])
		_stall_t0 = 0


func _btn(b: String) -> int:
	match b:
		"A": return 0x001
		"B": return 0x002
		"Select": return 0x004
		"Start": return 0x008
		"Right": return 0x010
		"Left": return 0x020
		"Up": return 0x040
		"Down": return 0x080
		"R": return 0x100
		"L": return 0x200
		"X": return 0x400
		"Y": return 0x800
	return 0


func _rec(side: int, L: int) -> PackedByteArray:
	if L <= delay:
		return PackedByteArray([0, 0, 0, 0, 0, 0, 0])
	var mine := (side == 0) == (role == "host")
	var d: Dictionary = _loc if mine else _rem
	if d.has(L):
		return d[L]
	return PackedByteArray([0, 0, 0, 0, 0, 0, 0])


## records of frame L -> what the DS sees + QoLMp's P2 fields (identical on both machines)
func _apply(L: int) -> Array:
	var r0 := _rec(0, L)
	var r1 := _rec(1, L)
	var w0 := (r0.decode_u16(0) | r0.decode_u16(2)) & 0xFFF
	var w1 := (r1.decode_u16(0) | r1.decode_u16(2)) & 0xFFF
	var c = qol.machine.core
	var st: int = c.r8(SCENE + 1)
	var dsw := w0 | (w1 & START)                     # either player pauses
	if st == 9 or (st >= 0x0F and st <= 0x14):       # pause menu / battle end screens: either player navigates
		dsw |= w1
	if (dsw & SOFT_RESET) == SOFT_RESET:
		dsw &= ~START                                # no soft reset (it would reset both machines)
	var touch := Vector2i(r0[5], r0[6]) if (r0[4] & 1) != 0 else Vector2i(-1, -1)
	var mp: QoLMp = qol.mp
	mp.pressed[1] = w1 & ~int(mp.held[1])
	mp.released[1] = int(mp.held[1]) & ~w1
	mp.held[1] = w1
	mp.latch[1] = int(mp.latch[1]) | int(mp.pressed[1])
	mp.pressed[0] = w0 & ~int(mp.held[0])
	mp.held[0] = w0
	mp.touch[1] = Vector2i(r1[5], r1[6]) if (r1[4] & 1) != 0 else Vector2i(-1, -1)
	if (r1[4] & 2) != 0:
		mp.tap[1] = Vector2i(r1[5], r1[6])
	return [0x3FF & ~(dsw & 0x3FF), 0x2C00 & ~(dsw & 0xC00), touch]


func _send_inputs() -> void:
	if net.peer == null:
		return
	if _oos_dbg.begins_with("silent") and _cur_L >= int(_oos_dbg.substr(7) if _oos_dbg.length() > 7 else "500"):
		return                                       # part 31 debug lanoos=silent@L: no input records from L on
	_t_send = Time.get_ticks_msec()
	var first := maxi(_rem_acked + 1, delay + 1)
	var last := mini(_loc_new, first + MAX_SEND - 1)
	var n := maxi(0, last - first + 1)
	var b := PackedByteArray()
	b.resize(24 + n * REC_LEN)
	b[0] = PKT_INPUT
	b.encode_u16(1, battle_no & 0xFFFF)
	b.encode_u32(3, first)
	b[7] = n
	for i in n:
		var r: PackedByteArray = _loc.get(first + i, PackedByteArray([0, 0, 0, 0, 0, 0, 0]))
		for k in REC_LEN:
			b[8 + i * REC_LEN + k] = r[k]
	var o := 8 + n * REC_LEN
	b.encode_u32(o, _rem_contig)
	b.encode_u32(o + 4, maxi(_cur_L, 0))
	b.encode_u32(o + 8, _crc_new)
	b.encode_u32(o + 12, int(_crc.get(_crc_new, 0)))
	net.send(QoLLanNet.CH_INPUT, b)


func _on_input(b: PackedByteArray) -> void:
	if b.size() < 24:
		return
	rx_inputs += 1
	var bid := b.decode_u16(1)
	var first := b.decode_u32(3)
	var n := b[7]
	if b.size() < 24 + n * REC_LEN:
		return
	if bid < _rem_bid:
		return
	if bid > _rem_bid:
		if bid < battle_no:                          # (part 31: numbers come from the host's STAGE_RESULT and may skip)
			return
		_rem = {}
		_rcrc = {}
		_rem_bid = bid
		if bid != battle_no:                         # a battle the other machine already started: kept for ours
			_rem_contig = 0
	for i in n:
		var f := first + i
		if not _rem.has(f):
			_rem[f] = b.slice(8 + i * REC_LEN, 8 + (i + 1) * REC_LEN)
	var o := 8 + n * REC_LEN
	var mine := bid == battle_no and (lockstep or in_battle or _linger_until > 0)
	if mine:
		while _rem.has(_rem_contig + 1):
			_rem_contig += 1
		for k in _rem.keys():
			if k < _rem_contig - 64:
				_rem.erase(k)
		_rem_acked = maxi(_rem_acked, b.decode_u32(o))
		for k in _loc.keys():
			if k < _rem_acked - 64:
				_loc.erase(k)
		_rem_cur = b.decode_u32(o + 4)
		var cf := b.decode_u32(o + 8)
		if cf > 0:
			_rcrc[cf] = b.decode_u32(o + 12)
			_check_crc(cf)


func _check_crc(L: int) -> void:
	if _desynced or not lockstep or not _crc.has(L) or not _rcrc.has(L):
		return
	if int(_crc[L]) == int(_rcrc[L]):
		return
	_desynced = true
	print("LAN DESYNC battle %d at L%d: this machine %08x, other %08x" % [battle_no, L, int(_crc[L]), int(_rcrc[L])])
	_send_msg({"t": "DESYNC", "frame": L, "crc": int(_crc[L]), "battle": battle_no})
	_event({"type": "desync", "frame": L})
	_abort("DESYNC")


## the desync checksum (1.5): team blocks + effect pool with the drawing-only fields zeroed, RNG, battle state, timer,
## camera x / y. MD5 hex (the first 8 digits are the u32 sent in the input packets)
static func _gameplay_hash(c) -> String:
	var t: int = c.r32(0x020DE3D0)
	var pool: int = c.r32(0x020DE3CC)
	if t < 0x02000000 or t >= 0x02400000 or pool < 0x02000000 or pool >= 0x02400000:
		return "000000000000"
	var M: PackedByteArray = c.M
	var tb := M.slice(t - 0x02000000, t - 0x02000000 + 0x167C)
	for side in 2:
		for k in 3:
			tb.encode_u32(side * 0x8E8 + k * 0x2D8 + 0x140, 0)
		tb.encode_u32(side * 0x8E8 + 0x8A4, 0)
	var pb := M.slice(pool - 0x02000000, pool - 0x02000000 + 0x4DF0)
	for i in 48:
		pb.encode_u32(i * 0x164 + 0x140, 0)
	for i in 8:
		pb.encode_u32(0x42C0 + i * 0x164 + 0x140, 0)
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(tb)
	h.update(pb)
	h.update(M.slice(0x020DD4E4 - 0x02000000, 0x020DD4EA - 0x02000000))
	var g: int = c.r32(0x020DE3A0)
	var ex := PackedByteArray()
	ex.resize(16)
	ex.encode_u8(0, c.r8(0x020DD4C5))
	if g >= 0x02000000 and g < 0x02400000:
		ex.encode_u16(2, c.r16(g + 0x1BCA6))
	var cam: int = c.r32(0x020DE3A4)
	if cam >= 0x02000000 and cam < 0x02400000:
		ex.encode_u32(4, c.r32(cam + 0xC))
		ex.encode_u32(8, c.r32(cam + 0x10))
	h.update(ex)
	return h.finish().hex_encode().substr(0, 12)


## lanhash: MD5 of the whole battle globals block (drawing fields included: differs with CAMERA ZOOM etc.)
static func _g_hash(c) -> String:
	var g: int = c.r32(0x020DE3A0)
	if g < 0x02000000 or g + 0x1C000 > 0x02400000:
		return "-"
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(c.M.slice(g - 0x02000000, g - 0x02000000 + 0x1C000))
	return h.finish().hex_encode().substr(0, 8)


## debug (landbg): the cheats / weird options that are on now
func _on_list() -> String:
	var on := []
	for k in QoLSettings.CHEATS:
		if settings.cheat(k):
			on.append(k)
	for k in QoLSettings.WEIRD:
		if bool(settings.get(k)):
			on.append(k)
	return str(on)


## the game is closing (QoLController._exit_tree): BYE to the other player, then the network is shut down
func on_exit() -> void:
	if net.con != null and net.peer != null and state >= LOBBY:
		_send_msg({"t": "BYE", "reason": "QUIT"})
	net.shutdown()


func _quit(why: String) -> void:
	var c = qol.machine.core
	print("LAN quit (%s), state %s, scene %02x state %d, stalls %d, sent %d dropped %d" % [why, state_name(), c.r8(SCENE),
		c.r8(SCENE + 1), stalls, net.sent, net.dropped])
	if _hash_f != null:
		_hash_f.flush()
		_hash_f = null
	if net.con != null and net.peer != null and state >= LOBBY:
		_send_msg({"t": "BYE", "reason": "QUIT"})
	net.flush()
	_quit_L = -1
	qol.game.get_tree().quit()


# ---- LAN SELECT (part 30, phase 3) -----------------------------------------------------------------------------------
## docs/LAN_DESIGN.md 4 / 9 phase 3: the team select (scene 4, mode 2, each machine its own team), the stage select
## (scene 5, the LOCAL two-outline code: red = host = index 0, blue = guest = index 1) and the way back to the room.
## QoLGame `# ---- LAN SELECT` runs on the game thread and only sets / reads the fields below; this main-thread part sends
## and receives the messages (channel 0, reliable, each tagged with `sel_round` = scene-4 entries since the last room
## entry, the same on both machines) after every game frame (_sel_step) and feeds the DS input (sel_filter).
## - select: GO on this machine -> SELECT_READY {team, boss} and the READY? overlay stays up ("WAITING FOR <NAME>");
##   the HOST leaves for the stage select when both are ready (sends SELECT_GO), the guest when the GO arrives; B / BACK
##   while waiting -> SELECT_UNREADY. B with no picks (the game's own exit to the VS menu) -> LEAVE_SELECT: the other
##   machine leaves too (force_leave).
## - stage: STAGE_CURSOR {icon, chosen} on change; the host decides the 50/50 when both chose (game thread) -> STAGE_RESULT
##   (teams, boss picks, stage id, seed, delay, save copy) -> both run the roulette -> FUN_02001014(7) -> the battle.
##   B with nothing chosen: host -> STAGE_BACK (both back to the team select); guest -> STAGE_BACK_REQ (the host answers
##   with STAGE_BACK unless it already decided).
## - force_leave (the other player left / went back to the room / the connection is lost): the scene's own B exits
##   (QoLGame presses them) -> the VS menu -> the room page (or the LAN page) with `notice`.
## Debug (inert without them): `lanpicks=a.b.c[@D]` (scene 4: these picks D frames (120) after the screen starts, then
## READY / GO), `lanstage=ICON[@D]` (scene 5: choose that icon after D (90) frames), `lanrounds=N` (after N team selects
## with picks: B with no picks = back to the room), `lanrejoin=N[@C]` (part 31: N frames after a session of this process
## ended - lanleave, the other left / lost, a failed connect (retried, not counted) - start the same `lan=` again; C (1)
## restarts), `lanquitat=WHAT[@N]` (part 31: quit like a window close N (30) frames after WHAT: lobby, select, ready,
## stage, chosen, roulette, intro, battle, pause, end), `lanleave=K` (leave the session the K-th time the room shows up:
## 1 = right after joining), `lanauto` (host: proposes every time the room shows up with a guest; guest: accepts).
var sel_round := 0                       ## scene-4 entries since the last room entry (both machines count alike)
var rounds_done := 0                     ## team selects finished with GO in this session (debug lanrounds)
var force_leave := false                 ## leave the select / stage for the room (QoLGame presses the screens' B)
var notice := {}                         ## {"title", "lines", "then"}: shown when the LAN pages open again
var press_b := false                     ## game thread -> sel_filter: one B press for the scene's own loop
var last_peer := ""                      ## the other player's name after it left (bands / notices)
var in_flow := false                     ## ACCEPTed: the select / stage / battle flow runs until the VS menu shows again
var _b_was := false
## select (game thread writes loc_*, main thread rem_* / go_round)
var loc_ready := false
var loc_team: Array = []                 ## this machine's team at GO (ids, fighters first, FUN_02066558's rules)
var loc_boss: Array = []                 ## BOSS CHARACTERS: ids picked as bosses
var _ready_sent := -1                    ## round whose READY was sent
var rem_ready_round := -1
var rem_team: Array = []
var rem_boss: Array = []
var go_round := -1                       ## guest: SELECT_GO received for this round
var _go_pending := false                 ## host: GO decided on the game thread, sent after the frame
var _left_sel := false                   ## game thread: this machine left the team select with B (no picks)
## stage
var loc_icon := -1
var loc_chosen := -1
var _sent_cursor := [-2, -2, -1]
var rem_round := -1
var rem_icon := -1
var rem_chosen := -1
var stage_res: Dictionary = {}           ## guest: the host's STAGE_RESULT (round, icons, winner, stage, teams, …)
var stage_decided: Dictionary = {}       ## host: decided on the game thread (round, icons, winner, stage), sent after the frame
var stage_back := false                  ## both back to the team select (QoLGame presses the stage screen's B)
var back_req := false                    ## game thread: B with nothing chosen
var _scene := -1
var _scene_t := 0                        ## game frames in the current scene
var lobby_n := 0                         ## room entries in this session (debug lanleave)
var _leave_at := -1
var _picks_dbg: Array = []               ## lanpicks
var boss_dbg: Array = []                 ## lanpicks: indexes of the picks made as bosses
var picks_delay := 120
var stage_dbg := -1                      ## lanstage
var stage_delay := 90
var _rounds_dbg := -1
var _leave_dbg := -1
var _leave_dbg0 := -1
var _rejoin_dbg := -1                    ## part 31 debug lanrejoin=N[@C]: frames after a lanleave until the same `lan=` start
var _rejoin_n := 0                       ## rejoins left
var _rejoin_at := -1
var _rj_active := false
var _qa_what := ""                       ## part 31 debug lanquitat
var _oos_dbg := ""                       ## part 31 debug lanoos
var _qa_n := 30
var _qa_at := -1
var _point_last := ""
var prop_pending := false                ## guest: a proposal waits for ACCEPT / DENY
var _rj_lobby := false


func _sel_setup() -> void:
	if Game.args.has("lanpicks"):
		var v := Game.flag("lanpicks").split("@")
		for x in v[0].split(".", false):
			_picks_dbg.append(int(x))
			if x.ends_with("b"):                     # "1b": picked as a boss (BOSS CHARACTERS, as with L held)
				boss_dbg.append(_picks_dbg.size() - 1)
		if v.size() > 1:
			picks_delay = int(v[1])
	if Game.args.has("lanstage"):
		var v := Game.flag("lanstage").split("@")
		stage_dbg = int(v[0])
		if v.size() > 1:
			stage_delay = int(v[1])
	_rounds_dbg = int(Game.flag("lanrounds", "-1"))
	_leave_dbg = int(Game.flag("lanleave", "-1"))
	_leave_dbg0 = _leave_dbg
	_oos_dbg = Game.flag("lanoos", "")               # part 31: lanoos=room|noresult|silent[@N] (forced divergences)
	if Game.args.has("lanquitat"):                   # part 31: lanquitat=WHAT[@N]: quit like a window close
		var v := Game.flag("lanquitat").split("@")
		_qa_what = v[0]
		_qa_n = int(v[1]) if v.size() > 1 else 30
	if Game.args.has("lanrejoin"):                   # part 31: lanrejoin=N[@C]: N frames after a lanleave, start again
		var v := Game.flag("lanrejoin").split("@")
		_rejoin_dbg = maxi(1, int(v[0]))
		_rejoin_n = int(v[1]) if v.size() > 1 else 1


## 0 = the host (P1, red), 1 = the guest (P2, blue)
func me() -> int:
	return 0 if role == "host" else 1


## the select / stage flow runs (QoLGame's LAN select hooks act)
func sel_on() -> bool:
	return force_leave or ((state == SELECT or state == STAGE) and connected())


## debug lanpicks: the picks to make in this team select ([] = by hand; [-1] = B, back to the room)
func script_picks() -> Array:
	if _picks_dbg.is_empty():
		return []
	if _rounds_dbg >= 0 and rounds_done >= _rounds_dbg:
		return [-1]
	return _picks_dbg


func _sel_reset_session() -> void:
	rounds_done = 0
	lobby_n = 1
	_leave_at = -1
	flow = 0                                         # part 31: flows (proposals) count from 1 in each session
	_flow_n = 0
	_prop_flow = 0
	prop_pending = false
	force_leave = false
	press_b = false
	_reset_flow(true)


func _sel_reset_round() -> void:
	loc_ready = false
	loc_team = []
	loc_boss = []
	_ready_sent = -1
	_go_pending = false
	loc_icon = -1
	loc_chosen = -1
	_sent_cursor = [-2, -2, -1]
	stage_decided = {}
	stage_back = false
	back_req = false
	_left_sel = false


## game thread (QoLGame, team select GO): this machine is ready with `team` / `boss`
func local_ready(team: Array, boss: Array) -> void:
	loc_team = team
	loc_boss = boss
	loc_ready = true


func local_unready() -> void:
	loc_ready = false


## game thread, every frame while ready: may this machine leave for the stage select? (host: the guest is ready too ->
## SELECT_GO goes out after the frame; guest: the host's GO arrived)
func sel_go() -> bool:
	if role == "host":
		if loc_ready and rem_ready_round == sel_round:
			_go_pending = true
			return true
		return false
	return go_round == sel_round


func remote_ready() -> bool:
	return rem_ready_round == sel_round


## game thread: the B exit of the team select (no picks): the room, the other player follows
func left_select() -> void:
	_left_sel = true


## the remote stage cursor of this round ([icon, chosen]; [-1, -1] = none yet)
func remote_cursor() -> Array:
	return [rem_icon, rem_chosen] if rem_round == sel_round else [-1, -1]


func stage_result() -> Dictionary:
	return stage_res if battle_fresh(stage_res) else {}   # part 31: this session, flow and round only


## main thread, before each frame (QoLController.filter_input) while the select / stage flow runs: the DS input of the
## team select (as typed; soft reset masked; port B presses), the stage select (blank: the local player's buttons / new
## tap go to QoLMp index me() for QoLGame's two-outline code)
func sel_filter(keys: int, ext: int, touch: Vector2i, new_touch: bool) -> Array:
	var c = qol.machine.core
	var sc: int = c.r8(SCENE)
	var w := (~keys & 0x3FF) | (~ext & 0xC00)
	if (w & SOFT_RESET) == SOFT_RESET:
		w &= ~START                                  # no soft reset during a session
	var mp: QoLMp = qol.mp
	if sc != 4 and sc != 5:
		w = 0                                        # (the way into the battle / out to the room: nothing to press)
		touch = Vector2i(-1, -1)
	if sc == 5:
		var p := me()
		mp.pressed[p] = w & ~int(mp.held[p])
		mp.released[p] = int(mp.held[p]) & ~w
		mp.held[p] = w
		mp.sel_tap[p] = touch if new_touch else Vector2i(-1, -1)
		mp.pressed[1 - p] = 0
		mp.released[1 - p] = 0
		mp.held[1 - p] = 0
		mp.sel_tap[1 - p] = Vector2i(-1, -1)
		w = 0
		touch = Vector2i(-1, -1)
	if press_b and not _b_was:                       # one B press (released the next frame)
		press_b = false
		_b_was = true
		w = (w & ~START) | 0x002
		touch = Vector2i(-1, -1)
	else:
		_b_was = false
		if force_leave:
			w = 0
			touch = Vector2i(-1, -1)
	return [0x3FF & ~(w & 0x3FF), 0x2C00 & ~(w & 0xC00), touch]


## after every game frame (main thread): scene changes, messages for what the game thread decided, debug flags
func _sel_step(core) -> void:
	var sc: int = core.r8(SCENE)
	_scene_t += 1
	if _left_sel:                                    # (before the scene change below makes it a room again)
		_left_sel = false
		if connected():
			_send_msg({"t": "LEAVE_SELECT", "round": sel_round})
			_log("LEAVE_SELECT sent")
	if sc != _scene:
		var prev := _scene
		_scene = sc
		_scene_t = 0
		_on_scene(prev, sc)
	if not connected():
		return
	if _oos_dbg == "room" and sc == 4 and _scene_t == 200 and not force_leave:
		_oos_dbg = ""
		print("LAN f%d lanoos room: leaving the team select WITHOUT telling the other machine" % qol.game.frames)
		force_leave = true
	if state == SELECT or state == STAGE:
		if loc_ready and _ready_sent != sel_round:
			_ready_sent = sel_round
			_send_msg({"t": "SELECT_READY", "round": sel_round, "team": loc_team, "boss": loc_boss})
			_log("SELECT_READY sent: round %d team %s boss %s" % [sel_round, loc_team, loc_boss])
		elif not loc_ready and _ready_sent == sel_round and sc == 4:
			_ready_sent = -1
			_send_msg({"t": "SELECT_UNREADY", "round": sel_round})
			_log("SELECT_UNREADY sent: round %d" % sel_round)
		if _go_pending:
			_go_pending = false
			_send_msg({"t": "SELECT_GO", "round": sel_round})
			_log("SELECT_GO sent: round %d" % sel_round)
		if sc == 5:
			var cur := [loc_icon, loc_chosen, sel_round]
			if loc_icon >= 0 and cur != _sent_cursor:
				_sent_cursor = cur
				_send_msg({"t": "STAGE_CURSOR", "round": sel_round, "icon": loc_icon, "chosen": loc_chosen})
			if back_req:
				back_req = false
				if role == "host":
					_send_msg({"t": "STAGE_BACK", "round": sel_round})
					stage_back = true
				else:
					_send_msg({"t": "STAGE_BACK_REQ", "round": sel_round})
				_log("stage B with nothing chosen (%s)" % role)
			if role == "host" and not stage_decided.is_empty():
				var d := stage_decided
				stage_decided = {}
				var info := d.duplicate()
				info["teams"] = [loc_team, rem_team]
				info["boss"] = [loc_boss, rem_boss]
				send_stage_result(info)
	if state == LOBBY and sc == 0x11 and core.r8(SCENE + 1) == 2:
		if _leave_dbg > 0 and lobby_n >= _leave_dbg:
			if _leave_at < 0:
				_leave_at = 10
			_leave_at -= 1
			if _leave_at == 0:
				print("LAN lanleave: leaving the room (room entry %d)" % lobby_n)
				_leave_dbg = -1
				leave()
				return
		elif _auto and role == "host" and not _proposed and not debug_battle and _scene_t > 30:
			propose_select()


func _on_scene(prev: int, sc: int) -> void:
	_log("scene %x -> %x (state %s, round %d)" % [prev, sc, state_name(), sel_round])
	if (sc == 4 or sc == 5) and in_flow and not connected() and not force_leave:
		force_leave = true                           # the other player went away before this machine got here
		if notice.is_empty():
			notice = {"title": "CONNECTION LOST", "lines": ["THE OTHER PLAYER IS GONE."], "then": "lobby" if role == "host" else "lan"}
	match sc:
		4:
			if connected():
				if state != SELECT:
					state = SELECT
				sel_round += 1
				_sel_reset_round()
				if qol != null and qol.mp != null:
					qol.mp.clear_inputs()
		5:
			if connected() and (state == SELECT or state == STAGE):
				state = STAGE
				loc_ready = false
				_ready_sent = -1
				rounds_done += 1
		0x11:
			force_leave = false
			press_b = false
			in_flow = false
			if prev == 4 or prev == 5 or prev == 0:
				if connected():
					state = LOBBY
					_proposed = false
					lobby_n += 1
				_reset_flow()                        # part 31: nothing of this flow survives into the next one
				battle_pending = false
				_pending_info = {}


func _on_sel_msg(t: String, m: Dictionary) -> void:
	var r := int(m.get("round", -1))
	_log("msg %s round %d (mine %d)" % [t, r, sel_round])
	match t:
		"SELECT_READY":
			rem_ready_round = r
			rem_team = m.get("team", []) if m.get("team") is Array else []
			rem_boss = m.get("boss", []) if m.get("boss") is Array else []
		"SELECT_UNREADY":
			if r == rem_ready_round:
				rem_ready_round = -1
		"SELECT_GO":
			go_round = r
		"LEAVE_SELECT":
			if _scene == 4 or _scene == 5:
				force_leave = true
				notice = {"title": "BACK TO THE ROOM", "lines": ["%s WENT BACK TO THE ROOM." % peer_name], "then": "lobby"}
		"STAGE_CURSOR":
			rem_round = r
			rem_icon = int(m.get("icon", -1))
			rem_chosen = int(m.get("chosen", -1))
		"STAGE_BACK":
			if _scene == 5 and r == sel_round:
				stage_back = true
		"STAGE_BACK_REQ":
			if role == "host" and _scene == 5 and r == sel_round and battle_info.get("round", -1) != sel_round \
				and stage_decided.is_empty():
				_send_msg({"t": "STAGE_BACK", "round": sel_round})
				stage_back = true


## the other player is gone while this machine is in a select / stage / battle: the notice for the room page
func _away_notice(kind: String) -> bool:
	if not (_scene == 4 or _scene == 5 or in_battle or state == BATTLE or in_flow or not notice.is_empty()):
		return false                                 # (part 31: + on the way in / out; a notice not shown yet is replaced)
	var who := peer_name if peer_name != "" else ("THE GUEST" if role == "host" else "THE HOST")
	if kind == "lost":
		notice = {"title": "CONNECTION LOST", "lines": ["NO ANSWER FROM %s." % who], "then": "lobby" if role == "host" else "lan"}
	else:
		notice = {"title": "%s LEFT" % who, "lines": ["THE ROOM IS OPEN AGAIN." if role == "host" else "THE ROOM WAS CLOSED."],
			"then": "lobby" if role == "host" else "lan"}
	return true


# ---- LAN SESSION RESET / WATCHDOG (part 31) --------------------------------------------------------------------------
## DATA_NOTES "Session 1 part 31 findings (LAN rejoin / disconnects)". The rejoin bug: the select / stage state of a
## session (stage_res, go_round, rem_ready_round, rem_team, the remote stage cursor) survived the session's end, and the
## next session's rounds count from 1 again, so a rejoined guest took the OLD session's SELECT_GO (left the team select
## alone) and its STAGE_RESULT of round 1 (roulette at once, then a battle with no session info = a plain, broken Free
## Battle) while the host waited in the stage select for ever; the host likewise took the old guest's READY / cursor.
## Now: (1) session id (random per connection, host -> WELCOME) + flow id (one per proposal, PROPOSE / ACCEPT) on every
## message; select / stage / battle messages of another session or flow are dropped ("STALE"); (2) all of that state is
## reset at the session start / end, at ACCEPT and when the room shows again (_reset_flow); (3) a battle starts only on a
## STAGE_RESULT of this session, flow and round (battle_fresh; a copy is taken at the 5 -> 7 redirect) and with the
## host's battle id from it (a battle only one machine started no longer breaks the ids of every later one); (4) WHERE
## {flow, step} once a second and on change: steps 3r / 3r+1 / 3r+2 = team select / stage select / battle of round r; a
## machine whose partner is in another flow or the room or two steps away for 5 s (one step: 30 s), or a lockstep stall
## of 20 s, sends BACK_TO_ROOM and goes back to the room with a notice — both always end up in the room together.
const FLOW_MSGS := ["SELECT_READY", "SELECT_UNREADY", "SELECT_GO", "LEAVE_SELECT", "STAGE_CURSOR", "STAGE_BACK",
	"STAGE_BACK_REQ", "STAGE_RESULT", "BACK_TO_ROOM"]
const OOS_FAR_MS := 5000                 ## the other machine in another flow / the room / two steps away
const OOS_NEAR_MS := 30000               ## one step apart (a transition that never finished)
const STALL_ABORT_MS := 20000            ## a lockstep stall this long with the peer still answering pings
const WHERE_MS := 1000
var session_id := 0                      ## this connection's id (host: random at HELLO; guest: from WELCOME); 0 = none
var flow := 0                            ## the select / stage / battle flow (proposal) both machines are in
var _flow_n := 0                         ## host: proposals made in this session
var _prop_flow := 0                      ## guest: the flow id of the last proposal
var start_info: Dictionary = {}          ## the STAGE_RESULT the running battle started on
var _pending_info: Dictionary = {}       ## copy taken at the 5 -> 7 redirect (consumed by wants_battle)
var _start_abort := ""
var _result_n := 0                       ## host: STAGE_RESULTs sent in this session (= battle ids)
var _room_req := ""
var rem_where: Dictionary = {}           ## the other machine's last WHERE {flow, p, battle}
var _where_p := -1                       ## this machine's step (-1 = not in a flow)
var _where_sent: Array = []
var _t_where := 0
var _oos_t0 := 0
var _oos_info := ""


## everything of the current flow (select rounds, ready / GO, the remote's team, cursor, STAGE_RESULT, WHERE)
func _reset_flow(all := false) -> void:
	sel_round = 0
	_sel_reset_round()
	rem_ready_round = -1
	rem_team = []
	rem_boss = []
	go_round = -1
	rem_round = -1
	rem_icon = -1
	rem_chosen = -1
	stage_res = {}
	if all or not debug_battle:
		battle_info = {}
	rem_where = {}
	_where_p = -1
	_where_sent = []
	_oos_t0 = 0


## this machine's step in the flow: 3r team select, 3r + 1 stage select, 3r + 2 battle (r = sel_round), -1 = no flow
func _update_where() -> void:
	var p := -1
	if in_flow:
		if in_battle or lockstep or aborting or _scene == 0:
			p = 3 * sel_round + 2
		elif _scene == 5:
			p = 3 * sel_round + 1
		elif _scene == 4:
			p = 3 * sel_round
		else:
			p = maxi(_where_p, 0)                    # (between scenes: the last step)
	_where_p = p


func _where_tick(now: int) -> void:
	_update_where()
	var key := [flow, _where_p, battle_no]
	if key != _where_sent or now - _t_where >= WHERE_MS:
		_where_sent = key
		_t_where = now
		_send_msg({"t": "WHERE", "p": _where_p, "battle": battle_no})
	if not in_flow or force_leave or aborting or stage_back or rem_where.is_empty():
		_oos_t0 = 0
		return
	var rf: int = rem_where["flow"]
	var rp: int = rem_where["p"]
	var lim := 0
	if rf != flow or rp < 0 or absi(rp - _where_p) >= 2:
		lim = OOS_FAR_MS
	elif rp != _where_p:
		lim = OOS_NEAR_MS
	if lim == 0:
		_oos_t0 = 0
		return
	if _oos_t0 == 0:
		_oos_t0 = now
		_oos_info = "this machine flow %d step %d, the other flow %d step %d" % [flow, _where_p, rf, rp]
		_log("steps differ: %s" % _oos_info)
	elif now - _oos_t0 > lim * _wd_scale():
		print("LAN OUT OF STEP for %d ms: %s" % [now - _oos_t0, _oos_info])
		_oos_t0 = 0
		_room_both("OUT OF STEP")


## the watchdog limits' factor: x4 in capture runs (slow); part 32 debug `lanwd=K` (test runs whose other side is a slow
## capture run)
func _wd_scale() -> int:
	return int(Game.flag("lanwd", "4" if Game.args.has("capture") else "1"))


## both machines back to the room: tell the other (it does the same on BACK_TO_ROOM), then this one
func _room_both(why: String) -> void:
	if connected():
		_send_msg({"t": "BACK_TO_ROOM", "reason": why, "battle": battle_no})
	_go_room(why)


## this machine back to the room (the select / stage: the screens' own B exits; a battle: the abort path) + notice
func _go_room(why: String, remote := false) -> void:
	if not in_flow and not in_battle:
		return
	print("LAN f%d back to the room: %s (scene %x, step %d, battle %s)" % [qol.game.frames if qol != null else -1, why,
		_scene, _where_p, in_battle])
	var who := peer_name if peer_name != "" else ("THE GUEST" if role == "host" else "THE HOST")
	if why == "NO INPUT":
		notice = {"title": "BATTLE STOPPED", "lines": [("%s GOT NO INPUT" if remote else "NO INPUT ARRIVED FROM %s") % who,
			"FOR 20 SECONDS. BACK IN THE ROOM."], "then": "lobby"}
	elif why != "DESYNC":
		notice = {"title": "OUT OF STEP", "lines": ["THE TWO GAMES WERE IN DIFFERENT", "PLACES. BOTH ARE BACK IN THE ROOM."],
			"then": "lobby"}
	if in_battle:
		if not aborting:
			_abort(why)
	else:
		force_leave = true


## part 31 debug: where this machine is in the flow ("POINT <name>" lines under landbg; lanquitat=WHAT[@N])
func _point(core) -> String:
	var sc: int = core.r8(SCENE)
	if state == CONNECTING:
		return "connecting"
	if lockstep or aborting:
		var st: int = core.r8(SCENE + 1)
		if aborting:
			return "aborting"
		if st == 9:
			return "pause"
		if st >= 0x0F:
			return "end"
		if _cur_L < 300:
			return "intro"
		return "battle"
	if sc == 4 and sel_on():
		return "ready" if loc_ready else "select"
	if sc == 5 and sel_on():
		if qol != null and qol.mp != null and int(qol.mp.cand) >= 0:
			return "roulette"
		return "chosen" if loc_chosen >= 0 else "stage"
	if sc == 0x11 and state == LOBBY:
		if (role == "guest" and prop_pending) or (role == "host" and _proposed):
			return "proposal"
		return "lobby"
	if sc == 0x11 and state == HOSTING:
		return "room"
	return ""


func _point_tick(core) -> void:
	var pt := _point(core)
	if pt != _point_last:
		_point_last = pt
		if pt != "":
			print("LAN f%d POINT %s (%s, flow %d round %d)" % [qol.game.frames, pt, role, flow, sel_round])
		if _qa_what != "" and pt == _qa_what and _qa_at < 0:
			_qa_at = _qa_n
	if _qa_at >= 0:
		_qa_at -= 1
		if _qa_at == 0:
			print("LAN f%d lanquitat %s: closing the game (window close path)" % [qol.game.frames, _qa_what])
			_qa_what = ""
			qol.game.get_tree().quit()
