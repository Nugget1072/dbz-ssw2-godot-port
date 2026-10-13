---
description: Export the Windows build into finished/ and update the hand-off docs
---
Delivery checklist (CLAUDE.md "Run, test, deliver"):
1. Off-identity check passes (`/offcheck`), and the feature's own captures were looked at.
2. `python tools/test/ssw2.py export` (imports, exports "Windows Desktop" to finished/DBZ_SSW2_Port.exe, copies
   docs/PLAYER_README.txt → finished/README.txt and docs/BUGFIXES.txt → finished/BUGFIXES.txt). Export templates
   4.7.2 must be installed (docs/CLAUDE_CODE.md). Close running game instances first.
3. Update HANDOFF.md (state + open items), docs/HISTORY.md (one paragraph for the part), CLAUDE.md if a rule or path
   changed, docs/PLAYER_README.txt / docs/BUGFIXES.txt for player-visible changes, decomp/DATA_NOTES.md (+ index)
   for every decoded fact.
4. `git add -A && git commit` with a message naming the part (the ROM, finished/, local/ and assets are git-ignored;
   check `git status` shows no ROM-derived file before committing).
