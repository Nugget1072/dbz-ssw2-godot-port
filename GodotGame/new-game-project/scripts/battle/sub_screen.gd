class_name BattleSubScreen
extends Node2D
## Bottom screen during battle (engine B), composed exactly as captured from the game (DATA_NOTES "Battle sub screen"):
##   palette  : game/game_bg.arc #102 (all 16 rows); colour 0 = backdrop
##   BG0 (pri 0): tiles = charselect/SubScrNBFC.bin:<p1>.nbfc @ tile 0, game/game_subbg.bin:e_pairatk.nbfc @ tile 0x7E
##                map   = 0x0007 fill; portrait <p1>.nbfs (cols 0-9, rows 0-15) at col 1 with palette 1 (col 0 = 0x1007);
##                        e_pairatk.nbfs rows 0-6 copied to rows 16-22, + 0x7E. Scroll (0, -8).
##   BG1/BG2 (pri 1/2): empty team slot: SubScrNBFC nul1.nbfc + nul1.nbfs over a 0x0004 fill, scroll x 424 / 344, y -8.

var bg: Array[DSTextBG] = []
var backdrop: ColorRect


func setup(p1_code: String, lang: String = "e") -> void:
	var pal := Assets.bytes("raw/game/game_bg/102.bin")
	backdrop = ColorRect.new()
	backdrop.size = Vector2(256, 192)
	var c0 := pal[0] | (pal[1] << 8)
	backdrop.color = Color8((c0 & 31) * 255 / 31, ((c0 >> 5) & 31) * 255 / 31, ((c0 >> 10) & 31) * 255 / 31)
	add_child(backdrop)
	var nbfc := "raw/charselect/SubScrNBFC/"
	var nbfs := "raw/charselect/SubScrNBFS/"
	# BG2, BG1 first (lower priority drawn first), then BG0
	for slot in [[344, "nul1"], [424, "nul1"]]:
		var l := DSTextBG.new()
		l.setup_raw(4)
		l.write_palette(0, pal)
		l.write_tiles(0, Assets.bytes(nbfc + String(slot[1]) + ".nbfc"))
		l.entries.fill(0x0004)
		l.blit_map(Assets.bytes(nbfs + String(slot[1]) + ".nbfs"), 16, 0, 0)
		l.flush_all()
		l.set_scroll(int(slot[0]), -8)
		add_child(l)
		bg.append(l)
	var b0 := DSTextBG.new()
	b0.setup_raw(4)
	b0.write_palette(0, pal)
	b0.write_tiles(0, Assets.bytes(nbfc + p1_code + ".nbfc"))
	b0.write_tiles(0x7E, Assets.bytes("raw/game/game_subbg/%s_pairatk.nbfc" % lang))
	b0.entries.fill(0x0007)
	b0.blit_map(Assets.bytes(nbfs + p1_code + ".nbfs"), 16, 1, 0, 10, 16, 0x1000)
	for y in 16:
		b0.set_entry(0, y, 0x1007)
	var pa := Assets.bytes("raw/game/game_subbg/%s_pairatk.nbfs" % lang)
	for y in range(16, 23):
		for x in 32:
			var i := ((y - 16) * 32 + x) * 2
			b0.set_entry(x, y, (pa[i] | (pa[i + 1] << 8)) + 0x7E)
	b0.flush_all()
	b0.set_scroll(0, -8)
	add_child(b0)
	bg.append(b0)
