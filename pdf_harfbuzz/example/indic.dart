import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shaped demo: run from pdf_harfbuzz/ with `dart run example/indic.dart FONT_DIRECTORY`.
Future<void> main(List<String> args) async {
  final directory = args.single;
  pw.Font font(String name) => pw.Font.ttf(
    File('$directory/$name').readAsBytesSync().buffer.asByteData(),
    shaper: const HarfBuzzTextShaper(),
  );
  final tamil = font('ta/NotoSansTamil-Regular.ttf');
  final hindi = font('hi/NotoSansDevanagari-Regular.ttf');
  final tamilBold = font('ta/NotoSansTamil-Bold.ttf');
  final hindiBold = font('hi/NotoSansDevanagari-Bold.ttf');
  final tamilAnek = font('ta/AnekTamil-ExtraBold.ttf');
  final hindiAnek = font('hi/AnekDevanagari-ExtraBold.ttf');
  final telugu = font('te/NotoSansTelugu-Regular.ttf');
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Indic rendering - OpenType shaping',
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
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OpenType - fonts and layout checks',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Noto Sans Bold'),
          pw.SizedBox(height: 8),
          pw.Text(
            'தமிழ் மொழி: கொ கோ கௌ ஸ்ரீ',
            style: pw.TextStyle(font: tamilBold, fontSize: 22),
          ),
          pw.Text(
            'हिन्दी: प्रार्थना राष्ट्र विद्यालय',
            style: pw.TextStyle(font: hindiBold, fontSize: 22),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Anek ExtraBold'),
          pw.SizedBox(height: 8),
          pw.Text(
            'வணக்கம்! தமிழ் மொழி அழகானது.',
            style: pw.TextStyle(font: tamilAnek, fontSize: 22),
          ),
          pw.Text(
            'नमस्ते! हिन्दी भाषा सुंदर है।',
            style: pw.TextStyle(font: hindiAnek, fontSize: 22),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Mixed language fallback / ordinary Text widget'),
          pw.SizedBox(height: 8),
          pw.Text(
            'Invoice 123 / தமிழ் / हिन्दी',
            style: pw.TextStyle(
              font: pw.Font.helvetica(),
              fontFallback: [tamil, hindi],
              fontSize: 20,
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text('Wrapping in narrow columns'),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Text(
                    'தமிழ் மொழி மிகவும் அழகானது. கல்வி அறிவை வளர்க்கும். அனைவருக்கும் வணக்கம்!',
                    style: pw.TextStyle(font: tamil, fontSize: 18),
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Text(
                    'हिन्दी भाषा बहुत सुंदर है। शिक्षा से ज्ञान बढ़ता है। प्रार्थना, शक्ति और संस्कृति।',
                    style: pw.TextStyle(font: hindi, fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text('Direct PDF text / mark placement and word spacing'),
          pw.SizedBox(height: 6),
          pw.CustomPaint(
            size: const PdfPoint(500, 32),
            painter: (canvas, size) {
              canvas.drawString(
                hindi.getFont(context),
                22,
                'किं कूँ क़ फ़ दृष्टि संस्कृत',
                0,
                8,
                wordSpace: 3,
              );
            },
          ),
          pw.SizedBox(height: 12),
          pw.Text('Telugu / same shaping engine'),
          pw.SizedBox(height: 8),
          pw.Text(
            'తెలుగు భాష అందమైనది. నమస్కారం!',
            style: pw.TextStyle(font: telugu, fontSize: 22),
          ),
        ],
      ),
    ),
  );
  final file = File('../output/pdf/indic-after.pdf');
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(await document.save());
  print(file.absolute.path);
}
