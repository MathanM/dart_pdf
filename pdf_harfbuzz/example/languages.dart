import 'dart:io';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';

import '../../pdf/example/language_regression.dart' as regression;

Future<void> main() async {
  final root = Directory.current.parent.path;
  final document = pw.Document();
  regression.addLanguageRegressionPages(
    document,
    root: root,
    loadFont: (bytes, language) =>
        pw.Font.ttf(bytes, shaper: HarfBuzzTextShaper(language: language)),
    shaped: true,
  );
  final output = File('$root/output/pdf/language-regression.pdf');
  output.parent.createSync(recursive: true);
  await output.writeAsBytes(await document.save());
  print(output.absolute.path);
}
