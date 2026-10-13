# barcheck.py DIR [Y_TOP] [Y_BOTTOM] -- checks the scrolling MODE SELECT bar in captures DIR/p*.png: along all 256
# columns the bar's top border must be black at row Y_TOP-1, white at Y_TOP, and its bottom border white at
# Y_BOTTOM, black at Y_BOTTOM+1 (full-window rows; mode select: 362 / 379, as in melonDS). Prints bad frames.
import sys, glob
from PIL import Image
import numpy as np
d = sys.argv[1]; yt = int(sys.argv[2]) if len(sys.argv) > 2 else 362; yb = int(sys.argv[3]) if len(sys.argv) > 3 else 379
checks = ((yt - 1, 'k'), (yt, 'w'), (yt + 1, 'd'), (yb - 1, 'd'), (yb, 'w'), (yb + 1, 'k'))
nbad = 0; files = sorted(glob.glob(d + '/p*.png'))
for f in files:
    a = np.asarray(Image.open(f).convert('L')).astype(int)
    bad = [(x, y) for x in range(256) for y, e in checks
           if (e == 'k' and a[y, x] > 60) or (e == 'w' and a[y, x] < 180) or (e == 'd' and a[y, x] > 150)]
    if bad:
        nbad += 1; print(f, len(bad), bad[:6])
print('frames with misplaced border pixels:', nbad, 'of', len(files))
