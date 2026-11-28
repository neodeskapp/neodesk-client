"""Build NeoDeskMarker.ttf: the font an installed NeoDesk puts on the computer
so the console's support and invite pages can tell that NeoDesk is there.

The font has one empty glyph, "Q", three em wide. A page measures "QQQQ" in
"NeoDesk Marker" with a fallback font; when the width is 12 em, the font
is installed. It draws nothing and no other text can use it by accident.

    python -I make_marker_font.py <out.ttf>
"""
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "NeoDesk Marker"
UPM = 1000
WIDTH = 3000  # three em per Q


def empty():
    return TTGlyphPen(None).glyph()


def main(out):
    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder([".notdef", "Q"])
    fb.setupCharacterMap({ord("Q"): "Q"})
    fb.setupGlyf({".notdef": empty(), "Q": empty()})
    fb.setupHorizontalMetrics({".notdef": (500, 0), "Q": (WIDTH, 0)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable(
        {
            "familyName": FAMILY,
            "styleName": "Regular",
            "uniqueFontIdentifier": "NeoDesk Marker Regular 1.0",
            "fullName": "NeoDesk Marker Regular",
            "psName": "NeoDeskMarker-Regular",
            "version": "Version 1.000",
            "copyright": "NeoDesk. AGPL-3.0.",
        }
    )
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, fsType=0)
    fb.setupPost()
    fb.save(out)


if __name__ == "__main__":
    main(sys.argv[1])
