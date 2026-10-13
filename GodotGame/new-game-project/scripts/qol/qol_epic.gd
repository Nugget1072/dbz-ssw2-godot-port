class_name QoLEpic
extends RefCounted
## EPIC MODE (WEIRD SETTING, part 21): the game's story text rewritten as 2006-2011 internet humour.
## Every line is made at run time from the text the game is about to draw (nothing from the ROM is stored here):
## a deterministic rule-based rewriter (seeded by a hash of each original string, so a line always reads the same)
## plus a few hand-written templates of my own for the game's recurring messages ("Learned ...", "New Character
## ... unlocked"). The result keeps the original's speaker line, quoted names ("Kaioken"), numbers and button
## names, and is re-wrapped to the text box (the font's advances, the box width, the original line count).
## Story text format (DATA_NOTES part 21): ASCII, escapes \n \' \" (\t), drawn by FUN_0200B954 which counts at
## most 128 glyphs and stops the game on an escape past byte 127 — rewritten strings stay <= 126 bytes.
## Also the hand-written descriptions for the Mode Select / Option screens' description boxes (images in the ROM;
## QoLGame redraws them with the game's font).

const MAX_BYTES := 126
const ADV_SPACE := 6

## glyph advances in pixels at scale 100 (code -> px), from the game's glyph table (set by QoLGame); default 6
var adv := {}
var _cache := {}
var _h := 0          ## hash of the string being rewritten (seed)
var names := {}      ## speaker names seen (first lines), kept capitalised

# ------------------------------------------------------------------------------------------------ word lists
## lower-case word -> [probability, replacement, replacement...] (one picked per string and word)
const WORDS := {
	"you": [0.6, "u"], "your": [0.6, "ur"], "you're": [0.6, "ur"], "yourself": [0.5, "urself"],
	"you'll": [0.5, "u'll"], "you've": [0.5, "u've"], "you'd": [0.5, "u'd"],
	"because": [1.0, "cuz"], "please": [1.0, "plz"], "thanks": [1.0, "thx"], "okay": [1.0, "k"], "ok": [1.0, "k"],
	"really": [0.6, "rly"], "what": [0.35, "wut"], "people": [0.8, "ppl"], "something": [0.6, "sumthin"],
	"nothing": [0.6, "nuthin"], "everyone": [0.6, "every1"], "anyone": [0.6, "any1"], "someone": [0.6, "some1"],
	"before": [0.4, "b4"], "the": [0.12, "teh"], "this": [0.25, "dis"], "with": [0.15, "wif"],
	"love": [0.8, "luv"], "ever": [0.6, "evar"], "yes": [0.5, "yus", "ya rly"], "hello": [1.0, "hai", "ohai"],
	"hey": [0.5, "sup", "yo"], "wow": [0.8, "woah", "w00t"], "cool": [0.8, "swag", "sweet"],
	"great": [0.8, "epic", "awesome"], "amazing": [0.9, "epic", "legendary"], "incredible": [0.9, "epic", "legendary"],
	"unbelievable": [0.9, "epic", "ridonkulous"], "wonderful": [0.8, "awesome", "epic"],
	"excellent": [0.8, "epic", "awesome"], "impressive": [0.8, "epic", "sick"], "magnificent": [0.8, "epic", "legendary"],
	"terrible": [0.8, "epic"], "terribly": [0.8, "epically"], "horrible": [0.8, "epic"],
	"dangerous": [0.8, "hardcore", "extreme"], "powerful": [0.5, "beastly", "OP"],
	"defeat": [0.7, "pwn"], "defeated": [0.7, "pwned"], "defeating": [0.7, "pwning"],
	"destroy": [0.7, "pwn"], "destroyed": [0.7, "pwned"], "destroying": [0.7, "pwning"],
	"kill": [0.8, "pwn"], "killed": [0.8, "pwned"], "killing": [0.8, "pwning"], "beaten": [0.6, "pwned"],
	"die": [0.6, "ragequit"], "dead": [0.6, "ded"],
	"weak": [0.6, "n00b"], "weakling": [0.9, "n00b"], "weaklings": [0.9, "n00bz"], "fool": [0.9, "noob"],
	"fools": [0.9, "noobz"], "idiot": [0.9, "n00b"], "idiots": [0.9, "n00bz"], "brat": [0.9, "n00b"],
	"insect": [0.8, "n00b"], "insects": [0.8, "n00bz"], "trash": [0.8, "n00bz"], "inferior": [0.8, "n00b"],
	"pathetic": [0.7, "fail", "lame"], "failure": [0.8, "epic fail"], "failures": [0.8, "epic fails"],
	"friend": [0.5, "bro"], "friends": [0.5, "broz"], "guys": [0.7, "dudes"], "kid": [0.7, "lil dude"],
	"boy": [0.5, "boi"], "buddy": [0.8, "bro"], "mister": [1.0, "mista"],
	"angry": [0.8, "raging"], "furious": [0.8, "raging"], "annoying": [0.7, "trollin'"],
	"laugh": [0.7, "lol"], "cry": [0.7, "QQ"], "crying": [0.7, "QQing"], "sad": [0.7, "emo"], "sorry": [0.7, "sry"],
	"food": [0.8, "noms"], "eat": [0.6, "nom"], "eating": [0.6, "nomming"], "delicious": [0.9, "nom nom"],
	"damn": [1.0, "dang"], "dammit": [1.0, "dang it"], "hell": [1.0, "heck"], "bastard": [1.0, "jerkface"],
	"nice": [0.6, "sweet"], "good": [0.3, "gud"], "best": [0.4, "bestest"], "technique": [0.5, "move"],
	"power": [0.25, "powah"], "monster": [0.6, "beast"], "strongest": [0.4, "most beastly"],
}
## phrases (regex, lower case match, case kept on the first letter) -> [probability, replacement]
const PHRASES := [
	["\\bdragon balls\\b", 1.0, "Dragon Ballz"],
	["\\bgoing to\\b", 0.8, "gonna"], ["\\bwant to\\b", 0.8, "wanna"], ["\\bgot to\\b", 0.8, "gotta"],
	["\\bhave to\\b", 0.5, "gotta"], ["\\bkind of\\b", 0.8, "kinda"], ["\\bout of\\b", 0.5, "outta"],
	["\\bi don't know\\b", 1.0, "idk"], ["\\boh my god\\b", 1.0, "OMG"], ["\\boh my\\b", 0.8, "OMG"],
	["\\bby the way\\b", 1.0, "btw"], ["\\bto be honest\\b", 1.0, "tbh"], ["\\bthank you\\b", 1.0, "thx"],
	["\\bcome on\\b", 0.7, "c'mon"], ["\\bof course\\b", 0.7, "ofc"], ["\\bfor fun\\b", 1.0, "for the lulz"],
	["\\bmy son\\b", 1.0, "mah boi"], ["\\bmy boy\\b", 1.0, "mah boi"], ["\\bi see\\b", 0.5, "I c"],
	["\\bgoodbye\\b", 0.7, "peace out"], ["\\bi am\\b", 0.7, "I'm"], ["\\bdo not\\b", 0.7, "don't"],
	["\\bit is\\b", 0.7, "it's"], ["\\bwhy won't you\\b", 1.0, "Y U NO"], ["\\bwhy don't you\\b", 1.0, "Y U NO"],
	["\\bwhy can't you\\b", 1.0, "Y U NO"], ["\\bpower level\\b", 1.0, "power level"],
]
## sentence starters that lose their capital after an interjection ("Dude, what...")
const COMMON := ["what", "what're", "what's", "how", "the", "this", "that", "that's", "it", "it's", "there", "there's",
	"we", "we're", "we'll", "they", "you", "your", "you're", "u", "ur", "let's", "so", "now", "but", "and", "is", "are",
	"don't", "do", "can", "can't", "who", "why", "where", "when", "he", "he's", "she", "his", "my", "our", "here",
	"no", "yes", "well", "just", "looks", "all", "not", "even", "maybe", "too", "then", "if", "go", "get", "huh"]
const PROTECT := ["Button", "Buttons", "button", "buttons", "Ki", "START", "SELECT", "Touch", "touch", "Screen",
	"screen", "Pad", "HP", "+", "Special", "Super", "Ultimate", "Team", "Attack", "Support", "Mode", "Story",
	"Saiyan", "Kaioken", "Kamehameha", "Namek", "Earth"]

## proper names that keep their capital at a sentence start (generic Dragon Ball names)
const PROPER := ["Goku", "Vegeta", "Gohan", "Piccolo", "Krillin", "Trunks", "Goten", "Gotenks", "Frieza", "Cell",
	"Buu", "Broly", "Cooler", "Ginyu", "Kakarot", "Hercule", "Babidi", "Dabura", "Bulma", "Videl", "Chichi", "Earth",
	"Namek", "Dragon", "Super", "Saiyan", "King", "Kai", "Android", "Dr", "Gero", "Tien", "Yamcha", "Kami", "Dende",
	"Bardock", "Zarbon", "Dodoria", "Recoome", "Burter", "Jeice", "Guldo", "Raditz", "Nappa", "Mister", "Mista", "Lord",
	"Supreme", "Elder", "Uub", "Pikkon", "Shenron", "Syenron", "Baragus", "Sauzer", "Neize", "Doray", "Yajirobe", "Bra",
	"Pan", "Kibito", "Yamu", "Spopovich", "Cui", "Salza", "Gogeta", "Vegito", "Majin", "Mr", "Kaioken"]
const EMO_HAPPY := [":D", ":D", ":D", "XD", "^_^"]
const EMO_COOL := ["B)", "B)", "8)"]
const EMO_SAD := [":'(", ":'(", "D:"]
const EMO_SURPRISE := [":O", ":O", "o_O"]
const EMO_ANGRY := [">:(", ">:(", ">:O"]
const INTERJ := {"neutral": ["lol,", "Dude,", "Bro,", "Yo,", "Srsly,"], "surprise": ["OMG", "Woah,", "OMG,"],
	"angry": ["Ugh,", "FFFUUU-"], "sad": ["Aww,", "Dude,"], "question": ["Srsly,", "Dude,", "O rly?"],
	"cool": ["Heh,", "Bro,"], "happy": ["Yay!", "W00t!", "lol,"]}
const TAGS := {"neutral": ["lol", "rofl", "lmao", "lulz"], "happy": ["lol", "ftw", "#winning", "ftw!"],
	"cool": ["ez", "gg ez", "lol", "like a boss"], "angry": ["rage!", "ugh"], "win": ["gg", "gg ez", "ftw"],
	"sad": ["fml", "QQ"], "question": ["lol", "o rly?"], "surprise": ["wtf", "omg"]}

## meme triggers: [regex on the lower-case body, probability, [lines to insert...]]
const MEMES := [
	["\\bdo you like\\b|\\bdo u like\\b", 1.0, ["Do u like waffles?"]],
	["hungry|\\beat\\b|\\bfood\\b|candy|chocolate|cake|delicious|sweets|\\bnom", 0.8,
		["Do u like waffles?", "It's raining tacos!", "The cake is a lie.", "Nom nom nom."]],
	["power level", 1.0, ["IT'S OVER 9000!!", "It's over 9000!"]],
	["power level|\\bpower\\b|\\bpowah\\b|\\blevel\\b|\\bki\\b|energy|stronger|beastly", 0.45,
		["It's over 9000!", "IT'S OVER 9000!!", "Over 9000!!1"]],
	["spaceship|\\bspace\\b|\\bship\\b", 0.8, ["SPAAAACE!", "SPAAAAACE!!"]],
	["planet|universe|\\bstars?\\b", 0.2, ["SPAAAACE!", "SPAAAAACE!!"]],
	["look out|watch out|out of the way|dodge|get away", 0.7, ["Do a barrel roll!"]],
	["kamehameha|\\bbeam\\b|energy wave|cannon|\\bblast\\b|\\bflash\\b|\\bwave\\b", 0.6,
		["IMMA FIRIN MAH LAZER!", "SHOOP DA WHOOP!"]],
	["fight me|bring it|take you on|let's do it|let's go|i accept|let's fight|i'll fight|fight him|ready\\?", 0.55,
		["Challenge accepted.", "Challenge accepted!", "LEEEROY JENKINS!"]],
	["leave it to me|i'll handle|i will handle|i'll take care|i got this|i'm ready|no problem", 0.6,
		["Like a boss.", "Like a boss! B)"]],
	["is that all|that's all|pathetic|\\bweak|inferior|insect|n00b|noob|fail", 0.5,
		["Problem?", "U mad bro?", "Trololo~"]],
	["\\bwon\\b|victory|pwned|defeated|did it", 0.4, ["Epic win!", "Epic win! gg"]],
	["\\blost\\b|failed|\\blose\\b|failure|\\bfail", 0.5, ["Epic fail.", "Epic fail lol."]],
	["jealous|\\benvy\\b|\\bhate", 0.6, ["Haters gonna hate."]],
	["\\bcool\\b|swag|style|handsome|look at me", 0.6, ["#swag", "Swag."]],
	["hopeless|no chance|doomed|can't win|it's over|we're finished|too late", 0.6,
		["Still awesome tho! :D", "Everything is awesome!"]],
	["enough|\\bdare\\b|pay for|\\bmad\\b|furious|raging|forgive", 0.4, ["FFFFUUUU-", "Y U DO DIS?!"]],
	["alone|by myself|on my own", 0.5, ["Forever alone.", "Forever alone :'("]],
]
const GENERIC := ["Epic!", "So epic.", "Awesome!", "#winning", "Like a boss.", "Swag.", "Epic win!", "lol"]


func _init() -> void:
	pass


# ------------------------------------------------------------------------------------------------ hashing
static func fnv(b: PackedByteArray) -> int:
	var h := 0x811C9DC5
	for c in b:
		h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
	return h


static func _mix(x: int) -> int:
	x &= 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	return (x ^ (x >> 16)) & 0xFFFFFFFF


## deterministic "random" number in [0, 1) for decision `k` of the current string
func _r(k: String) -> float:
	return float(_mix(_h ^ (hash(k) & 0xFFFFFFFF))) / 4294967296.0


func _pick(arr: Array, k: String) -> Variant:
	return arr[int(_r(k + "#pick") * arr.size()) % arr.size()]


# ------------------------------------------------------------------------------------------------ widths
func width(s: String, scale: int = 100) -> int:
	var w := 0
	for ch in s:
		var c := ch.unicode_at(0)
		w += (ADV_SPACE if c == 32 else int(adv.get(c, 6))) * scale / 100
	return w


# ------------------------------------------------------------------------------------------------ story text
## `raw`: the string's bytes as the game stores them (escapes included, no terminator); `x`: its left edge in
## pixels; `scale`: the glyph scale (100 = 1x). Returns the bytes to draw instead (or `raw` unchanged).
func story(raw: PackedByteArray, x: int, scale: int) -> PackedByteArray:
	var key := raw.hex_encode() + ":%d:%d" % [x, scale]
	if _cache.has(key):
		return _cache[key]
	var out := _story(raw, x, scale)
	_cache[key] = out
	return out


func _story(raw: PackedByteArray, x: int, scale: int) -> PackedByteArray:
	for c in raw:
		if c >= 0x80 or c < 0x20:
			return raw                     # 2-byte glyphs / control bytes: not English story text
	var s := raw.get_string_from_ascii()
	var p := ""
	var i := 0
	while i < s.length():
		var ch := s[i]
		if ch == "\\":
			if i + 1 >= s.length():
				return raw
			var e := s[i + 1]
			if e == "n":
				p += "\n"
			elif e == "'" or e == "\"":
				p += e
			else:
				return raw                 # \t, \\ ...: keep as is
			i += 2
			continue
		p += ch
		i += 1
	var lines := p.split("\n")
	var has_name := lines.size() >= 2 and _is_name(lines[0])
	var head := lines[0] if has_name else ""
	if head != "":
		names[head] = true
	var body_lines := lines.slice(1) if has_name else lines
	var orig_w := 0
	for l in body_lines:
		orig_w = maxi(orig_w, width(l, scale))
	var box_w := clampi(246 - x, 150, 228) if x >= 0 and x < 200 else 200
	var max_w := maxi(orig_w, box_w)
	var orig_l := body_lines.size()
	var max_l := maxi(orig_l, 3) if has_name and head != "" else (orig_l if orig_l >= 3 else orig_l + 1)
	_h = fnv(raw)
	var body := " ".join(body_lines).strip_edges()
	if body == "" or body.replace(".", "").replace("!", "").replace("?", "").strip_edges() == "":
		return raw                         # "...", "!?": nothing to say
	# templates for the recurring messages (own text; quoted names kept)
	var t := _template(body, body_lines)
	if not t.is_empty():
		if _fits_lines(t, max_w, maxi(orig_l, t.size()), scale):
			var enc := _encode(head, has_name, t)
			if enc.size() <= MAX_BYTES:
				return enc
	for level in [3, 2, 1, 0]:
		var text := _rewrite(body, level)
		var wrapped := _wrap(text, max_w, max_l, scale)
		if wrapped.is_empty() or (wrapped.size() > 1 and _lonely(wrapped[wrapped.size() - 1])):
			continue
		var enc := _encode(head, has_name, wrapped)
		if enc.size() <= MAX_BYTES:
			return enc
	return raw


## an emoticon / tag alone on the last line looks lost: that level does not fit
func _lonely(l: String) -> bool:
	return l.length() <= 9 and l.split(" ").size() <= 2 and not l.contains(".")


func _is_name(l: String) -> bool:
	if l == "":
		return true                        # narration boxes start with an empty line
	if l.length() > 18 or l.ends_with(".") or l.ends_with("!") or l.ends_with(","):
		return false
	if l.ends_with("?") and l.to_upper() != l:
		return false
	return l.split(" ").size() <= 3


func _encode(head: String, has_name: bool, lines: Array) -> PackedByteArray:
	var parts: Array = []
	if has_name:
		parts.append(head)
	parts.append_array(lines)
	return "\\n".join(PackedStringArray(parts)).to_ascii_buffer()


func _fits_lines(lines: Array, max_w: int, max_l: int, scale: int) -> bool:
	if lines.size() > max_l:
		return false
	for l in lines:
		if width(l, scale) > max_w:
			return false
	return true


## greedy word wrap; [] when it does not fit
func _wrap(text: String, max_w: int, max_l: int, scale: int) -> Array:
	var out: Array = []
	var cur := ""
	for w in text.split(" ", false):
		var cand: String = w if cur == "" else cur + " " + w
		if width(cand, scale) <= max_w:
			cur = cand
			continue
		if cur == "" or width(w, scale) > max_w:
			return []
		out.append(cur)
		cur = w
	if cur != "":
		out.append(cur)
	return out if out.size() <= max_l else []


# ------------------------------------------------------------------------------------------------ templates
func _template(body: String, lines: Array) -> Array:
	var re := RegEx.new()
	re.compile("^(Learned special ability|Learned Team Super Attack|Learned Ultimate Attack) (\".+\")!$")
	var m := re.search(body)
	if m:
		var q := m.get_string(2) + "!"
		match m.get_string(1):
			"Learned special ability":
				return [_pick(["OMG! U learned a sick new move", "New special move get! W00t!", "U can haz special ability"], "tpl"), q + " " + _pick([":D", "B)", "XD"], "tple")]
			"Learned Team Super Attack":
				return [_pick(["Team combo unlocked! Epic win!", "BFF team attack get! ftw", "Team attack unlocked! Teamwork ftw"], "tpl"), q + " " + _pick([":D", "B)", "^_^"], "tple")]
			_:
				return [_pick(["ULTIMATE move get! Over 9000!", "Ultimate attack unlocked! Epic!", "U can haz ULTIMATE ATTACK"], "tpl"), q + " " + _pick([":O", "B)", ":D"], "tple")]
	re.compile("^New Character (\".+\") Has been unlocked!$")
	m = re.search(body)
	if m:
		if lines.size() >= 3:
			return [_pick(["New dude unlocked:", "OMG new character:", "Check out dis new dude:"], "tpl"), m.get_string(1), _pick(["Epic win! B)", "Awesome! :D", "W00t! ftw"], "tple")]
		return ["New dude " + m.get_string(1), _pick(["unlocked! Epic win! B)", "unlocked! Awesome! :D", "unlocked! W00t! ftw"], "tple")]
	return []


# ------------------------------------------------------------------------------------------------ rewriter
## level 3: everything; 2: no meme lines; 1: one emoticon at the end only; 0: words and phrases only
func _rewrite(body: String, level: int) -> String:
	# quoted names stay as they are: replaced by placeholders while rewriting
	var quotes: Array = []
	var qre := RegEx.new()
	qre.compile("\"[^\"]*\"")
	var text := body
	for m in qre.search_all(body):
		text = text.replace(m.get_string(), "\u0001%d\u0002" % quotes.size())
		quotes.append(m.get_string())
	var instr := _is_instruction(body)
	# phrases
	for ph in PHRASES:
		var re := RegEx.new()
		re.compile("(?i)" + ph[0])
		var k := 0
		var res := ""
		var last := 0
		for m in re.search_all(text):
			var src := m.get_string()
			var rep: String = ph[2]
			if _r("ph" + ph[0] + str(k)) < float(ph[1]):
				res += text.substr(last, m.get_start() - last) + (rep if rep.begins_with("Y U") or rep.begins_with("Dragon") or rep.begins_with("OMG") or rep.begins_with("I") else _case_like(src, rep))
				last = m.get_end()
			k += 1
		text = res + text.substr(last)
	# words, grouped into sentences
	var words := Array(text.split(" ", false))
	var sentences: Array = []      # [ [words...], ... ]
	var cur: Array = []
	for wi in words.size():
		var w: String = words[wi]
		cur.append(_word(w, wi, instr))
		var stripped := w.rstrip("\"')\u0002 0123456789")
		if stripped.ends_with(".") or stripped.ends_with("!") or stripped.ends_with("?"):
			sentences.append(cur)
			cur = []
	if not cur.is_empty():
		sentences.append(cur)
	# extras: an emoticon at the end (most strings), then at most `budget` more: a meme line, an interjection, one
	# emoticon inside, a tag ("lol", "gg") — one per sentence, so the line stays readable
	var n := sentences.size()
	var budget: int = [0, 0, 2, 3][level]
	var meme := [] if level < 3 else _meme_for(text.to_lower(), instr)
	if not meme.is_empty():
		budget -= 1
	var ij_at := -1
	var emo_at := -1
	var tag_at := -1
	if budget > 0 and not instr and _r("ij") < 0.25:
		ij_at = int(_r("ijs") * n) % n
		budget -= 1
	if budget > 0 and n >= 2 and _r("emomid") < 0.3:
		emo_at = int(_r("emos") * (n - 1)) % (n - 1)
		if emo_at != ij_at:
			budget -= 1
		else:
			emo_at = -1
	if budget > 0 and not instr and _r("tag") < 0.25:
		tag_at = n - 1
		budget -= 1
	var end_emo := level >= 1 and _r("emoend") < 0.85
	var out: Array = []
	var meme_done := false
	for si in n:
		var sw: Array = sentences[si]
		var stext := " ".join(PackedStringArray(sw))
		var mood := _mood(stext)
		var last := si == n - 1
		if si == ij_at and sw.size() > 1:
			var first: String = sw[0]
			var ij: String = _pick(INTERJ[mood], "ij")
			if not ij.ends_with("!") and not ij.ends_with("?") and not _keep_capital(first, text):
				sw[0] = first.substr(0, 1).to_lower() + first.substr(1)
			sw.insert(0, ij)
		# YouTube Poop: a lone shouted name gets stretched ("Krillin!!!" -> "KRILLIIIN!!!")
		if level >= 2 and sw.size() <= 2 and _r("ytp" + str(si)) < 0.45:
			var lw: String = sw[sw.size() - 1]
			var core := lw.rstrip("!")
			if lw.ends_with("!") and core.length() >= 4 and core.is_valid_identifier() and core[0] == core[0].to_upper() and core.to_lower() != core:
				sw[sw.size() - 1] = _stretch(core) + lw.substr(core.length())
		var has_emo := false
		if (last and end_emo) or si == emo_at:
			sw.append(_emoticon(mood, "emo" + str(si)))
			has_emo = true
		if si == tag_at and not (has_emo and last and meme.size() > 0):
			var tg: Array = TAGS["win"] if _has(stext.to_lower(), ["pwn", "won", "defeat", " win", "beat"]) else TAGS.get(mood, TAGS["neutral"])
			sw.append(_pick(tg, "tag"))
		out.append(" ".join(PackedStringArray(sw)))
		if not meme_done and not meme.is_empty() and (int(meme[0]) == si or (last and (int(meme[0]) < 0 or int(meme[0]) >= n))):
			out.append(meme[1])
			meme_done = true
	var res2 := " ".join(PackedStringArray(out))
	for qi in quotes.size():
		res2 = res2.replace("\u0001%d\u0002" % qi, quotes[qi])
	return res2


## a sentence's first word keeps its capital after an interjection when it is "I...", shouted, or a name (seen as a
## speaker or capitalised inside the text)
func _keep_capital(w: String, text: String) -> bool:
	var core := w.rstrip(",.!?;:")
	if core == "" or core == "I" or core.begins_with("I'") or (core.length() > 1 and core == core.to_upper()):
		return true
	return names.has(core) or core.begins_with("\u0001") or core.trim_suffix("'s") in PROPER


func _is_instruction(body: String) -> bool:
	var re := RegEx.new()
	re.compile("Button|button|[Tt]ouch|[Pp]ress |Screen|[0-9]|D-Pad|\\+|gauge|Gauge")
	return re.search(body) != null


## one word: replacements, laughter, s -> z
func _word(w: String, wi: int, instr: bool) -> String:
	if w.contains("\u0001"):
		return w
	var re := RegEx.new()
	re.compile("^([^A-Za-z0-9']*)([A-Za-z0-9'\\-]*[A-Za-z0-9])(.*)$")
	var m := re.search(w)
	if m == null:
		return w
	var pre := m.get_string(1)
	var core := m.get_string(2)
	var post := m.get_string(3)
	if core == "" or core in PROTECT or _has_digit(core):
		return w
	var low := core.to_lower()
	# laughter -> trololo / lol
	var lre := RegEx.new()
	lre.compile("^[a-z]{0,4}?((ha|he|ho|hi|hu|fu|ke|ku|mu|hee|hoo)h?){2,}[a-z]?$")
	if lre.search(low):
		var l: String = _pick(["Trololo", "LOLOLOL", "ROFL", "LMAO", "Trololololo"], "laugh" + str(wi))
		return pre + (l.to_upper() if core == core.to_upper() else l) + post
	if WORDS.has(low) and not instr:
		var e: Array = WORDS[low]
		if _r("w" + low + str(wi)) < float(e[0]):
			var rep: String = e[1 + int(_r("wv" + low) * (e.size() - 1)) % (e.size() - 1)]
			return pre + _case_like(core, rep) + post
	elif low in ["you", "your", "you're"] and _r("w" + low + str(wi)) < 0.5:
		return pre + _case_like(core, WORDS[low][1]) + post
	# s -> z at the end of a word (lower-case words; "Dragon Ballz" is done by the phrases)
	if core.length() >= 2 and core.ends_with("s") and not core.ends_with("ss") and core == low and not core.contains("'"):
		if _r("z" + str(wi)) < 0.4:
			return pre + core.substr(0, core.length() - 1) + "z" + post
	return w


static func _has_digit(s: String) -> bool:
	for ch in s:
		if ch >= "0" and ch <= "9":
			return true
	return false


static func _has(s: String, keys: Array) -> bool:
	for k in keys:
		if s.contains(k):
			return true
	return false


static func _case_like(src: String, rep: String) -> String:
	if rep == "":
		return rep
	if src.length() > 1 and src == src.to_upper() and src != src.to_lower():
		return rep.to_upper()
	var f := src.substr(0, 1)
	if f == f.to_upper() and f != f.to_lower():
		return rep.substr(0, 1).to_upper() + rep.substr(1)
	return rep


static func _stretch(core: String) -> String:
	var up := core.to_upper()
	for i in range(up.length() - 1, -1, -1):
		if up[i] in ["A", "E", "I", "O", "U"]:
			return up.substr(0, i + 1) + up[i].repeat(3) + up.substr(i + 1)
	return up


func _mood(s: String) -> String:
	var l := s.to_lower()
	if _hasw(l, ["\\w*aaa", "\\w*ooo", "aa+h", "g+a+h", "ugh", "ack", "argh", "eek", "gah", "uwa", "uga", "ooh"]):
		return "surprise"
	if s.contains("!!") or _hasw(l, ["damn", "dang", "dare", "pwn", "destroy", "pay for", "forgive", "shut up",
			"enough", "angry", "raging", "rage", "furious", "jerkface", "die!", "ragequit", "regret", "grr", "maa",
			"beat u", "beat you", "smash", "get you", "get u", "kick", "punish", "n00b", "noob", "silence", "fail"]):
		return "angry"
	if s.contains("?!") or s.contains("!?") or _hasw(l, ["what?", "huh", "wha", "impossible", "no way", "can't be",
			"whoa", "woah", "omg", "eek", "what is", "what's"]):
		return "surprise"
	if _hasw(l, ["sorry", "sry", "can't", "couldn't", "lost", "dead", "ded", "died", "cry", "tears", "alone", "sad",
			"too late", "goodbye", "peace out", "miss ", "hurt", "pain", "ow!", "owww", "no...", "lonely", "weak", "emo"]):
		return "sad"
	if s.ends_with("?"):
		return "question"
	if _hasw(l, ["i'm", "i am", "my power", "strongest", "elite", "ready", "watch", "leave it", "easy", "prince",
			"no problem", "of course", "ofc", "heh", "hmph", "ez", "beastly", "swag"]):
		return "cool"
	if s.ends_with("!") or _hasw(l, ["yes", "yay", "great", "epic", "awesome", "thx", "thanks", "fun", "happy", "lol"]):
		return "happy"
	return "neutral"


var _re_cache := {}


## word-start match of any key (keys are regex pieces) in `l`
func _hasw(l: String, keys: Array) -> bool:
	var k := ",".join(PackedStringArray(keys))
	if not _re_cache.has(k):
		var re := RegEx.new()
		re.compile("\\b(" + "|".join(PackedStringArray(keys)).replace("?", "\\?").replace(".", "\\.") + ")")
		_re_cache[k] = re
	return (_re_cache[k] as RegEx).search(l) != null


func _emoticon(mood: String, k: String) -> String:
	match mood:
		"angry":
			return _pick(EMO_ANGRY, k)
		"sad":
			return _pick(EMO_SAD, k)
		"surprise", "question":
			return _pick(EMO_SURPRISE, k)
		"cool":
			return _pick(EMO_COOL, k)
		"happy":
			return _pick(EMO_HAPPY, k)
	return _pick([":D", ":O", "B)", ":D"], k)


## [sentence index (-1 = end), text] of the meme line for this body, or []
func _meme_for(low: String, instr: bool) -> Array:
	if instr:
		return [] if _r("memei") > 0.25 else [-1, _pick(["Ez.", "Like a boss.", "Epic!"], "memei")]
	for i in MEMES.size():
		var mm: Array = MEMES[i]
		var re := RegEx.new()
		re.compile(mm[0])
		var m := re.search(low)
		if m and _r("meme" + str(i)) < float(mm[1]):
			# after the sentence that holds the trigger
			var sre := RegEx.new()       # sentence index = runs of . ! ? before the trigger
			sre.compile("[.!?]+")
			return [sre.search_all(low.substr(0, m.get_start())).size(), _pick(mm[2], "meme" + str(i))]
	if _r("memeg") < 0.12:
		return [-1, _pick(GENERIC, "memeg")]
	return []


# ------------------------------------------------------------------------------------------------ menu descriptions
## hand-written description boxes (own text): Mode Select tiles in the game's order (Z-Battle, Story, VS, Maximum,
## ???, Free Battle, Practice, Data File, Option) and the Option screen rows (Time Limit, Game Rank, Damage, Back
## Light, Credit, Option Mode x2). Lines of at most 36 characters, at most 5 lines.
const MODE_DESC := [
	"Pwn computer n00bz one after\nanother! No lag, no mercy.\nEpic win guaranteed! B)",
	"Live the EPIC story of ur fave dude!\nReal plotz + crazy \"what-if\" ones\nwhere everybody powers up to\nOVER 9000!!! :D",
	"Pwn ur bros over wireless! lol\nEach n00b needs a Nintendo DS\nand a Game Card. No haxx plz :O",
	"Hardcore mode 4 l33t pros only!\nBeat it = new dude unlocked.\nFFFFUUUU- guaranteed. >:(",
	"Wat iz dis? :O\nNobody knowz... trololo",
	"Pick ANY dude u want and enjoy\nepic team battlez! Swag B)",
	"Learn 2 play wif Gotenks, or just\nspar wif any1 u like.\nPractice makes epic! XD",
	"All ur sick Special Moves in one\nplace. Knowledge iz power! B)",
	"Tweak stuff. Like a boss. B)",
]
const OPTION_DESC := [
	"Set da time limit 4 battlez:\nON: Time Limit (hurry up lol)\nOFF: No Time Limit (4ever!) :D",
	"How hard do u want it? :O\n1......Easy (ez lol)\n2......Normal\n3......Hard (FFFUUU-)",
	"How much do hits hurt? :'(\n1......Normal\n2......Heavy\n3......Extra-Heavy (over 9000!)",
	"Lights on or off? Ur call B)\nON: BACKLIGHT\nOFF: NO BACKLIGHT (emo mode)",
	"Check out the epic dudes who\nmade dis game! Respect. B)",
	"Change settingz here, bro!\nMessed up? Press SELECT to\nrestore defaults. Phew! :D",
	"Change settingz here, bro!\nMessed up? Press SELECT to\nrestore defaults. Phew! :D",
]


# ------------------------------------------------------------------------------------------------ pictures (part 23)
## Data File character bar suffix
const NAME_SUFFIX := ["B)", "(Boss)", "(Epic)", "(Pro)", "ftw", "lol", "xD"]
## Data File help panels: [left x, capital top y, lines] (own text; the game's text font, 6 px per letter)
const HELP_TEXT := {
	"arts_help": [
		[35, 6, ["Button Mashin' Technique"]],
		[41, 20, ["Super Attack wif dis icon? MASH", "dat button like crazy 4 more", "powah! Over 9000 clicks lol"]],
		[35, 70, ["Hold-It-Down Ability"]],
		[41, 84, ["Super Attack wif dis icon? Just", "hold the button down 4 more", "power. Ez. B)"]],
		[35, 134, ["ULTIMATE ATTACK (OP)"]],
		[41, 148, ["Only works when ur Health is red,", "and only once per battle.", "Clutch time! >:O"]],
	],
	"sp_help": [[36, 34, ["Press the L Button 4 ur Special", "Ability when ur Ki is high enough.",
		"Some dudes only get it in a", "certain condition, some just do", "it automatically (lazy lol).",
		"Ki cost depends on the character.", "Like a boss. B)"]]],
	"teamarts_help": [[24, 36, ["Team Super Attack = ur whole crew", "teams up 4 one MEGA attack! Tap the",
		"Team Super Attack button when", "Energy is over 200 (not 9000 lol).", "But if a bro gets KO'd, his Team",
		"Supers are gone. Forever alone :'("]]],
	"sup_help": [[33, 63, ["Wanna call ur Support bro? Touch", "the Support Character on the Touch",
		"Screen and he jumps in wif his", "attack or ability. Teamwork ftw! B)"]]],
}
const MOVE_WORDS := {"Super": "Supah", "Attack": "Attakk", "Blast": "Blazt", "Death": "Deth", "Kill": "Pwn",
	"Explosion": "Splosion", "Shots": "Shotz", "Ball": "Ballz", "Power": "Powah", "Special": "Speshul",
	"Smasher": "Smashah", "Evil": "Evul", "Revive": "Respawn", "Relax!": "Chillax!", "Angry": "Ragin'",
	"Pride": "Swag", "Frenzy": "Rage Mode", "Absorbtion": "Nom Nom", "Pose": "Pose B)", "Unleashed": "Unleashed!!1",
	"Defeat": "Pwn", "Victory": "Epic Win", "Awareness": "Swag", "Storm": "Storm", "Ultimate": "Ultimate"}
const MOVE_SPECIAL := {"Kamehameha": "KAMEHAMEHAAA", "Spirit Bomb": "Spirit Bomb (plz)", "Final Flash": "Final Flash (pew)",
	"Galick Gun": "Galick Gun (pew)", "Level 20 Kaioken": "Kaioken x9000", "Instant Transmission": "Instant Teleport lol",
	"Big Bang Attack": "Big Bang Attakk B)", "Happy Sweets": "Happy Waffles", "Self-Destruct": "Ragequit Boom",
	"Regeneration Ability": "Respawn Hax", "Special Beam Cannon": "Speshul Beam Cannon", "Death Ball": "Deth Ballz"}
const MOVE_TAIL := ["!!1", " B)", " lol", " ftw", " (OP)", " XD", "!!"]
const INPUTS := {"Pressing up": ["Up! Up! lol", "Mash up", "Push up"], "Pressing down": ["Down low B)", "Smash down", "Push down"],
	"Pressing sideways": ["Sideways lol", "Mash sideways", "Push sideways"],
	"When close to opponent": ["All up in their face", "Close 2 n00b", "Close 2 foe"]}


## candidates (best first) for a text read from a Data File picture: kind "name" (move / ability / team attack),
## "input" (how to do it), "desc" (description sentences)
func picture_text(text: String, kind: String) -> Array:
	_h = fnv(text.to_utf8_buffer())
	var out: Array = []
	var marks := ""
	var core := text
	for m in ["™", "®"]:
		if core.ends_with(m):
			marks = m
			core = core.trim_suffix(m).strip_edges()
	match kind:
		"input":
			if INPUTS.has(core):
				var arr: Array = INPUTS[core].duplicate()
				var i := int(_r("in") * arr.size()) % arr.size()
				out.append(arr[i])
				out.append_array(arr)
			out.append(core.replace("Pressing", "Pressin'"))
		"name":
			var tail: String = _pick(MOVE_TAIL, "tail")
			var r := core
			if MOVE_SPECIAL.has(core):
				r = MOVE_SPECIAL[core]
			else:
				var ws := core.split(" ")
				for k in ws.size():
					if MOVE_WORDS.has(ws[k]):
						ws[k] = MOVE_WORDS[ws[k]]
					elif ws[k].length() >= 4 and ws[k].ends_with("s") and _r("z" + str(k)) < 0.6:
						ws[k] = ws[k].substr(0, ws[k].length() - 1) + "z"
				r = " ".join(ws)
			if MOVE_SPECIAL.has(core):
				out.append(r + marks)
			else:
				out.append(r + marks + tail)
				out.append(r + marks + "!")
				out.append(r + marks)
				out.append(core + marks + tail)
			var sh := r
			for pair in [["Speshul", "Spesh"], ["Special", "Spesh"], ["Attakk", "Atk"], ["Attack", "Atk"], ["Change", "Swap"], ["Supah", "Supa"], ["Super", "Supa"], ["Ultimate", "Ulti"], ["Energy", "Nrg"]]:
				sh = sh.replace(pair[0], pair[1])
			out.append(sh + marks + "!")
			out.append(sh + marks)
		_:
			for level in [3, 2, 1, 0]:
				out.append(_rewrite(text, level))
	out.append(text + "!")
	return out


## candidates for one staff-credits line; `ink` = its colour (13 yellow: roles and cast characters, 15 white:
## names and team titles, others: company names)
const CAST := {"Goku": "Goku B)", "Gohan": "Gohan :D", "Bardock": "Bardock B)", "Piccolo": "Piccolo -_-",
	"Krillin": "Krillin :'(", "Yajirobe": "Yajirobe lol", "Vegeta": "Vegeta >:(", "Trunks": "Trunkz", "Hercule": "Hercule (champ)",
	"Yamcha": "Yamcha (RIP)", "Tien": "Tien :O", "CellJr": "Cell Jr. lol", "Babidi": "Babidi :O", "Shenron": "Shenron (wishez)",
	"Recoome": "Recoome lol", "Frieza": "Frieza (da bawss)", "Cooler": "Cooler B)", "Zarbon": "Zarbon (so pretty)",
	"Sauzer": "Sauzer :D", "Dodoria": "Dodoria lol", "Ginyu": "Ginyu (posing)", "Burter": "Burter (so fast)",
	"Jeice": "Jeice :D", "Android#16": "Android #16 <3", "Android#17": "Android #17 B)", "Android#18": "Android #18 >:(",
	"Dr.Gero": "Dr. Gero (n00b)", "Cell": "Cell (perfect)", "Dabura": "Dabura >:(", "MajinBuu": "Majin Buu :D",
	"Guldo": "Guldo :O", "Broly": "xX_Broly_Xx", "CAST": "CAST (EPIC)", "Development": "Dev Team FTW",
	"SPECIALTHANKSTO:": "SPECIAL THX 2 :", "Synthesis:": "Synthesis (swag):"}
const ROLES := [["Executive Producer", "Chief Waffle Officer"], ["Chief Production Producer", "Chief Hype Producer"],
	["Production Producer", "Hype Producer"], ["Chief Development Producer", "Chief Dev Pwner"],
	["Development Producer", "Dev Pwner"], ["Chief Producer", "Chief Hype Producer"], ["Producer", "Epic Producer"],
	["Localization Coordinator", "Translation Wizard"], ["Localisation", "Translation"], ["Business", "Bizness"],
	["Coordinators", "Coordinatorz"], ["Coordinator", "Coordinator lol"], ["Team Leader", "Raid Leader"],
	["Project Manager", "Project Boss"], ["Product Manager", "Product Boss"], ["Manager", "Boss"], ["manager", "boss"], ["Maneger", "Boss"],
	["Director", "Big Boss"], ["Chief Designer", "Chief Swag Designer"], ["Effect Designer", "FX Wizard"],
	["Designer", "Swag Designer"], ["Chief Programer", "Chief Code Ninja"], ["Programer", "Code Ninja"],
	["Chief Planner", "Chief Master Planner"], ["Planner", "Master Planner"], ["Script", "Script Kiddie"],
	["Debug", "Bug Pwner"], ["Composer", "Epic Beat Dropper"], ["Consultant", "Advice Dude"], ["Expert", "Pro"],
	["Copy Writer", "Copypasta Writer"], ["Quality", "Kwality"], ["Marketing", "Hype"], ["Evaluation", "Testing"],
	["Executive", "Exec"], ["Communications", "Chatting"], ["International Operations.", "Being Awesome."],
	["Certification", "Approval"], ["Consulting", "Advice"], ["Materials", "Stuff"]]
const PERSON_TAIL := [" B)", " :D", " (pro)", " ftw", " (l33t)", " <3", " xD"]


func credit_text(t: String, ink: int) -> Array:
	_h = fnv(t.to_utf8_buffer())
	var key := t.replace(" ", "")
	var out: Array = []
	if CAST.has(key):
		out.append(CAST[key])
	var is_caps := t == t.to_upper() and t.to_lower() != t.to_upper()
	if ink == 13 and not CAST.has(key):
		var r := t
		var done := []
		for pair in ROLES:
			var re := RegEx.new()
			var pat := str(pair[0])
			re.compile("\\b" + pat.replace(".", "\\.") + ("\\b" if not pat.ends_with(".") else ""))
			var m := re.search(r)
			if m == null:
				continue
			# a word already rewritten is not rewritten again ("Coordinatorz")
			var overlap := false
			for dn in done:
				if m.get_start() < dn[1] and m.get_end() > dn[0]:
					overlap = true
			if overlap:
				continue
			r = r.substr(0, m.get_start()) + pair[1] + r.substr(m.get_end())
			var grow: int = str(pair[1]).length() - str(pair[0]).length()
			for dn in done:
				if dn[0] >= m.get_end():
					dn[0] += grow
					dn[1] += grow
			done.append([m.get_start(), m.get_start() + str(pair[1]).length()])
		if r != t:
			out.append(r)
		out.append(t + " ftw")
	elif is_caps:
		out.append(t + " FTW")
		out.append(t + "!!")
	elif ink != 15 and ink != 13:
		out.append(t + " FTW")
		out.append(t + " B)")
	else:
		var tail: String = _pick(PERSON_TAIL, "pt")
		out.append(t + tail)
		out.append(t + " :D")
		out.append(t + " B)")
	out.append(t + "!")
	return out


## Data File touch-screen items (only letters these pictures have: S u p e r A t a c k i l b y T m o, and the
## small S e l c t a n i m o d s p y f)
## (keys: the text without spaces, I read as l)
const SUB_TEXT := {"Selectanitemtodisplayinfo": "Select an item to display info lol", "SuperAttack": "Sick Attack",
	"SpecialAbility": "Special Abilitay", "TeamSuperAttack": "Team Sick Attack", "Support": "Support bro"}
const TAB_TEXT := {"ARTS": "EPIC ARTS", "ULTIMATEATTACKS": "OP ATTACKS", "SPECIALABILITIES": "EPIC ABILITIES",
	"TEAMARTS": "TEAM COMBOS", "SUPPORT": "SUPPORT BRO", "SPECIAL": "EPIC"}
