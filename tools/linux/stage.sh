#!/bin/bash
# stage.sh U K OUTDIR EVERY FROM TO  -- port capture of a Free Battle (Goku vs Goku) on the stage reached with
# U presses of Up and K presses of Right on the stage select (0 0 = first stage)
. "$(dirname "$0")/env.sh"
U=$1; K=$2
IN="2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2620:Down:4,2660:A:4,2810:A:4,2870:Start:4,2960:A:4,3020:A:4,3080:Start:4,3170:A:4"
F=3330
for i in $(seq 1 $U); do IN="$IN,$F:Up:4"; F=$((F+30)); done
for i in $(seq 1 $K); do IN="$IN,$F:Right:4"; F=$((F+30)); done
IN="$IN,$F:A:4"
GDT=${GDT:-1500} "$(dirname "$0")/cap.sh" "$3" "$4" "$6" "$5" inputs=$IN "${@:7}"
