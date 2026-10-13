extends Node
## Global game state and feature flags (autoload "Game").
## Command line: everything after `--` is parsed as key=value flags, e.g.
##   godot --path . -- scene=res://scenes/battle/Battle.tscn p1=gkn p2=vgn stage=10 single_screen=1

const DS_W := 256
const DS_H := 192

var args: Dictionary = {}

## Match setup (filled by the select screens; defaults = the reference Free Battle capture)
var p1_char: String = "gkn"
var p2_char: String = "vgn"
var stage_id: int = 10          # 10 = Ruins (stg_11), first icon on the stage select
var p2_cpu: bool = true

## QoL feature flags (all default to the faithful DS behaviour)
var single_screen: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p1_char = String(args.get("p1", p1_char))
	p2_char = String(args.get("p2", p2_char))
	stage_id = int(args.get("stage", str(stage_id)))
	p2_cpu = String(args.get("p2_cpu", "1")) == "1"
	single_screen = String(args.get("single_screen", "0")) == "1"


func flag(name: String, default_value: String = "") -> String:
	return String(args.get(name, default_value))
