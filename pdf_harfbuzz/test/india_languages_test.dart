import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:test/test.dart';

void main() {
  final languages = (jsonDecode(
    File('test/data/india_languages.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final manifest = jsonDecode(
    File('fonts/noto/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  ByteData bytesFor(Map<String, dynamic> language) {
    final entry = (manifest['fonts'] as List).singleWhere(
      (f) => f['folder'] == language['folder'],
    );
    return File('fonts/noto/${entry['folder']}/${entry['filename']}')
        .readAsBytesSync()
        .buffer
        .asByteData();
  }

  for (final language in languages) {
    group(language['name'], () {
      final bytes = bytesFor(language);
      final shaper = HarfBuzzTextShaper(language: language['code']);
      test('covers all sample, conjunct, vowel and localized-letter glyphs', () {
        final text =
            '${language['nativeName']} ${language['sample']} ${language['stress']}';
        final run = shaper.shape(bytes, text);
        expect(run.glyphs, isNotEmpty);
        expect(run.glyphs.where((g) => g.glyphId == 0), isEmpty);
        expect(
          run.glyphs.every(
            (g) =>
                g.xAdvance.isFinite && g.xOffset.isFinite && g.yOffset.isFinite,
          ),
          isTrue,
        );
        expect(run.breaks.last, text.length);
        final font = PdfTtfFont(PdfDocument(), bytes, shaper: shaper);
        expect(
          font.stringMetrics(text).advanceWidth,
          closeTo(run.glyphs.fold(0.0, (x, g) => x + g.xAdvance), 1e-9),
        );
      });
      test('embeds every substituted glyph without corrupting outlines', () {
        final parser = TtfParser(bytes);
        final run = shaper.shape(bytes, language['stress']);
        final ids = [0, ...run.glyphs.map((g) => g.glyphId)];
        final subset = TtfParser(
          TtfWriter(parser).withGlyphs(ids).buffer.asByteData(),
        );
        for (var i = 0; i < ids.length; i++) {
          expect(
            subset.glyphInfoMap[i]!.advanceWidth,
            parser.glyphInfoMap[ids[i]]!.advanceWidth,
          );
          if (parser.readGlyph(ids[i]).compounds.isEmpty) {
            expect(subset.readGlyph(i).data, parser.readGlyph(ids[i]).data);
          }
        }
      });
      test('ordinary Text wraps and preserves logical Unicode', () async {
        final document = pw.Document(compress: false);
        document.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(180, 1200),
            margin: const pw.EdgeInsets.all(12),
            build: (_) => pw.Text(
              language['sample'],
              textDirection: language['direction'] == 'rtl'
                  ? pw.TextDirection.rtl
                  : pw.TextDirection.ltr,
              style: pw.TextStyle(
                font: pw.Font.ttf(bytes, shaper: shaper),
                fontSize: 20,
              ),
            ),
          ),
        );
        final pdf = latin1.decode(await document.save());
        final words = actualTexts(pdf);
        // Long words may wrap between clusters; compare the logical characters
        // independently of the whitespace introduced at physical line breaks.
        expect(
          words.join().replaceAll(RegExp(r'\s'), ''),
          (language['sample'] as String).replaceAll(RegExp(r'\s'), ''),
        );
        expect(pdf, contains('/CIDFontType2'));
        expect(pdf, isNot(contains('/Subtype /Image')));
        final matrices = RegExp(r'1 0 0 1 [-0-9.]+ ([-0-9.]+) Tm')
            .allMatches(pdf);
        expect(matrices.map((m) => m[1]).toSet().length, greaterThan(1));
      });
    });
  }
  final urdu = bytesFor(languages.singleWhere((l) => l['code'] == 'ur'));
  const shaper = HarfBuzzTextShaper(language: 'ur');
  test(
    'Urdu uses joining, descending clusters and GPOS Nastaliq placement',
    () {
      final run = shaper.shape(urdu, 'پاکستان');
      expect(run.glyphs.first.cluster, greaterThan(run.glyphs.last.cluster));
      expect(run.glyphs.any((g) => g.yOffset != 0), isTrue);
      final parser = TtfParser(urdu);
      expect(
        run.glyphs.any(
          (g) => !parser.charToGlyphIndexMap.values.contains(g.glyphId),
        ),
        isTrue,
      );
    },
  );
  for (final digits in ['123', '۲۰۲۶', '١٢٣']) {
    test('Urdu preserves numeric order: $digits', () {
      final alone = shaper.shape(urdu, digits).glyphs;
      expect(
        alone.map((g) => g.cluster),
        orderedEquals(alone.map((g) => g.cluster).toList()..sort()),
      );
      final text = 'سال $digits میں';
      final start = text.indexOf(digits);
      final mixed = shaper
          .shape(urdu, text)
          .glyphs
          .where(
            (g) => g.cluster >= start && g.cluster < start + digits.length,
          );
      expect(mixed.map((g) => g.glyphId), alone.map((g) => g.glyphId));
    });
  }
  test('Urdu bypasses legacy Arabic conversion in the widget layer', () async {
    final recorder = _RecordingShaper();
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Text(
          'اردو زبان',
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: pw.Font.ttf(urdu, shaper: recorder)),
        ),
      ),
    );
    await document.save();
    expect(recorder.texts, containsAll(['اردو', 'زبان']));
    expect(
      recorder.texts.any((s) => s.runes.any((r) => r >= 0xfb50 && r <= 0xfeff)),
      isFalse,
    );
  });
}

List<String> actualTexts(String pdf) =>
    RegExp(r'/ActualText <feff([0-9a-f]+)>').allMatches(pdf).map((m) {
      final hex = m[1]!;
      return String.fromCharCodes([
        for (var i = 0; i < hex.length; i += 4)
          int.parse(hex.substring(i, i + 4), radix: 16),
      ]);
    }).toList();

class _RecordingShaper extends PdfTextShaper {
  final texts = <String>[];
  @override
  PdfGlyphRun shape(ByteData font, String text) {
    texts.add(text);
    return const HarfBuzzTextShaper(language: 'ur').shape(font, text);
  }
}
