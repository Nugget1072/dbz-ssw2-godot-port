#!/bin/bash
# qoltest.sh DIR  -- scripted walk through the QoL settings menu (part 12-13 layout), captures every 10 frames
# 2480-4350, keys (K) and taps (T) mixed so that every page is used both ways:
#   2480 T Dragon Ball tile -> menu | 2520 K Left + 2540 A: 1X -> confirm | 2580 K B: undo
#   2620 T FULL -> confirm | 2660 T KEEP | 2700 T 2X -> confirm, no answer -> back to FULL at ~3300
#   3340 K Down/Right/A: 120 FPS | 3440 K Down/Left/A: FPS counter ON | 3540 T SOUND FX OFF
#   3580 K Down (JUKEBOX row: PLAY) | 3680 A: jukebox | 3720 A: play OP | 3800 Right + 3830 A: next (BGM 01)
#   3900 T PLAY/PAUSE: pause | 3940 K Down + 3970 A: BACK | 4010 K Down (wraps to the header: EXIT) + 4040 A
#   4100 K Up (game: tile 1) | 4150 K Down (port: centre) | 4180 A: menu | 4210 B: close
#   4260 K Left (game: MAXIMUM) | 4290 A: start Maximum | 4295 Right during the transition: must reach the game
# Settings go to DIR.cfg (expected: fullscreen, scale 2, fps 120, fps_counter on, music on, sfx off).
D="$1"
IN="2141:Start:4,2300:Start:4,2480:T128/86:4,2520:Left:4,2540:A:4,2580:B:4,2620:T231/43:4,2660:T93/134:4,2700:T133/43:4"
IN="$IN,3340:Down:4,3370:Right:4,3400:A:4,3440:Down:4,3470:Left:4,3500:A:4,3540:T235/151:4"
IN="$IN,3580:Down:4,3680:A:4,3720:A:4,3800:Right:4,3830:A:4,3900:T128/114:4"
IN="$IN,3940:Down:4,3970:A:4,4010:Down:4,4040:A:4,4100:Up:4,4150:Down:4,4180:A:4,4210:B:4"
IN="$IN,4260:Left:4,4290:A:4,4295:Right:4"
rm -f "$D.cfg"
"$(dirname "$0")/cap.sh" "$D" 10 4350 2480 inputs=$IN qolcfg="$D.cfg" qoldbg
echo "--- settings saved:"; cat "$D.cfg"
