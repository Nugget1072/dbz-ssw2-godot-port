#!/bin/bash
# stagecmp.sh U K NAME  -- the same stage in melonDS (from reference/states/st_stagesel.mst) and in the port,
# battle intro, every 6th frame; prints the median pixel difference after matching frames (lag frames).
# Korin (2 0) was 26.4 k px median in part 9 (most of it is the fighters' idle animation phase, not the stage).
. "$(dirname "$0")/env.sh"
U=$1; K=$2; R=$OUT/sc_$3; P=$OUT/sp_$3
cmds="run:30"
for i in $(seq 1 $U); do cmds="$cmds p:Up run:26"; done
for i in $(seq 1 $K); do cmds="$cmds p:Right run:26"; done
cmds="$cmds p:A"
for i in $(seq 0 109); do cmds="$cmds run:6 s:r$i"; done
ST="$REPO/reference/states/st_stagesel.mst" python3 "$(dirname "$0")/melon.py" $R $cmds > /dev/null
A=$((3330 + 30*U + 30*K))
"$(dirname "$0")/stage.sh" $U $K $P 6 $((A+330)) $((A+640)) > /dev/null 2>&1
START=0 python3 "$(dirname "$0")/match.py" $R $P > $P/match.txt
awk '{print $NF}' $P/match.txt | sort -n | awk '{a[NR]=$1} END {print "frames",NR,"median diff",a[int(NR/2)+1],"max",a[NR]}'
