import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngpixels import pixels

first, second, rows_to_compare = pixels(sys.argv[1]), pixels(sys.argv[2]), int(sys.argv[3])
columns = int(sys.argv[4]) if len(sys.argv) > 4 else None
if first[0] != second[0]:
    print("different width")
    sys.exit(0)
bpp = first[2]
different = 0
for row_a, row_b in zip(first[3][:rows_to_compare], second[3][:rows_to_compare]):
    for x in range(0, (columns * bpp) if columns else len(row_a), bpp):
        if max(abs(row_a[x + i] - row_b[x + i]) for i in range(min(bpp, 3))) > 12:
            different += 1
print("same" if different == 0 else f"{different} pixels differ")
