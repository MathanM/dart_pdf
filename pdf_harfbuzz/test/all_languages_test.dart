import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:test/test.dart';

import 'arabic_regression_test.dart' show glyphData, positionedWords;
import 'india_languages_test.dart' show actualTexts;
import 'support/reference_shaper.dart';

List<Map<String, dynamic>> readCatalog(String name) =>
    (jsonDecode(File('test/data/$name.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

void main() {
  final languages = [
    for (final (catalog, directory) in [
      ('india_languages', 'noto'),
      ('regression_languages', 'regression'),
      ('cjk_languages', ''),
    ])
      for (final language in readCatalog(catalog))
        {...language, 'directory': directory},
  ];
  final coverage = readCatalog('language_coverage');
  final fonts = <String, ByteData>{};
  ByteData loadFont(Map<String, dynamic> language) {
    String? path = language['fontFile'];
    if (path == null) {
      final manifest = jsonDecode(
        File('fonts/${language['directory']}/manifest.json').readAsStringSync(),
      );
      final entry = (manifest['fonts'] as List).singleWhere(
        (f) => f['folder'] == language['folder'],
      );
      path =
          'fonts/${language['directory']}/${entry['folder']}/${entry['filename']}';
    }
    return fonts.putIfAbsent(
      path,
      () => File(path!).readAsBytesSync().buffer.asByteData(),
    );
  }

  test('Language coverage includes every catalog entry exactly once', () {
    final catalogCodes = languages.map((l) => l['code']).toList();
    final coverageCodes = coverage.map((l) => l['code']).toList();
    expect(catalogCodes.toSet().length, catalogCodes.length);
    expect(coverageCodes.toSet().length, coverageCodes.length);
    expect(coverageCodes, unorderedEquals(catalogCodes));
  });

  for (final language in languages) {
    final row = coverage.singleWhere((c) => c['code'] == language['code']);
    final bytes = loadFont(language);
    final rtl = language['direction'] == 'rtl';
    final shaper = HarfBuzzTextShaper(language: language['code']);
    final source = '${language['sample']} ${language['stress']}';
    final probe = row['probe'] as String;
    group('Coverage ${language['code']} ${language['name']}', () {
      test('shaping', () {
        final run = shaper.shape(bytes, source);
        expect(run.glyphs, isNotEmpty);
        expect(run.glyphs.where((g) => g.glyphId == 0), isEmpty);
        final font = PdfTtfFont(PdfDocument(), bytes, shaper: shaper);
        expect(
          font.stringMetrics(source).advanceWidth,
          closeTo(run.glyphs.fold(0.0, (x, g) => x + g.xAdvance), 1e-9),
        );
        expect(
          glyphData(shaper.shape(bytes, probe)),
          referenceShape(
            bytes,
            probe,
            script: row['script'],
            language: language['code'],
            rtl: rtl,
          ),
        );
      });

      test('subsetting', () {
        final original = TtfParser(bytes);
        final ids = [
          0,
          ...shaper.shape(bytes, source).glyphs.map((g) => g.glyphId),
        ];
        final subset = TtfParser(
          TtfWriter(original).withGlyphs(ids).buffer.asByteData(),
        );
        for (var cid = 0; cid < ids.length; cid++) {
          expect(
            subset.glyphInfoMap[cid]!.advanceWidth,
            original.glyphInfoMap[ids[cid]]!.advanceWidth,
          );
          expect(
            outline(subset, cid),
            outline(original, ids[cid]),
            reason: '${language['name']} CID $cid / source GID ${ids[cid]}',
          );
        }
      });

      test('wrapping and Unicode', () async {
        final sample = List.filled(3, language['sample']).join(' ');
        final document = pw.Document(compress: false);
        document.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(170, 1800),
            margin: const pw.EdgeInsets.all(12),
            build: (_) => pw.Text(
              sample,
              textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              style: pw.TextStyle(
                font: pw.Font.ttf(bytes, shaper: shaper),
                fontSize: 18,
              ),
            ),
          ),
        );
        final pdf = latin1.decode(await document.save());
        final fragments = actualTexts(pdf);
        String compact(String s) => s.replaceAll(RegExp(r'\s'), '');
        expect(compact(fragments.join()), compact(sample));
        final boundaries = <int>{0};
        var offset = 0;
        for (final cluster in compact(sample).characters) {
          offset += cluster.length;
          boundaries.add(offset);
        }
        offset = 0;
        for (final fragment in fragments) {
          offset += compact(fragment).length;
          expect(
            boundaries,
            contains(offset),
            reason: 'A line must not split a grapheme',
          );
        }
        final positions = positionedWords(pdf).map((w) => w.$3).toList();
        expect(
          positions.reduce(math.max) - positions.reduce(math.min),
          greaterThan(27),
          reason: 'The sample must actually wrap onto multiple lines',
        );
        expect(RegExp(r'/Subtype\s*/Image').hasMatch(pdf), isFalse);
      });

      if (row['fallback'] == true) {
        test('fallback', () async {
          final recorder = RecordingShaper(shaper);
          final document = pw.Document(compress: false);
          document.addPage(
            pw.Page(
              build: (_) => pw.Text(
                'prefix $probe suffix',
                style: pw.TextStyle(
                  font: pw.Font.helvetica(),
                  fontSize: 18,
                  fontFallback: [pw.Font.ttf(bytes, shaper: recorder)],
                ),
              ),
            ),
          );
          final pdf = latin1.decode(await document.save());
          expect(recorder.inputs, contains(probe));
          expect(actualTexts(pdf), contains(probe));
        });
      }
    });
  }
}

/// Compare every contour and compound recursively, ignoring only the component
/// IDs which necessarily change in a subset. Preserve component transforms and
/// hint instructions so corrupt compound outlines cannot pass unnoticed.
List<Object> outline(TtfParser font, int id, [Set<int> ancestors = const {}]) {
  if (ancestors.contains(id)) throw StateError('Cyclic compound glyph $id');
  final glyph = font.readGlyph(id);
  final data = Uint8List.fromList(glyph.data);
  if (glyph.compounds.isEmpty) return [data];
  final view = data.buffer.asByteData();
  var offset = 10;
  var flags = 32;
  while (flags & 32 != 0) {
    flags = view.getUint16(offset);
    view.setUint16(offset + 2, 0);
    offset += flags & 1 != 0 ? 8 : 6;
    offset += flags & 8 != 0
        ? 2
        : flags & 64 != 0
        ? 4
        : flags & 128 != 0
        ? 8
        : 0;
  }
  return [
    data,
    for (final component in glyph.compounds)
      outline(font, component, {...ancestors, id}),
  ];
}

class RecordingShaper extends PdfTextShaper {
  RecordingShaper(this.delegate);
  final PdfTextShaper delegate;
  final inputs = <String>[];
  @override
  PdfGlyphRun shape(ByteData font, String text) {
    inputs.add(text);
    return delegate.shape(font, text);
  }
}
