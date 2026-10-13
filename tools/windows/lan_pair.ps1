# Two headless game instances on 127.0.0.1: a LAN lockstep battle (`lanbattle=1`, docs/LAN_DESIGN.md 8), then
# tools/linux/lan_cmp.py on the two `lanhash` logs (exit 0 = gameplay identical every lockstep frame). Part 36.
# The guest runs with another RTC, CAMERA ZOOM 4 and no cheats of its own (it must get the host's by the snapshot).
# Usage (from the folder root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\windows\lan_pair.ps1 -tag lan1 -cheats green_demon
#     [-hin "60:Left:700"] [-gin "60:Left:700"] [-quit 2600] [-extra "gddbg"]
# Output: local\lan\TAG\ (h/g .log .txt .cfg .sav; git-ignored). Kills only the two processes it started (on timeout).
param([string]$tag = "lan1", [string]$cheats = "", [string]$hin = "60:Left:700", [string]$gin = "60:Left:700",
      [int]$quit = 2600, [string]$extra = "")
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
$proj = "$repo\GodotGame\new-game-project"
$godot = "$repo\tools\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$rom = (Get-ChildItem "$repo\finished\*.nds" | Select-Object -First 1).FullName
$sav = "$proj\data\save100.sav"
$H = "$repo\local\lan\$tag"
Remove-Item -Recurse -Force $H -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $H | Out-Null
Copy-Item $sav "$H\h.sav"; Copy-Item $sav "$H\g.sav"
# the standard Free Battle path (tools/test/ssw2.py BATTLE_PATH): Goku vs Goku, ice stage (lanbstage=E)
$path = "2141:Start:4,2396:T128/120:6,2560:Right:4,2590:Right:4,2620:Down:4,2660:A:4,2810:A:4,2870:Start:4,2960:A:4,3020:A:4,3080:Start:4,3170:A:4,3330:A:4"
$common = @("--headless", "--fixed-fps", "60", "--path", "`"$proj`"", "res://scenes/GameDS.tscn", "--", "`"nds=$rom`"", "turbo",
  "maxfps=0", "mp=1", "lanbattle=1", "lanteams=0/0", "lanbstage=E", "inputs=$path", "lanquit=$quit") + ($extra -split " " | Where-Object { $_ })
$hargs = $common + @("`"sav=$H\h.sav`"", "`"save=$H\h.out.sav`"", "`"qolcfg=$H\h.cfg`"", "lan=host", "lanname=HOST", "lanauto",
  "laninputs=$hin", "`"lanhash=$H\h.txt`"", "rtc=2026-01-01T12:00:00")
if ($cheats) { $hargs += "cheats=$cheats" }
$gargs = $common + @("`"sav=$H\g.sav`"", "`"save=$H\g.out.sav`"", "`"qolcfg=$H\g.cfg`"", "lan=join:127.0.0.1:8082", "lanname=GUEST",
  "lanauto", "laninputs=$gin", "`"lanhash=$H\g.txt`"", "rtc=2026-07-15T09:41:27", "zoom=4")
$ph = Start-Process -FilePath $godot -ArgumentList $hargs -RedirectStandardOutput "$H\h.log" -RedirectStandardError "$H\h.err" -PassThru -NoNewWindow
Start-Sleep -Seconds 3
$pg = Start-Process -FilePath $godot -ArgumentList $gargs -RedirectStandardOutput "$H\g.log" -RedirectStandardError "$H\g.err" -PassThru -NoNewWindow
$ok = $ph.WaitForExit(900000) -and $pg.WaitForExit(900000)
if (-not $ok) { "TIMEOUT: stopping the two instances"; foreach ($p in @($ph, $pg)) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } } }
& "$repo\tools\Python3.14.8\python.exe" "$repo\tools\linux\lan_cmp.py" "$H\h.txt" "$H\g.txt"
"lan_cmp exit $LASTEXITCODE (0 = gameplay identical); logs in $H"
