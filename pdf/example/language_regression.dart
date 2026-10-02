import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared by the unchanged-package comparison and the native shaping demo.
/// Keep this example compatible with the original Font.ttf API.
void addLanguageRegressionPages(
  pw.Document document, {
  required String root,
  required pw.Font Function(ByteData, String) loadFont,
  required bool shaped,
}) {
  final catalog =
      (jsonDecode(
                File(
                  '$root/pdf_harfbuzz/test/data/regression_languages.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  final manifest = jsonDecode(
    File(
      '$root/pdf_harfbuzz/fonts/regression/manifest.json',
    ).readAsStringSync(),
  );
  ByteData bytes(String path) =>
      File(path).readAsBytesSync().buffer.asByteData();
  final fonts = <String, pw.Font>{};
  for (final language in catalog) {
    final entry = (manifest['fonts'] as List).singleWhere(
      (f) => f['folder'] == language['folder'],
    );
    final path = !shaped && language['code'] == 'ar'
        ? '$root/pdf/hacen-tunisia.ttf'
        : '$root/pdf_harfbuzz/fonts/regression/${entry['folder']}/${entry['filename']}';
    fonts[language['code']] = loadFont(bytes(path), language['code']);
  }
  final cjk = loadFont(bytes('$root/pdf/genyomintw.ttf'), 'ja');
  // Bitmap emoji use the existing fallback image path, without a shaper.
  final emoji = pw.Font.ttf(bytes('$root/pdf/emoji.ttf'));
  final bold = loadFont(bytes('$root/pdf/open-sans-bold.ttf'), 'en');
  final regular = loadFont(bytes('$root/pdf/open-sans.ttf'), 'en');
  final mode = shaped ? 'OpenType / HarfBuzz' : 'Existing renderer / no shaper';
  pw.Widget heading(String title) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 20)),
      pw.SizedBox(height: 6),
      pw.Text(
        mode,
        style: pw.TextStyle(
          font: regular,
          fontSize: 11,
          color: PdfColors.grey700,
        ),
      ),
      pw.SizedBox(height: 18),
    ],
  );
  pw.Widget text(String code, String value, {double size = 16}) => pw.Text(
    value,
    textDirection: ['ar', 'fa', 'he'].contains(code)
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr,
    style: pw.TextStyle(font: fonts[code], fontSize: size),
  );
  pw.Widget section(Map<String, dynamic> language) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          language['name'],
          style: pw.TextStyle(
            font: regular,
            fontSize: 11,
            color: PdfColors.grey700,
          ),
        ),
        pw.SizedBox(height: 7),
        text(language['code'], language['sample']),
        pw.SizedBox(height: 7),
        text(language['code'], language['stress'], size: 16),
        if (shaped && language['code'] == 'ar') ...[
          pw.SizedBox(height: 6),
          text('ar', 'إِنْسَانَ  اللّٰهُ  بِسْمِ اللّٰهِ', size: 18),
        ],
      ],
    ),
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          heading('Arabic and right-to-left scripts'),
          for (final language in catalog.take(3)) section(language),
          text('ar', 'السعر (123) ريال، والعدد ١٢٣ صحيح.', size: 20),
          pw.SizedBox(height: 12),
          text('ar', 'ترتيب Right Order في منتصف النص العربي.', size: 20),
          pw.SizedBox(height: 12),
          pw.Container(
            width: 260,
            child: text(
              'ar',
              'اللغة العربية جميلة. مرحباً بكم! اللغة العربية جميلة. مرحباً بكم! اللغة العربية جميلة. مرحباً بكم!',
              size: 22,
            ),
          ),
        ],
      ),
    ),
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          heading('Latin, Greek and Cyrillic'),
          for (final language in catalog.skip(3)) section(language),
        ],
      ),
    ),
  );
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          heading('CJK, font fallback and text layout'),
          pw.Text(
            'Chinese / Japanese',
            style: pw.TextStyle(font: regular, fontSize: 12),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '你好，世界！中文文字測試。\nこんにちは世界。日本語の文字。',
            style: pw.TextStyle(font: cjk, fontSize: 24),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Hello 中文 world! Dancing 💃🏃',
            style: pw.TextStyle(
              font: regular,
              fontSize: 24,
              fontFallback: [cjk, emoji],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(font: regular, fontSize: 20),
              children: [
                const pw.TextSpan(text: 'Regular café / '),
                pw.TextSpan(
                  text: 'Bold résumé',
                  style: pw.TextStyle(font: bold),
                ),
                const pw.TextSpan(
                  text: ' / underlined',
                  style: pw.TextStyle(decoration: pw.TextDecoration.underline),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final align in [pw.TextAlign.left, pw.TextAlign.justify])
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.only(right: 14),
                    child: pw.Text(
                      'Office text wraps across several lines. Accented characters like café and naïve remain readable. This paragraph checks spacing and alignment.',
                      textAlign: align,
                      style: pw.TextStyle(font: fonts['en'], fontSize: 17),
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Built-in Helvetica: ABC xyz 0123456789',
            style: const pw.TextStyle(fontSize: 18),
          ),
        ],
      ),
    ),
  );
}

Future<void> main(List<String> args) async {
  final root =
      Platform.environment['LANGUAGE_REPO_ROOT'] ??
      Directory.current.parent.path;
  final document = pw.Document();
  addLanguageRegressionPages(
    document,
    root: root,
    loadFont: (bytes, _) => pw.Font.ttf(bytes),
    shaped: false,
  );
  final output = File(
    args.isNotEmpty
        ? args.first
        : '$root/output/pdf/languages-legacy-current.pdf',
  );
  output.parent.createSync(recursive: true);
  await output.writeAsBytes(await document.save());
  print(output.absolute.path);
}
