extends Node
## Entry scene: jumps to the scene given by `scene=` (default: the original game, scenes/GameDS.tscn).

func _ready() -> void:
	var target := Game.flag("scene", "res://scenes/GameDS.tscn")
	get_tree().change_scene_to_file.call_deferred(target)
