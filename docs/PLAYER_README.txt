DRAGON BALL Z: SUPERSONIC WARRIORS 2 - Godot port
==================================================

HOW TO PLAY
  1. Put your own ROM of the European cartridge in this folder, next to DBZ_SSW2_Port.exe.
     Any file name works (game.nds, dbz.bin, ...); the game checks the contents, not the name.
  2. Run DBZ_SSW2_Port.exe (keep libdsnative.windows.x86_64.dll next to it; it makes the game faster).
  The game itself contains no ROM or game assets. Copy this folder to any Windows 10/11 PC and it runs.
  Everything is unlocked. Progress is saved in DBZ_SSW2_Port.sav (delete it to reset to 100%).

CONTROLS - KEYBOARD (default; change them in the settings menu: SETTINGS 2 -> CONTROLS)
  Arrow keys .......... D-pad   (fly / move the cursor)
  X ................... A       (ki blast / confirm)
  Z ................... B       (guard / back)
  S ................... X       (dash attack; X+A = super attack)
  C ................... Y       (melee attack, press again for a combo)
  A ................... L       (power up, e.g. Goku's Kaioken)
  D ................... R       (charge ki; R+A / R+B = special moves)
  Enter ............... Start   (pause)
  Backspace ........... Select  (not used in battle)
  Mouse (lower screen)  Touch screen (Team Arts, calling your support, menus)
  F3 .................. FPS counter on/off       F11 ..... Fullscreen on/off

CONTROLS - GAMEPAD (Xbox layout, default)
  D-pad = D-pad, B = A, A = B, Y = X, X = Y, LB = L, RB = R, Start = Start, Back = Select

SETTINGS (new in this port)
  On the MODE SELECT screen, the middle tile (the port's "PORT" button) opens the settings menu: move onto it with the
  arrow keys and press X (A), or click it with the mouse. It looks and works like the game's OPTION MODE screen:
    Up/Down choose a row - Left/Right move the white cursor - X (A) or Enter press the button - Z (B) back.
    Every button can also be clicked. The top screen explains the row under the cursor. The menu uses the game's
    own cursor / select / back sounds.
  WINDOW SIZE ...... 1X, 2X, 4X or 8X the DS screens, or FULL (full screen, as large as your screen allows,
                     same shape as the DS, every DS pixel the same size). A new size must be confirmed with
                     KEEP within 10 seconds, otherwise the old size comes back by itself.
  FRAME RATE ....... 60, 120, 240 or MAX (uncapped) pictures per second. The game always runs at the DS's normal
                     speed; above 60 the extra pictures show moving things in between their DS positions
                     (smoother motion, about one frame of extra delay). 60 = exactly like the DS.
  FPS COUNTER ...... ON / OFF: the frame rate in the top left corner. F3 turns it on/off at any time.
  MUSIC ............ ON / OFF
  SOUND FX ......... ON / OFF (everything that is not music: hits, voices, menu sounds)
  JUKEBOX - PLAY ... every music track in the game (38): PREVIOUS / PLAY-PAUSE / NEXT / BACK.
  Page 2 ("SETTINGS 2"):
  CONTROLS - SET ... one row per DS button with what it does ("Y  ATTACK") and two boxes: KEY (keyboard) and
                     PAD (gamepad). Press a box (click it, or move onto it and press A), then press the new key
                     or gamepad button (sticks and triggers work too). Esc or a click elsewhere cancels; a key
                     that another button already uses is swapped with it. Page 2 of CONTROLS has DEFAULT, which
                     gives every button its original key back. F3 / F11 / Esc cannot be used.
                     Page 3 of CONTROLS is MOUSE CURSOR (see below); DEFAULT resets it too.
  GAMEPAD MOUSE CURSOR  with a gamepad connected, a small arrow cursor appears on the lower (touch) screen: move it
                     with the right stick and press the right stick to touch the screen where it points (hold it
                     to keep touching). It works everywhere the touch screen is used, including this menu. It
                     hides after a few seconds without use, or when you use the real mouse, and comes back when
                     you move the stick. CONTROLS page 3: CURSOR ON / OFF, SPEED 1-5, and the keys / gamepad
                     inputs for its directions and its click (TOUCH). DEFAULT = right stick, ON, speed 5.
  VOLUME ........... 0, 25, 50, 75 or 100 % for everything (music and sound effects).
  AUTO PAUSE ....... ON: the game pauses while its window is not in front, and goes on when you come back.
  DETAILED SHADOWS . ON: the round shadow under each fighter becomes a black shadow of the fighter itself, in its
                     current pose (supports get one too). OFF: the game's own round shadows.
  ZOOM ............. battle camera distance: 100 = the game's own camera; 70 / 85 show more of the stage; 115 / 130
                     bring the camera closer while the fighters are near each other (both always stay on screen).
                     The far background layers keep their size.
  HI-SCORES - RESET  puts the Z-Battle HI-SCORE RANKING back to the game's own list (100000 ... 60000) and saves,
                     and clears the ALL-STAR and ENDLESS records (see NEW GAMEMODES). It asks "ARE YOU SURE?" first
                     (YES / NO; NO is selected first, Z (B) = NO). Nothing else in your save changes (story, unlocks).
  Page 3 ("SETTINGS 3"):
  AUTO SKIP ........ ON: Story Mode dialogue and narration scenes skip themselves (the game's own SKIP button is
                     pressed for you, so story progress and unlocks are exactly as when you watch them), and the
                     blue VS screen before every Z-Battle fight is skipped. Menus, battles, results and the Story
                     endings are left alone. OFF plays like the original.
  DAMAGE NUMBERS ... every hit's damage pops up over the fighter who was hit: white for small hits, then yellow,
                     orange and big red for heavy ones, grey when guarded; quick hits (beams) add up into one
                     growing number, and numbers stack instead of overlapping.
  INPUT DISPLAY .... in battles, a small strip between the ki gauges shows player 1's D-pad and buttons while held,
                     plus the last few inputs with how many frames each was held, like a training mode.
  The arrows at the top right (or the L / R buttons = A / D keys) switch pages; EXIT goes back to Mode Select.
  The middle tile of Mode Select shows the port's own "PORT" button instead of the game's unused Dragon Ball tile.

LOCAL MULTIPLAYER (settings page 4, BIG CHANGES -> MULTIPLAYER; OFF by default - with it OFF the game is exactly the original)
  With MULTIPLAYER ON, VS BATTLE on the Mode Select screen offers LOCAL and LAN (network play: see LAN MULTIPLAYER
  below). LOCAL opens the controller setup:
  - For PLAYER 1 and PLAYER 2 choose the device with LEFT / RIGHT, the box's arrows, or A for a list: the keyboard
    or any connected gamepad (a missing gamepad shows NOT CONNECTED). Default: PLAYER 1 = keyboard, PLAYER 2 = the
    first gamepad. Two gamepads work, and both players can share the keyboard: PLAYER 2 then has its own keys
    (I K J L = D-pad, N = A, M = B, H = X, G = Y, U = L, O = R, P = START, Y = SELECT).
  - CONTROLS SET changes a player's buttons (only that player's keyboard / gamepad is accepted); DEFAULT gives
    them back. Each gamepad player gets a cursor on the touch screen (right stick + right-stick press): red for
    PLAYER 1, blue for PLAYER 2; the mouse belongs to the keyboard player.
  - These controls replace the normal ones during local play; the normal controls come back at Mode Select.
  - READY (bottom right) -> "READY TO CONTINUE?" YES goes on to the character select. B goes back.
  Character select: red outline = PLAYER 1, blue = PLAYER 2 (purple when both are on the same fighter). A = pick
  (a team holds up to 3, a support counts as one), B = remove your last pick, START = done (a full team is done
  automatically). Up / Down changes the DP tab for both players (the other outline comes along). PLAYER 1's team is
  the PLAYER list ("1P"), PLAYER 2's the ENEMY list ("2P"). When both are done, READY? appears: GO goes on, BACK
  lets both pick on. B when nobody has picked anything goes back to the controller setup.
  Each player's picks are checked against their own team and D.P only: one player's full team never greys out or
  blocks the other's picks. A team needs at least one fighter (START and the last free slot are kept for one).
  Stage select: each player chooses a stage (A or a tap; B to change your mind). When both have chosen, a short
  roulette picks one of the two (50/50; the same stage if you agree), then the battle starts.
  Battle: PLAYER 2 controls the second team. The touch screen shows both teams: PLAYER 1 on the left half, PLAYER 2
  on the right; per player the active fighter (top left), the two bench fighters sharing the split box (bottom
  left; tap one to switch), the support (top right; tap to call; with SAME CHARACTERS a team can take two supports:
  the box is split in half and each half calls its support; each player has their own support slot, so both
  players can have a support on screen at the same time, even the same character) and Touch! (team attack: red diamond PLAYER 1, blue
  PLAYER 2, bright when Team Arts is ready). Either player's START
  pauses. After the battle (or "Return to Character Select") you are back at the character select for another
  round; "Return to Menu" ends local play. In local play every cheat works for both players (HARD MODE: both take
  double damage); BOSS CHARACTERS: hold L while picking; RANDOM CHARACTERS gives both players a random team.

LAN MULTIPLAYER (MULTIPLAYER ON, VS BATTLE -> LAN; two PCs / Steam Decks on the same home network, no internet play)
  - Both players need the SAME port build (the same downloaded version) and the same ROM; otherwise the guest sees
    DIFFERENT GAME VERSION / DIFFERENT ROM.
  - HOST: type a display name -> your room opens and shows this PC's address and port (e.g. 192.168.1.23:8082).
    Windows asks once whether DBZ_SSW2_Port.exe may use the network: allow it for PRIVATE networks (if the network
    is set to "Public", Windows blocks the guest). Steam Deck / Linux: nothing to allow.
  - JOIN: type a display name and the host's address exactly as its room shows it (keyboard, D-pad or taps;
    "192.168.1.23" or "192.168.1.23:8082"). Nobody answering for 15 seconds = UNABLE TO CONNECT (wrong address,
    host not in its room, firewall, or not the same network).
  - In the room the host presses START to go to the character select; the guest ACCEPTs (or DENYs). Each player
    picks their own team on their own screen (GO waits for the other player), then both choose a stage (50/50
    roulette as in local play) and fight: the host is PLAYER 1 (left), the guest PLAYER 2 (right); each player's
    touch screen shows their own team. After the battle both are back at the character select; B with no picks
    (or the pause menu's "Mode Select") goes back to the room; B in the room leaves it.
  - The battle uses the HOST's cheats and weird options on both PCs (the guest's own come back when it leaves, even
    after a crash; its settings file is never changed). Window size, frame rate, sound, controls, camera zoom,
    shadows, damage numbers and input display stay each player's own.
  - PING (bottom left, under Team Arts) is the network round trip: a few ms on a wired / good Wi-Fi network; the
    bars turn yellow from 30 ms and red from 80 ms. Both PCs run the same battle frame by frame (lockstep), so
    "WAITING FOR PLAYER" appears when the other PC falls behind (slow Wi-Fi, a loading hitch); a dropped connection
    shows CONNECTION LOST after a few seconds and both players are back in the room / LAN page.

CHEATS (settings pages 5-9, sorted by theme; all OFF unless you turn them on; they act for player 1 only)
  While any cheat is on, Z-Battle scores are not put in the HI-SCORE RANKING and ALL-STAR / ENDLESS runs are not
  recorded (settings and weird stuff don't count).
 Page 5 FIGHTING
  INFINITE HEALTH .. player 1's team takes no damage (hits still land, the life bar stays full).
  HARD MODE ........ enemy attacks do double damage to you, and enemies have double health (they take half damage).
  ONE-HIT KO ....... every hit from player 1 knocks out the enemy fighter (guarded hits do normal damage).
  NO COOLDOWN ...... attacks can be used again at once: ki blasts and super attacks start even while another
                     attack is still firing (a beam that gets cut short keeps going for a second).
  ATTACK SPAM ...... attacks restart at once and every hit connects: spam heavy attacks, dash attacks and combos
                     (supers, throws and team attacks still play out in full).
 Page 6 KI & ASSISTS
  INFINITE KI ...... the ki gauge stays at 200 %: ki blasts and supers cost nothing.
  KI HOMING ........ player 1's ki blasts curve toward the enemy (beams are not affected).
  TRIPLE KI BLASTS . every ki blast you fire becomes three shots in a fan (beam attacks are not changed).
  INFINITE ASSISTS . player 1's support character can be called again and again.
  ASSIST SPAM ...... call your support again while one is still fighting: every call brings one more (up to 8
                     at once, each with its own attack). Supports are called by touching their portrait.
 Page 7 CHARACTERS
  SAME CHARACTERS .. pick the same fighter more than once in the character select screens (e.g. three Gokus).
                     As in the normal game a team takes at most one support and needs a fighter, and a
                     fighter always starts the battle (local multiplayer: up to two supports, see above).
  BOSS CHARACTERS .. hold L (A key) while picking a character: you get its boss version (more HP, cheaper
                     supers; Final Boss SSJ Goku, Boss Cell and Boss Broly also have their boss-only moves).
                     A skull marks boss portraits; the LIST button shows the bosses' names (also in
                     BOSS_CHARACTERS.txt). Works for both teams in Free Battle, and in Z-Battle / Maximum.
  RANDOM CHARACTERS  every battle, player 1's team is replaced by random characters (same team size, always
                     at least one real fighter). Your own picks are kept for the next battle.
  CHARACTER SHUFFLE  every 10 seconds player 1's fighter turns into a random character from the whole roster
                     (not a support character); its HP stays the same. The change waits for a calm moment (not
                     during an attack, a hit, a guard or a super), so it can come a little later than 10 seconds.
  CHAOS SHUFFLE .... like CHARACTER SHUFFLE, but every second and right away. Supers, throws and grabs (yours or
                     the enemy's) and summoned helpers are let finish first. Your ki blasts in flight vanish at
                     each change. Wins over CHARACTER SHUFFLE.
 Page 8 STAGE & MUSIC
  RANDOM STAGE ..... every battle is fought on a random stage (with that stage's music).
  STAGE SHUFFLE .... every 10 seconds the battle moves to another random stage; fighters, HP and music go on.
  RANDOM MUSIC ..... every piece of music is swapped for another; switching it on again gives a new mix.
 Page 9 CHALLENGES
  GREEN DEMON ...... a green 1-UP mushroom (after the Super Mario 64 fan challenge) appears off screen in every
                     battle and slowly creeps toward your fighter. If it touches your fighter, that fighter is
                     knocked out at once, with a big explosion (guarding and INFINITE HEALTH don't help); then
                     it warps far away and waits a moment while your next fighter comes in. Keep moving: normal
                     flying outruns it, and if a knock-back throws you far away it catches up quickly until it
                     is just off screen. It ignores the enemy completely and flies through enemy fighters.
                     Local / LAN multiplayer: it hunts both players: it picks one at random and switches to the
                     other every 10 seconds, except while it is right next to its target; once that player gets
                     away it picks a random target again. It knocks out either player it touches.
  BOMB RAIN ........ little walking bombs fall from the sky during fights. A direct hit takes a quarter of a
                     fighter's max HP and knocks them back; a bomb that lands nearby hurts less (guarding helps).
                     Watch the shadows on the floor and move away - they hurt both teams. Uses the game's own
                     explosion and sound. (It was a weird option before; now it is a cheat, so no scores or
                     records while it is on. A BOMB RAIN that was on in an older settings.cfg stays on.)
WEIRD STUFF (settings pages 10-12, after the cheats; all OFF unless you turn them on; for fun)
 Page 10: BEVEL EMBOSS, TOUCH FUZZY, GAME BOY, MIRROR MODE, SCREEN SHAKE, CRT TV. Page 11: BLOOD, AFTERIMAGES,
 2ND FIDDLE, EPIC MODE, FLASHY KI, KO CONFETTI. Page 12: RAINBOW KI.
  BEVEL EMBOSS ..... every picture gets a Photoshop-style bevel & emboss (light top-left edges, shadowed
                     bottom-right), menus included (the port's own settings menu stays flat so it stays readable).
  TOUCH FUZZY ...... in every battle (Story, Z-Battle, Maximum, Practice, Free Battle...): a slow rainbow shimmer
                     and a wobbly floor and background, like Yoshi's Island. Only the picture changes.
  GAME BOY ......... everything in the 4 shades of green of the first Game Boy, menus included.
  MIRROR MODE ...... battles are shown flipped left-right (the touch screen is not), and LEFT / RIGHT are swapped so
                     it still plays naturally. The life-bar numbers read mirrored too; the pause menu is not mirrored.
  SCREEN SHAKE ..... the battle screen shakes when a hit lands: the harder the hit, the bigger and longer the shake
                     (at most 6 DS pixels, so even one-hit KOs stay watchable).
  CRT TV ........... the picture looks like an old TV: soft scanlines (2X window or bigger), a little glow and dark
                     rounded corners. The port's settings menu stays sharp.
  BLOOD ............ drops of blood fly off a fighter that gets hit, fall to the ground and fade. Harder hits
                     throw more and faster drops (a punch about 3, a super about 12, at most 30 per hit, so
                     ONE-HIT KO / HARD MODE can't flood the screen).
  AFTERIMAGES ...... fast moves (dashes, knock-backs, teleports) leave fading blue afterimages, like in the anime.
  EPIC MODE ........ the game's text goes full 2006-2011 internet (lol, ROFL, B), :D, "over 9000!", waffles...):
                     story / tutorial dialogue, the Mode Select and Option descriptions, the DATA FILE (move names,
                     inputs, descriptions, help panels, touch-screen items) and the staff credits (Option -> Credit).
                     The opening is untouched; names, results screens and logos stay as they are. English only.
  2ND FIDDLE ....... you fight in the second player's colours (e.g. SSJ Trunks with the red jacket); a player 2 with
                     the same character gets the normal colours. Starts with the next battle.
  FLASHY KI ........ bigger, pulsing auras while charging or powered up, rising sparkles when charging ki, and
                     glowing ki blasts (halo + trail) and beams.
  KO CONFETTI ...... a burst of colourful confetti when a fighter is knocked out; it flutters down and lies on the
                     floor for a moment.
  RAINBOW KI ....... ki blasts and beams cycle through the colours of the rainbow.
  Cheats are saved with the settings; the PORT tile's description says how many are on.
  Settings (and your controls) are kept in settings.cfg next to the exe (delete it for the defaults).
  The window's icon is the game's own icon, read from your ROM when the game starts (the exe file itself has a
  plain "SW2" icon, because nothing from the ROM is built into it). Full screen has black borders.

FUN FACTS
  - Not a remake: the original DS program was decompiled with Ghidra and machine-translated, all 3,316 functions.
  - Even the DS sound chip's driver (the ARM7 CPU's code) was translated, so music and effects are the real thing.
  - Every fix was checked frame-by-frame against the melonDS emulator, down to the RAM contents.
  - The 3D stages are drawn by your GPU, but with the DS's own rules (pixel snapping, polygon clipping, edges).
  - Hot spots of the old DS code (3D geometry, sound mixing, file lookups) were rewritten in C++, with identical results.
  - One bug made the Story menu say "3/14" maps cleared: a function's oversized stack buffer overwrote its caller's data.
  - The wobbly "MODE SELECT" bar was a polygon-clipping detail: the DS clips a 4-sided shape as one piece, not two triangles.
  - Its last stray pixels only showed on real graphics cards: they rebuild long thin triangles from rounded corners.

NEW GAMEMODES / ALL-STAR / ENDLESS (settings page 4, BIG CHANGES -> NEW GAMEMODES; OFF by default)
  With NEW GAMEMODES ON, Mode Select's FREE BATTLE tile becomes GAMEMODE (Free Battle is not reachable while it is
  on; every other mode is unchanged). GAMEMODE opens a 4-slot menu: ALL-STAR, ENDLESS (the last two slots are EMPTY
  for now); Up / Down + A, or tap a slot and tap it again; B goes back. ALL-STAR: pick your team (up to 3, a support counts as one) and confirm with GO. Then fight all 26 playable
  characters one after another in story order: Goku, Krillin, Piccolo, Gohan (Kid), Vegeta, Ginyu, Frieza, SSJ Goku,
  Cooler, Mecha Frieza, Trunks (Teen), Trunks (Super), Metal Cooler, Dr. Gero, SSJ Vegeta, Android 18, Cell (2nd
  form), Cell, Broly, Gohan (Super 2), Gohan (Teen), Majin Vegeta, Majin Buu, Gotenks, Gotenks (Super 3), Kid Buu.
  The enemy can't tag out or use Team Arts; you can. The top shows a count-up clock (MM:SS, stops at the last KO,
  at most 99:59) and how many you have beaten (n/26). Three HEARTS under Team Arts on the touch screen: tap one (or
  press SELECT) to fully heal and revive your whole team; each heart works once per battle. Lose (or Return to
  Character Select) -> back to the All-Star team select; B there -> the GAMEMODE menu.
  The stage is always the Time Chamber, but in deep space: a night sky with a navy-to-black gradient, a faint
  Milky-Way band and coloured twinkling stars (the floor and buildings keep their colours; the hourglasses' glass
  shows the sky through it). Its music plays first; when a track ends, a random other stage's track follows, and so
  on. (The normal Time Chamber elsewhere is unchanged.) Every life bar (yours and the enemy's) always shows the real
  health, also after a heart, a revive or when the next enemy comes in; each team member keeps its own bar colour
  (yellow / lavender / green), as in the original game.
  After a win the ALL-STAR RECORDS screen, laid out like the game's own results screen: top = your team's portraits,
  ALL-STAR table (enemies beaten, hearts used, rank, best time, New Record! / Not Ranked / not recorded with cheats)
  with your clear TIME in the orange bar and the WINNER banner; bottom = the top 5 clear times (fastest first; equal
  times: fewer hearts used first) with each team's faces and hearts used, your new row lit. Records are kept in
  allstar_records.cfg next to the exe (settings page 2 HI-SCORES RESET clears them); nothing is recorded while cheats are on. Press A / START /
  B, tap Character Select or click it with the gamepad cursor to return to the All-Star team select. The Gamemode
  menu's header reads GAMEMODE SELECT.
  ENDLESS: pick your team the same way, then fight random enemies with no end (any of the 26 fighters; never the
  same one twice in a row, and the two enemies on the field are always different). Everything else is as in
  ALL-STAR: the Time Chamber in deep space with its rotating music, three HEARTS, no enemy tag / Team Arts, the
  clock (MM:SS) at the top; under it the number of enemies beaten so far. When your whole team is knocked out
  (Game Over) the ENDLESS RECORDS screen opens: top = your team, the ENDLESS table (enemies beaten, hearts used,
  rank, best run, New Record! / Not Ranked / not recorded with cheats), your TIME in the orange bar and the game's
  own "Game Over" title; bottom = the top 5 runs (most enemies first; equal: faster, then fewer hearts) with the
  enemies beaten (n KO), each team's faces and the time, your new row lit. A run that beat nobody is not ranked.
  Records are kept in endless_records.cfg next to the exe; nothing is recorded while cheats are on. A / START / B
  or Character Select returns to the team select (the pause menu's Return to Character Select does too, without a
  record); B there -> the GAMEMODE menu.

PERFORMANCE (settings page 4, BIG CHANGES; OFF by default)
  For slow PCs and the Steam Deck. ON: the next game frame is computed while the current picture is uploaded and
  drawn, and FRAME RATE 120 / 240 / MAX act as 60 (no in-between frames). The game itself plays exactly the same
  (same speed, same results; LAN partners may use different settings). OFF: as before. Part of the speed-up is
  always on (both modes), with identical results.

STEAM DECK / LINUX (PROTON)
  The Windows exe runs under Proton. If a frame takes longer than the PC can show it, the game now works out the
  next frame while the picture is being drawn (automatic; fast PCs are unchanged). To measure the speed, add
  DBZ_PERFLOG=1 %command% to the game's Steam launch options: the game then writes perflog.txt next to the exe
  (frames per second, game frames per second and frame times every 5 seconds, and whether PERFORMANCE is on).
  F3 shows the FPS counter. LAN timing log: start with "-- lanpace pingdbg" (Steam: %command% -- lanpace pingdbg).
