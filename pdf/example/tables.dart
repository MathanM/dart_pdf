import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Visual review of table layout: column minimal widths, column and row
/// spans, repeated headers and page breaks.
///
/// Run from pdf/ with `dart run example/tables.dart`.
Future<void> main() async {
  final document = pw.Document();
  var number = 0;

  /// A scenario starts on a new page, with what to check above the table
  List<pw.Widget> scenario(
    String title,
    List<String> checks,
    List<pw.Widget> content, {
    bool newPage = true,
  }) => [
    if (newPage && number > 0) pw.NewPage(),
    pw.Header(level: 1, text: '${++number}. $title'),
    for (final check in checks) pw.Bullet(text: check),
    pw.SizedBox(height: 8),
    ...content,
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          'Table review - page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        ...scenario(
          'Columns never break a word',
          [
            ('Every word stays on one line: the narrow columns are at least '
                'as wide as their longest word.'),
            ('The long text columns take the remaining width and wrap '
                'between words.'),
          ],
          [
            _table([
              ['Id', 'Description', 'Status', 'Notes'],
              ['1', _lorem(30), 'Incomprehensibilities', 'Short'],
              ['2', _lorem(12), 'Ok', 'Antidisestablishmentarianism is long'],
              ['3', 'Tiny', 'Pending', _lorem(20)],
            ], header: true),
          ],
        ),
        ...scenario(
          'Column width types keep their minimal width',
          [
            'Fixed 40 / Flex 1 / Flex 3 / Fraction 0.2 columns.',
            ('The flex columns get their share, but never less than their '
                'longest word ("Characteristically", "Uncharacteristically").'),
          ],
          [
            _table(
              [
                ['Fixed', 'Flex 1', 'Flex 3', 'Fraction'],
                ['A', 'Characteristically', _lorem(25), 'x'],
                ['B', 'b', 'Uncharacteristically', _lorem(8)],
              ],
              header: true,
              columnWidths: const {
                0: pw.FixedColumnWidth(40),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(3),
                3: pw.FractionColumnWidth(0.2),
              },
            ),
          ],
          newPage: false,
        ),
        ...scenario(
          'Minimal widths wider than the page',
          [
            ('12 columns of long words cannot fit: every column shrinks in '
                'proportion, and only then are words broken.'),
            'The table stays inside the page margins.',
          ],
          [
            _table([
              [for (var i = 0; i < 12; i++) 'Column$i'],
              for (var r = 0; r < 3; r++)
                [for (var i = 0; i < 12; i++) 'Value${r}x$i'],
            ], header: true),
          ],
          newPage: false,
        ),
        ...scenario(
          'Column spans and row spans',
          [
            ('Tinted cells span several columns or rows; their fill covers '
                'exactly the cells named in their label.'),
            'Borders are drawn around the spans, never through them.',
            'Cells after a span shift to the next free column.',
          ],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
              children: [
                _row(['A1', 'B1', 'C1', 'D1', 'E1'], header: true),
                pw.TableRow(
                  children: [
                    _cell('A2:B2 (colSpan 2)', colSpan: 2, tint: true),
                    _cell('C2'),
                    _cell('D2:D4 (rowSpan 3)', rowSpan: 3, tint: true),
                    _cell('E2'),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell('A3:A4 (rowSpan 2)', rowSpan: 2, tint: true),
                    _cell('B3:C4 (2 x 2)', colSpan: 2, rowSpan: 2, tint: true),
                    _cell('E3'),
                  ],
                ),
                pw.TableRow(children: [_cell('E4')]),
                pw.TableRow(
                  children: [
                    _cell('A5'),
                    _cell('B5:E5 (colSpan 4)', colSpan: 4, tint: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _cell('A6:E6 (whole row)', colSpan: 5, tint: true),
                  ],
                ),
              ],
            ),
          ],
        ),
        ...scenario(
          'Row spans and vertical alignment',
          [
            'The tall spanning cell on the left makes its 3 rows grow evenly.',
            ('Spanning cells are aligned top / middle / bottom / full across '
                'all the rows they cover.'),
          ],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              children: [
                _row(['Tall', 'Top', 'Middle', 'Bottom', 'Full'], header: true),
                pw.TableRow(
                  children: [
                    _cell(_lorem(40), rowSpan: 3),
                    for (final alignment in [
                      pw.TableCellVerticalAlignment.top,
                      pw.TableCellVerticalAlignment.middle,
                      pw.TableCellVerticalAlignment.bottom,
                      pw.TableCellVerticalAlignment.full,
                    ])
                      _cell(
                        'rowSpan 3',
                        rowSpan: 3,
                        tint: true,
                        alignment: alignment,
                      ),
                  ],
                ),
                pw.TableRow(children: []),
                pw.TableRow(children: []),
                _row(['After', 'a', 'b', 'c', 'd']),
              ],
            ),
          ],
          newPage: false,
        ),
        ...scenario(
          'Large table with a repeated header',
          [
            ('150 rows over several pages, the header row repeats on top of '
                'every page.'),
            'Rows are numbered: none is missing or duplicated between pages.',
            'Striped rows keep alternating across page breaks.',
          ],
          [
            _table(
              [
                ['#', 'Name', 'Description', 'Amount'],
                for (var i = 1; i <= 150; i++)
                  ['$i', 'Item $i', _lorem(3 + i % 9), '${i * 17 % 997}.00'],
              ],
              header: true,
              striped: true,
            ),
          ],
        ),
        ...scenario(
          'Two row header with spans, over several pages',
          [
            ('The header is 2 rows: "Region" spans both, "Q1" / "Q2" span '
                'their 3 months.'),
            'Both header rows repeat together on every page.',
          ],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: _headerDecoration,
                  children: [
                    _cell('Region', rowSpan: 2, bold: true),
                    _cell('Q1', colSpan: 3, bold: true),
                    _cell('Q2', colSpan: 3, bold: true),
                  ],
                ),
                _row(['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'], header: true),
                for (var i = 1; i <= 90; i++)
                  _row([
                    'Region $i',
                    for (var m = 0; m < 6; m++) '${(i * 31 + m * 7) % 100}',
                  ], decoration: i.isEven ? _stripe : null),
              ],
            ),
          ],
        ),
        ...scenario(
          'Row span groups are never split between pages',
          [
            ('Each tinted group spans 2 to 6 rows. Page breaks only fall '
                'between groups: a group continues on the next page as a '
                'whole.'),
            'The 2 row header repeats on each page.',
          ],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: _headerDecoration,
                  children: [
                    _cell('Group', rowSpan: 2, bold: true),
                    _cell('Details', colSpan: 2, bold: true),
                  ],
                ),
                _row(['Line', 'Value'], header: true),
                for (var g = 1; g <= 14; g++) ...[
                  pw.TableRow(
                    children: [
                      _cell(
                        'Group $g\n(rowSpan ${2 + g % 5})',
                        rowSpan: 2 + g % 5,
                        tint: true,
                        alignment: pw.TableCellVerticalAlignment.middle,
                      ),
                      _cell('Group $g line 1'),
                      _cell(_lorem(2 + g % 4)),
                    ],
                  ),
                  for (var l = 2; l <= 2 + g % 5; l++)
                    _row(['Group $g line $l', _lorem(1 + l % 3)]),
                ],
              ],
            ),
          ],
        ),
        ...scenario(
          'Header is never left alone at the bottom of a page',
          [
            ('The table below starts near the bottom of this page. Its '
                'header does not stay here alone: it moves to the next page '
                'with the first rows.'),
          ],
          [
            pw.SizedBox(
              height: 600,
              child: pw.Placeholder(color: PdfColors.grey300),
            ),
            _table([
              ['Header', 'Moves with its rows'],
              for (var i = 1; i <= 5; i++) ['Row $i', _lorem(150)],
            ], header: true),
          ],
        ),
        ...scenario(
          'A row span group taller than a page',
          [
            ('The tinted cell spans 4 rows that together exceed a page. As '
                'the group cannot fit on any page, it is split between rows '
                'right here: the rows that fit stay on this page.'),
            ('The rest of the group goes on on the next page after the '
                'repeated header, with the tinted cell drawn again beside '
                'its remaining rows.'),
          ],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              children: [
                _row(['Group', 'Content'], header: true),
                pw.TableRow(
                  children: [
                    _cell('rowSpan 4', rowSpan: 4, tint: true),
                    _cell('Line 1 ${_lorem(400)}'),
                  ],
                ),
                for (var l = 2; l <= 4; l++) _row(['Line $l ${_lorem(400)}']),
                _row(['Next', 'Row after the group']),
              ],
            ),
          ],
        ),
        ...scenario(
          'A single row taller than a page',
          [
            ('The middle row is taller than any page: it moves to the next '
                'page, where it is cut at the bottom margin. That page leaves '
                'the header out to show as much of the row as possible.'),
            'The table then goes on with the header repeated.',
          ],
          [
            _table([
              ['Header', 'Content'],
              ['Before', 'A normal row'],
              ['Huge', _lorem(1500)],
              ['After', 'The table continues'],
            ], header: true),
          ],
        ),
        ...scenario(
          'Nested tables and spans',
          ['A table inside a column span keeps its own minimal widths.'],
          [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey600),
              children: [
                _row(['Outer A', 'Outer B', 'Outer C'], header: true),
                pw.TableRow(
                  children: [
                    pw.TableCell(
                      colSpan: 2,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: _table([
                          ['Inner', 'Incomprehensibilities'],
                          ['x', _lorem(15)],
                        ], header: true),
                      ),
                    ),
                    _cell(_lorem(10)),
                  ],
                ),
              ],
            ),
          ],
        ),
        ...scenario(
          'TableHelper.fromTextArray',
          ['The helper still lays out as before, with long words kept whole.'],
          [
            pw.TableHelper.fromTextArray(
              headers: ['Code', 'Label', 'Comment'],
              data: [
                for (var i = 1; i <= 40; i++)
                  ['C$i', 'Electroencephalography', _lorem(4 + i % 6)],
              ],
            ),
          ],
          newPage: false,
        ),
      ],
    ),
  );

  final file = File('../output/pdf/tables.pdf');
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(await document.save());
  print(file.absolute.path);
}

const _headerDecoration = pw.BoxDecoration(color: PdfColors.blueGrey100);

const _stripe = pw.BoxDecoration(color: PdfColors.grey100);

const _words = [
  'lorem',
  'ipsum',
  'dolor',
  'sit',
  'amet',
  'consectetur',
  'adipiscing',
  'elit',
  'sed',
  'do',
  'eiusmod',
  'tempor',
  'incididunt',
  'ut',
  'labore',
  'et',
  'dolore',
  'magna',
  'aliqua',
];

String _lorem(int count) =>
    [for (var i = 0; i < count; i++) _words[i % _words.length]].join(' ');

pw.Widget _cell(
  String text, {
  int colSpan = 1,
  int rowSpan = 1,
  bool tint = false,
  bool bold = false,
  pw.TableCellVerticalAlignment? alignment,
}) => pw.TableCell(
  colSpan: colSpan,
  rowSpan: rowSpan,
  verticalAlignment: alignment,
  child: pw.Container(
    color: tint ? PdfColors.amber100 : null,
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  ),
);

pw.TableRow _row(
  List<String> cells, {
  bool header = false,
  pw.BoxDecoration? decoration,
}) => pw.TableRow(
  repeat: header,
  decoration: header ? _headerDecoration : decoration,
  children: [for (final text in cells) _cell(text, bold: header)],
);

pw.Table _table(
  List<List<String>> rows, {
  bool header = false,
  bool striped = false,
  Map<int, pw.TableColumnWidth>? columnWidths,
}) => pw.Table(
  border: pw.TableBorder.all(color: PdfColors.grey600),
  columnWidths: columnWidths,
  children: [
    for (var i = 0; i < rows.length; i++)
      _row(
        rows[i],
        header: header && i == 0,
        decoration: striped && i.isEven ? _stripe : null,
      ),
  ],
);
