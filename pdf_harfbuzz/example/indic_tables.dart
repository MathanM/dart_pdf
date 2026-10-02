import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';

/// Shaped text in narrow table columns: words are never broken.
///
/// Run from pdf_harfbuzz/ after `bun run tool/download_noto.ts` at repo root.
Future<void> main() async {
  final languages = (jsonDecode(
    File('test/data/india_languages.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final manifest = jsonDecode(
    File('fonts/noto/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  pw.Widget cell(pw.Widget child, {int colSpan = 1, int rowSpan = 1}) =>
      pw.TableCell(
        colSpan: colSpan,
        rowSpan: rowSpan,
        child: pw.Padding(padding: const pw.EdgeInsets.all(4), child: child),
      );

  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Header(level: 1, text: 'Shaped text in table columns'),
        pw.Bullet(
          text: 'Each word stays whole on one line: the narrow middle '
              'column is as wide as its longest shaped word.',
        ),
        pw.Bullet(
          text: 'Conjuncts and vowel signs are never split from their '
              'consonant at a line break.',
        ),
        pw.SizedBox(height: 8),
        for (final language in languages) ...[
          () {
            final entry = (manifest['fonts'] as List).singleWhere(
              (f) => f['folder'] == language['folder'],
            );
            final style = pw.TextStyle(
              fontSize: 12,
              font: pw.Font.ttf(
                File('fonts/noto/${entry['folder']}/${entry['filename']}')
                    .readAsBytesSync()
                    .buffer
                    .asByteData(),
                shaper: HarfBuzzTextShaper(language: language['code']),
              ),
            );
            final direction = language['direction'] == 'rtl'
                ? pw.TextDirection.rtl
                : pw.TextDirection.ltr;
            pw.Text text(String value) =>
                pw.Text(value, style: style, textDirection: direction);
            final words = '${language['sample']} ${language['stress']}'
                .split(RegExp(r'\s+'))
                .where((word) => word.isNotEmpty)
                .toList();

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey600),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    repeat: true,
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.blueGrey100),
                    children: [
                      cell(
                        pw.Text(
                          '${language['name']} - ${language['code']}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        colSpan: 3,
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      cell(text(language['sample'] as String)),
                      cell(text(words.join(' '))),
                      cell(text(language['stress'] as String), rowSpan: 2),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      cell(text(language['nativeName'] as String),
                          colSpan: 2),
                    ],
                  ),
                ],
              ),
            );
          }(),
        ],
      ],
    ),
  );

  final file = File('../output/pdf/indic-tables.pdf');
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(await document.save());
  print(file.absolute.path);
}
