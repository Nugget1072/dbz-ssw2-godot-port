#!/bin/bash
# qoltest2.sh DIR  -- part 13: settings pages + cheats, keys (K) and taps (T); captures every 10 frames 2480-3200:
#   2480 T Dragon Ball tile -> menu | 2520 + 2530 K R: page 3 (CHEATS 1) | 2550 K Left + 2570 A: NO COOLDOWN on
#   2600..2760 T the ON hexagons of INFINITE HEALTH, ONE-HIT KO, INFINITE KI, KI HOMING, SAME CHARACTERS
#   2800 T < (page 2) | 2840 T > (page 3) | 2880 K L (page 2) | 2940 T EXIT (tile text: "Cheats on: 6")
#   3000 K A: menu | 3030 K Up (header) + 3050/3070 Right (EXIT) + 3090 A: close
# Settings go to DIR.cfg (expected: all six cheats true).
D="$1"
IN="2141:Start:4,2300:Start:4,2480:T128/86:4,2520:R:4,2530:R:4,2550:Left:4,2570:A:4,2600:T202/70:4,2640:T202/97:4"
IN="$IN,2680:T202/124:4,2720:T202/151:4,2760:T202/178:4,2800:T143/14:4,2840:T193/14:4,2880:L:4,2940:T231/14:4"
IN="$IN,3000:A:4,3030:Up:4,3050:Right:4,3070:Right:4,3090:A:4"
rm -f "$D.cfg"
"$(dirname "$0")/cap.sh" "$D" 10 3200 2480 inputs=$IN qolcfg="$D.cfg"
echo "--- settings saved:"; cat "$D.cfg"
