---
description: Run the off-identity check (battle PNGs + CHT lines, intro PNGs) that every change must pass
argument-hint: [--battle | --intro]
---
Run the off-identity check and report the result:

`python tools/test/ssw2.py offcheck $ARGUMENTS` (Windows without python on PATH: `tools\Python3.14.8\python.exe tools\test\ssw2.py offcheck $ARGUMENTS`).

- The battle part takes several minutes, the intro part ~5 more; run it in the background and keep working.
- PASS needs: battle PNGs 21/21, CHT lines identical, intro PNGs 221/221.
- If it says there is no baseline for this machine's tag: baselines must come from a known-good state (the last
  delivered build). Ask before recording (`python tools/test/ssw2.py baseline`), or `git stash` the change first.
- On a FAIL, look at the differing PNGs (Read them) and the first differing CHT line before claiming anything.
