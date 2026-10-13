@echo off
rem Game-speed test on THIS PC: runs the exported game 5 times (about 2-3 minutes; each run closes itself) and
rem writes finished\pace_*.txt. Every "PACE game" line must read about 59.8 frames/s (the DS rate) whatever the
rem display does: default, V-Sync off + uncapped, simulated 144 / 240 Hz, and a 60 Hz display with V-Sync off.
cd /d "%~dp0..\..\finished"
DBZ_SSW2_Port.exe -- pacelog quit_at=1500 save=pace_test.sav > pace_default.txt 2>&1
DBZ_SSW2_Port.exe -- pacelog quit_at=1500 save=pace_test.sav vsync=0 maxfps=0 > pace_uncapped.txt 2>&1
DBZ_SSW2_Port.exe -- pacelog quit_at=1500 save=pace_test.sav vsync=0 fakehz=144 maxfps=144 > pace_144.txt 2>&1
DBZ_SSW2_Port.exe -- pacelog quit_at=1500 save=pace_test.sav vsync=0 fakehz=240 maxfps=240 > pace_240.txt 2>&1
DBZ_SSW2_Port.exe -- pacelog quit_at=1500 save=pace_test.sav vsync=0 fakehz=60 maxfps=0 > pace_60_uncapped.txt 2>&1
del pace_test.sav 2>nul
