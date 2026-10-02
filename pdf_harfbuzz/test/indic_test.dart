import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:test/test.dart';

void main() {
  final directory = Platform.environment['INDIC_FONT_DIR'];
  if (directory == null) {
    throw StateError(
      'Set INDIC_FONT_DIR to the demo font directory (see README).',
    );
  }
  ByteData load(String name) =>
      File('$directory/$name').readAsBytesSync().buffer.asByteData();
  final tamil = load('ta/NotoSansTamil-Regular.ttf');
  final hindi = load('hi/NotoSansDevanagari-Regular.ttf');
  const shaper = HarfBuzzTextShaper();

  test('Tamil split vowels have canonically equivalent shaping', () {
    for (final pair in [('கொ', 'கொ'), ('கோ', 'கோ'), ('கௌ', 'கௌ')]) {
      final a = shaper.shape(tamil, pair.$1).glyphs;
      final b = shaper.shape(tamil, pair.$2).glyphs;
      expect(
        a.map((g) => (g.glyphId, g.xAdvance, g.xOffset, g.yOffset)),
        b.map((g) => (g.glyphId, g.xAdvance, g.xOffset, g.yOffset)),
      );
      expect(a.first.cluster, 0);
      expect(a.every((g) => g.cluster == 0), isTrue);
    }
  });

  test('Hindi pre-base matra reorders and conjunct comes from GSUB', () {
    final parser = TtfParser(hindi);
    final ki = shaper.shape(hindi, 'कि');
    expect(ki.glyphs.first.glyphId, isNot(parser.charToGlyphIndexMap[0x915]));
    expect(ki.breaks, [2]);
    final ksha = shaper.shape(hindi, 'क्ष');
    expect(ksha.glyphs.length, lessThan(3));
    expect(
      ksha.glyphs.any(
        (g) => !parser.charToGlyphIndexMap.values.contains(g.glyphId),
      ),
      isTrue,
    );
    expect(ksha.breaks, [3]);
  });

  test('Mixed scripts in one font are shaped as separate script runs', () {
    final whole = shaper.shape(hindi, 'ABCकि').glyphs;
    final latin = shaper.shape(hindi, 'ABC').glyphs;
    final indic = shaper.shape(hindi, 'कि').glyphs;
    expect(
      whole.map((g) => g.glyphId),
      [...latin, ...indic].map((g) => g.glyphId),
    );
    expect(
      whole.skip(latin.length).map((g) => g.cluster),
      indic.map((g) => g.cluster + 3),
    );
  });

  test('Mark placement is included in measured ink bounds', () {
    final font = PdfTtfFont(PdfDocument(), hindi, shaper: shaper);
    const text = 'किं कूँ क़ फ़ दृष्टि';
    final run = font.shape(text);
    expect(run.glyphs.any((g) => g.xOffset != 0 || g.yOffset != 0), isTrue);
    final bounds = font.stringMetrics(text);
    var x = 0.0;
    for (final glyph in run.glyphs) {
      final metric = font.font.glyphInfoMap[glyph.glyphId]!;
      expect(
        x + glyph.xOffset + metric.left,
        greaterThanOrEqualTo(bounds.left - 1e-9),
      );
      expect(
        x + glyph.xOffset + metric.right,
        lessThanOrEqualTo(bounds.right + 1e-9),
      );
      expect(
        glyph.yOffset + metric.top,
        greaterThanOrEqualTo(bounds.top - 1e-9),
      );
      expect(
        glyph.yOffset + metric.bottom,
        lessThanOrEqualTo(bounds.bottom + 1e-9),
      );
      x += glyph.xAdvance;
    }
  });

  test('GSUB glyphs, duplicates, compound closure and empty space survive subsetting', () {
    for (final (bytes, text) in [
      (tamil, 'கொ ஸ்ரீ க்ஷ'),
      (hindi, 'प्रार्थना क्ष ज्ञ कि'),
    ]) {
      final original = TtfParser(bytes);
      final ids = [
        0,
        ...shaper.shape(bytes, text).glyphs.map((g) => g.glyphId),
      ];
      final subset = TtfParser(
        TtfWriter(original).withGlyphs(ids).buffer.asByteData(),
      );
      for (var i = 0; i < ids.length; i++) {
        expect(
          subset.glyphInfoMap[i]!.advanceWidth,
          original.glyphInfoMap[ids[i]]!.advanceWidth,
        );
        final before = original.readGlyph(ids[i]);
        final after = subset.readGlyph(i);
        if (before.compounds.isEmpty) expect(after.data, before.data);
        for (final component in after.compounds) {
          expect(component, lessThan(subset.numGlyphs));
        }
      }
      final space = original.charToGlyphIndexMap[32]!;
      expect(original.readGlyph(space).data, isEmpty);
    }
  });

  test('ByteData views preserve font parsing, shaping and subset bytes', () {
    final padded = Uint8List(tamil.lengthInBytes + 32)
      ..setAll(16, tamil.buffer.asUint8List());
    final view = ByteData.view(padded.buffer, 16, tamil.lengthInBytes);
    final a = TtfParser(tamil);
    final b = TtfParser(view);
    expect(b.fontName, a.fontName);
    final ids = [
      0,
      ...shaper.shape(view, 'தமிழ்').glyphs.map((g) => g.glyphId),
    ];
    expect(TtfWriter(b).withGlyphs(ids), TtfWriter(a).withGlyphs(ids));
  });

  test('Metrics use shaped advances and cluster spacing', () {
    for (final (bytes, text) in [(tamil, 'கொகோ'), (hindi, 'प्रार्थना')]) {
      final font = PdfTtfFont(PdfDocument(), bytes, shaper: shaper);
      final run = font.shape(text);
      final width = run.glyphs.fold(0.0, (x, g) => x + g.xAdvance);
      expect(font.stringMetrics(text).advanceWidth, closeTo(width, 1e-9));
      expect(
        font.stringMetrics(text, letterSpacing: .1).advanceWidth,
        closeTo(
          width + (run.glyphs.map((g) => g.cluster).toSet().length - 1) * .1,
          1e-9,
        ),
      );
    }
  });

  test(
    'Direct PDF drawing embeds shaped glyphs and logical ActualText',
    () async {
      final document = PdfDocument(compress: false);
      final font = PdfTtfFont(document, hindi, shaper: shaper);
      PdfPage(document).getGraphics().drawString(
        font,
        24,
        'हिन्दी क्ष कि',
        40,
        600,
        charSpace: 1.5,
        wordSpace: 4,
        scale: .8,
      );
      final data = latin1.decode(await document.save());
      expect(
        data,
        contains(
          '/ActualText <feff0939093f0928094d0926094000200915094d093700200915093f>',
        ),
      );
      expect(data, contains('/CIDFontType2'));
      expect(data, contains(' Tm <'));
      expect(data, isNot(contains('/Subtype /Image')));
    },
  );

  test('Protected text does not expose ActualText', () async {
    final document = PdfDocument(compress: false);
    final font = PdfTtfFont(document, tamil, shaper: shaper, protect: true);
    PdfPage(document).getGraphics().drawString(font, 24, 'தமிழ்', 40, 600);
    final data = latin1.decode(await document.save());
    expect(data, isNot(contains('/ActualText')));
    expect(data, contains('<0020>'));
  });

  test('Fallback passes complete Indic runs to shaping', () async {
    final recorder = _RecordingShaper();
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Text(
          'Invoice தமிழ் हिन्दी',
          style: pw.TextStyle(
            font: pw.Font.helvetica(),
            fontFallback: [
              pw.Font.ttf(tamil, shaper: recorder),
              pw.Font.ttf(hindi, shaper: recorder),
            ],
          ),
        ),
      ),
    );
    await document.save();
    expect(recorder.texts, contains('தமிழ்'));
    expect(recorder.texts, contains('हिन्दी'));
  });

  test(
    'Very narrow wrapping never cuts Tamil clusters or Hindi conjuncts',
    () async {
      for (final (bytes, text, fragments) in [
        (tamil, 'கொகோகௌ', ['கொ', 'கோ', 'கௌ']),
        (hindi, 'क्षत्रज्ञ', ['क्ष', 'त्र', 'ज्ञ']),
      ]) {
        final recorder = _RecordingShaper();
        final document = pw.Document(compress: false);
        document.addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(10, 842),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Text(
              text,
              style: pw.TextStyle(
                font: pw.Font.ttf(bytes, shaper: recorder),
                fontSize: 24,
              ),
            ),
          ),
        );
        final pdf = latin1.decode(await document.save());
        final actualTexts = RegExp(r'/ActualText <feff([0-9a-f]+)>')
            .allMatches(pdf)
            .map((m) {
              final hex = m[1]!;
              return String.fromCharCodes([
                for (var i = 0; i < hex.length; i += 4)
                  int.parse(hex.substring(i, i + 4), radix: 16),
              ]);
            })
            .toList();
        expect(actualTexts, fragments);
        final baselines = RegExp(
          r'/ActualText <feff[0-9a-f]+> >> BDC 1 0 0 1 [-0-9.]+ ([-0-9.]+) Tm',
        ).allMatches(pdf).map((m) => m[1]).toSet();
        expect(
          baselines.length,
          fragments.length,
          reason: 'Each overflowing cluster needs its own line',
        );
      }
    },
  );

  test(
    'All supplied Tamil, Hindi and Telugu weights shape without missing glyphs',
    () {
      for (final (dir, sample) in [
        ('ta', 'தமிழ் கொ கோ கௌ ஸ்ரீ'),
        ('hi', 'हिन्दी प्रार्थना क्ष ज्ञ कि'),
        ('te', 'తెలుగు భాష అందమైనది'),
      ]) {
        for (final file in Directory(
          '$directory/$dir',
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
          final bytes = file.readAsBytesSync().buffer.asByteData();
          expect(
            shaper.shape(bytes, sample).glyphs.every((g) => g.glyphId != 0),
            isTrue,
            reason: file.path,
          );
        }
      }
    },
  );
}

class _RecordingShaper extends PdfTextShaper {
  final texts = <String>[];
  @override
  PdfGlyphRun shape(ByteData font, String text) {
    texts.add(text);
    return const HarfBuzzTextShaper().shape(font, text);
  }
}
