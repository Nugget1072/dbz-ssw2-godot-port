extends Node
## Sound manager (autoload "Sound"). One music lead at a time (onboarding §1 rule).
## Music = SDAT STRM tracks decoded to WAV by decomp/tools/convert_sound.py; loop points from sound.json.

var music: AudioStreamPlayer
var current: String = ""
var _index: Dictionary = {}


func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.bus = "Master"
	add_child(music)
	if Assets.exists("sound/sound.json"):
		_index = Assets.json("sound/sound.json")


func play_music(name: String) -> void:
	if name == current and music.playing:
		return
	stop_music()
	var rel := "sound/strm/%s.wav" % name
	if not Assets.exists(rel):
		push_warning("music missing: " + rel)
		return
	var s := AudioStreamWAV.load_from_file(Assets.path(rel))
	if s == null:
		return
	var meta: Dictionary = (_index.get("strm", {}) as Dictionary).get(name, {})
	if bool(meta.get("loop", false)):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = int(meta.get("loop_start", 0))
		s.loop_end = int(meta.get("samples", s.get_length() * s.mix_rate))
	music.stream = s
	music.play()
	current = name


func stop_music() -> void:
	music.stop()
	current = ""


## Battle BGM: stage id s plays STRM_BGM_{s+1:02d} (Ruins = stage 10 = BGM_11 verified by waveform
## correlation 0.65 against emulator audio; the rest of the mapping is assumed, confidence M).
func battle_music_for_stage(stage_id: int) -> String:
	return "STRM_BGM_%02d" % (stage_id + 1)
