import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngpixels import pixels


first, second = pixels(sys.argv[1]), pixels(sys.argv[2])
if first[:3] != second[:3]:
    print(0)
    sys.exit(0)
bpp = first[2]
different = 0
for row_a, row_b in zip(first[3], second[3]):
    if row_a != row_b:
        for x in range(0, len(row_a), bpp):
            if row_a[x:x + bpp] != row_b[x:x + bpp]:
                different += 1
print(different)
