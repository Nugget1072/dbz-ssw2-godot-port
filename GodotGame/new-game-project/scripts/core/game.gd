extends Node
## Global game state and feature flags (autoload "Game").
## Command line: everything after `--` is parsed as key=value flags, e.g.
##   godot --path . res://scenes/GameDS.tscn -- capture=out cap_every=50 cap_to=5300
## (full list: docs/DEBUG_FLAGS.md)

const DS_W := 256
const DS_H := 192

var args: Dictionary = {}

## QoL feature flags (all default to the faithful DS behaviour)
var single_screen: bool = false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	single_screen = String(args.get("single_screen", "0")) == "1"


func flag(name: String, default_value: String = "") -> String:
	return String(args.get(name, default_value))
