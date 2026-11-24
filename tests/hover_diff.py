import struct
import sys
import zlib


def pixels(path):
    data = open(path, "rb").read()
    position, idat, width, height, color = 8, b"", 0, 0, 0
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        body = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            width, height, _, color = struct.unpack(">IIBB", body[:10])
        if kind == b"IDAT":
            idat += body
        position += 12 + length
    raw = zlib.decompress(idat)
    bpp = {2: 3, 6: 4}[color]
    stride = width * bpp
    rows, previous, offset = [], bytearray(stride), 0
    for _ in range(height):
        filter_type = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = previous[x]
            c = previous[x - bpp] if x >= bpp else 0
            if filter_type == 1:
                line[x] = (line[x] + a) & 255
            elif filter_type == 2:
                line[x] = (line[x] + b) & 255
            elif filter_type == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif filter_type == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                predictor = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + predictor) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, bpp, rows


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
