import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';

/// Run from pdf_harfbuzz/ after `bun run tool/download_noto.ts` at repo root.
Future<void> main() async {
  final languages = (jsonDecode(
    File('test/data/india_languages.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final manifest = jsonDecode(
    File('fonts/noto/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final fonts = <String, pw.Font>{};
  for (final language in languages) {
    final entry = (manifest['fonts'] as List).singleWhere(
      (f) => f['folder'] == language['folder'],
    );
    fonts[language['code']] = pw.Font.ttf(
      File('fonts/noto/${entry['folder']}/${entry['filename']}')
          .readAsBytesSync()
          .buffer
          .asByteData(),
      shaper: HarfBuzzTextShaper(language: language['code']),
    );
  }
  pw.Text text(Map<String, dynamic> language, String value, double size) =>
      pw.Text(
        value,
        textDirection: language['direction'] == 'rtl'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr,
        style: pw.TextStyle(font: fonts[language['code']], fontSize: size),
      );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a3,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Ten languages of India',
            style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Google Fonts / Noto / OpenType glyph shaping',
            style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 18),
          for (var i = 0; i < languages.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 15),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(
                    width: 115,
                    child: pw.Text(
                      '${i + 1}. ${languages[i]['name']}',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                  ),
                  pw.Expanded(
                    child: text(languages[i], languages[i]['sample'], 20),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Top ten by mother-tongue speakers: Census of India 2011. Hindi and Marathi share Devanagari.',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  for (var i = 0; i < languages.length; i += 2) {
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'Noto / shaping and wrapping',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            for (final language in languages.skip(i).take(2))
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 20),
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      '${language['name']} / ${language['family']}',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    text(language, language['nativeName'], 26),
                    pw.SizedBox(height: 8),
                    text(language, language['sample'], 20),
                    pw.SizedBox(height: 10),
                    text(language, language['stress'], 18),
                    pw.SizedBox(height: 14),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: text(
                            language,
                            '${language['sample']} ${language['sample']}',
                            14,
                          ),
                        ),
                        pw.SizedBox(width: 18),
                        pw.Expanded(
                          child: text(
                            language,
                            language['code'] == 'ur'
                                ? 'سال ۲۰۲۶ میں قیمت 123 روپے ہے۔'
                                : '${language['nativeName']} 123 / 2026',
                            16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  final output = File('../output/pdf/india-ten-languages.pdf');
  output.parent.createSync(recursive: true);
  await output.writeAsBytes(await document.save());
  print(output.absolute.path);
}
