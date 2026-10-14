class_name QoLSettings
extends RefCounted
## The port's own options (QoL settings menu), stored in settings.cfg next to the exe (editor: user://).

const SCALES := [1, 2, 4, 8]               ## window size = DS screens (256x384) times this
const FPS := [60, 120, 240, 0]             ## display frame rate cap; 0 = uncapped (V-Sync off)

var scale: int = 2
var fullscreen: bool = false
var fps: int = 60
var fps_counter: bool = false
## cheats (settings page 2), all off unless the player turns them on; saved like the other settings
const CHEATS := ["no_cooldown", "infinite_health", "one_hit_ko", "infinite_ki", "ki_homing", "same_characters",
	"boss_characters", "random_characters", "infinite_assists", "assist_spam", "random_music", "character_shuffle",
	"chaos_shuffle", "stage_shuffle", "triple_ki", "attack_spam", "hard_mode", "random_stage", "green_demon", "bomb_rain",
	"ultra_instinct", "randomizer", "flightless", "smash_knockback",   # part 39
	"hot_potato", "ricochet_ki",   # part 40
	"vampire", "time_skip", "dragon_balls"]   # part 41
var music_seed := 0                       ## RANDOM MUSIC: the current shuffle (a new one each time it is switched on)
var cheats := {}
var music: bool = true
var sfx: bool = true
var volume: int = 100                     ## master volume in percent (settings page 2)
var auto_pause: bool = false              ## pause while the window is not in front (settings page 2)
var detailed_shadows: bool = false        ## fighters' ground shadows drawn as their silhouettes (settings page 2)
const ZOOMS := [0, 1, 2, 3, 4]             ## CAMERA ZOOM levels (settings page 2): 2 = the game's own camera
var camera_zoom: int = 2
## WEIRD SETTINGS page (part 21): picture / text effects, all off by default
var bevel_emboss: bool = false            ## Photoshop-style bevel & emboss on everything drawn
var touch_fuzzy: bool = false             ## battles: rainbow tint + wavy floor / background (looks only)
var epic_mode: bool = false               ## the game's text rewritten as 2006-2011 internet humour
var second_fiddle: bool = false           ## player 1 in the second-player colours, a same-character player 2 normal
var blood: bool = false                   ## part 22: droplets fly off fighters that take damage
var afterimages: bool = false             ## part 22: fast fighters leave fading afterimages
var game_boy: bool = false                ## part 22: the picture in 4 shades of Game Boy green
var mirror_mode: bool = false             ## part 22: battle screen flipped left-right, left / right controls swapped
var flashy_ki: bool = false               ## part 23: bigger / brighter auras, ki blasts, beams
var screen_shake: bool = false            ## part 23: the battle picture shakes on hits
var ko_confetti: bool = false             ## part 23: confetti burst when a fighter is knocked out
var damage_numbers: bool = false          ## part 24: each hit's damage pops up as a floating number
var rainbow_ki: bool = false              ## part 24: ki blasts and beams cycle through rainbow colours
## part 25: walking bombs rain on the battle (they hurt). Part 38: a cheat (page 9 CHALLENGES, [cheats] bomb_rain;
## counts in cheats_on(), so no leaderboard entry while it is on); this property just reads / writes cheats["bomb_rain"]
var bomb_rain: bool:
	get: return cheat("bomb_rain")
	set(v): cheats["bomb_rain"] = v
var input_display: bool = false           ## part 25: player 1's buttons shown on the battle screen
var crt_tv: bool = false                  ## part 25: old-TV picture (scanlines, glow, dark corners)
var performance_mode: bool = false        ## part 32 (BIG CHANGES page): cheaper paths for slow PCs / Steam Deck
var new_gamemodes: bool = false           ## part 34 (BIG CHANGES page): FREE BATTLE tile -> GAMEMODE (ALL-STAR)
var multiplayer: bool = false             ## part 27 (MULTIPLAYER page): VS BATTLE opens LOCAL / LAN
var lan_name := ""                        ## part 30 LAN menus: the last DISPLAY NAME and host IP[:PORT] typed ([lan])
var lan_ip := ""
var auto_skip: bool = false               ## part 24 (settings page 3): skip Story cutscenes / Z-Battle blue screens
const WEIRD := ["bevel_emboss", "touch_fuzzy", "epic_mode", "second_fiddle", "blood", "afterimages", "game_boy", "mirror_mode",
	"flashy_ki", "screen_shake", "ko_confetti", "rainbow_ki", "crt_tv"]
## part 26: DAMAGE NUMBERS and INPUT DISPLAY are settings (page 3) now; still saved in [weird] (old files keep them)
var controls := QoLControls.new()         ## key / gamepad mapping of the DS buttons (settings page 2 → CONTROLS)
var mp_input := QoLMpInput.new(controls)  ## part 27 LOCAL MULTIPLAYER: devices + mappings per player ([mp] keys)


## "" = do not load / save (frame-exact captures start from the defaults unless given `qolcfg=PATH`)
static func path() -> String:
	if Game.args.has("qolcfg"):
		return Game.flag("qolcfg")
	if Game.args.has("capture"):
		return ""
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("settings.cfg")
	return "user://settings.cfg"


## The user:// copy is the exported game's fallback for a read-only game folder (save_file). Part 37: never for an
## explicit `qolcfg=` file: a test run with a fresh qolcfg used to load the player's own user:// settings (cheats /
## weird options on) in the exported exe only, which looked like an editor-vs-exe emulation difference.
func load_file() -> void:
	var c := ConfigFile.new()
	var fallback := OS.has_feature("template") and not Game.args.has("qolcfg")
	if path() == "" or (c.load(path()) != OK and (not fallback or c.load("user://settings.cfg") != OK)):
		return
	scale = int(_val(c, "display", "window_scale", scale))
	if not scale in SCALES:
		scale = 2
	fullscreen = bool(_val(c, "display", "fullscreen", fullscreen))
	fps_counter = bool(_val(c, "display", "fps_counter", fps_counter))
	fps = int(_val(c, "display", "fps", fps))
	if not fps in FPS:
		fps = 60
	music = bool(_val(c, "sound", "music", music))
	sfx = bool(_val(c, "sound", "sound_effects", sfx))
	volume = clampi(int(_val(c, "sound", "volume", volume)), 0, 100)
	auto_pause = bool(_val(c, "display", "auto_pause", auto_pause))
	detailed_shadows = bool(_val(c, "display", "detailed_shadows", detailed_shadows))
	camera_zoom = clampi(int(_val(c, "display", "camera_zoom", camera_zoom)), 0, 4)
	auto_skip = bool(_val(c, "game", "auto_skip", auto_skip))
	multiplayer = bool(_val(c, "mp", "enabled", multiplayer))
	new_gamemodes = bool(_val(c, "game", "new_gamemodes", new_gamemodes))
	performance_mode = bool(_val(c, "display", "performance_mode", performance_mode))
	lan_name = str(_val(c, "lan", "name", lan_name)).left(10)
	lan_ip = str(_val(c, "lan", "last_ip", lan_ip)).left(21)
	bevel_emboss = bool(_val(c, "weird", "bevel_emboss", bevel_emboss))
	touch_fuzzy = bool(_val(c, "weird", "touch_fuzzy", touch_fuzzy))
	epic_mode = bool(_val(c, "weird", "epic_mode", epic_mode))
	second_fiddle = bool(_val(c, "weird", "second_fiddle", second_fiddle))
	for k in ["blood", "afterimages", "game_boy", "mirror_mode", "flashy_ki", "screen_shake", "ko_confetti", "damage_numbers", "rainbow_ki", "input_display", "crt_tv"]:
		set(k, bool(_val(c, "weird", k, get(k))))
	controls.load_cfg(c)
	mp_input.load_cfg(c)
	mp_input.refresh_defaults()
	for k in CHEATS:
		cheats[k] = bool(_val(c, "cheats", k, false))
	if not c.has_section_key("cheats", "bomb_rain"):   # part 38: files from before BOMB RAIN became a cheat
		cheats["bomb_rain"] = bool(_val(c, "weird", "bomb_rain", false))
	music_seed = int(_val(c, "cheats", "music_seed", 0))


## a value of the default's type: a hand-edited or damaged settings.cfg ("true" in quotes, a list, ...) must not
## stop the loading half way (bool("true") is a script error; part 22 QA)
static func _val(c: ConfigFile, sec: String, key: String, def: Variant) -> Variant:
	var v: Variant = c.get_value(sec, key, def)
	if typeof(v) == typeof(def):
		return v
	if typeof(v) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
		return type_convert(v, typeof(def))
	if v is String:
		var t: String = v.strip_edges().to_lower()
		if def is bool and t in ["true", "false", "1", "0", "yes", "no", "on", "off"]:
			return t in ["true", "1", "yes", "on"]
		if def is int and t.is_valid_int():
			return int(t)
	return def


func save_file() -> void:
	if path() == "":
		return
	var c := ConfigFile.new()
	c.set_value("display", "window_scale", scale)
	c.set_value("display", "fullscreen", fullscreen)
	c.set_value("display", "fps", fps)
	c.set_value("display", "fps_counter", fps_counter)
	c.set_value("sound", "music", music)
	c.set_value("sound", "sound_effects", sfx)
	c.set_value("sound", "volume", volume)
	c.set_value("display", "auto_pause", auto_pause)
	c.set_value("display", "detailed_shadows", detailed_shadows)
	c.set_value("display", "camera_zoom", camera_zoom)
	c.set_value("game", "auto_skip", auto_skip)
	c.set_value("mp", "enabled", multiplayer)
	c.set_value("game", "new_gamemodes", new_gamemodes)
	c.set_value("display", "performance_mode", performance_mode)
	c.set_value("lan", "name", lan_name)
	c.set_value("lan", "last_ip", lan_ip)
	c.set_value("weird", "bevel_emboss", bevel_emboss)
	c.set_value("weird", "touch_fuzzy", touch_fuzzy)
	c.set_value("weird", "epic_mode", epic_mode)
	c.set_value("weird", "second_fiddle", second_fiddle)
	for k in ["blood", "afterimages", "game_boy", "mirror_mode", "flashy_ki", "screen_shake", "ko_confetti", "damage_numbers", "rainbow_ki", "input_display", "crt_tv"]:
		c.set_value("weird", k, get(k))
	controls.save_cfg(c)
	mp_input.save_cfg(c)
	for k in CHEATS:
		c.set_value("cheats", k, cheat(k))
	c.set_value("cheats", "music_seed", music_seed)
	if override_active:   # part 30 LAN guest: the file keeps this player's own values, never the host's (5.4)
		for k: String in _own:
			if k.begins_with("cheat:"):
				c.set_value("cheats", k.substr(6), _own[k])
			elif k == "music_seed":
				c.set_value("cheats", "music_seed", _own[k])
			else:
				c.set_value("weird", k, _own[k])
	var err := c.save(path())
	if err != OK and OS.has_feature("template") and not Game.args.has("qolcfg"):   # read-only folder: keep it in the user data folder (never a test's qolcfg values, part 37)
		c.save("user://settings.cfg")


## frames above the DS's 60 are blended between game frames (smooth motion)
func smooth() -> bool:
	return fps != 60


func cheat(name: String) -> bool:
	return bool(cheats.get(name, false))


func cheats_on() -> int:
	var n := 0
	for k in CHEATS:
		if cheat(k):
			n += 1
	return n


# ---- LAN SNAPSHOT (part 30) -----------------------------------------------------------------------------------------
## docs/LAN_DESIGN.md 5.4: the host's cheats + weird options + RANDOM MUSIC seed are used by the guest for the session.
## begin_override keeps the guest's own values of exactly those keys in `_own`; save_file writes `_own` for them while
## the override is active, so settings.cfg never holds host values whoever saves (a crash / kill needs no recovery);
## end_override puts them back. Everything else (window, sound, controls, zoom, shadows, ...) stays the player's own.
var override_active := false
var _own := {}


## the host's values to send (WELCOME): {"v": 1, "cheats": {name: bool}, "music_seed": int, "weird": {name: bool}}
func snapshot() -> Dictionary:
	var ch := {}
	for k in CHEATS:
		ch[k] = cheat(k)
	var w := {}
	for k in WEIRD:
		w[k] = bool(get(k))
	return {"v": 1, "cheats": ch, "music_seed": music_seed, "weird": w}


func begin_override(snap: Dictionary) -> void:
	if not override_active:
		_own = {}
		for k in CHEATS:
			_own["cheat:" + k] = cheat(k)
		for k in WEIRD:
			_own[k] = bool(get(k))
		_own["music_seed"] = music_seed
		override_active = true
	var ch = snap.get("cheats", {})
	var w = snap.get("weird", {})
	for k in CHEATS:
		cheats[k] = ch is Dictionary and bool(ch.get(k, false))
	for k in WEIRD:
		set(k, w is Dictionary and bool(w.get(k, false)))
	var ms = snap.get("music_seed", music_seed)
	if typeof(ms) == TYPE_INT:
		music_seed = ms


func end_override() -> void:
	if not override_active:
		return
	for k: String in _own:
		if k.begins_with("cheat:"):
			cheats[k.substr(6)] = _own[k]
		elif k == "music_seed":
			music_seed = _own[k]
		else:
			set(k, _own[k])
	_own = {}
	override_active = false
