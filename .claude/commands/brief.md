---
description: Rewrite the user's request into a detailed brief (project rule 10), send it, then work from it
argument-hint: [the request]
---
Project rule 10 (CLAUDE.md): before working on a user task, rewrite the request into a more detailed brief.

Request: $ARGUMENTS

1. Read `HANDOFF.md` and the CLAUDE.md "Where to read next" rows that match the request (design docs, QOL_ARCHITECTURE).
2. Write the brief: goal, each requested change as a numbered item with the concrete acceptance check (which screen,
   which capture, which log line), the standing constraints that apply (off-identity, both touch/mouse and
   buttons/keyboard for every new UI, settings UI on the bottom screen in the game's style, page order
   settings → Big Changes → cheats → weird, no ROM data in git, never hand-edit scripts/gen/), what is out of scope,
   and open questions answered with "what looks most like the game and works best".
3. Show the brief to the user, then do the work from it (track it as a task list).
