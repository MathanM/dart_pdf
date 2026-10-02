import 'dart:convert';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:test/test.dart';

/// Shaped words are never broken in table columns.
void main() {
  final languages = (jsonDecode(
    File('test/data/india_languages.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  final manifest = jsonDecode(
    File('fonts/noto/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  late pw.Context context;

  setUp(() {
    final document = PdfDocument();
    final page = PdfPage(document);
    context = pw.Context(
      document: document,
      page: page,
      canvas: page.getGraphics(),
    ).inheritFromAll(<pw.Inherited>[pw.ThemeData.base()]);
  });

  for (final language in languages) {
    group('${language['name']}', () {
      late pw.TextStyle style;
      late pw.TextDirection direction;
      late List<String> words;

      setUp(() {
        final entry = (manifest['fonts'] as List).singleWhere(
          (f) => f['folder'] == language['folder'],
        );
        style = pw.TextStyle(
          fontSize: 14,
          font: pw.Font.ttf(
            File('fonts/noto/${entry['folder']}/${entry['filename']}')
                .readAsBytesSync()
                .buffer
                .asByteData(),
            shaper: HarfBuzzTextShaper(language: language['code']),
          ),
        );
        direction = language['direction'] == 'rtl'
            ? pw.TextDirection.rtl
            : pw.TextDirection.ltr;
        words = '${language['sample']} ${language['stress']}'
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .toList();
      });

      pw.Text text(String value, {bool? softWrap}) => pw.Text(
        value,
        style: style,
        textDirection: direction,
        softWrap: softWrap,
      );

      /// The laid out size of [value] on a single line
      PdfRect natural(String value) {
        final widget = text(value, softWrap: false);
        widget.layout(context, const pw.BoxConstraints());
        return widget.box!;
      }

      test('min width fits every shaped word on one line', () {
        final all = words.join(' ');
        final minWidth = text(all).getMinIntrinsicWidth(context);

        double height(String value, double width) {
          final widget = text(value);
          widget.layout(context, pw.BoxConstraints(maxWidth: width));
          return widget.box!.height;
        }

        for (final word in words) {
          expect(
            height(word, minWidth),
            closeTo(natural(word).height, 0.001),
            reason: word,
          );
        }

        // Any narrower and the widest word has to break
        expect(
          words.any(
            (word) => height(word, minWidth - 1) > natural(word).height + 0.001,
          ),
          isTrue,
        );
      });

      test('narrow table columns keep words whole', () {
        final longest = words.reduce(
          (a, b) => natural(a).width >= natural(b).width ? a : b,
        );
        final longestCell = text(longest);
        final table = pw.Table(
          border: pw.TableBorder.all(),
          children: [
            pw.TableRow(
              children: [
                text(words.join(' ')),
                longestCell,
                text(words.reversed.join(' ')),
              ],
            ),
          ],
        );

        table.layout(
          context,
          pw.BoxConstraints(maxWidth: natural(longest).width * 4),
        );

        expect(
          longestCell.box!.height,
          closeTo(natural(longest).height, 0.001),
        );
      });
    });
  }
}
