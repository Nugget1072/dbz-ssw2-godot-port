class_name QoLLanNet
extends RefCounted
# ---- LAN NET (part 30)
## LAN MULTIPLAYER transport (docs/LAN_DESIGN.md 5.1): one ENetConnection, used directly (no MultiplayerAPI).
## Channels: 0 = session messages (FLAG_RELIABLE), 1 = lockstep input packets (FLAG_UNSEQUENCED, redundant records),
## 2 = ping / pong (unreliable). Host: create_host_bound("*", port, 2 peers, 3 channels) — the second peer slot only
## exists so a third machine gets a "FULL" reject instead of a silent timeout; guest: create_host(1, 3) +
## connect_to_host(ip, port, 3). Port 8082 UDP by default; when the bind fails 8083..8091 are tried (`port` = the port
## actually bound). QoLLan (main thread) takes the received events with service() once per Godot frame and before every
## game frame of a lockstep battle; since phase 4 the connection itself is serviced by the network thread below.
## Part 30 phase 4 (QA): a small network thread services the connection every ~1 ms (all ENet calls of both threads under
## one mutex; received events are queued for the main thread's service()), every send is flushed at once, and pings are
## answered / timed (µs) in that thread — so PING is the real round trip, not the two machines' frame times (it read
## 25-60 ms on localhost in real time and ~500 ms in capture runs before). Debug `lanthread=0`: the old single-thread way.
## Test impairment (debug flags, per process, applied to this side's OUTGOING packets): `lanlag=MS` delay,
## `lanjitter=MS` ± random extra delay, `lanloss=PCT` drop (channels 1 / 2 only: ENet retransmits reliable packets,
## so a "lost" reliable packet would only be late). Reliable packets keep their order (never sent before an earlier one).

const DEFAULT_PORT := 8082
const PORT_TRIES := 10                   ## 8082 .. 8091
const CH_SESSION := 0
const CH_INPUT := 1
const CH_PING := 2
const CHANNELS := 3

var con: ENetConnection = null
var peer: ENetPacketPeer = null          ## the session's peer (guest: the host; host: the guest that sent HELLO)
var is_host := false
var port := 0
var lag_ms := 0
var jitter_ms := 0
var loss_pct := 0.0
var _rng := RandomNumberGenerator.new()
var _queue: Array = []                   ## impairment: [due ms, peer, channel, bytes, flags] sorted by due
var _last_due := [0, 0, 0]               ## per channel: due time of the last queued packet (reliable order)
var sent := 0                            ## statistics (debug): packets sent / dropped by the impairment
var dropped := 0
## phase 4: network thread (see the header)
const PKT_PING := 2                      ## channel 2: [2, u64 send time µs] -> answered with [3, the same time]
const PKT_PONG := 3
var threaded := true
var _mutex := Mutex.new()                ## (reentrant) every ENet call + _queue / _inbox / _closing
var _thread: Thread = null
var _run := false
var _idle_since := 0
var _inbox: Array = []                   ## events received by the thread, taken by service()
var loops := 0                           ## part 32 debug (lanpace): network-thread passes


func _init() -> void:
	lag_ms = int(Game.flag("lanlag", "0"))
	jitter_ms = int(Game.flag("lanjitter", "0"))
	loss_pct = float(Game.flag("lanloss", "0"))
	_rng.seed = int(Game.flag("lanimpseed", str(Time.get_ticks_usec())))
	threaded = Game.flag("lanthread", "1") != "0"


## start hosting: binds `want` (else the next free port of 8083..8091 when `want` is the default); OK or the error
func host(want: int = DEFAULT_PORT) -> int:
	close()
	_mutex.lock()
	is_host = true
	var err := ERR_CANT_CREATE
	var tries := PORT_TRIES if want == DEFAULT_PORT else 1
	for i in tries:
		var c := ENetConnection.new()
		err = c.create_host_bound("*", want + i, 2, CHANNELS)
		if err == OK:
			port = want + i
			con = c
			break
	_mutex.unlock()
	if err == OK:
		_start_thread()
	return err


## start joining ip:port (the connection itself is reported by service() as "connect" or "disconnect")
func join(ip: String, p: int = DEFAULT_PORT) -> int:
	close()
	_mutex.lock()
	is_host = false
	var c := ENetConnection.new()
	var err := c.create_host(1, CHANNELS)
	if err == OK:
		peer = c.connect_to_host(ip, p, CHANNELS)
		if peer == null:
			c.destroy()
			err = ERR_CANT_CONNECT
		else:
			c.flush()
			con = c
			port = p
	_mutex.unlock()
	if err == OK:
		_start_thread()
	return err


func active() -> bool:
	return con != null


## network events since the last call: [{"type": "connect"|"receive"|"disconnect", "peer": ENetPacketPeer,
## "ch": int, "data": PackedByteArray}]. Also sends impairment-delayed packets that are due.
## Pings are answered here and pongs come out as {"type": "rtt", "peer", "us": round trip in µs}.
func service() -> Array:
	_mutex.lock()
	if not threaded or _thread == null:
		_service_locked()
	var out := _inbox
	_inbox = []
	_mutex.unlock()
	return out


## (mutex held) one ENet service pass: due impairment packets out, events into _inbox
func _service_locked() -> void:
	if con == null:
		return
	_flush_queue()
	for guard in 256:
		var ev: Array = con.service(0)
		var t: int = ev[0]
		if t == ENetConnection.EVENT_NONE or t == ENetConnection.EVENT_ERROR:
			break
		var p: ENetPacketPeer = ev[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				p.set_timeout(32, 5000, 10000)
				_inbox.append({"type": "connect", "peer": p})
			ENetConnection.EVENT_DISCONNECT:
				_inbox.append({"type": "disconnect", "peer": p})
			ENetConnection.EVENT_RECEIVE:
				var ch: int = ev[3]
				var d := p.get_packet()
				if ch == CH_PING and d.size() == 9 and d[0] == PKT_PING:
					var b := d.duplicate()               # answered at once (also for a peer the session ignores)
					b[0] = PKT_PONG
					_send_locked(CH_PING, b, p)
				elif ch == CH_PING and d.size() == 9 and d[0] == PKT_PONG:
					var rtt := Time.get_ticks_usec() - d.decode_s64(1)
					if rtt >= 0 and rtt < 60000000:
						_inbox.append({"type": "rtt", "peer": p, "us": rtt})
				else:
					_inbox.append({"type": "receive", "peer": p, "ch": ch, "data": d})
		if con == null:
			break


## a ping to the session peer (its pong comes back as an "rtt" event)
func send_ping() -> void:
	var b := PackedByteArray([PKT_PING, 0, 0, 0, 0, 0, 0, 0, 0])
	_mutex.lock()
	b.encode_s64(1, Time.get_ticks_usec())
	_send_locked(CH_PING, b, null)
	_mutex.unlock()


func _start_thread() -> void:
	if not threaded:
		return
	_mutex.lock()
	var running := _thread != null and _run
	_idle_since = 0
	_mutex.unlock()
	if running:
		return
	if _thread != null:                              # it ended itself (idle) or is ending: _run is false
		_thread.wait_to_finish()
	_run = true
	_thread = Thread.new()
	_thread.start(_loop)


## the network thread: services the connection (and a gracefully closing one) every ~1 ms; ends itself after 3 s with
## nothing open (joined by the next _start_thread / shutdown)
func _loop() -> void:
	while true:
		_mutex.lock()
		if not _run:
			_mutex.unlock()
			break
		_service_locked()
		_service_closing_locked()
		loops += 1
		var idle := con == null and _closing == null
		var now := Time.get_ticks_msec()
		if not idle:
			_idle_since = 0
		elif _idle_since == 0:
			_idle_since = now
		elif now - _idle_since > 3000:
			_run = false
		_mutex.unlock()
		OS.delay_usec(1000)


## quitting (QoLController._exit_tree): the peer is disconnected LATER (what was sent, e.g. a BYE, still arrives: the
## other machine reports "<NAME> LEFT", not a lost connection), waiting up to `wait_ms` for that; then the network
## thread is joined
func shutdown(wait_ms := 300) -> void:
	_mutex.lock()
	if con != null and peer != null and peer.is_active():
		close_graceful()
		_closing_until = mini(_closing_until, Time.get_ticks_msec() + wait_ms)
	else:
		close()
	_mutex.unlock()
	var t0 := Time.get_ticks_msec()
	while _closing != null and Time.get_ticks_msec() - t0 <= wait_ms + 50:
		if not threaded or _thread == null or not _thread.is_alive():
			service_closing()
		OS.delay_msec(2)
	_mutex.lock()
	_finish_closing()
	_run = false
	_mutex.unlock()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func send(ch: int, data: PackedByteArray, to: ENetPacketPeer = null) -> void:
	_mutex.lock()
	_send_locked(ch, data, to)
	_mutex.unlock()


## (mutex held) sent and flushed at once (phase 4: ENet otherwise sends only at the next service call)
func _send_locked(ch: int, data: PackedByteArray, to: ENetPacketPeer) -> void:
	var p := to if to != null else peer
	if con == null or p == null:
		return
	var flags := ENetPacketPeer.FLAG_RELIABLE if ch == CH_SESSION else (ENetPacketPeer.FLAG_UNSEQUENCED if ch == CH_INPUT else 0)
	if lag_ms <= 0 and jitter_ms <= 0 and loss_pct <= 0.0:
		if p.is_active():
			p.send(ch, data, flags)
			con.flush()
		sent += 1
		return
	if ch != CH_SESSION and loss_pct > 0.0 and _rng.randf() * 100.0 < loss_pct:
		dropped += 1
		return
	var due := Time.get_ticks_msec() + lag_ms + (_rng.randi_range(-jitter_ms, jitter_ms) if jitter_ms > 0 else 0)
	if ch == CH_SESSION:
		due = maxi(due, _last_due[ch])        # reliable messages stay in order
	_last_due[ch] = due
	var i := _queue.size()
	while i > 0 and _queue[i - 1][0] > due:
		i -= 1
	_queue.insert(i, [due, p, ch, data, flags])
	_flush_queue()


func _flush_queue() -> void:
	var now := Time.get_ticks_msec()
	var any := false
	while not _queue.is_empty() and _queue[0][0] <= now:
		var q: Array = _queue.pop_front()
		var p: ENetPacketPeer = q[1]
		if p != null and p.is_active():
			p.send(q[2], q[3], q[4])
			sent += 1
			any = true
	if any and con != null:
		con.flush()


## send what is queued now (before quitting)
func flush() -> void:
	_mutex.lock()
	if con != null:
		for q in _queue:
			var p: ENetPacketPeer = q[1]
			if p != null and p.is_active():
				p.send(q[2], q[3], q[4])
		_queue.clear()
		con.flush()
	_mutex.unlock()


## ENet's own round-trip time to the session peer (ms), -1 when not connected
func enet_rtt() -> int:
	_mutex.lock()
	var r := -1
	if peer != null and peer.is_active():
		r = int(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	_mutex.unlock()
	return r


func disconnect_peer(p: ENetPacketPeer, later := true) -> void:
	_mutex.lock()
	if p != null and p.is_active():
		if later:
			p.peer_disconnect_later()
		else:
			p.peer_disconnect()
		if con != null:
			con.flush()
	_mutex.unlock()


func close() -> void:
	_mutex.lock()
	_finish_closing()
	if con != null:
		flush()
		if peer != null and peer.is_active():
			peer.peer_disconnect_now()
		con.destroy()
	con = null
	peer = null
	_queue.clear()
	_inbox.clear()
	_last_due = [0, 0, 0]
	_mutex.unlock()


## part 30 phase 3: end the session but let the last reliable messages (BYE) arrive first. ENet drops the packets a
## peer still had queued for the application when its disconnect is processed in the same service call (the other
## machine saw "lost / DISCONNECTED" instead of the BYE), so the peer is asked to disconnect LATER (after everything
## sent was acknowledged) and the connection is serviced for up to 1.5 s by service_closing()
var _closing: ENetConnection = null
var _closing_until := 0


func close_graceful() -> void:
	_mutex.lock()
	_finish_closing()
	if con != null:
		flush()
		if peer != null and peer.is_active():
			peer.peer_disconnect_later()
			con.flush()
			_closing = con
			_closing_until = Time.get_ticks_msec() + 1500
		else:
			con.destroy()
	con = null
	peer = null
	_queue.clear()
	_inbox.clear()
	_last_due = [0, 0, 0]
	_mutex.unlock()
	if _closing != null:
		_start_thread()


func closing() -> bool:
	return _closing != null


## keeps a gracefully closing connection alive until its peer disconnected (or 1.5 s passed) (the network thread does
## this itself)
func service_closing() -> void:
	if threaded and _thread != null and _thread.is_alive():
		return
	_mutex.lock()
	_service_closing_locked()
	_mutex.unlock()


func _service_closing_locked() -> void:
	if _closing == null:
		return
	for guard in 64:
		var ev: Array = _closing.service(0)
		if ev[0] == ENetConnection.EVENT_NONE or ev[0] == ENetConnection.EVENT_ERROR:
			break
		if ev[0] == ENetConnection.EVENT_DISCONNECT:
			_closing_until = 0
			break
	if Time.get_ticks_msec() >= _closing_until:
		_finish_closing()


func _finish_closing() -> void:
	if _closing != null:
		_closing.destroy()
		_closing = null


## this machine's addresses for the HOST page: IPv4 private ranges first (10/8, 172.16/12, 192.168/16), then
## link-local 169.254/16; no loopback / IPv6; at most `n`
static func local_addresses(n: int = 3) -> PackedStringArray:
	var pri := PackedStringArray()
	var link := PackedStringArray()
	var other := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if not a.is_valid_ip_address() or ":" in a or a.begins_with("127."):
			continue
		var q := a.split(".")
		var b0 := int(q[0])
		var b1 := int(q[1])
		if b0 == 10 or (b0 == 172 and b1 >= 16 and b1 <= 31) or (b0 == 192 and b1 == 168):
			pri.append(a)
		elif b0 == 169 and b1 == 254:
			link.append(a)
		else:
			other.append(a)
	var all := pri + other + link
	return all.slice(0, n)


## "192.168.1.23" or "192.168.1.23:8082" -> [ip, port] ([] when not valid: 4 octets 0-255, port 1-65535)
static func parse_address(s: String) -> Array:
	var t := s.strip_edges()
	var p := DEFAULT_PORT
	if ":" in t:
		var q := t.split(":")
		if q.size() != 2 or not q[1].is_valid_int():
			return []
		p = int(q[1])
		t = q[0]
	var o := t.split(".")
	if o.size() != 4 or p < 1 or p > 65535:
		return []
	for x in o:
		if not x.is_valid_int() or int(x) < 0 or int(x) > 255:
			return []
	return [t, p]
