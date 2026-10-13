class_name QoLMarkers
extends Control
## BOSS CHARACTERS (part 14): a small skull on the portrait of every fighter picked as a boss: on the character
## select screen (upper screen) and in battle (the team panels on the lower screen). Points are top-left corners in
## the 256x384 DS space, set every frame by QoLController.

const SKULL := [
	"..#####..",
	".#######.",
	"#########",
	"##..#..##",
	"##..#..##",
	"#########",
	".###.###.",
	"..#####..",
	"..#.#.#..",
]

var points: Array = []


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(256, 384)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90


func show_at(p: Array) -> void:
	if p != points:
		points = p
		queue_redraw()


func _draw() -> void:
	for p: Vector2 in points:
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(11, 11)), Color.BLACK)   # outline / backing
		for y in SKULL.size():
			var row: String = SKULL[y]
			for x in row.length():
				if row[x] == "#":
					draw_rect(Rect2(p.x + x, p.y + y, 1, 1), Color8(255, 247, 239))
		draw_rect(Rect2(p.x + 2, p.y + 3, 2, 2), Color8(255, 36, 0))       # red eyes, like the menu's values
		draw_rect(Rect2(p.x + 5, p.y + 3, 2, 2), Color8(255, 36, 0))
