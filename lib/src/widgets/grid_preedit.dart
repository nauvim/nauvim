import 'package:flutter/widgets.dart' show CharacterRange, TextSelection;

import 'editor_text_input.dart';

/// Local cell allocation for printable grid preedit with default Neovim widths.
///
/// Cell ranges use Flutter's UTF-16 offsets. The host's redraw supplies actual
/// cell assignments after commit.
final class GridPreedit {
  factory GridPreedit(EditorPreedit preedit) {
    final cells = <({String text, int start, int end, int columns})>[];
    final graphemes = CharacterRange(preedit.text);
    var columns = 0;
    var start = 0;
    while (graphemes.moveNext()) {
      final text = graphemes.current;
      final end = start + text.length;
      final width = _columns(text);
      cells.add((text: text, start: start, end: end, columns: width));
      columns += width;
      start = end;
    }
    return GridPreedit._(preedit.text, preedit.selection, cells, columns);
  }

  const GridPreedit._(this.text, this.selection, this.cells, this.columns);

  final String text;
  final TextSelection selection;
  final List<({String text, int start, int end, int columns})> cells;
  final int columns;
}

int _columns(String grapheme) {
  final runes = grapheme.runes.iterator;
  if (!runes.moveNext()) return 1;
  final first = runes.current;
  if (first < 0x80) return 1;
  if (_contains(_doubleWidth, first)) return 2;
  if (runes.moveNext() &&
      runes.current == 0xfe0f &&
      _contains(_emojiPresentationWidth, first)) {
    return 2;
  }
  return 1;
}

bool _contains(List<(int, int)> ranges, int rune) {
  var lo = 0;
  var hi = ranges.length;
  while (lo < hi) {
    final mid = lo + ((hi - lo) ~/ 2);
    final (first, last) = ranges[mid];
    if (rune < first) {
      hi = mid;
    } else if (rune > last) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

// Derived and condensed from JuliaStrings/utf8proc v2.11.3 Unicode 17.0.0
// property data, the utf8proc version pinned by Neovim v0.12.6.
// https://github.com/JuliaStrings/utf8proc/blob/v2.11.3/utf8proc_data.c
//
// Widths combine charwidth == 2 and the default Neovim emoji rule for
// non-ambiguous pictographs and regional indicators from U+1F000.
// https://github.com/neovim/neovim/blob/v0.12.6/src/nvim/mbyte.c#L425-L493

const _doubleWidth = [
  (0x1100, 0x115f),
  (0x231a, 0x231b),
  (0x2329, 0x232a),
  (0x23e9, 0x23ec),
  (0x23f0, 0x23f0),
  (0x23f3, 0x23f3),
  (0x25fd, 0x25fe),
  (0x2614, 0x2615),
  (0x2630, 0x2637),
  (0x2648, 0x2653),
  (0x267f, 0x267f),
  (0x268a, 0x268f),
  (0x2693, 0x2693),
  (0x26a1, 0x26a1),
  (0x26aa, 0x26ab),
  (0x26bd, 0x26be),
  (0x26c4, 0x26c5),
  (0x26ce, 0x26ce),
  (0x26d4, 0x26d4),
  (0x26ea, 0x26ea),
  (0x26f2, 0x26f3),
  (0x26f5, 0x26f5),
  (0x26fa, 0x26fa),
  (0x26fd, 0x26fd),
  (0x2705, 0x2705),
  (0x270a, 0x270b),
  (0x2728, 0x2728),
  (0x274c, 0x274c),
  (0x274e, 0x274e),
  (0x2753, 0x2755),
  (0x2757, 0x2757),
  (0x2795, 0x2797),
  (0x27b0, 0x27b0),
  (0x27bf, 0x27bf),
  (0x2b1b, 0x2b1c),
  (0x2b50, 0x2b50),
  (0x2b55, 0x2b55),
  (0x2e80, 0x2e99),
  (0x2e9b, 0x2ef3),
  (0x2f00, 0x2fd5),
  (0x2ff0, 0x3029),
  (0x302e, 0x303e),
  (0x3041, 0x3096),
  (0x309b, 0x30ff),
  (0x3105, 0x312f),
  (0x3131, 0x318e),
  (0x3190, 0x31e5),
  (0x31ef, 0x321e),
  (0x3220, 0x3247),
  (0x3250, 0xa48c),
  (0xa490, 0xa4c6),
  (0xa960, 0xa97c),
  (0xac00, 0xd7a3),
  (0xf900, 0xfa6d),
  (0xfa70, 0xfad9),
  (0xfe10, 0xfe19),
  (0xfe30, 0xfe52),
  (0xfe54, 0xfe66),
  (0xfe68, 0xfe6b),
  (0xff01, 0xff60),
  (0xffe0, 0xffe6),
  (0x16fe0, 0x16fe3),
  (0x16ff0, 0x16ff6),
  (0x17000, 0x18cd5),
  (0x18cff, 0x18d1e),
  (0x18d80, 0x18df2),
  (0x1aff0, 0x1aff3),
  (0x1aff5, 0x1affb),
  (0x1affd, 0x1affe),
  (0x1b000, 0x1b122),
  (0x1b132, 0x1b132),
  (0x1b150, 0x1b152),
  (0x1b155, 0x1b155),
  (0x1b164, 0x1b167),
  (0x1b170, 0x1b2fb),
  (0x1d300, 0x1d356),
  (0x1d360, 0x1d376),
  (0x1f004, 0x1f004),
  (0x1f0cf, 0x1f0cf),
  (0x1f18e, 0x1f18e),
  (0x1f191, 0x1f19a),
  (0x1f1e6, 0x1f202),
  (0x1f210, 0x1f23b),
  (0x1f240, 0x1f248),
  (0x1f250, 0x1f251),
  (0x1f260, 0x1f265),
  (0x1f300, 0x1f321),
  (0x1f324, 0x1f393),
  (0x1f396, 0x1f397),
  (0x1f399, 0x1f39b),
  (0x1f39e, 0x1f3f0),
  (0x1f3f3, 0x1f3f5),
  (0x1f3f7, 0x1f4fd),
  (0x1f4ff, 0x1f53d),
  (0x1f549, 0x1f54e),
  (0x1f550, 0x1f567),
  (0x1f56f, 0x1f570),
  (0x1f573, 0x1f57a),
  (0x1f587, 0x1f587),
  (0x1f58a, 0x1f58d),
  (0x1f590, 0x1f590),
  (0x1f595, 0x1f596),
  (0x1f5a4, 0x1f5a5),
  (0x1f5a8, 0x1f5a8),
  (0x1f5b1, 0x1f5b2),
  (0x1f5bc, 0x1f5bc),
  (0x1f5c2, 0x1f5c4),
  (0x1f5d1, 0x1f5d3),
  (0x1f5dc, 0x1f5de),
  (0x1f5e1, 0x1f5e1),
  (0x1f5e3, 0x1f5e3),
  (0x1f5e8, 0x1f5e8),
  (0x1f5ef, 0x1f5ef),
  (0x1f5f3, 0x1f5f3),
  (0x1f5fa, 0x1f64f),
  (0x1f680, 0x1f6c5),
  (0x1f6cb, 0x1f6d2),
  (0x1f6d5, 0x1f6d8),
  (0x1f6dc, 0x1f6e5),
  (0x1f6e9, 0x1f6e9),
  (0x1f6eb, 0x1f6ec),
  (0x1f6f0, 0x1f6f0),
  (0x1f6f3, 0x1f6fc),
  (0x1f7e0, 0x1f7eb),
  (0x1f7f0, 0x1f7f0),
  (0x1f90c, 0x1f93a),
  (0x1f93c, 0x1f945),
  (0x1f947, 0x1f9ff),
  (0x1fa70, 0x1fa7c),
  (0x1fa80, 0x1fa8a),
  (0x1fa8e, 0x1fac6),
  (0x1fac8, 0x1fac8),
  (0x1facd, 0x1fadc),
  (0x1fadf, 0x1faea),
  (0x1faef, 0x1faf8),
  (0x20000, 0x2a6df),
  (0x2a700, 0x2b81d),
  (0x2b820, 0x2cead),
  (0x2ceb0, 0x2ebe0),
  (0x2ebf0, 0x2ee5d),
  (0x2f800, 0x2fa1d),
  (0x30000, 0x3134a),
  (0x31350, 0x33479),
];

// Pictographs and regional indicators that become wide with an immediately
// following U+FE0F. Already-wide characters are in _doubleWidth.
const _emojiPresentationWidth = [
  (0xa9, 0xa9),
  (0xae, 0xae),
  (0x203c, 0x203c),
  (0x2049, 0x2049),
  (0x2122, 0x2122),
  (0x2139, 0x2139),
  (0x2194, 0x2199),
  (0x21a9, 0x21aa),
  (0x2328, 0x2328),
  (0x23cf, 0x23cf),
  (0x23ed, 0x23ef),
  (0x23f1, 0x23f2),
  (0x23f8, 0x23fa),
  (0x24c2, 0x24c2),
  (0x25aa, 0x25ab),
  (0x25b6, 0x25b6),
  (0x25c0, 0x25c0),
  (0x25fb, 0x25fc),
  (0x2600, 0x2604),
  (0x260e, 0x260e),
  (0x2611, 0x2611),
  (0x2618, 0x2618),
  (0x261d, 0x261d),
  (0x2620, 0x2620),
  (0x2622, 0x2623),
  (0x2626, 0x2626),
  (0x262a, 0x262a),
  (0x262e, 0x262f),
  (0x2638, 0x263a),
  (0x2640, 0x2640),
  (0x2642, 0x2642),
  (0x265f, 0x2660),
  (0x2663, 0x2663),
  (0x2665, 0x2666),
  (0x2668, 0x2668),
  (0x267b, 0x267b),
  (0x267e, 0x267e),
  (0x2692, 0x2692),
  (0x2694, 0x2697),
  (0x2699, 0x2699),
  (0x269b, 0x269c),
  (0x26a0, 0x26a0),
  (0x26a7, 0x26a7),
  (0x26b0, 0x26b1),
  (0x26c8, 0x26c8),
  (0x26cf, 0x26cf),
  (0x26d1, 0x26d1),
  (0x26d3, 0x26d3),
  (0x26e9, 0x26e9),
  (0x26f0, 0x26f1),
  (0x26f4, 0x26f4),
  (0x26f7, 0x26f9),
  (0x2702, 0x2702),
  (0x2708, 0x2709),
  (0x270c, 0x270d),
  (0x270f, 0x270f),
  (0x2712, 0x2712),
  (0x2714, 0x2714),
  (0x2716, 0x2716),
  (0x271d, 0x271d),
  (0x2721, 0x2721),
  (0x2733, 0x2734),
  (0x2744, 0x2744),
  (0x2747, 0x2747),
  (0x2763, 0x2764),
  (0x27a1, 0x27a1),
  (0x2934, 0x2935),
  (0x2b05, 0x2b07),
  (0x1f170, 0x1f171),
  (0x1f17e, 0x1f17f),
];

// utf8proc and Unicode data notices
//
// Copyright (c) 2014-2021 Steven G. Johnson, Jiahao Chen, Peter Colberg,
// Tony Kelman, Scott P. Jones, Jonas Fonseca, and other contributors.
// Copyright (c) 2009, 2013 Public Software Group e. V., Berlin, Germany.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
// COPYRIGHT AND PERMISSION NOTICE
//
// Copyright (c) 1991-2007 Unicode, Inc. All rights reserved. Distributed
// under the Terms of Use in http://www.unicode.org/copyright.html.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of the Unicode data files and any associated documentation (the "Data
// Files") or Unicode software and any associated documentation (the
// "Software") to deal in the Data Files or Software without restriction,
// including without limitation the rights to use, copy, modify, merge,
// publish, distribute, and/or sell copies of the Data Files or Software, and
// to permit persons to whom the Data Files or Software are furnished to do
// so, provided that (a) the above copyright notice(s) and this permission
// notice appear with all copies of the Data Files or Software, (b) both the
// above copyright notice(s) and this permission notice appear in associated
// documentation, and (c) there is clear notice in each modified Data File or
// in the Software as well as in the documentation associated with the Data
// File(s) or Software that the data or software has been modified.
//
// THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
// KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
// THIRD PARTY RIGHTS. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS
// INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR
// CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
// USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
// TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THE DATA FILES OR SOFTWARE.
//
// Except as contained in this notice, the name of a copyright holder shall
// not be used in advertising or otherwise to promote the sale, use or other
// dealings in these Data Files or Software without prior written
// authorization of the copyright holder.
//
// Unicode and the Unicode logo are trademarks of Unicode, Inc., and may be
// registered in some jurisdictions. All other trademarks and registered
// trademarks mentioned herein are the property of their respective owners.
