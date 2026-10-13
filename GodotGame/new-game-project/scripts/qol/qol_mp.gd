class_name QoLMp
extends RefCounted
# ---- MULTIPLAYER (part 27)
## LOCAL MULTIPLAYER session state (docs/MULTIPLAYER_DESIGN.md 3.1). One instance lives in QoLController (`mp`) and
## is shared with QoLGame (`QoLGame.mp`); it is only "in use" while `active` (a LOCAL session is running), so with
## MULTIPLAYER off or outside a session every QoLGame override just calls super.
## Hand-off: the main thread writes the per-player input fields in GameDS._tick_begin (before the game frame), the
## game thread reads them inside the overrides — the same pattern as machine.keyinput.

enum { NONE, SETUP, SELECT, STAGE, BATTLE }

## DS button bits (KEYINPUT layout, 1 = pressed here)
const A := 0x001
const B := 0x002
const SELECT_BTN := 0x004
const START := 0x008
const RIGHT := 0x010
const LEFT := 0x020
const UP := 0x040
const DOWN := 0x080
const R := 0x100
const L := 0x200
const X := 0x400
const Y := 0x800

var active := false                 ## a LOCAL session is running (setup page opened from the VS menu until it ends)
var stage := NONE                   ## SETUP, SELECT, STAGE, BATTLE
var go := false                     ## setup page: YES on "READY TO CONTINUE?" (the VS menu override leaves the scene)
var dev := [-1, 0]                  ## input device per player: -1 keyboard, 0..n joypad index
## per player, DS layout words of this game frame (main thread → game thread)
var held := [0, 0]
var pressed := [0, 0]
var released := [0, 0]
## per player battle touch on its own panel half, in DS panel coordinates ((-1, -1) = none) and edge flags
var touch := [Vector2i(-1, -1), Vector2i(-1, -1)]
var tflags := [0, 0]
## character select (3.5)
var cur := [0, 0]
var tab := 0
var ready := [false, false]
## stage select (3.6)
var icon := [0, 0]
var chosen := [-1, -1]
## one-frame DS key injections requested by the overrides (e.g. B to leave a screen)
var inject := 0
## extra object draws for the two-outline trick: object -> [[o, x, y, colour], …] (3.5 / 3.6)
var dup := {}
var rng := RandomNumberGenerator.new()
## ---- MP input / menu (part 27, phases 3-4: QoLMpInput / QoLMpMenu / QoLController.mp_frame)
## raw touch sources of this game frame, lower-screen pixels ((-1, -1) = none): `mtouch` mouse or scripted `inputs=`
## tap, `ptouch` scripted `p2inputs=` tap, `ctouch[p]` player p's gamepad cursor click
var mtouch := Vector2i(-1, -1)
var ptouch := Vector2i(-1, -1)
var ctouch := [Vector2i(-1, -1), Vector2i(-1, -1)]
## stages whose DS pad input is blank (the port drives the screen itself: the setup page, QoLGame
## `# ---- MULTIPLAYER SELECT` for the character / stage select)
var port_stages := [SETUP, SELECT, STAGE]
## (BATTLE touch routing: QoLController.mp_frame calls QoLMpPanel.route(mp) after the sources above are filled)
## scene 3 left with B and nothing picked: the VS menu (scene 0x11) reopens the controller setup page
var reopen_setup := false
## VS menu choice seen on the game thread (QoLGame.f_0207b778), acted on by QoLController.after_step: 1 LOCAL, 2 LAN
var menu_req := 0
## ---- MP battle (part 27, phases 1-2: QoLGame `# ---- MULTIPLAYER BATTLE`, QoLMpPanel)
## per player: buttons pressed since the game last read that player's input (main thread ORs `pressed` in, the
## game-thread input call consumes it), so a press during a frame without an input call (hit stop) is not lost
var latch := [0, 0]
## per player: the last NEW touch (panel coordinates) not yet seen by the game's input call ((-1, -1) = none)
var tap := [Vector2i(-1, -1), Vector2i(-1, -1)]
var debug_battle := false           ## the session was started by the debug flag `mpbattle=1` (a plain Free Battle)
## ---- MP select / stage (part 27, phases 5-7: QoLGame `# ---- MULTIPLAYER SELECT`, QoLMpSelect)
## per player: where a NEW touch began this game frame (lower-screen pixels; mouse / scripted taps belong to
## `mouse_p` = the keyboard player, a gamepad cursor to its player, `p2inputs=` taps to PLAYER 2) or (-1, -1)
var sel_tap := [Vector2i(-1, -1), Vector2i(-1, -1)]
var mouse_p := 0
var winner := -1                    ## stage select: the icon the 50/50 chose (-1 = not yet)
var cand := -1                      ## stage select: the roulette's current icon (-1 = no roulette)
## ---- LAN (part 30): a LAN battle uses the MP battle rules (P2 = the other machine's player through f_0202dce0) without
## a LOCAL session: `lan` true, `active` false (no local devices / cursors / select overrides), stage BATTLE; the fields
## held / pressed / latch / touch / tap of both players are written by QoLLan from the exchanged input records
var lan := false


func start() -> void:
	active = true
	stage = SETUP
	go = false
	clear_inputs()
	ready = [false, false]
	chosen = [-1, -1]
	winner = -1
	cand = -1
	inject = 0
	dup = {}
	rng.seed = int(Game.flag("mpseed", str(Time.get_ticks_usec())))


func stop() -> void:
	active = false
	stage = NONE
	go = false
	clear_inputs()
	dup = {}
	inject = 0


func clear_inputs() -> void:
	held = [0, 0]
	pressed = [0, 0]
	released = [0, 0]
	touch = [Vector2i(-1, -1), Vector2i(-1, -1)]
	tflags = [0, 0]
	latch = [0, 0]
	tap = [Vector2i(-1, -1), Vector2i(-1, -1)]
	sel_tap = [Vector2i(-1, -1), Vector2i(-1, -1)]


func in_battle() -> bool:
	return (active or lan) and stage == BATTLE
