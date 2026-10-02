import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:test/test.dart';

void main() {
  test('missing Arabic marks subset to .notdef, never an unrelated glyph', () {
    final font = TtfParser(
      File('hacen-tunisia.ttf').readAsBytesSync().buffer.asByteData(),
    );
    // Hacen Tunisia has precomposed Arabic letters but no standalone hamzas.
    // Legacy bidi decomposition can introduce these characters. Both CIDs
    // must retain the source .notdef outline even when glyph zero repeats.
    expect(font.charToGlyphIndexMap[0x654], isNull);
    expect(font.charToGlyphIndexMap[0x655], isNull);
    final subset = TtfParser(
      TtfWriter(font).withChars([0, 0x655, 0x654]).buffer.asByteData(),
    );
    for (var cid = 0; cid < 3; cid++) {
      expect(subset.readGlyph(cid).data, font.readGlyph(0).data);
      expect(
        subset.glyphInfoMap[cid]!.advanceWidth,
        font.glyphInfoMap[0]!.advanceWidth,
      );
    }
  });
}
