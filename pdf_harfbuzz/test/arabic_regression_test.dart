import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi_bindings.dart' as hb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:test/test.dart';

import 'india_languages_test.dart' show actualTexts;

ByteData regressionFont(String folder) {
  final manifest = jsonDecode(
    File('fonts/regression/manifest.json').readAsStringSync(),
  );
  final entry = (manifest['fonts'] as List).singleWhere(
    (f) => f['folder'] == folder,
  );
  return File('fonts/regression/$folder/${entry['filename']}')
      .readAsBytesSync()
      .buffer
      .asByteData();
}

void main() {
  final languages = (jsonDecode(
    File('test/data/regression_languages.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  for (final language in languages) {
    test(
      '${language['name']} covers glyphs and preserves PDF Unicode',
      () async {
        final bytes = regressionFont(language['folder']);
        final text = '${language['sample']} ${language['stress']}';
        final shaper = HarfBuzzTextShaper(language: language['code']);
        final run = shaper.shape(bytes, text);
        expect(run.glyphs, isNotEmpty);
        expect(run.glyphs.where((g) => g.glyphId == 0), isEmpty);
        expect(run.breaks.last, text.length);
        final document = pw.Document(compress: false);
        document.addPage(
          pw.Page(
            build: (_) => pw.Text(
              text,
              textDirection: language['direction'] == 'rtl'
                  ? pw.TextDirection.rtl
                  : pw.TextDirection.ltr,
              style: pw.TextStyle(
                font: pw.Font.ttf(bytes, shaper: shaper),
                fontSize: 18,
              ),
            ),
          ),
        );
        final pdf = latin1.decode(await document.save());
        expect(
          actualTexts(pdf).join().replaceAll(RegExp(r'\s'), ''),
          text.replaceAll(RegExp(r'\s'), ''),
        );
        expect(RegExp(r'/Subtype\s*/Image').hasMatch(pdf), isFalse);
      },
    );
  }
  final arabic = regressionFont('notonaskharabic');
  for (final word in [
    'السلام',
    'السَّلَامُ',
    'لا',
    'لأ',
    'لإ',
    'لآ',
    'الـــسَلاْمُ',
    'بـب',
    'ب\u200dب',
    'ب\u200cب',
    'می‌روم',
    'إِنْسَانَ',
    'اللّٰهُ',
  ]) {
    test('Arabic joining and GPOS match HarfBuzz for $word', () {
      final actual = const HarfBuzzTextShaper(language: 'ar')
          .shape(arabic, word);
      expect(actual.glyphs.where((g) => g.glyphId == 0), isEmpty);
      expect(glyphData(actual), directArabicShape(arabic, word));
    });
  }
  for (final digits in ['123', '١٢٣', '۱۲۳', '12.50']) {
    test('Arabic preserves numbers and mirrored parentheses: $digits', () {
      final text = 'السعر ($digits) ريال';
      final run = const HarfBuzzTextShaper(language: 'ar').shape(arabic, text);
      final start = text.indexOf(digits);
      final numberClusters = run.glyphs
          .where((g) => g.cluster >= start && g.cluster < start + digits.length)
          .map((g) => g.cluster)
          .toList();
      expect(numberClusters, orderedEquals([...numberClusters]..sort()));
      final parser = TtfParser(arabic);
      expect(
        run.glyphs.singleWhere((g) => g.cluster == text.indexOf('(')).glyphId,
        parser.charToGlyphIndexMap[')'.codeUnitAt(0)],
      );
      expect(
        run.glyphs.singleWhere((g) => g.cluster == text.indexOf(')')).glyphId,
        parser.charToGlyphIndexMap['('.codeUnitAt(0)],
      );
    });
  }
  test('accented Latin inside Arabic retains original source clusters', () {
    const shaper = HarfBuzzTextShaper(language: 'ar');
    const text = 'العربي café résumé العربي';
    final run = shaper.shape(arabic, text);
    for (final word in ['café', 'résumé']) {
      final start = text.indexOf(word);
      final actual = run.glyphs.where(
        (g) => g.cluster >= start && g.cluster < start + word.length,
      );
      final expected = shaper.shape(arabic, word).glyphs;
      expect(actual.map((g) => g.glyphId), expected.map((g) => g.glyphId));
      expect(
        actual.map((g) => g.cluster - start),
        expected.map((g) => g.cluster),
      );
    }
  });
  for (final alignment in [pw.TextAlign.start, pw.TextAlign.justify]) {
    for (final width in [550.0, 200.0]) {
      test(
        'RTL keeps English words in order at width $width / $alignment',
        () async {
          const source = 'ترتيب Right Order في النص العربي مرحبا بكم';
          final document = pw.Document(compress: false);
          document.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(width, 800),
              margin: const pw.EdgeInsets.all(12),
              build: (_) => pw.Text(
                source,
                textDirection: pw.TextDirection.rtl,
                textAlign: alignment,
                style: pw.TextStyle(
                  font: pw.Font.ttf(
                    arabic,
                    shaper: const HarfBuzzTextShaper(language: 'ar'),
                  ),
                  fontSize: 20,
                ),
              ),
            ),
          );
          final pdf = latin1.decode(await document.save());
          final words = positionedWords(pdf);
          final right = words.singleWhere((w) => w.$1 == 'Right');
          final order = words.singleWhere((w) => w.$1 == 'Order');
          // When wrapped onto different lines, the first logical word must be
          // on the earlier (higher PDF y) line. On one line, English is LTR.
          if ((right.$3 - order.$3).abs() < 0.1) {
            expect(right.$2, lessThan(order.$2));
          } else {
            expect(right.$3, greaterThan(order.$3));
          }
          expect(actualTexts(pdf).join(' '), source);
        },
      );
    }
  }
  test('CJK shaping and emoji fallback remain available together', () async {
    final cjk = File('../pdf/genyomintw.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData();
    final emoji = File('../pdf/emoji.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData();
    const text = '你好，世界！こんにちは世界。';
    final run = const HarfBuzzTextShaper().shape(cjk, text);
    expect(run.glyphs.where((g) => g.glyphId == 0), isEmpty);
    final document = pw.Document(compress: false);
    document.addPage(
      pw.Page(
        build: (_) => pw.Text(
          'Hello $text 💃🏃',
          style: pw.TextStyle(
            font: pw.Font.ttf(
              regressionFont('notosans'),
              shaper: const HarfBuzzTextShaper(),
            ),
            fontFallback: [
              pw.Font.ttf(cjk, shaper: const HarfBuzzTextShaper()),
              pw.Font.ttf(emoji),
            ],
          ),
        ),
      ),
    );
    final pdf = latin1.decode(await document.save());
    expect(actualTexts(pdf).join(' '), contains(text));
    expect(
      RegExp(r'/Subtype\s*/Image').allMatches(pdf).length,
      greaterThanOrEqualTo(2),
    );
  });
  test('RTL link decoration encloses visually reordered words', () async {
    final document = pw.Document(compress: false);
    document.addPage(
      pw.Page(
        build: (_) => pw.RichText(
          textDirection: pw.TextDirection.rtl,
          text: pw.TextSpan(
            text: 'العربي Right Order العربي',
            annotation: pw.AnnotationUrl('https://example.com'),
            style: pw.TextStyle(
              font: pw.Font.ttf(arabic, shaper: const HarfBuzzTextShaper()),
              fontSize: 20,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
    final pdf = latin1.decode(await document.save());
    final rect = RegExp(r'/Rect\s*\[([-.0-9 ]+)\]').firstMatch(pdf)!;
    final coords = rect[1]!
        .trim()
        .split(RegExp(r'\s+'))
        .map(double.parse)
        .toList();
    expect(coords[2] - coords[0], greaterThan(100));
    expect(coords[3], greaterThan(coords[1]));
    for (final word in positionedWords(pdf)) {
      expect(word.$2, greaterThanOrEqualTo(coords[0] - 1));
      expect(word.$2, lessThanOrEqualTo(coords[2] + 1));
    }
  });
}

List<(String, double, double)> positionedWords(String pdf) =>
    RegExp(
      r'/Span << /ActualText <feff([0-9a-f]+)> >> BDC (.*?)EMC',
      dotAll: true,
    ).allMatches(pdf).map((match) {
      final word = actualTexts(match[0]!).single;
      final matrix = RegExp(r'1 0 0 1 ([-0-9.]+) ([-0-9.]+) Tm')
          .firstMatch(match[2]!)!;
      return (word, double.parse(matrix[1]!), double.parse(matrix[2]!));
    }).toList();

List<List<num>> glyphData(PdfGlyphRun run) => run.glyphs
    .map(
      (g) => <num>[
        g.glyphId,
        g.cluster,
        g.xAdvance,
        g.yAdvance,
        g.xOffset,
        g.yOffset,
      ],
    )
    .toList();

// Independent oracle: shape a complete logical Arabic word in one native
// buffer, with no script itemization, bidi conversion, or PDF code involved.
List<List<num>> directArabicShape(ByteData bytes, String text) =>
    using((arena) {
      final data = arena<Uint8>(bytes.lengthInBytes);
      data
          .asTypedList(bytes.lengthInBytes)
          .setAll(
            0,
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
      final blob = hb.hb_blob_create(
        data.cast(),
        bytes.lengthInBytes,
        hb.hb_memory_mode_t.HB_MEMORY_MODE_READONLY,
        nullptr,
        nullptr,
      );
      final face = hb.hb_face_create(blob, 0);
      final font = hb.hb_font_create(face);
      final buffer = hb.hb_buffer_create();
      try {
        hb.hb_ot_font_set_funcs(font);
        final upem = hb.hb_face_get_upem(face);
        hb.hb_font_set_scale(font, upem, upem);
        final input = arena<Uint16>(text.length)
          ..asTypedList(text.length).setAll(0, text.codeUnits);
        hb.hb_buffer_add_utf16(buffer, input, text.length, 0, text.length);
        hb.hb_buffer_set_direction(buffer, hb.hb_direction_t.HB_DIRECTION_RTL);
        hb.hb_buffer_set_script(buffer, hb.hb_script_t.HB_SCRIPT_ARABIC);
        hb.hb_buffer_set_language(
          buffer,
          hb.hb_language_from_string(
            'ar'.toNativeUtf8(allocator: arena).cast(),
            -1,
          ),
        );
        hb.hb_shape(font, buffer, nullptr, 0);
        final count = arena<UnsignedInt>();
        final infos = hb.hb_buffer_get_glyph_infos(buffer, count);
        final positions = hb.hb_buffer_get_glyph_positions(buffer, nullptr);
        return [
          for (var i = 0; i < count.value; i++)
            <num>[
              infos[i].codepoint,
              infos[i].cluster,
              positions[i].x_advance / upem,
              positions[i].y_advance / upem,
              positions[i].x_offset / upem,
              positions[i].y_offset / upem,
            ],
        ];
      } finally {
        hb.hb_buffer_destroy(buffer);
        hb.hb_font_destroy(font);
        hb.hb_face_destroy(face);
        hb.hb_blob_destroy(blob);
      }
    });
