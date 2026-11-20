"""Build the original, minimal TrueType fixture used by grid_renderer_test.dart."""

from pathlib import Path
import struct


def pack(fmt, *values):
    return struct.pack('>' + fmt, *values)


def glyph(rectangles):
    points = [point for left, bottom, right, top in rectangles
              for point in [(left, bottom), (left, top), (right, top), (right, bottom)]]
    data = pack('hhhhh', len(rectangles), min(x for x, _ in points),
                min(y for _, y in points), max(x for x, _ in points),
                max(y for _, y in points))
    data += pack('H' * len(rectangles), *[4 * i + 3 for i in range(len(rectangles))])
    data += pack('H', 0) + bytes([1] * len(points))
    for axis in (0, 1):
        previous = 0
        for point in points:
            data += pack('h', point[axis] - previous)
            previous = point[axis]
    return data + bytes((-len(data)) % 4)


glyphs = [
    glyph([(100, 200, 900, 800)]),
    glyph([(100, 200, 900, 800)]),
    glyph([(100, 200, 300, 800), (700, 200, 900, 800)]),
    glyph([(200, 200, 600, 800), (1400, 200, 1800, 800)]),
    b'',
    glyph([(100, 200, 1800, 800)]),
    glyph([(-100, 200, 900, 800)]),
]
offsets = [0]
for data in glyphs:
    offsets.append(offsets[-1] + len(data))

mapping = [(0x20, 4), (0x4D, 1), (0x78, 2), (0xE000, 3),
           (0xE001, 5), (0xE002, 6), (0xFFFF, 0)]
codes = [code for code, _ in mapping]
segments = len(mapping)
search = 1 << (segments.bit_length() - 1)
subtable = pack('7H', 4, 16 + 8 * segments, 0, 2 * segments,
                2 * search, search.bit_length() - 1, 2 * (segments - search))
subtable += pack('H' * segments, *codes) + pack('H', 0) + pack('H' * segments, *codes)
subtable += pack('H' * segments, *[(index - code) & 0xFFFF for code, index in mapping])
subtable += bytes(2 * segments)

names = [(1, 'NauvimGridTest'), (2, 'Regular'), (3, 'NauvimGridTest-Regular'),
         (4, 'NauvimGridTest Regular'), (6, 'NauvimGridTest-Regular'),
         (16, 'NauvimGridTest'), (17, 'Regular')]
name_records = b''
name_strings = b''
for name_id, text in names:
    encoded = text.encode('utf-16-be')
    name_records += pack('6H', 3, 1, 0x409, name_id, len(encoded), len(name_strings))
    name_strings += encoded

os2 = pack('Hh3H', 4, 1000, 400, 5, 0) + bytes(22) + bytes(10)
os2 += bytes(16) + b'NAUV' + pack('3H', 0xC0, 0x20, 0xE000)
os2 += pack('3h2H', 1000, 0, 0, 1000, 0) + bytes(8)
os2 += pack('2h3H', 600, 800, 0, 0x20, 1)

tables = {
    b'OS/2': os2,
    b'cmap': pack('HHHHI', 0, 1, 3, 1, 12) + subtable,
    b'glyf': b''.join(glyphs),
    b'head': pack('4I2H2Q4h2H3h', 0x10000, 0x10000, 0, 0x5F0F3CF5, 0,
                  1000, 0, 0, -100, 0, 2000, 1000, 0, 8, 2, 1, 0),
    b'hhea': pack('I3hH11hH', 0x10000, 1000, 0, 0, 2000,
                  -100, -800, 2000, 1, 0, 0, 0, 0, 0, 0, 0, len(glyphs)),
    b'hmtx': b''.join(pack('Hh', advance, bearing) for advance, bearing in
                      [(1000, 100), (1000, 100), (1000, 100), (2000, 200),
                       (1000, 0), (1000, 100), (1000, -100)]),
    b'loca': pack('I' * len(offsets), *offsets),
    b'maxp': pack('I14H', 0x10000, len(glyphs), 8, 2, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0),
    b'name': pack('3H', 0, len(names), 6 + 12 * len(names)) + name_records + name_strings,
    b'post': pack('Ii2h5I', 0x30000, 0, -100, 50, 0, 0, 0, 0, 0),
}


def checksum(data):
    padded = data + bytes((-len(data)) % 4)
    return sum(struct.unpack('>' + 'I' * (len(padded) // 4), padded)) & 0xFFFFFFFF


directory = b''
body = b''
head_offset = 0
for tag, data in sorted(tables.items()):
    offset = 12 + 16 * len(tables) + len(body)
    directory += tag + pack('3I', checksum(data), offset, len(data))
    if tag == b'head':
        head_offset = offset
    body += data + bytes((-len(data)) % 4)
font = bytearray(pack('I4H', 0x10000, len(tables), 128, 3, 32) + directory + body)
struct.pack_into('>I', font, head_offset + 8, (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF)
Path(__file__).with_name('grid_test.ttf').write_bytes(font)
