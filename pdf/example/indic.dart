import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Baseline: run from pdf/ with `dart run example/indic.dart FONT_DIRECTORY`.
Future<void> main(List<String> args) async {
  final directory = args.single;
  pw.Font font(String name) => pw.Font.ttf(
    File('$directory/$name').readAsBytesSync().buffer.asByteData(),
  );
  final tamil = font('ta/NotoSansTamil-Regular.ttf');
  final hindi = font('hi/NotoSansDevanagari-Regular.ttf');
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Indic rendering - original renderer',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 28),
          pw.Text('Tamil / Noto Sans Tamil'),
          pw.SizedBox(height: 12),
          pw.Text(
            'தமிழ் மொழி மிகவும் அழகானது. வணக்கம்!',
            style: pw.TextStyle(font: tamil, fontSize: 24),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'கி கீ கு கூ கெ கே கை கொ கோ கௌ ஸ்ரீ க்ஷ',
            style: pw.TextStyle(font: tamil, fontSize: 24),
          ),
          pw.SizedBox(height: 36),
          pw.Text('Hindi / Noto Sans Devanagari'),
          pw.SizedBox(height: 12),
          pw.Text(
            'हिन्दी भाषा बहुत सुंदर है। नमस्ते भारत!',
            style: pw.TextStyle(font: hindi, fontSize: 24),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'कि की कु कू कृ के कै को कौ क्ष त्र ज्ञ श्र',
            style: pw.TextStyle(font: hindi, fontSize: 24),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'प्रार्थना राष्ट्र विद्यालय शक्ति दृष्टि संस्कृति',
            style: pw.TextStyle(font: hindi, fontSize: 24),
          ),
        ],
      ),
    ),
  );
  final file = File('../output/pdf/indic-before.pdf');
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(await document.save());
  print(file.absolute.path);
}
