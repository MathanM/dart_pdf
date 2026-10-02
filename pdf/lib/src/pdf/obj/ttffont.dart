/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../document.dart';
import '../font/arabic.dart' as arabic;
import '../font/bidi_utils.dart' as bidi;
import '../font/font_metrics.dart';
import '../font/text_shaper.dart';
import '../font/ttf_parser.dart';
import '../font/ttf_writer.dart';
import '../format/array.dart';
import '../format/dict.dart';
import '../format/name.dart';
import '../format/num.dart';
import '../format/stream.dart';
import '../format/string.dart';
import '../options.dart';
import 'font.dart';
import 'font_descriptor.dart';
import 'object.dart';
import 'object_stream.dart';
import 'unicode_cmap.dart';

class PdfTtfFont extends PdfFont {
  /// Constructs a [PdfTtfFont]
  PdfTtfFont(
    PdfDocument pdfDocument,
    ByteData bytes, {
    bool protect = false,
    this.shaper,
  }) : font = TtfParser(bytes),
       super.create(pdfDocument, subtype: '/TrueType') {
    file = PdfObjectStream(pdfDocument, isBinary: true);
    unicodeCMap = PdfUnicodeCmap(pdfDocument, protect);
    descriptor = PdfFontDescriptor(this, file);
    widthsObject = PdfObject<PdfArray>(pdfDocument, params: PdfArray());
    if (shaper != null && (!font.unicode || font.glyphOffsets.isEmpty)) {
      throw UnsupportedError(
        'OpenType shaping requires Unicode TrueType outlines (glyf/loca)',
      );
    }
  }

  @override
  String get subtype => font.unicode ? '/Type0' : super.subtype;

  late PdfUnicodeCmap unicodeCMap;

  late PdfFontDescriptor descriptor;

  late PdfObjectStream file;

  late PdfObject<PdfArray> widthsObject;

  final TtfParser font;

  final PdfTextShaper? shaper;
  final _runs = <String, PdfGlyphRun>{};
  final _glyphIds = <int>[0];
  final _glyphCids = <(int, String), int>{};

  /// Shape once for both layout and painting. A bounded cache avoids retaining
  /// every string in large documents.
  PdfGlyphRun shape(String text) {
    final cached = _runs.remove(text);
    if (cached != null) {
      _runs[text] = cached;
      return cached;
    }
    final run = shaper!.shape(font.bytes, text);
    for (final glyph in run.glyphs) {
      if (glyph.glyphId < 0 ||
          glyph.glyphId >= font.glyphOffsets.length ||
          glyph.cluster < 0 ||
          glyph.cluster >= text.length ||
          !glyph.xAdvance.isFinite ||
          !glyph.yAdvance.isFinite ||
          !glyph.xOffset.isFinite ||
          !glyph.yOffset.isFinite) {
        throw StateError('Invalid OpenType glyph in font $fontName');
      }
    }
    if (_runs.length >= 256) {
      _runs.remove(_runs.keys.first);
    }
    _runs[text] = run;
    return run;
  }

  /// Register a shaped glyph independently of the font's Unicode cmap.
  int registerGlyph(int glyphId, String unicode) {
    return _glyphCids.putIfAbsent((glyphId, unicode), () {
      if (_glyphIds.length >= 65535) {
        throw StateError('PDF font exceeds 65535 CIDs');
      }
      final cid = _glyphIds.length;
      _glyphIds.add(glyphId);
      unicodeCMap.cmap.add(0);
      unicodeCMap.unicode[cid] = unicode;
      return cid;
    });
  }

  PdfFontMetrics _shapedMetrics(String text, double letterSpacing) {
    final glyphs = shape(text).glyphs;
    if (glyphs.isEmpty) {
      return PdfFontMetrics.zero;
    }
    var x = 0.0;
    var y = 0.0;
    var left = double.infinity;
    var right = double.negativeInfinity;
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (var i = 0; i < glyphs.length; i++) {
      final glyph = glyphs[i];
      final metric = font.glyphInfoMap[glyph.glyphId]!;
      left = math.min(left, x + glyph.xOffset + metric.left);
      right = math.max(right, x + glyph.xOffset + metric.right);
      top = math.min(top, y + glyph.yOffset + metric.top);
      bottom = math.max(bottom, y + glyph.yOffset + metric.bottom);
      x += glyph.xAdvance;
      y += glyph.yAdvance;
      if (i + 1 < glyphs.length && glyph.cluster != glyphs[i + 1].cluster) {
        x += letterSpacing;
      }
    }
    return PdfFontMetrics(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      ascent: math.max(ascent, bottom),
      descent: math.min(descent, top),
      advanceWidth: x,
      leftBearing: left,
    );
  }

  @override
  String get fontName => font.fontName;

  @override
  double get ascent => font.ascent.toDouble() / font.unitsPerEm;

  @override
  double get descent => font.descent.toDouble() / font.unitsPerEm;

  @override
  int get unitsPerEm => font.unitsPerEm;

  @override
  PdfFontMetrics glyphMetrics(int charCode) {
    final g = font.charToGlyphIndexMap[charCode];

    if (g == null) {
      return PdfFontMetrics.zero;
    }

    if (useBidi && bidi.isArabicDiacriticValue(charCode)) {
      final metric = font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
      return metric.copyWith(advanceWidth: 0);
    }

    if (useArabic && arabic.isArabicDiacriticValue(charCode)) {
      final metric = font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
      return metric.copyWith(advanceWidth: 0);
    }

    return font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
  }

  void _buildTrueType(PdfDict params) {
    int charMin;
    int charMax;

    file.buf.putBytes(font.bytes.buffer.asUint8List());
    file.params['/Length1'] = PdfNum(font.bytes.lengthInBytes);

    params['/BaseFont'] = PdfName('/$fontName');
    params['/FontDescriptor'] = descriptor.ref();
    charMin = 32;
    charMax = 255;
    for (var i = charMin; i <= charMax; i++) {
      widthsObject.params.add(
        PdfNum((glyphMetrics(i).advanceWidth * 1000.0).toInt()),
      );
    }
    params['/FirstChar'] = PdfNum(charMin);
    params['/LastChar'] = PdfNum(charMax);
    params['/Widths'] = widthsObject.ref();
  }

  void _buildType0(PdfDict params) {
    int charMin;
    int charMax;

    final ttfWriter = TtfWriter(font);
    final data = shaper == null
        ? ttfWriter.withChars(unicodeCMap.cmap)
        : ttfWriter.withGlyphs(_glyphIds);
    file.buf.putBytes(data);
    file.params['/Length1'] = PdfNum(data.length);

    final descendantFont = PdfDict.values({
      '/Type': const PdfName('/Font'),
      '/BaseFont': PdfName('/$fontName'),
      '/FontFile2': file.ref(),
      '/FontDescriptor': descriptor.ref(),
      '/W': PdfArray([const PdfNum(0), widthsObject.ref()]),
      '/CIDToGIDMap': const PdfName('/Identity'),
      '/DW': const PdfNum(1000),
      '/Subtype': const PdfName('/CIDFontType2'),
      '/CIDSystemInfo': PdfDict.values({
        '/Supplement': const PdfNum(0),
        '/Registry': PdfString.fromString('Adobe'),
        '/Ordering': PdfString.fromString('Identity-H'),
      }),
    });

    params['/BaseFont'] = PdfName('/$fontName');
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/DescendantFonts'] = PdfArray([descendantFont]);
    params['/ToUnicode'] = unicodeCMap.ref();

    charMin = 0;
    charMax = unicodeCMap.cmap.length - 1;
    for (var i = charMin; i <= charMax; i++) {
      widthsObject.params.add(
        PdfNum(
          ((shaper == null
                          ? glyphMetrics(unicodeCMap.cmap[i])
                          : font.glyphInfoMap[_glyphIds[i]]!)
                      .advanceWidth *
                  1000.0)
              .toInt(),
        ),
      );
    }
  }

  @override
  void prepare() {
    super.prepare();

    if (font.unicode) {
      _buildType0(params);
    } else {
      _buildTrueType(params);
    }
  }

  @override
  void putText(PdfStream stream, String text) {
    if (shaper != null) {
      throw StateError(
        'Shaped text must be painted with PdfGraphics.drawString',
      );
    }
    if (!font.unicode) {
      super.putText(stream, text);
      return;
    }

    final runes = text.runes;

    stream.putByte(0x3c);
    for (final rune in runes) {
      var char = unicodeCMap.cmap.indexOf(rune);
      if (char == -1) {
        char = unicodeCMap.cmap.length;
        unicodeCMap.cmap.add(rune);
      }

      stream.putBytes(latin1.encode(char.toRadixString(16).padLeft(4, '0')));
    }
    stream.putByte(0x3e);
  }

  @override
  PdfFontMetrics stringMetrics(String s, {double letterSpacing = 0}) {
    if (shaper != null) {
      return _shapedMetrics(s, letterSpacing);
    }
    if (s.isEmpty || !font.unicode) {
      return super.stringMetrics(s, letterSpacing: letterSpacing);
    }

    final runes = s.runes;
    final bytes = <int>[];
    runes.forEach(bytes.add);

    final metrics = bytes.map(glyphMetrics);
    return PdfFontMetrics.append(metrics, letterSpacing: letterSpacing);
  }

  @override
  bool isRuneSupported(int charCode) {
    // Join controls affect shaping even though they have no visible outline.
    if (shaper != null && (charCode == 0x200c || charCode == 0x200d)) {
      return true;
    }
    return font.charToGlyphIndexMap.containsKey(charCode);
  }
}
