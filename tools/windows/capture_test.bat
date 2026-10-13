@echo off
rem Frame-exact capture with the exported game on THIS PC's graphics card (for GPU-specific rendering bugs).
rem Double-click; the screenshots land in finished\cap\p<frame>.png (relative paths resolve next to the exe).
rem Default: mode select with its scrolling bar, frames 2440-2560. Compare them with captures of the same frames
rem from another machine with tools/linux/cmpdirs.py, and check the bar with tools/linux/barcheck.py.
cd /d "%~dp0..\..\finished"
"DBZ_SSW2_Port.exe" -- capture=cap cap_every=1 cap_from=2440 cap_to=2560 inputs=2141:Start:4,2300:Start:4 save=cap_test.sav quit_at=2562 > cap_log.txt 2>&1
del cap_test.sav 2>nul
