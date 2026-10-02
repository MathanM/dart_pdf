/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:test/test.dart';

late Context context;

/// Records `page:name` for each painted cell
final painted = <String>[];

class Probe extends SingleChildWidget {
  Probe(this.name, Widget child) : super(child: child);

  final String name;

  @override
  void paint(Context context) {
    super.paint(context);
    painted.add('${context.pageNumber}:$name');
    paintChild(context);
  }
}

Widget probe(String name, {double height = 20, int rowSpan = 1}) => TableCell(
  rowSpan: rowSpan,
  child: Probe(name, SizedBox(height: height, width: 50)),
);

/// Renders [widgets] in a MultiPage and returns the page count
Future<int> render(List<Widget> widgets) async {
  painted.clear();
  final document = Document();
  document.addPage(MultiPage(build: (context) => widgets));
  await document.save();
  return document.document.pdfPageList.pages.length;
}

Widget cell(String text, {int colSpan = 1, int rowSpan = 1, double? height}) =>
    TableCell(
      colSpan: colSpan,
      rowSpan: rowSpan,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: height == null
            ? Text(text)
            : SizedBox(height: height, child: Text(text)),
      ),
    );

TableRow row(List<Widget> cells, {bool repeat = false}) =>
    TableRow(children: cells, repeat: repeat);

double lineHeight() {
  final text = Text('X');
  text.layout(context, const BoxConstraints());
  return text.box!.height;
}

double wordWidth(String word) {
  final text = Text(word);
  text.layout(context, const BoxConstraints());
  return text.box!.width;
}

void main() {
  setUp(() {
    final document = PdfDocument();
    final page = PdfPage(document);
    context = Context(
      document: document,
      page: page,
      canvas: page.getGraphics(),
    ).inheritFromAll(<Inherited>[ThemeData.base()]);
  });

  group('min width', () {
    test('Text reports its widest word', () {
      final width = Text(
        'a Supercalifragilistic b',
      ).getMinIntrinsicWidth(context);
      expect(width, closeTo(wordWidth('Supercalifragilistic'), 0.001));
    });

    test('Text without soft wrap reports its whole line', () {
      final width = Text(
        'one two',
        softWrap: false,
      ).getMinIntrinsicWidth(context);
      expect(width, closeTo(wordWidth('one two'), 0.5));
    });

    test('Padding and Row add up', () {
      final width = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(children: [Text('aaa'), Text('bbbb')]),
      ).getMinIntrinsicWidth(context);
      expect(width, closeTo(wordWidth('aaa') + wordWidth('bbbb') + 6, 0.001));
    });

    test('table columns never break a word', () {
      const long = 'Incomprehensibilities';
      final longCell = Text(long);
      final table = Table(
        border: TableBorder.all(),
        children: [
          TableRow(
            children: [
              Text(
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit, '
                'sed do eiusmod tempor incididunt ut labore',
              ),
              longCell,
              Text(
                'Ut enim ad minim veniam, quis nostrud exercitation '
                'ullamco laboris nisi ut aliquip ex ea commodo',
              ),
            ],
          ),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 300));

      expect(table.box!.width, closeTo(300, 0.001));
      expect(longCell.box!.width, greaterThanOrEqualTo(wordWidth(long)));
      expect(longCell.box!.height, closeTo(lineHeight(), 0.001));
    });

    test('flex columns keep their minimal width', () {
      const long = 'Incomprehensibilities';
      final longCell = Text(long);
      final table = Table(
        columnWidths: const {0: FlexColumnWidth(5), 1: FlexColumnWidth(1)},
        children: [
          TableRow(children: [Text('a'), longCell]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 200));

      expect(table.box!.width, closeTo(200, 0.001));
      expect(longCell.box!.width, greaterThanOrEqualTo(wordWidth(long)));
    });

    test('words break when even the minimal widths overflow', () {
      final table = Table(
        children: [
          TableRow(
            children: [Text('Incomprehensibilities'), Text('Unbelievably')],
          ),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 50));

      expect(table.box!.width, closeTo(50, 0.001));
    });

    test('nested table min width is the sum of its columns', () {
      final table = Table(
        children: [
          TableRow(children: [Text('aaa bb'), Text('cccc d')]),
        ],
      );
      expect(
        table.getMinIntrinsicWidth(context),
        closeTo(wordWidth('aaa') + wordWidth('cccc'), 0.001),
      );
    });
  });

  group('spans', () {
    test('a column span covers the width of its columns', () {
      final a = cell('a');
      final b = cell('b');
      final wide = cell('wide', colSpan: 2);
      final c = cell('c');
      final table = Table(
        columnWidths: const {
          0: FixedColumnWidth(30),
          1: FixedColumnWidth(40),
          2: FixedColumnWidth(50),
        },
        tableWidth: TableWidth.min,
        children: [
          row([a, b, cell('x')]),
          row([wide, c]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 500));

      expect(wide.box!.left, 0);
      expect(wide.box!.width, closeTo(70, 0.001));
      expect(c.box!.left, closeTo(70, 0.001));
      expect(c.box!.width, closeTo(50, 0.001));
    });

    test('a row span covers the height of its rows and shifts cells', () {
      final tall = cell('tall', rowSpan: 2);
      final r0 = cell('r0', height: 10);
      final r1 = cell('r1', height: 15);
      final table = Table(
        columnWidths: const {0: FixedColumnWidth(30), 1: FixedColumnWidth(40)},
        tableWidth: TableWidth.min,
        defaultVerticalAlignment: TableCellVerticalAlignment.full,
        children: [
          row([tall, r0]),
          row([r1]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 500));

      expect(r1.box!.left, closeTo(30, 0.001));
      expect(table.box!.height, closeTo(14 + 19, 0.001));
      expect(tall.box!.height, closeTo(table.box!.height, 0.001));
      expect(tall.box!.bottom, closeTo(0, 0.001));
    });

    test('rows grow to fit a row span taller than them', () {
      final tall = cell('tall', rowSpan: 2, height: 100);
      final table = Table(
        children: [
          row([tall, cell('a')]),
          row([cell('b')]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 500));

      expect(table.box!.height, closeTo(104, 0.001));
    });

    test('a wide span grows its columns to its minimal width', () {
      const long = 'Incomprehensibilities';
      final table = Table(
        children: [
          row([cell('a'), cell('b')]),
          row([cell(long, colSpan: 2)]),
        ],
      );
      expect(
        table.getMinIntrinsicWidth(context),
        closeTo(wordWidth(long) + 4, 0.001),
      );
    });
  });

  group('pages', () {
    test('headers repeat on the next page', () {
      final header = cell('Header');
      final table = Table(
        children: [
          row([header], repeat: true),
          for (var i = 0; i < 10; i++) row([cell('row $i', height: 20)]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 200, maxHeight: 70));
      final saved = table.saveContext().clone() as TableContext;
      expect(saved.lastLine, 3);
      expect(table.hasMoreWidgets, isTrue);

      table.restoreContext(saved);
      table.layout(context, const BoxConstraints(maxWidth: 200, maxHeight: 70));

      expect(header.box!.top, closeTo(table.box!.height, 0.001));
      expect((table.saveContext() as TableContext).lastLine, 5);
    });

    test('headers are not left alone at the bottom of a page', () {
      final table = Table(
        children: [
          row([cell('Header')], repeat: true),
          row([cell('body', height: 50)]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 200, maxHeight: 30));

      expect(table.box!.height, 0);
      expect((table.saveContext() as TableContext).lastLine, 0);
    });

    test('rows joined by a row span stay on the same page', () {
      final table = Table(
        children: [
          row([cell('a', height: 20), cell('b', height: 20)]),
          row([cell('span', rowSpan: 2, height: 20), cell('c', height: 20)]),
          row([cell('d', height: 20)]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 200, maxHeight: 60));

      expect((table.saveContext() as TableContext).lastLine, 1);
      expect(table.box!.height, closeTo(24, 0.001));
    });

    test('a long table with spans and headers spans pages', () {
      final document = Document();
      document.addPage(
        MultiPage(
          build: (context) => [
            Table(
              border: TableBorder.all(),
              children: [
                row([cell('Name'), cell('Value', colSpan: 2)], repeat: true),
                for (var i = 0; i < 60; i++)
                  if (i.isEven)
                    row([
                      cell('group $i', rowSpan: 2),
                      cell('left $i'),
                      cell('right $i'),
                    ])
                  else
                    row([cell('left $i'), cell('right $i')]),
              ],
            ),
          ],
        ),
      );

      expect(document.document.pdfPageList.pages.length, greaterThan(1));
    });

    test('a row taller than any page is split where it starts', () async {
      final pages = await render([
        SizedBox(height: 100),
        Table(
          children: [
            row([probe('H')], repeat: true),
            row([probe('huge', height: 2000)]),
            row([probe('after')]),
          ],
        ),
      ]);

      // The row can't fit on any page: it is clipped on the first one,
      // without the headers that leave it no room
      expect(pages, 2);
      expect(painted, ['1:huge', '2:H', '2:after']);
    });

    test('headers are dropped when a row needs the whole page', () async {
      final pages = await render([
        SizedBox(height: 100),
        Table(
          children: [
            row([probe('H', height: 100)], repeat: true),
            for (var i = 0; i < 3; i++) row([probe('r$i', height: 700)]),
          ],
        ),
      ]);

      expect(pages, 4);
      expect(painted, ['2:r0', '3:r1', '4:r2']);
    });

    test('a row span group taller than a page is split', () async {
      final pages = await render([
        SizedBox(height: 100),
        Table(
          children: [
            row([probe('a'), probe('span', rowSpan: 3)]),
            row([probe('b', height: 500)]),
            row([probe('c', height: 500)]),
            row([probe('d'), probe('e')]),
          ],
        ),
      ]);

      // The group can't fit on any page: it is split where it starts, and
      // the cut span goes on over the rows of the next page
      expect(pages, 2);
      expect(painted, ['1:a', '1:span', '1:b', '2:span', '2:c', '2:d', '2:e']);
    });

    test('headers stay when the first row of a split group fits', () async {
      final pages = await render([
        Table(
          children: [
            row([probe('H')], repeat: true),
            row([probe('a', height: 600), probe('span', rowSpan: 2)]),
            row([probe('b', height: 600)]),
          ],
        ),
      ]);

      // A table at the top of the first page doesn't leave it blank
      expect(pages, 2);
      expect(painted, ['1:H', '1:a', '1:span', '2:H', '2:span', '2:b']);
    });

    test('a table of repeated rows only fills its pages', () async {
      final pages = await render([
        Table(
          children: [
            for (var i = 0; i < 12; i++)
              row([probe('r$i', height: 100)], repeat: true),
          ],
        ),
      ]);

      expect(pages, 2);
      expect(painted.where((p) => p.startsWith('2:')), isNot(contains('2:r0')));
      expect(painted.length, 12);
    });

    test('headers repeat on every page and never end a page', () async {
      final pages = await render([
        Table(
          children: [
            row([probe('H')], repeat: true),
            for (var i = 0; i < 100; i++) row([probe('r$i')]),
          ],
        ),
      ]);

      expect(pages, greaterThan(1));
      for (var page = 1; page <= pages; page++) {
        final onPage = painted.where((p) => p.startsWith('$page:')).toList();
        expect(onPage.first, '$page:H');
        expect(onPage.length, greaterThan(1));
      }
      expect(painted.where((p) => !p.endsWith(':H')).length, 100);
    });
  });

  group('robustness', () {
    test('flex columns whose minimal width overflows still fit', () {
      final table = Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        children: [
          TableRow(children: [Text('Hello'), Text('Incomprehensibilities')]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 60));

      expect(table.box!.width, closeTo(60, 0.001));
    });

    test('overlapping spans keep the earlier row span', () {
      final w = cell('w');
      final table = Table(
        columnWidths: const {
          0: FixedColumnWidth(10),
          1: FixedColumnWidth(20),
          2: FixedColumnWidth(30),
        },
        tableWidth: TableWidth.min,
        children: [
          row([cell('x'), cell('y', rowSpan: 3)]),
          row([cell('z', colSpan: 2)]),
          row([cell('p'), w]),
        ],
      );

      table.layout(context, const BoxConstraints(maxWidth: 500));

      // Column 1 is still covered by y on the last row
      expect(w.box!.left, closeTo(30, 0.001));
    });

    test('fraction columns without a bounded width', () {
      final table = Table(
        columnWidths: const {0: FractionColumnWidth(0.5)},
        children: [
          TableRow(children: [Text('a'), Text('b')]),
        ],
      );

      table.layout(context, const BoxConstraints());

      expect(table.box!.width.isFinite, isTrue);
    });
  });
}
