# melon.py OUTDIR cmd... -- scripted melonDS (headless core) run for reference shots. ST=<savestate> to start from one.
#   to:F  run:N  p:KEY[+KEY][:FRAMES]  t:X:Y[:FRAMES]  s:NAME (screenshot OUTDIR/NAME.png)  w:ADDR:VAL16  save:STATE
#   hp (print fighter HP)  ko:N:EVERY / win:N (battle helpers)  sheet:a,b,c (side-by-side of shots)
# ROM / SAV: environment (default baseroms/*.nds or finished/*.nds, and 100Save/*.sav or the project's data/save100.sav)
import sys, os, glob
REPO = os.environ.get('REPO') or os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'tools', 'melonds-headless'))
from mh import MH
# part 21: baseroms/ and 100Save/ may be gone: the ROM then lives in finished/, the 100% save in the project's data/
ROM = os.environ.get('ROM') or sorted(glob.glob(os.path.join(REPO, 'baseroms', '*.nds')) + glob.glob(os.path.join(REPO, 'finished', '*.nds')))[0]
SAV = os.environ.get('SAV') or sorted(glob.glob(os.path.join(REPO, '100Save', '*.sav')) + [os.path.join(REPO, 'GodotGame', 'new-game-project', 'data', 'save100.sav')])[0]
e=MH(ROM, SAV)
if os.environ.get('ST'): e.load_state(os.environ['ST'])
out=sys.argv[1]; os.makedirs(out,exist_ok=True)
def runto(f):
    while e.frame<f: e.run(1)
for c in sys.argv[2:]:
    p=c.split(':')
    if p[0]=='to': runto(int(p[1]))
    elif p[0]=='run': e.run(int(p[1]))
    elif p[0]=='p': e.press(p[1].split('+'),int(p[2]) if len(p)>2 else 4)
    elif p[0]=='t': e.touch(int(p[1]),int(p[2]),int(p[3]) if len(p)>3 else 6)
    elif p[0]=='s': e.screens().save(f'{out}/{p[1]}.png'); print('shot',p[1],e.frame)
    elif p[0]=='w':
        a=int(p[1],16); v=int(p[2]) & 0xFFFF
        e.lib.mh_write8(a, v & 0xFF); e.lib.mh_write8(a+1, v >> 8)
    elif p[0]=='ko':   # ko:N:EVERY  - run N frames, zeroing enemy HP every EVERY frames and pressing A
        n=int(p[1]); ev=int(p[2]); t=0
        while t<n:
            for k in range(1,2):
                a=0x021075C8+0x24A+k*0x8E8
                if e.s16(a)>0: e.lib.mh_write8(a,0); e.lib.mh_write8(a+1,0)
            e.press(['A'],4); e.run(ev-4); t+=ev
    elif p[0]=='win':   # win:N  - run N frames: enemy HP 1, ours full, press A/Right alternately
        n=int(p[1]); t=0
        while t<n:
            a1=0x021075C8+0x24A+0x8E8; a0=0x021075C8+0x24A
            if e.s16(a1)>1: e.lib.mh_write8(a1,1); e.lib.mh_write8(a1+1,0)
            e.lib.mh_write8(a0,0x68); e.lib.mh_write8(a0+1,0x29)
            e.press([os.environ.get('WB','B')],3); e.run(9); t+=12
    elif p[0]=='hp':
        print('HP', e.frame, [(k, e.u8(0x021075C8+0x1A+k*0x8E8), e.s16(0x021075C8+0x24A+k*0x8E8)) for k in range(8)], hex(e.u32(0x020DE3D0)))
    elif p[0]=='save': e.save_state(p[1])
    elif p[0]=='sheet':
        from PIL import Image
        ims=[Image.open(f'{out}/{n}.png') for n in p[1].split(',')]
        o=Image.new('RGB',(sum(i.width+8 for i in ims),max(i.height for i in ims)),'white'); x=0
        for i in ims: o.paste(i,(x,0)); x+=i.width+8
        o.save(f'{out}/sheet.png')
