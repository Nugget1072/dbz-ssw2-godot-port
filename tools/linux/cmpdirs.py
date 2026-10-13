# cmpdirs.py DIR_A DIR_B [v] -- pixel differences between same-named captures p<N>.png of two runs (e.g. two GPUs)
import sys, glob, os
from PIL import Image
import numpy as np
A,B=sys.argv[1],sys.argv[2]
tot=0; nf=0
for f in sorted(glob.glob(A+'/p*.png')):
    g=os.path.join(B,os.path.basename(f))
    if not os.path.exists(g): continue
    a=np.asarray(Image.open(f).convert('RGB')).astype(int); b=np.asarray(Image.open(g).convert('RGB')).astype(int)
    d=(np.abs(a-b).sum(axis=2)>0)
    n=int(d.sum()); tot+=n; nf+=1
    if n and len(sys.argv)>3: ys,xs=np.nonzero(d); print(os.path.basename(f), n, list(zip(xs[:6],ys[:6])))
print('frames',nf,'diff px total',tot)
