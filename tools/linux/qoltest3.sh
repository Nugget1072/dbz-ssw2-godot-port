#!/bin/bash
# qoltest3.sh DIR  -- part 16: settings page 2 + CONTROLS (raw keys K<name> go through the input map); captures
# every 10 frames 2480-3100:
#   2480 T Dragon Ball tile -> menu | 2520 K R: SETTINGS 2 | 2550 K A: CONTROLS SET | 2580-2620 Down x3 (Y row)
#   2640 Left (KEY box) + 2650 A: waiting | 2680 Kspace: Y = SPACE | 2720 Down (L row) + 2740 A, 2770 Kescape:
#   cancelled | 2800 T X row PAD box: waiting, 2830 T anywhere: cancelled | 2860 K R: CONTROLS 2 |
#   2900 T BACK -> SETTINGS 2 | 2940 T AUTO PAUSE ON | 2980 T VOLUME 50 | 3040 K B: menu closed
# Settings go to DIR.cfg (expected: ds_y_key = "k:32" (Space), ds_l_key unchanged "k:65", volume 50, auto_pause true).
D="$1"
IN="2141:Start:4,2300:Start:4,2480:T128/86:4,2520:R:4,2550:A:4,2580:Down:4,2600:Down:4,2620:Down:4,2640:Left:4"
IN="$IN,2650:A:4,2680:Kspace:6,2720:Down:4,2740:A:4,2770:Kescape:4,2800:T225/91:4,2830:T60/170:4,2860:R:4"
IN="$IN,2900:T231/14:4,2940:T202/97:4,2980:T171/70:4,3040:B:4"
rm -f "$D.cfg"
"$(dirname "$0")/cap.sh" "$D" 10 3100 2480 inputs=$IN qolcfg="$D.cfg"
echo "--- settings saved:"; cat "$D.cfg"
