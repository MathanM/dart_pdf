import 'dart:typed_data';

import 'package:bidi/bidi.dart' as bidi;

/// An OpenType shaping engine. Input is logical Unicode text, not presentation
/// forms. Implementations must apply script-specific reordering, GSUB and GPOS.
///
/// The optional native implementation is in package:pdf_harfbuzz. Keeping this
/// interface independent of FFI allows other backends (including web) to be used.
abstract class PdfTextShaper {
  const PdfTextShaper();

  PdfGlyphRun shape(ByteData font, String text);

  /// Index-preserving input for a separate bidi ordering pass.
  ///
  /// The legacy bidi engine also normalizes and reshapes letters, which can
  /// change its reported source offsets. Non-composing representatives retain
  /// bidi classes and UTF-16 lengths; brackets and controls stay intact. Never
  /// pass the result to a shaper or use it for painting or Unicode extraction.
  static String bidiIndexText(String text) {
    final result = StringBuffer();
    for (final rune in text.runes) {
      final replacement = switch (bidi.getCharacterType(rune)) {
        bidi.CharacterType.ltr => 0x78, // x
        bidi.CharacterType.rtl => 0x5d0, // Hebrew alef
        bidi.CharacterType.al => 0x627, // Arabic alef (no lam-alef ligature)
        bidi.CharacterType.nonspacingMark => 0x338, // combining overlay
        _ => rune,
      };
      result.writeCharCode(replacement);
      if (rune > 0xffff && replacement <= 0xffff) {
        result.writeCharCode(replacement);
      }
    }
    return result.toString();
  }
}

/// A positioned glyph from the original font, with coordinates in em units.
class PdfShapedGlyph {
  const PdfShapedGlyph({
    required this.glyphId,
    required this.cluster,
    required this.xAdvance,
    this.yAdvance = 0,
    this.xOffset = 0,
    this.yOffset = 0,
  });

  final int glyphId;

  /// UTF-16 offset into the original string. All glyphs in the same shaping
  /// cluster have the same offset, even after reordering or ligature formation.
  final int cluster;
  final double xAdvance;
  final double yAdvance;
  final double xOffset;
  final double yOffset;
}

class PdfGlyphRun {
  PdfGlyphRun({required List<PdfShapedGlyph> glyphs, required List<int> breaks})
    : glyphs = List.unmodifiable(glyphs),
      breaks = List.unmodifiable(breaks);

  final List<PdfShapedGlyph> glyphs;

  /// Ascending UTF-16 offsets at grapheme/shaping cluster boundaries, including
  /// the text's end. Each side MUST be shaped again after a break: OpenType
  /// contextual positioning can change even at a grapheme boundary.
  final List<int> breaks;
}
