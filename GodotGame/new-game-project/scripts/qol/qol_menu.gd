class_name QoLMenu
extends Control
## The QoL settings menu on the bottom screen, styled after the game's own OPTION MODE screen: the Mode Select
## hexagon background (the game's BG1 layer, still scrolled by the game: QoLController hides the other layers),
## a black title plate, black rows with orange trim and bold italic labels, and orange hexagon buttons (current
## value in red, cursor = white hexagon). Every button works with the D-pad (Up/Down row, Left/Right button, A or
## Start = press, B = back, L / R = page) and with a tap (touch / mouse). Pages: "main" .. "main3" (settings,
## pages 1-3), "cheats".."cheats6" (pages 5-10, by theme: CHEAT_PAGES; part 42: "cheats6" POWERS = page 9 before "cheats5" CHALLENGES = page 10), "weird".."weird3" (pages 11-13, WEIRD_PAGES), "mpset" (page 4, MULTIPLAYER), "jukebox", "confirm" (window size), "controls1" + "controls2"
## (CONTROLS, part 16) + "controls3" (MOUSE CURSOR: the gamepad cursor of the touch screen, QoLCursor, part 24). Row 0 of every page but the jukebox is the header: page arrows + EXIT (controls: BACK).

const TRIM := Color8(190, 125, 28)          ## orange lines along the black bands (Option screen)
const HEX_EDGE := Color8(255, 166, 0)
const HEX_FILL := Color8(133, 101, 0)
const HEX_TEXT := Color8(255, 255, 255)
const HEX_RED := Color8(255, 36, 0)
const CURSOR := Color8(255, 247, 239)
const CONFIRM_SECONDS := 10
const ROW_Y := 31
const ROW_PITCH := 27
const HEX_H := 24
const PAGES := ["main", "main2", "main3", "mpset", "cheats", "cheats2", "cheats3", "cheats4", "cheats6", "cheats5", "weird", "weird2", "weird3"]   ## the pages the header's arrows flip through (settings, then cheats)
const CPAGES := ["controls1", "controls2", "controls3"]   ## CONTROLS: 7 rows per page (smaller rows than the other pages)
const CROW_Y := 37                         ## CONTROLS: first row (the KEY / PAD captions sit above it)
const CROW_PITCH := 22
const CHEX_H := 20
const VOLUMES := [0, 25, 50, 75, 100]
const ZOOM_LABELS := ["70", "85", "100", "115", "130"]   ## CAMERA ZOOM levels 0-4 (QoLGame ZOOM_K), 2 = original
## per DS button (QoLControls.BUTTONS order): what it does, for the upper screen (checked in battle, part 16)
const BUTTON_HELP := {
	"ds_a": "Fire a ki blast (costs ki).\nX+A: super attack (50% ki).\nR+A: special move.",
	"ds_b": "Guard against attacks.\nR+B: special ki attack.\nY+B: special move.",
	"ds_x": "Dash attack toward the enemy.\nX+A: super attack.",
	"ds_y": "Melee attack (punches and\nkicks); press again for a combo.",
	"ds_l": "Power up (e.g. Goku's Kaioken):\nstronger while the ki gauge\ndrains. (BOSS CHARACTERS cheat:\nhold it while picking.)",
	"ds_r": "Charge ki while held.\nR+A, R+B: special moves.",
	"ds_start": "Pause the battle.\nMenus: confirm.",
	"ds_select": "Not used in battle by the game.\nTIME SKIP cheat: skip time.\nALL-STAR: a heart (or tap it).",   # part 41 (part 42: shorter)
	"ds_up": "Fly up. Menus: cursor up.",
	"ds_down": "Fly down. Menus: cursor down.",
	"ds_left": "Fly left. Menus: cursor left.",
	"ds_right": "Fly right. Menus: cursor right.",
	# the gamepad cursor (CONTROLS page 3, part 24)
	"qol_cur_up": "Moves the gamepad cursor up\n(default: the right stick).\nIt only shows while a gamepad\nis connected.",
	"qol_cur_down": "Moves the gamepad cursor down\n(default: the right stick).\nIt only shows while a gamepad\nis connected.",
	"qol_cur_left": "Moves the gamepad cursor left\n(default: the right stick).\nIt only shows while a gamepad\nis connected.",
	"qol_cur_right": "Moves the gamepad cursor right\n(default: the right stick).\nIt only shows while a gamepad\nis connected.",
	"qol_cur_click": "Touches the lower screen where\nthe cursor points, as long as\nit is held (default: press\nthe right stick, R-STICK).",
}
## CONTROLS page 3 (part 24): the cursor's ON/OFF and SPEED rows
const CURSOR_ON_HELP := "ON: a mouse cursor on the touch\nscreen: right stick = move,\nright-stick press = touch. It\nonly shows while a gamepad is\nconnected. OFF: no cursor."
const CURSOR_SPEED_HELP := "How fast the cursor moves:\n1 slow ... 5 fast (5: default).\nTilt the stick a little for fine\nmoves, all the way for fast\nones; it speeds up a little."
## cheat pages by theme (part 19): page -> [plate title, rows [cheat, label, upper-screen description]]
const CHEAT_PAGES := {
	"cheats": ["FIGHTING", [
		["infinite_health", "INFINITE HEALTH", "Player 1's team takes no damage.\nHits still land, but the life\nbar never goes down."],
		["hard_mode", "HARD MODE", "Enemy attacks do double damage\nto player 1, and enemies have\ndouble health (they take half\ndamage)."],
		["one_hit_ko", "ONE-HIT KO", "Every hit from player 1 knocks\nout the enemy fighter it hits.\n(Guarded hits do normal damage.)"],
		["no_cooldown", "NO COOLDOWN", "Attacks can be used again at once:\nki blasts and super attacks start\neven while another attack is\nstill firing. (Player 1 only.)"],
		["attack_spam", "ATTACK SPAM", "Attacks restart at once and\nevery hit connects: spam heavy\nattacks, dash attacks, combos.\n(Supers and throws still play\nout in full.)"],
		["nondirectional", "NONDIRECTIONAL", "Hold a direction with X+A to\npick which super comes out,\nfrom any angle: UP / DOWN /\nsideways supers anywhere.\n(No direction: as normal.)"],   # part 42
	]],
	"cheats2": ["KI & ASSISTS", [
		["infinite_ki", "INFINITE KI", "Player 1's ki gauge stays full\n(200%): ki blasts and super\nattacks cost nothing."],
		["ki_homing", "KI HOMING", "Player 1's ki blasts curve\ntoward the enemy.\nBeam attacks are not affected."],
		["triple_ki", "TRIPLE KI BLASTS", "Every ki blast player 1 fires\nbecomes three shots in a fan.\nBeam attacks are not changed."],
		["ricochet_ki", "RICOCHET KI", "Player 1's ki blasts bounce off\nthe edges of the screen and off\nthe floor, up to 3 times, instead\nof flying away: missed shots\ncome back! (Beams don't.)"],   # part 40
		["infinite_assists", "INFINITE ASSISTS", "Player 1's support character\ncan be called again and again."],
		["assist_spam", "ASSIST SPAM", "Call your support character\nwhile one is still fighting:\nevery call brings one more\n(up to 8 at once). Touch the\nsupport's portrait to call."],
	]],
	"cheats3": ["CHARACTERS", [
		["same_characters", "SAME CHARACTERS", "Pick the same fighter more\nthan once (e.g. three Gokus).\nA team still takes one\nsupport and at least one\nfighter, who starts first."],
		["boss_characters", "BOSS CHARACTERS", "Hold L (A key) while picking a\ncharacter: you get its boss\nversion from Maximum / Z-Battle.\nA skull marks boss portraits.\nLIST shows the bosses."],
		["random_characters", "RANDOM CHARACTERS", "Every battle, player 1's team is\nreplaced by random characters\n(same size, always at least one\nfighter). Your picks are kept."],
		["character_shuffle", "CHARACTER SHUFFLE", "Every 10 seconds player 1's\nfighter turns into a random\ncharacter from the whole roster\n(not supports). HP stays the\nsame. Waits for a calm moment."],
		["chaos_shuffle", "CHAOS SHUFFLE", "Like CHARACTER SHUFFLE, but\nevery second and right away.\nSupers, throws and grabs are\nlet finish first. Your shots in\nflight vanish at each change."],
		["randomizer", "RANDOMIZER", "Every super attack (X+A) is\ndone by a random fighter: you\nturn into them for the super,\nthen back. Hit during it: back\nat once. HP stays the same."],   # part 39
	]],
	"cheats4": ["STAGE & MUSIC", [
		["random_stage", "RANDOM STAGE", "Every battle is fought on a\nrandom stage, with the music\nof that stage, whatever stage\nwas picked or set by the mode."],
		["stage_shuffle", "STAGE SHUFFLE", "Every 10 seconds the battle\nmoves to another random stage.\nThe fighters, their HP and the\nmusic keep going."],
		["random_music", "RANDOM MUSIC", "Every piece of music in the\ngame is swapped for another.\nSwitching it on again gives a\nnew mix. (Not the jukebox.)"],
	]],
	"cheats5": ["CHALLENGES", [   # part 36
		["green_demon", "GREEN DEMON", "A green 1-UP slowly chases\nyour fighter. If it touches\nyou, that fighter is KO'd at\nonce! Keep moving to escape.\n(Multiplayer: it hunts both.)"],
		["bomb_rain", "BOMB RAIN", "Little bombs rain down in\nbattle! A direct hit takes 1/4\nof max HP, a blast nearby less.\nWatch their shadows and dodge.\n(They hurt both teams.)"],   # part 38: was WEIRD STUFF 3
		["flightless", "FLIGHTLESS", "Nobody can fly! Fighters in\nthe air fall fast to the\nground; UP is a jump. Supers\nstill work in the air.\n(Both teams.)"],   # part 39 (part 40: higher jump)
		["smash_knockback", "SMASH KNOCKBACK", "Hurt fighters fly farther, like\nSmash Bros, even off the screen!\nOff screen they lose HP until\nthey come back (a marker shows\nwhere). (Both teams.)"],   # part 39 (part 40: off the camera)
		["hot_potato", "HOT POTATO", "A lit bomb lands on a fighter.\nHit the other team to pass it\non! When the countdown hits 0\nit explodes on whoever holds\nit (30% of max HP)."],   # part 40
		["dragon_balls", "DRAGON BALL HUNT", "The 7 Dragon Balls appear one\nby one: fly into them to grab\nthem. Getting hit drops one!\nAll 7: Shenron restores your\nHP and ki. (Both teams.)"],   # part 41
	]],
	"cheats6": ["POWERS", [   # part 41 (ULTRA INSTINCT moved here from FIGHTING)
		["ultra_instinct", "ULTRA INSTINCT", "Tap B just as a hit comes\n(5 frames!) to PARRY it: no\ndamage, the attacker is stunned\nand ki blasts fly back. A tap\nthat parries nothing: red flash."],   # part 39 (page 5 until part 41)
		["vampire", "VAMPIRE", "Every hit drains life: the\nattacker heals 40% of the\ndamage it deals (green sparks\nfly back to it). Both teams.\nLong fights, wild comebacks!"],   # part 41
		["z_vanish", "Z-VANISH", "Being hit? Press B (50% ki)\nto vanish and reappear behind\nthe attacker, free to strike\nback! Not while knocked down\nor grabbed. The CPU does it too."],   # part 42
		["time_skip", "TIME SKIP", "Press SELECT with 100% ki to\nskip time: the enemy freezes\nfor 2 seconds while you keep\nmoving and hitting. The CPU\ncan do it too! (Costs 100%.)"],   # part 41
		["body_change", "BODY CHANGE", "Ginyu's trick! Every 20 seconds\nthe two fighters swap their HP\n(as a share of max HP). A purple\ncountdown warns you: be ahead\nwhen it hits 0! (Both teams.)"],   # part 42
	]],
}
## WEIRD SETTINGS (part 21, page 7, after the cheats): [QoLSettings field, label, description]
## WEIRD STUFF (parts 21-22, pages 7-8 after the cheats): page -> [plate title, rows [QoLSettings field, label, text]]
const WEIRD_PAGES := {
	"weird": ["WEIRD STUFF 1", [
		["bevel_emboss", "BEVEL EMBOSS", "Every picture gets a bevel &\nemboss look (light top-left\nedges, shadowed bottom-right),\nlike the Photoshop effect.\nThe settings menu stays flat."],
		["touch_fuzzy", "TOUCH FUZZY", "Battles only: a slow rainbow\nshimmer over the screen and a\nwobbly floor and background,\nlike Yoshi's Island. Only the\nlooks change, not the fight."],
		["game_boy", "GAME BOY", "Everything in the 4 shades of\ngreen of the first Game Boy,\nmenus included."],
		["mirror_mode", "MIRROR MODE", "Battles are shown flipped left\nto right (the touch screen is\nnot); LEFT and RIGHT are\nswapped too, so it still plays\nnaturally."],
		["screen_shake", "SCREEN SHAKE", "The battle screen shakes when\na hit lands; the harder the\nhit, the bigger the shake (with\na limit). Only the looks\nchange."],
		["crt_tv", "CRT TV", "The picture looks like an old\nTV: soft scanlines (2X window\nor bigger), a little glow and\ndark rounded corners. The\nsettings menu stays sharp."],
	]],
	"weird2": ["WEIRD STUFF 2", [
		["blood", "BLOOD", "Drops of blood fly off a\nfighter that gets hit, more for\nharder hits (with a limit),\nfall to the ground and fade.\nOnly the looks change."],
		["afterimages", "AFTERIMAGES", "Fast moves (dashes, knock-\nbacks, teleports) leave fading\nblue afterimages behind the\nfighter, like in the anime."],
		["second_fiddle", "2ND FIDDLE", "Player 1 fights in the second\nplayer's colours; a player 2\nwith the same character gets\nthe normal colours. From the\nnext battle on."],
		["epic_mode", "EPIC MODE", "The game's text goes full\n2006 internet: lol, B), ROFL,\nover 9000! Story, menus, Data\nFile and credits (not the\nopening). Still makes sense!"],
		["flashy_ki", "FLASHY KI", "Bigger, brighter auras while\ncharging, and sparkly glowing\nki blasts and beams. Only the\nlooks change."],
		["ko_confetti", "KO CONFETTI", "A burst of colourful confetti\nwhen a fighter is knocked out.\nOnly the looks change."],
	]],
	"weird3": ["WEIRD STUFF 3", [
		["rainbow_ki", "RAINBOW KI", "Ki blasts and beams cycle\nthrough all the colours of the\nrainbow. Only the looks change."],
	]],
}
## BOSS CHARACTERS' LIST button: the bosses' names on the upper screen (three columns, "\t" between them)
const BOSS_LIST := "SSJ Goku\tCell\tBroly\nGohan\tSSJ Vegeta\tTrunks\nGotenks\tFrieza\tMajin Buu\nKid Buu\tCooler\tMajin Vegeta\nGoku\tVegeta\tMecha Frieza\nGinyu\tDr. Gero\tImperf. Cell"

var qol                                     ## QoLController (or the preview tool's stand-in)
var font: QoLFont
var page := "main"
var row := 0                                ## cursor: row and button on the current page
var col := 0
var _rows: Array = []                       ## [{label, desc, buttons: [{id, text, rect}]}] of the current page
var _prev_window := {}                      ## window size before a change (for UNDO)
var _confirm_left := 0.0
var _flash := {}                            ## button id -> seconds of "pressed" highlight
var _held_frames := {}
var _wait := {}                             ## CONTROLS: waiting for a new input {action, kind, frames}
var _wait_release := false                  ## after a mapping: menu input ignored until every button is released
var _notice := ""                           ## CONTROLS: one-line result shown on the upper screen
var _notice_lb := ""                        ## HI-SCORES: "reset" confirmation on the upper screen
var _notice_action := ""                    ## (only while the cursor is on that button's row)
const WAIT_FRAMES := 360                    ## 6 seconds to press the new input

signal focus_changed


func _init() -> void:
	position = Vector2(0, 192)
	size = Vector2(256, 192)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # taps arrive through the game's touch input (frame_input)
	visible = false


func open() -> void:
	page = "main"
	_notice_lb = ""
	_build()
	_focus_value(1)
	visible = true
	queue_redraw()
	focus_changed.emit()


func close() -> void:
	_wait = {}
	if page == "confirm":
		_undo_window()
	if qol.sound.jb_active:
		qol.on_game_thread(qol.sound.jb_stop)
	visible = false
	qol.settings.save_file()
	focus_changed.emit()


func _process(delta: float) -> void:
	if not visible or _flash.is_empty():
		return
	for k in _flash.keys():
		_flash[k] -= delta
		if _flash[k] <= 0.0:
			_flash.erase(k)
	queue_redraw()


# ------------------------------------------------------------------------------------------------ pages
func _build() -> void:
	_rows = []
	match page:
		"main", "main2", "main3", "mpset", "confirm", "lbconfirm", "cheats", "cheats2", "cheats3", "cheats4", "cheats5", "cheats6", "weird", "weird2", "weird3", "controls1", "controls2", "controls3":
			_rows.append({"label": "", "desc": "", "buttons": [
				{"id": "pg_prev", "text": "", "rect": Rect2(126, 4, 24, 20)},   # part 24 QA: 36 px between the arrows
				{"id": "pg_next", "text": "", "rect": Rect2(186, 4, 24, 20)},   # for the counter ("10/10" is 34 px)
				{"id": "cback" if page in CPAGES else "exit", "text": "BACK" if page in CPAGES else "EXIT", "rect": Rect2(211, 4, 41, 20)}]})
	match page:
		"weird", "weird2", "weird3":
			for w in WEIRD_PAGES[page][1]:
				_add_row(w[1], [["wset:%s:1" % w[0], "ON"], ["wset:%s:0" % w[0], "OFF"]], w[2])
			_layout_main()
		"cheats", "cheats2", "cheats3", "cheats4", "cheats5", "cheats6":
			for c in CHEAT_PAGES[page][1]:
				var bs := [["cheat:%s:1" % c[0], "ON"], ["cheat:%s:0" % c[0], "OFF"]]
				if c[0] == "boss_characters":
					bs.push_front(["bosslist", "LIST"])
				_add_row(c[1], bs, c[2])
			_layout_main()
		"main2", "lbconfirm":
			_add_row("CONTROLS", [["controls", "SET"]], "Keys and gamepad buttons for\nevery DS button, and the gamepad\nmouse cursor (CONTROLS page 3).\nDEFAULT (page 2 of CONTROLS)\ngives back the original keys.")
			var vol := []
			for v in VOLUMES:
				vol.append(["vol:%d" % v, str(v)])
			_add_row("VOLUME", vol, "Volume of everything (music and\nsound effects), in percent.\nMUSIC and SOUND FX on page 1\nturn each one on or off.")
			_add_row("AUTO PAUSE", [["apause:1", "ON"], ["apause:0", "OFF"]], "ON: the game pauses while its\nwindow is not in front (another\nwindow chosen or minimized)\nand goes on when you come back.")
			_add_row("DETAILED SHADOWS", [["shadows:1", "ON"], ["shadows:0", "OFF"]], "ON: the round shadows under the\nfighters become black shadows\nof the fighters themselves,\nin the same pose.\nOFF: the game's round shadows.")
			var zm := []
			for i in ZOOM_LABELS.size():
				zm.append(["zoom:%d" % i, ZOOM_LABELS[i]])
			_add_row("ZOOM", zm, "Battle camera distance in %:\n100.......the game's own camera\n70 85......see more of the stage\n115 130....closer, while the\nfighters are near each other.")
			_add_row("HI-SCORES", [["lbask", "RESET"]], "Z-Battle HI-SCORE RANKING back\nto the game's own list, ALL-STAR\nand ENDLESS records cleared\n(asks first). No scores with\ncheats on; weird stuff is fine.")
			_layout_main()
			if page == "lbconfirm":
				_rows.append({"label": "", "desc": "", "buttons": [
					{"id": "lbyes", "text": "YES", "rect": Rect2(66, 122, 54, HEX_H)},
					{"id": "lbno", "text": "NO", "rect": Rect2(136, 122, 54, HEX_H)}]})
		"main3":
			_add_row("AUTO SKIP", [["askip:1", "ON"], ["askip:0", "OFF"]], "ON: Story Mode dialogue and\nnarration scenes are skipped\nby themselves, and so are the\nblue VS screens before Z-Battle\nfights. OFF: like the original.")
			_add_row("DAMAGE NUMBERS", [["wset:damage_numbers:1", "ON"], ["wset:damage_numbers:0", "OFF"]], "The damage of every hit pops\nup as a number and floats away.\nBigger hits: bigger, hotter\nnumbers. Handy to compare\nmoves; the fight is the same.")
			_add_row("INPUT DISPLAY", [["wset:input_display:1", "ON"], ["wset:input_display:0", "OFF"]], "Battles: player 1's D-pad and\nbuttons are shown while held,\nwith the last few inputs, like\na training mode. Good for\nlearning supers and combos.")
			_layout_main()
		"mpset":
			_add_row("MULTIPLAYER", [["mpon:1", "ON"], ["mpon:0", "OFF"]], "ON: VS BATTLE on the Mode Select\nscreen opens LOCAL (two players\non this PC, keyboard / gamepads)\nand LAN (a friend's PC on your\nnetwork). OFF: as in the game.")
			_add_row("PERFORMANCE", [["perf:1", "ON"], ["perf:0", "OFF"]], "ON: for slow PCs / Steam Deck.\nThe picture is prepared while\nthe game runs on, no in-between\nframes. The game plays exactly\nthe same. OFF: as before.")
			_add_row("NEW GAMEMODES", [["newmodes:1", "ON"], ["newmodes:0", "OFF"]], "ON: the FREE BATTLE tile on the\nMode Select screen becomes\nGAMEMODE: the new modes\nALL-STAR and ENDLESS. OFF:\nFREE BATTLE as in the game.")
			_layout_main()
		"controls1", "controls2":
			var bl: Array = QoLControls.BUTTONS
			var idx := range(0, 7) if page == "controls1" else range(7, bl.size())
			for i in idx:
				var a: String = bl[i][0]
				var m: Dictionary = qol.controls.map[a]
				_rows.append({"label": bl[i][1], "func": bl[i][2], "action": a, "desc": "", "buttons": [
					{"id": "map:%s:key" % a, "text": QoLControls.name_of(m["key"]), "rect": Rect2()},
					{"id": "map:%s:pad" % a, "text": QoLControls.name_of(m["pad"]), "rect": Rect2()}]})
			if page == "controls2":
				_rows.append({"label": "ALL BUTTONS", "func": "", "desc": "", "buttons": [
					{"id": "cdefault", "text": "DEFAULT", "rect": Rect2()}]})
			for r in range(1, _rows.size()):
				var y := _row_y(r)
				var bs: Array = _rows[r]["buttons"]
				if bs.size() == 2:
					bs[0]["rect"] = Rect2(142, y, 54, CHEX_H)
					bs[1]["rect"] = Rect2(197, y, 56, CHEX_H)
				else:
					bs[0]["rect"] = Rect2(173, y, 80, CHEX_H)
		"controls3":   # the gamepad cursor (part 24): its 5 inputs, then ON/OFF and SPEED
			for c in QoLControls.CURSOR_ACTIONS:
				var a: String = c[0]
				var m: Dictionary = qol.controls.map[a]
				var y := _row_y(_rows.size())
				_rows.append({"label": c[1], "func": "TOUCH" if a == "qol_cur_click" else "", "action": a, "desc": "", "buttons": [
					{"id": "map:%s:key" % a, "text": QoLControls.name_of(m["key"]), "rect": Rect2(142, y, 54, CHEX_H)},
					{"id": "map:%s:pad" % a, "text": QoLControls.name_of(m["pad"]), "rect": Rect2(197, y, 56, CHEX_H)}]})
			var yo := _row_y(_rows.size())
			_rows.append({"label": "CURSOR", "func": "", "id": "curon", "desc": CURSOR_ON_HELP, "buttons": [
				{"id": "curon:1", "text": "ON", "rect": Rect2(142, yo, 54, CHEX_H)},
				{"id": "curon:0", "text": "OFF", "rect": Rect2(197, yo, 56, CHEX_H)}]})
			var ys := _row_y(_rows.size())
			var sp := []
			for i in 5:
				sp.append({"id": "curspd:%d" % (i + 1), "text": str(i + 1), "rect": Rect2(99 + i * 31, ys, 30, CHEX_H)})
			_rows.append({"label": "SPEED", "func": "", "id": "curspd", "desc": CURSOR_SPEED_HELP, "buttons": sp})
		"main", "confirm":
			var win := []
			for v in QoLSettings.SCALES:
				win.append(["win:%d" % v, "%dX" % v])
			win.append(["win:full", "FULL"])
			_add_row("WINDOW SIZE", win, "Size of the game window:\n1X-8X.......times the DS screens\nFULL........full screen\nA new size must be kept (KEEP)\nwithin %d seconds." % CONFIRM_SECONDS)
			var fr := []
			for v in QoLSettings.FPS:
				fr.append(["fps:%d" % v, "MAX" if v == 0 else str(v)])
			_add_row("FRAME RATE", fr, "Pictures per second on screen:\n60..........exactly like the DS\n120 240.....smoother motion\nMAX.........no limit\nThe game speed never changes.")
			_add_row("FPS COUNTER", [["fpsc:1", "ON"], ["fpsc:0", "OFF"]], "Show the frame rate in the top\nleft corner of the screen.\nThe F3 key turns it on and off\nat any time.")
			_add_row("MUSIC", [["music:1", "ON"], ["music:0", "OFF"]], "Turn the music on or off.")
			_add_row("SOUND FX", [["sfx:1", "ON"], ["sfx:0", "OFF"]], "Turn the sound effects on or off\n(everything that is not music:\nhits, voices, menu sounds).")
			_add_row("JUKEBOX", [["jukebox", "PLAY"]], "Listen to every music track\nof the game:\nPREVIOUS, PLAY/PAUSE, NEXT.")
			_layout_main()
			if page == "confirm":
				_rows.append({"label": "", "desc": "", "buttons": [
					{"id": "keep", "text": "KEEP", "rect": Rect2(66, 122, 54, HEX_H)},
					{"id": "undo", "text": "UNDO", "rect": Rect2(136, 122, 54, HEX_H)}]})
		"jukebox":
			_rows.append({"label": "", "desc": "", "buttons": [
				{"id": "prev", "text": "", "rect": Rect2(30, 94, 58, 40)},
				{"id": "play", "text": "", "rect": Rect2(99, 94, 58, 40)},
				{"id": "next", "text": "", "rect": Rect2(168, 94, 58, 40)}]})
			_rows.append({"label": "", "desc": "", "buttons": [{"id": "back", "text": "BACK", "rect": Rect2(203, 163, 48, HEX_H)}]})


func _add_row(label: String, buttons: Array, desc: String) -> void:
	var bs := []
	for b in buttons:
		bs.append({"id": b[0], "text": b[1], "rect": Rect2()})
	_rows.append({"label": label, "desc": desc, "buttons": bs})


## content rows (1..): buttons right-aligned, like the Option screen
func _layout_main() -> void:
	for r in range(1, _rows.size()):
		var y := _row_y(r)
		var bs: Array = _rows[r]["buttons"]
		var x := 252.0
		for i in range(bs.size() - 1, -1, -1):
			var w := maxf(30.0, font.width(bs[i]["text"], QoLFont.BOLD) + 14.0)
			bs[i]["rect"] = Rect2(x - w, y, w, HEX_H)
			x -= w + 1.0


func _row_y(r: int) -> int:
	if page in CPAGES:
		return CROW_Y + (r - 1) * CROW_PITCH
	return ROW_Y + (r - 1) * ROW_PITCH


func _page_no() -> int:
	if page in CPAGES:
		return CPAGES.find(page) + 1
	return maxi(0, PAGES.find({"confirm": "main", "lbconfirm": "main2"}.get(page, page))) + 1


func _page_count() -> int:
	return CPAGES.size() if page in CPAGES else PAGES.size()


## L / R or the header arrows: the next / previous page (the cursor stays on the arrow it pressed)
func _flip(d: int) -> void:
	var on_header := row == 0
	var c := col
	var list: Array = CPAGES if page in CPAGES else PAGES
	page = list[posmod(_page_no() - 1 + d, list.size())]
	_build()
	if on_header:
		row = 0
		col = c
	else:
		_focus_value(1)


## the button that shows the current value (red text)
func _is_value(id: String) -> bool:
	var s: QoLSettings = qol.settings
	var p := id.split(":")
	match p[0]:
		"win": return s.fullscreen if p[1] == "full" else (not s.fullscreen and int(p[1]) == s.scale)
		"fps": return int(p[1]) == s.fps
		"fpsc": return (p[1] == "1") == s.fps_counter
		"music": return (p[1] == "1") == s.music
		"sfx": return (p[1] == "1") == s.sfx
		"cheat": return (p[2] == "1") == s.cheat(p[1])
		"vol": return int(p[1]) == s.volume
		"apause": return (p[1] == "1") == s.auto_pause
		"askip": return (p[1] == "1") == s.auto_skip
		"mpon": return (p[1] == "1") == s.multiplayer
		"perf": return (p[1] == "1") == s.performance_mode
		"newmodes": return (p[1] == "1") == s.new_gamemodes
		"shadows": return (p[1] == "1") == s.detailed_shadows
		"zoom": return int(p[1]) == s.camera_zoom
		"wset": return (p[2] == "1") == bool(s.get(p[1]))
		"curon": return (p[1] == "1") == s.controls.cursor_enabled
		"curspd": return int(p[1]) == s.controls.cursor_speed
	return false


## cursor onto row `r`, on its current value (or the button nearest to the cursor's x)
func _focus_value(r: int) -> void:
	var cx := 0.0
	if row < _rows.size() and col < _rows[row]["buttons"].size():
		cx = _cur_rect().get_center().x
	row = clampi(r, 0, _rows.size() - 1)
	var bs: Array = _rows[row]["buttons"]
	col = -1
	for i in bs.size():
		if _is_value(bs[i]["id"]):
			col = i
	if col < 0:
		col = 0
		var best := INF
		for i in bs.size():
			var d: float = absf(bs[i]["rect"].get_center().x - cx)
			if d < best:
				best = d
				col = i
	focus_changed.emit()


func _cur_rect() -> Rect2:
	return _rows[row]["buttons"][col]["rect"]


func cur_id() -> String:
	if row >= _rows.size() or col >= _rows[row]["buttons"].size():
		return ""
	return _rows[row]["buttons"][col]["id"]


## top screen texts for the cursor's row (the game's Option screen explains the selected option there)
func focus_title() -> String:
	match page:
		"jukebox": return "JUKEBOX"
		"confirm": return "WINDOW SIZE"
		"lbconfirm": return "RESET HI-SCORES"
	if cur_id() == "exit":
		return "EXIT"
	if cur_id() == "cback":
		return "BACK"
	if page in CPAGES and row > 0 and row < _rows.size():
		var rw: Dictionary = _rows[row]
		if rw.has("action") and rw["action"].begins_with("qol_cur_"):
			return QoLControls.label_of(rw["action"])
		if rw.has("action"):
			return "%s - %s" % [rw["label"], rw["func"]] if not rw["func"].begins_with("(") else "%s BUTTON" % rw["label"]
		if rw.get("id", "") == "curon":
			return "MOUSE CURSOR"
		if rw.get("id", "") == "curspd":
			return "CURSOR SPEED"
		return "DEFAULT CONTROLS"
	if cur_id() == "bosslist":
		return "BOSS LIST"
	if cur_id().begins_with("pg_"):
		return "PAGE %d / %d" % [_page_no(), _page_count()]   # CONTROLS: 1 / 2 (part 22 QA: said "/ 7")
	return _rows[row]["label"] if row < _rows.size() else "SETTINGS"


func focus_desc() -> String:
	match page:
		"jukebox": return "Listen to the game's music:\nPREVIOUS / NEXT...change track\nPLAY/PAUSE........play or pause\nBACK..............the settings"
		"lbconfirm": return "HI-SCORE RANKING back to the\ngame's list, ALL-STAR / ENDLESS\nrecords cleared. Nothing else\nchanges (unlocks, story).\nYES......reset    NO......keep"
		"confirm": return "Keep the new window size?\nKEEP......keep it\nUNDO......go back\nWithout an answer the old size\ncomes back by itself."
	if cur_id() == "bosslist":
		return BOSS_LIST
	if cur_id() == "lbask" and _notice_lb != "":
		return _notice_lb + "\nThe Z-Battle HI-SCORE RANKING\nis back to the game's own list;\nALL-STAR / ENDLESS records\nare cleared."
	if cur_id() == "exit":
		return "Leave the settings and go back\nto the Mode Select menu.\n(B does the same.)"
	if cur_id() == "cback":
		return "Back to the settings.\n(B does the same.)\nThe controls are saved at once."
	if page in CPAGES:
		return _controls_desc()
	if cur_id().begins_with("pg_"):
		return "1-3 settings, 4 big changes.\nCheats: 5 fighting, 6 ki, 7 char-\nacters, 8 stage & music, 9 powers,\n10 challenges. 11-13 weird.\nL and R change the page too."
	return _rows[row]["desc"] if row < _rows.size() else ""


func _controls_desc() -> String:
	if cur_id().begins_with("pg_"):
		return "CONTROLS has three pages:\n1..........A B X Y L R START\n2..........SELECT, D-pad, DEFAULT\n3..........gamepad mouse cursor\nL and R change the page too."
	if row <= 0 or row >= _rows.size():
		return ""
	var rw: Dictionary = _rows[row]
	if rw.get("id", "") in ["curon", "curspd"]:
		return rw["desc"]
	if not rw.has("action"):
		return "All DS buttons back to their\noriginal keys and gamepad\nbuttons (arrows, X Z S C A D...),\nthe mouse cursor to the right\nstick, ON, speed 5." + ("  In use now." if qol.controls.is_default() else "")
	var a: String = rw["action"]
	var m: Dictionary = qol.controls.map[a]
	if not _wait.is_empty():
		var what := "KEY" if _wait["kind"] == "key" else "GAMEPAD BUTTON"
		return "Press the new %s\nfor %s now.\nEsc or a tap: cancel.  %d\n%s" % [what, _label_of(a), ceili((WAIT_FRAMES - _wait["frames"]) / 60.0),
			"(F3 and F11 are kept for the\nFPS counter and full screen.)" if _wait["kind"] == "key" else "(sticks and triggers work too)"]
	var head := "KEY: %s   PAD: %s" % [QoLControls.name_of(m["key"]), QoLControls.name_of(m["pad"])]
	if _notice != "" and _notice_action == a:
		head = _notice
	return BUTTON_HELP.get(a, "") + "\n" + head + ("\nPress a box to change it." if BUTTON_HELP.get(a, "").count("\n") < 2 else "")


# ------------------------------------------------------------------------------------------------ actions
func _press(id: String) -> void:
	var s: QoLSettings = qol.settings
	_flash[id] = 0.15
	qol.se(QoLController.SE_BACK if id in ["exit", "cback", "back", "undo", "lbno"] else (QoLController.SE_MOVE if id.begins_with("pg_") else QoLController.SE_DECIDE))
	var p := id.split(":")
	match p[0]:
		"win":
			var full := p[1] == "full"
			if _is_value(id):
				return
			_prev_window = {"scale": s.scale, "full": s.fullscreen}
			s.fullscreen = full
			if not full:
				s.scale = int(p[1])
			qol.apply_window()
			page = "confirm"
			_confirm_left = CONFIRM_SECONDS
			_build()
			row = _rows.size() - 1
			col = 0
		"fps":
			s.fps = int(p[1])
			qol.apply_display()
		"fpsc":
			s.fps_counter = p[1] == "1"
			qol.apply_display()
		"cheat":
			var was := s.cheat(p[1])
			s.cheats[p[1]] = p[2] == "1"
			if was != s.cheat(p[1]) and qol.has_method("cheat_changed"):
				qol.cheat_changed(p[1], s.cheat(p[1]))
		"bosslist": pass
		"vol":
			s.volume = int(p[1])
			qol.apply_display()
		"apause": s.auto_pause = p[1] == "1"
		"askip": s.auto_skip = p[1] == "1"
		"mpon": s.multiplayer = p[1] == "1"
		"newmodes": s.new_gamemodes = p[1] == "1"
		"perf":
			s.performance_mode = p[1] == "1"
			if qol.has_method("apply_performance"):
				qol.apply_performance()
		"shadows": s.detailed_shadows = p[1] == "1"
		"zoom": s.camera_zoom = int(p[1])
		"wset": s.set(p[1], p[2] == "1")
		"curon":
			qol.controls.cursor_enabled = p[1] == "1"
			qol.apply_controls()
		"curspd":
			qol.controls.cursor_speed = clampi(int(p[1]), 1, 5)
			qol.apply_controls()
		"controls":
			page = "controls1"
			_notice = ""
			_build()
			_focus_value(1)
		"cback":
			_wait = {}
			page = "main2"
			_build()
			_focus_value(1)
		"map":
			_wait = {"action": p[1], "kind": p[2], "frames": 0}
			_notice = ""
		"cdefault":
			qol.controls.reset()
			qol.apply_controls()
			_notice = ""
			_build()
		"pg_prev": _flip(-1)
		"pg_next": _flip(1)
		"music": s.music = p[1] == "1"
		"sfx": s.sfx = p[1] == "1"
		"jukebox": _open_jukebox()
		"exit":
			close()
			return
		"keep":
			page = "main"
			_build()
			_focus_value(1)
		"undo": _undo_window()
		"lbask":
			page = "lbconfirm"
			_build()
			row = _rows.size() - 1
			col = 1                                    # NO first: the safe answer
		"lbyes":
			var core = qol.machine.core if "machine" in qol and qol.machine != null else null
			if core != null and core.has_method("reset_leaderboards"):
				qol.on_game_thread(core.reset_leaderboards)
				_notice_lb = "HI-SCORES RESET"
			QoLAllStarRecords.reset_files()            # part 38: the ALL-STAR / ENDLESS records too
			page = "main2"
			_build()
			_focus_value(_rows.size() - 1)
		"lbno":
			page = "main2"
			_build()
			_focus_value(_rows.size() - 1)
		"prev": _jb_step(-1)
		"next": _jb_step(1)
		"play": _jb_toggle()
		"back": _leave_jukebox()
	s.save_file()
	queue_redraw()
	focus_changed.emit()


func _undo_window() -> void:
	var s: QoLSettings = qol.settings
	if not _prev_window.is_empty():
		s.scale = _prev_window["scale"]
		s.fullscreen = _prev_window["full"]
		qol.apply_window()
	s.save_file()
	page = "main"
	_build()
	_focus_value(1)
	queue_redraw()


func _open_jukebox() -> void:
	if not qol.sound.ok:
		return
	page = "jukebox"
	_build()
	row = 0
	col = 1
	qol.on_game_thread(qol.sound.jb_start)


func _jb_step(d: int) -> void:
	var snd = qol.sound
	var n: int = snd.tracks.size()
	snd.jb_index = (snd.jb_index + d + n) % n
	if snd.jb_playing:
		var i: int = snd.jb_index
		qol.on_game_thread(func(): snd.jb_play(i))
	elif snd.has_meta("paused_at"):
		snd.remove_meta("paused_at")


func _jb_toggle() -> void:
	var snd = qol.sound
	if snd.jb_playing:
		qol.on_game_thread(snd.jb_pause)
		snd.jb_playing = false
		snd.set_meta("paused_at", snd.jb_index)
	elif snd.has_meta("paused_at") and snd.get_meta("paused_at") == snd.jb_index:
		qol.on_game_thread(snd.jb_resume)
		snd.jb_playing = true
		snd.remove_meta("paused_at")
	else:
		var i: int = snd.jb_index
		qol.on_game_thread(func(): snd.jb_play(i))
		snd.jb_playing = true
		if snd.has_meta("paused_at"):
			snd.remove_meta("paused_at")


func _leave_jukebox() -> void:
	var snd = qol.sound
	qol.on_game_thread(snd.jb_stop)
	if snd.has_meta("paused_at"):
		snd.remove_meta("paused_at")
	snd.jb_playing = false
	page = "main"
	_build()
	row = _rows.size() - 1   # the JUKEBOX row
	col = 0


## CONTROLS: is the menu waiting for a new key / pad input, and for which kind ("key" / "pad")
func waiting_kind() -> String:
	return _wait.get("kind", "") if visible else ""


func finish_wait(code: String) -> void:
	var a: String = _wait["action"]
	var kind: String = _wait["kind"]
	_wait = {}
	var other: String = qol.controls.assign(a, kind, code)
	qol.apply_controls()
	_notice_action = a
	_notice = "%s = %s" % [_label_of(a), QoLControls.name_of(code)]
	if other != "" and qol.controls.map[other][kind] == "":   # the cursor's empty key slot went to `other`
		_notice += " (%s: no %s now)" % [_label_of(other), "key" if kind == "key" else "pad"]
	elif other != "":
		_notice += " (swapped with %s)" % _label_of(other)
	_wait_release = true
	qol.se(QoLController.SE_DECIDE)
	_flash["map:%s:%s" % [a, kind]] = 0.3
	_build()
	queue_redraw()
	focus_changed.emit()


func cancel_wait() -> void:
	qol.se(QoLController.SE_BACK)
	_wait = {}
	_notice = ""
	_wait_release = true
	queue_redraw()
	focus_changed.emit()


func _label_of(action: String) -> String:
	return QoLControls.label_of(action)


# ------------------------------------------------------------------------------------------------ input
## Called by QoLController once per emulated frame with the player's input: `newly` = KEYINPUT bits pressed this
## frame, `down` = held, `tap` = where a touch began (or (-1, -1)). Directions repeat while held (0.35 s, then
## every 0.1 s). Bits: 0 A, 1 B, 3 Start, 4 right, 5 left, 6 up, 7 down, 8 R, 9 L.
func frame_input(newly: int, down: int, tap: Vector2i) -> void:
	if not visible:
		return
	if not _wait.is_empty():   # CONTROLS: waiting for the new input (QoLController sends the raw events)
		_wait["frames"] += 1
		if tap.x >= 0 or _wait["frames"] >= WAIT_FRAMES:
			cancel_wait()
		elif _wait["frames"] % 60 == 0:
			focus_changed.emit()
		return
	if _wait_release:          # the input just mapped is still held: it must not act in the menu
		if down != 0 or tap.x >= 0:
			return
		_wait_release = false
	if page == "confirm":   # counted in game frames (the game always runs at the DS's 59.83 per second)
		var shown := ceili(_confirm_left)
		_confirm_left -= 1.0 / 59.8261
		if _confirm_left <= 0.0:
			_undo_window()
			focus_changed.emit()
			return
		if ceili(_confirm_left) != shown:
			queue_redraw()
	if tap.x >= 0:
		_tap(Vector2(tap))
		return
	var moved := false
	for b in [6, 7, 5, 4]:
		if (down & (1 << b)) == 0:
			_held_frames.erase(b)
			continue
		var f: int = _held_frames.get(b, -1) + 1
		_held_frames[b] = f
		if f == 0 or (f >= 21 and (f - 21) % 6 == 0):
			moved = _move(b) or moved
	if moved:
		qol.se(QoLController.SE_MOVE)
		queue_redraw()
		focus_changed.emit()
	if (newly & 0x300) != 0 and (page in PAGES or page in CPAGES):   # L / R: previous / next page
		qol.se(QoLController.SE_MOVE)
		_flip(1 if newly & 0x100 else -1)
		queue_redraw()
		focus_changed.emit()
	elif newly & 9:          # A or Start
		_press(cur_id())
	elif newly & 2:          # B
		if not page in CPAGES and page != "lbconfirm":   # (those play it in _press: one sound, part 24 QA)
			qol.se(QoLController.SE_BACK)
		match page:
			"main", "main2", "main3", "mpset", "cheats", "cheats2", "cheats3", "cheats4", "cheats5", "cheats6", "weird", "weird2", "weird3": close()
			"controls1", "controls2", "controls3": _press("cback")
			"jukebox": _leave_jukebox()
			"confirm": _undo_window()
			"lbconfirm": _press("lbno")
		queue_redraw()
		focus_changed.emit()


func _move(b: int) -> bool:
	var bs: Array = _rows[row]["buttons"]
	match b:
		4:
			if col < bs.size() - 1:
				col += 1
				return true
		5:
			if col > 0:
				col -= 1
				return true
		6, 7:
			if page == "confirm" or page == "lbconfirm":
				return false
			_focus_value(posmod(row + (1 if b == 7 else -1), _rows.size()))
			return true
	return false


func _tap(p: Vector2) -> void:
	for r in _rows.size():
		if (page == "confirm" or page == "lbconfirm") and r != _rows.size() - 1:
			continue
		var bs: Array = _rows[r]["buttons"]
		for i in bs.size():
			if bs[i]["rect"].grow(1).has_point(p):
				row = r
				col = i
				_press(bs[i]["id"])
				queue_redraw()
				focus_changed.emit()
				return
	if page in PAGES or page in CPAGES:   # a tap on a row's label moves the cursor there
		for r in range(1, _rows.size()):
			if Rect2(0, _row_y(r) + 2, 140, 18).has_point(p):
				qol.se(QoLController.SE_MOVE)
				_focus_value(r)
				queue_redraw()
				return


# ------------------------------------------------------------------------------------------------ drawing
func _draw() -> void:
	match page:
		"controls1", "controls2", "controls3":
			_draw_controls()
		"main", "main2", "main3", "mpset", "confirm", "lbconfirm", "cheats", "cheats2", "cheats3", "cheats4", "cheats5", "cheats6", "weird", "weird2", "weird3":
			_plate("BIG CHANGES" if page == "mpset" else CHEAT_PAGES[page][0] if CHEAT_PAGES.has(page) else (WEIRD_PAGES[page][0] if WEIRD_PAGES.has(page) else ("SETTINGS 3" if page == "main3" else ("SETTINGS 2" if page == "main2" or page == "lbconfirm" else "SETTINGS"))))
			var modal := page == "confirm" or page == "lbconfirm"
			for r in (_rows.size() - (1 if modal else 0)):
				if r > 0:
					_band(_row_y(r) + 3, 18, _rows[r]["label"])
				for i in _rows[r]["buttons"].size():
					var b: Dictionary = _rows[r]["buttons"][i]
					var cur: bool = not modal and r == row and i == col
					_hex(b["rect"], b["text"], _is_value(b["id"]), cur, _flash.has(b["id"]))
					if b["id"].begins_with("pg_"):
						_arrow(b["rect"].get_center(), -1 if b["id"] == "pg_prev" else 1)
			font.draw_centered(self, Rect2(150, 4, 36, 20), "%d/%d" % [_page_no(), PAGES.size()], HEX_TEXT, QoLFont.BOLD, Color.BLACK)
			if page == "confirm":
				_draw_confirm()
			elif page == "lbconfirm":
				_draw_lbconfirm()
		"jukebox":
			_draw_jukebox()


## CONTROLS: header like the other pages; one band per DS button: its name (white) and what it does (orange),
## then a KEY and a PAD hexagon (the one waiting for a new input blinks white with "PRESS")
func _draw_controls() -> void:
	_plate("MOUSE CURSOR" if page == "controls3" else "CONTROLS")
	for i in _rows[0]["buttons"].size():
		var b: Dictionary = _rows[0]["buttons"][i]
		_hex(b["rect"], b["text"], false, row == 0 and col == i, _flash.has(b["id"]))
		if b["id"].begins_with("pg_"):
			_arrow(b["rect"].get_center(), -1 if b["id"] == "pg_prev" else 1)
	font.draw_centered(self, Rect2(150, 4, 36, 20), "%d/%d" % [_page_no(), CPAGES.size()], HEX_TEXT, QoLFont.BOLD, Color.BLACK)
	font.draw_centered(self, Rect2(142, 26, 54, 11), "KEY", HEX_EDGE, QoLFont.BOLD, Color.BLACK)
	font.draw_centered(self, Rect2(197, 26, 56, 11), "PAD", HEX_EDGE, QoLFont.BOLD, Color.BLACK)
	for r in range(1, _rows.size()):
		var y := _row_y(r)
		var rw: Dictionary = _rows[r]
		draw_rect(Rect2(0, y + 1, 256, 1), TRIM)
		draw_rect(Rect2(0, y + 2, 256, 16), Color.BLACK)
		draw_rect(Rect2(0, y + 18, 256, 1), TRIM)
		font.draw(self, Vector2(5, y + 3), rw["label"], HEX_TEXT, QoLFont.BIG)
		if rw.get("func", "") != "":
			font.draw(self, Vector2(56, y + 3), rw["func"], HEX_EDGE, QoLFont.BIG)
		for i in rw["buttons"].size():
			var b: Dictionary = rw["buttons"][i]
			var waiting: bool = not _wait.is_empty() and b["id"] == "map:%s:%s" % [_wait["action"], _wait["kind"]]
			var blink: bool = waiting and (_wait["frames"] / 15) % 2 == 0
			_hex(b["rect"], "PRESS" if waiting else b["text"], _is_value(b["id"]), (r == row and i == col) or blink, _flash.has(b["id"]) or (waiting and not blink))


## the title plate (Option screen): orange line, black plate with a slanted end, white block and underline
func _plate(t: String) -> void:
	draw_rect(Rect2(0, 1, 127, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 2), Vector2(125, 2), Vector2(112, 26), Vector2(0, 26)]), Color.BLACK)
	draw_line(Vector2(125.5, 2), Vector2(112.5, 26), TRIM)
	draw_rect(Rect2(0, 26, 113, 1), TRIM)
	draw_colored_polygon(PackedVector2Array([Vector2(7, 6), Vector2(15, 6), Vector2(12, 21), Vector2(4, 21)]), CURSOR)
	font.draw(self, Vector2(19, 6), t, HEX_TEXT, QoLFont.BIG)
	draw_rect(Rect2(16, 21, 90, 1), CURSOR)


## a page arrow (white triangle) on a header hexagon
func _arrow(c: Vector2, d: int) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-4 * d, -6), c + Vector2(5 * d, 0), c + Vector2(-4 * d, 6)]), HEX_TEXT)


## a black row band with orange trim above and below, and its bold italic label
func _band(y: int, h: int, label: String) -> void:
	draw_rect(Rect2(0, y - 1, 256, 1), TRIM)
	draw_rect(Rect2(0, y, 256, h), Color.BLACK)
	draw_rect(Rect2(0, y + h, 256, 1), TRIM)
	if label != "":
		font.draw(self, Vector2(5, y + 3), label, HEX_TEXT, QoLFont.BIG)


func _hex_points(r: Rect2, inset: float) -> PackedVector2Array:
	var s := r.size.y * 0.32
	var x0 := r.position.x + inset
	var x1 := r.end.x - inset
	var y0 := r.position.y + inset
	var y1 := r.end.y - inset
	var ym := r.position.y + r.size.y / 2.0
	var si := s - inset * 0.4
	return PackedVector2Array([Vector2(x0 + si, y0), Vector2(x1 - si, y0), Vector2(x1, ym), Vector2(x1 - si, y1), Vector2(x0 + si, y1), Vector2(x0, ym)])


## an Option-screen hexagon button: orange (cursor: white) rim, black line, brown face; the value in red
func _hex(r: Rect2, text: String, value: bool, cursor: bool, flash: bool) -> void:
	draw_colored_polygon(_hex_points(r, 0), CURSOR if cursor else HEX_EDGE)
	draw_colored_polygon(_hex_points(r, 2), Color.BLACK)
	draw_colored_polygon(_hex_points(r, 3), HEX_EDGE if flash else HEX_FILL)
	if text != "":
		# 7-letter pad names (R-STICK, PADDLE1) in the CONTROLS boxes: the narrower font, not over the rim (part 24 QA)
		var st := QoLFont.BOLD if font.width(text, QoLFont.BOLD) <= r.size.x - 10 else QoLFont.REGULAR
		font.draw_centered(self, r, text, HEX_RED if value else HEX_TEXT, st)


func _draw_jukebox() -> void:
	var snd = qol.sound
	_plate("JUKEBOX")
	var n: int = snd.tracks.size()
	var t: Dictionary = snd.tracks[snd.jb_index] if n > 0 else {"name": "-", "kind": ""}
	draw_rect(Rect2(0, 32, 256, 1), TRIM)
	draw_rect(Rect2(0, 33, 256, 50), Color.BLACK)
	draw_rect(Rect2(0, 83, 256, 1), TRIM)
	font.draw(self, Vector2(8, 37), "TRACK %02d / %02d" % [snd.jb_index + 1, n], HEX_TEXT, QoLFont.BOLD)
	var kind := "MIDI" if t["kind"] == "seq" else "STREAM"
	font.draw(self, Vector2(248 - font.width(kind, QoLFont.BOLD), 37), kind, HEX_EDGE, QoLFont.BOLD)
	font.draw_centered(self, Rect2(0, 51, 256, 13), t["name"], HEX_TEXT, QoLFont.BIG)
	var status := "PRESS PLAY"
	if snd.jb_message != "":
		status = snd.jb_message
	elif snd.jb_playing:
		status = "NOW PLAYING"
	elif snd.has_meta("paused_at"):
		status = "PAUSED"
	font.draw_centered(self, Rect2(0, 69, 256, 10), status, HEX_EDGE, QoLFont.BOLD)
	var names := {"prev": "PREVIOUS", "play": "PLAY/PAUSE", "next": "NEXT"}
	for i in 3:
		var b: Dictionary = _rows[0]["buttons"][i]
		var r: Rect2 = b["rect"]
		_hex(r, "", false, row == 0 and col == i, _flash.has(b["id"]))
		_icon(b["id"], r.get_center(), snd.jb_playing)
		font.draw_centered(self, Rect2(r.position.x - 8, r.end.y + 4, r.size.x + 16, 10), names[b["id"]], HEX_TEXT, QoLFont.REGULAR, Color.BLACK)
	_band(166, 18, "")
	var bb: Dictionary = _rows[1]["buttons"][0]
	_hex(bb["rect"], bb["text"], false, row == 1, _flash.has("back"))


func _icon(id: String, c: Vector2, playing: bool) -> void:
	var w := HEX_TEXT
	match id:
		"prev":
			draw_rect(Rect2(c.x - 13, c.y - 8, 3, 16), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 0), c + Vector2(1, -8), c + Vector2(1, 8)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(1, 0), c + Vector2(11, -8), c + Vector2(11, 8)]), w)
		"next":
			draw_rect(Rect2(c.x + 10, c.y - 8, 3, 16), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(9, 0), c + Vector2(-1, -8), c + Vector2(-1, 8)]), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-1, 0), c + Vector2(-11, -8), c + Vector2(-11, 8)]), w)
		"play":
			if playing:
				draw_rect(Rect2(c.x - 7, c.y - 9, 5, 18), w)
				draw_rect(Rect2(c.x + 2, c.y - 9, 5, 18), w)
			else:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -10), c + Vector2(9, 0), c + Vector2(-6, 10)]), w)


## HI-SCORES reset: "are you sure?" in the style of the window-size confirm (dimmed page, black band, two hexagons)
func _draw_lbconfirm() -> void:
	draw_rect(Rect2(0, 28, 256, 164), Color(0, 0, 0, 0.55))
	var y := 66
	draw_rect(Rect2(0, y - 1, 256, 1), TRIM)
	draw_rect(Rect2(0, y, 256, 88), Color.BLACK)
	draw_rect(Rect2(0, y + 88, 256, 1), TRIM)
	font.draw_centered(self, Rect2(0, y + 9, 256, 13), "ARE YOU SURE?", HEX_TEXT, QoLFont.BIG)
	font.draw_centered(self, Rect2(0, y + 31, 256, 10), "RESET ALL HI-SCORES AND RECORDS", HEX_EDGE, QoLFont.BOLD)
	var bs: Array = _rows[_rows.size() - 1]["buttons"]
	for i in bs.size():
		_hex(bs[i]["rect"], bs[i]["text"], false, col == i, _flash.has(bs[i]["id"]))


func _draw_confirm() -> void:
	draw_rect(Rect2(0, 28, 256, 164), Color(0, 0, 0, 0.55))
	var y := 66
	draw_rect(Rect2(0, y - 1, 256, 1), TRIM)
	draw_rect(Rect2(0, y, 256, 88), Color.BLACK)
	draw_rect(Rect2(0, y + 88, 256, 1), TRIM)
	font.draw_centered(self, Rect2(0, y + 9, 256, 13), "KEEP THIS SIZE?", HEX_TEXT, QoLFont.BIG)
	var back := "FULL SCREEN" if _prev_window.get("full", false) else "%dX" % _prev_window.get("scale", 2)
	font.draw_centered(self, Rect2(0, y + 31, 256, 10), "BACK TO %s IN %d" % [back, ceili(maxf(_confirm_left, 0.0))], HEX_EDGE, QoLFont.BOLD)
	var bs: Array = _rows[_rows.size() - 1]["buttons"]
	for i in bs.size():
		_hex(bs[i]["rect"], bs[i]["text"], false, col == i, _flash.has(bs[i]["id"]))
