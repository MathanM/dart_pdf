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

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../pdf.dart';
import '../../widgets.dart';

/// A horizontal group of cells in a [Table].
@immutable
class TableRow {
  const TableRow({
    required this.children,
    this.repeat = false,
    this.verticalAlignment,
    this.decoration,
  });

  /// The widgets that comprise the cells in this row.
  final List<Widget> children;

  /// Repeat this row on all pages
  final bool repeat;

  final BoxDecoration? decoration;

  final TableCellVerticalAlignment? verticalAlignment;
}

enum TableCellVerticalAlignment { bottom, middle, top, full }

enum TableWidth { min, max }

class TableBorder extends Border {
  /// Creates a border for a table.
  const TableBorder({
    BorderSide left = BorderSide.none,
    BorderSide top = BorderSide.none,
    BorderSide right = BorderSide.none,
    BorderSide bottom = BorderSide.none,
    this.horizontalInside = BorderSide.none,
    this.verticalInside = BorderSide.none,
  }) : super(top: top, bottom: bottom, left: left, right: right);

  /// A uniform border with all sides the same color and width.
  factory TableBorder.all({
    PdfColor color = PdfColors.black,
    double width = 1.0,
    BorderStyle style = BorderStyle.solid,
  }) {
    final side = BorderSide(color: color, width: width, style: style);
    return TableBorder(
      top: side,
      right: side,
      bottom: side,
      left: side,
      horizontalInside: side,
      verticalInside: side,
    );
  }

  /// Creates a border for a table where all the interior sides use the same styling and all the exterior sides use the same styling.
  factory TableBorder.symmetric({
    BorderSide inside = BorderSide.none,
    BorderSide outside = BorderSide.none,
  }) {
    return TableBorder(
      top: outside,
      right: outside,
      bottom: outside,
      left: outside,
      horizontalInside: inside,
      verticalInside: inside,
    );
  }

  final BorderSide horizontalInside;
  final BorderSide verticalInside;

  void paintTable(
    Context context,
    PdfRect box, [
    List<double?>? widths,
    List<double>? heights,
  ]) {
    super.paint(context, box);

    if (verticalInside.style.paint) {
      verticalInside.style.setStyle(context);
      var offset = box.left;
      for (final width in widths!.sublist(0, widths.length - 1)) {
        offset += width!;
        context.canvas.moveTo(offset, box.bottom);
        context.canvas.lineTo(offset, box.top);
      }
      context.canvas.setStrokeColor(verticalInside.color);
      context.canvas.setLineWidth(verticalInside.width);
      context.canvas.strokePath();

      verticalInside.style.unsetStyle(context);
    }

    if (horizontalInside.style.paint) {
      horizontalInside.style.setStyle(context);
      var offset = box.top;
      for (final height in heights!.sublist(0, heights.length - 1)) {
        offset -= height;
        context.canvas.moveTo(box.left, offset);
        context.canvas.lineTo(box.right, offset);
      }
      context.canvas.setStrokeColor(horizontalInside.color);
      context.canvas.setLineWidth(horizontalInside.width);
      context.canvas.strokePath();
      horizontalInside.style.unsetStyle(context);
    }
  }

  /// Paints the outside border around [box], and inside it the right and
  /// bottom edges of each cell that don't lie on the outside border. Unlike
  /// [paintTable], this follows merged cells. [cells] are relative to the
  /// bottom-left corner of [box].
  void paintCells(Context context, PdfRect box, Iterable<PdfRect> cells) {
    super.paint(context, box);

    const tolerance = 0.001;

    if (verticalInside.style.paint) {
      verticalInside.style.setStyle(context);
      for (final cell in cells) {
        if (cell.right < box.width - tolerance) {
          context.canvas
            ..moveTo(
              box.left + cell.right,
              box.bottom + math.max(0, cell.bottom),
            )
            ..lineTo(
              box.left + cell.right,
              box.bottom + math.min(box.height, cell.top),
            );
        }
      }
      context.canvas.setStrokeColor(verticalInside.color);
      context.canvas.setLineWidth(verticalInside.width);
      context.canvas.strokePath();
      verticalInside.style.unsetStyle(context);
    }

    if (horizontalInside.style.paint) {
      horizontalInside.style.setStyle(context);
      for (final cell in cells) {
        if (cell.bottom > tolerance) {
          context.canvas
            ..moveTo(box.left + cell.left, box.bottom + cell.bottom)
            ..lineTo(box.left + cell.right, box.bottom + cell.bottom);
        }
      }
      context.canvas.setStrokeColor(horizontalInside.color);
      context.canvas.setLineWidth(horizontalInside.width);
      context.canvas.strokePath();
      horizontalInside.style.unsetStyle(context);
    }
  }
}

class TableContext extends WidgetContext {
  int firstLine = 0;
  int lastLine = 0;

  /// Whether the table continues from a previous page. Spanning widgets are
  /// continued at the top of a fresh page, so if not even one row fits it
  /// never will: the page places one anyway, or the table would never end.
  bool _continued = false;

  @override
  void apply(TableContext other) {
    firstLine = other.firstLine;
    lastLine = other.lastLine;
    _continued = other._continued;
  }

  @override
  WidgetContext clone() {
    return TableContext()..apply(this);
  }

  @override
  String toString() =>
      '$runtimeType firstLine: $firstLine lastLine: $lastLine continued: $_continued';
}

/// A cell of a [TableRow] that spans several columns or rows.
///
/// Like in an HTML table, the positions a span covers are left out of the
/// rows it reaches into: with a `rowSpan: 2` cell in the first column, the
/// next row's first child lands in the second column.
///
/// A spanning cell is laid out over the combined width of its columns, and
/// the rows grow if needed to fit it. Rows joined by a row span are never
/// split across pages.
class TableCell extends SingleChildWidget {
  TableCell({
    Widget? child,
    this.colSpan = 1,
    this.rowSpan = 1,
    this.verticalAlignment,
  }) : assert(colSpan > 0),
       assert(rowSpan > 0),
       super(child: child);

  /// The number of columns this cell covers.
  final int colSpan;

  /// The number of rows this cell covers.
  final int rowSpan;

  /// Overrides the alignment of the row the cell starts in.
  final TableCellVerticalAlignment? verticalAlignment;

  @override
  void paint(Context context) {
    super.paint(context);
    paintChild(context);
  }
}

/// Where a cell sits in the table grid, once spans are resolved.
class _Cell {
  _Cell(this.widget, this.row, this.column, this.colSpan, this.rowSpan)
    : origin = null;

  /// The part of [cell] from [row], when a page break cuts its row span
  _Cell.continued(_Cell this.origin, this.row)
    : widget = origin.widget,
      column = origin.column,
      colSpan = origin.colSpan,
      rowSpan = origin.rowEnd - row;

  final Widget widget;
  final int row;
  final int column;
  final int colSpan;
  final int rowSpan;

  /// The cell this one continues on a new page
  final _Cell? origin;

  int get rowEnd => row + rowSpan;

  int get columnEnd => column + colSpan;

  /// The area the cell covers in the table, set at layout time.
  PdfRect slot = PdfRect.zero;
}

class ColumnLayout {
  ColumnLayout(this.width, this.flex, [this.minWidth = 0]);

  final double width;
  final double flex;

  /// The narrowest width the column can take without breaking its content
  /// mid-word, see [Widget.getMinIntrinsicWidth].
  final double minWidth;
}

abstract class TableColumnWidth {
  const TableColumnWidth();

  ColumnLayout layout(
    Widget child,
    Context context,
    BoxConstraints constraints,
  );
}

class IntrinsicColumnWidth extends TableColumnWidth {
  const IntrinsicColumnWidth({this.flex});

  final double? flex;

  @override
  ColumnLayout layout(
    Widget child,
    Context context,
    BoxConstraints constraints,
  ) {
    final minWidth = child.getMinIntrinsicWidth(context);
    if (flex != null) {
      return ColumnLayout(0, flex!, minWidth);
    }

    child.layout(context, const BoxConstraints());
    assert(child.box != null);
    final calculatedWidth = child.box!.width == double.infinity
        ? 0.0
        : child.box!.width;
    final childFlex =
        flex ??
        (child is Expanded
            ? child.flex.toDouble()
            : (child.box!.width == double.infinity ? 1 : 0));
    return ColumnLayout(calculatedWidth, childFlex, minWidth);
  }
}

class FixedColumnWidth extends TableColumnWidth {
  const FixedColumnWidth(this.width);

  final double width;

  @override
  ColumnLayout layout(
    Widget child,
    Context context,
    BoxConstraints? constraints,
  ) {
    return ColumnLayout(width, 0, width);
  }
}

class FlexColumnWidth extends TableColumnWidth {
  const FlexColumnWidth([this.flex = 1.0]);

  final double flex;

  @override
  ColumnLayout layout(
    Widget child,
    Context context,
    BoxConstraints? constraints,
  ) {
    return ColumnLayout(0, flex, child.getMinIntrinsicWidth(context));
  }
}

class FractionColumnWidth extends TableColumnWidth {
  const FractionColumnWidth(this.value);

  final double value;

  @override
  ColumnLayout layout(
    Widget child,
    Context context,
    BoxConstraints? constraints,
  ) {
    // Without a bounded width there is nothing to take a fraction of
    final width = constraints!.hasBoundedWidth
        ? constraints.maxWidth * value
        : 0.0;
    return ColumnLayout(width, 0, width);
  }
}

typedef OnCellFormat = String Function(int index, dynamic data);
typedef OnCellDecoration =
    BoxDecoration Function(int index, dynamic data, int rowNum);

/// A widget that uses the table layout algorithm for its children.
class Table extends Widget with SpanningWidget {
  Table({
    this.children = const <TableRow>[],
    this.border,
    this.defaultVerticalAlignment = TableCellVerticalAlignment.top,
    this.columnWidths,
    this.defaultColumnWidth = const IntrinsicColumnWidth(),
    this.tableWidth = TableWidth.max,
  }) : super();

  @Deprecated('Use TableHelper.fromTextArray() instead.')
  factory Table.fromTextArray({
    Context? context,
    required List<List<dynamic>> data,
    EdgeInsets cellPadding = const EdgeInsets.all(5),
    double cellHeight = 0,
    Alignment cellAlignment = Alignment.topLeft,
    Map<int, Alignment>? cellAlignments,
    TextStyle? cellStyle,
    TextStyle? oddCellStyle,
    OnCellFormat? cellFormat,
    OnCellDecoration? cellDecoration,
    int headerCount = 1,
    List<dynamic>? headers,
    EdgeInsets? headerPadding,
    double? headerHeight,
    Alignment headerAlignment = Alignment.center,
    Map<int, Alignment>? headerAlignments,
    TextStyle? headerStyle,
    OnCellFormat? headerFormat,
    TableBorder? border = const TableBorder(
      left: BorderSide(),
      right: BorderSide(),
      top: BorderSide(),
      bottom: BorderSide(),
      horizontalInside: BorderSide(),
      verticalInside: BorderSide(),
    ),
    Map<int, TableColumnWidth>? columnWidths,
    TableColumnWidth defaultColumnWidth = const IntrinsicColumnWidth(),
    TableWidth tableWidth = TableWidth.max,
    BoxDecoration? headerDecoration,
    BoxDecoration? headerCellDecoration,
    BoxDecoration? rowDecoration,
    BoxDecoration? oddRowDecoration,
  }) => TableHelper.fromTextArray(
    context: context,
    data: data,
    cellPadding: cellPadding,
    cellHeight: cellHeight,
    cellAlignment: cellAlignment,
    cellAlignments: cellAlignments,
    cellStyle: cellStyle,
    oddCellStyle: oddCellStyle,
    cellFormat: cellFormat,
    cellDecoration: cellDecoration,
    headerCount: headerCount = 1,
    headers: headers,
    headerPadding: headerPadding,
    headerHeight: headerHeight,
    headerAlignment: headerAlignment,
    headerAlignments: headerAlignments,
    headerStyle: headerStyle,
    headerFormat: headerFormat,
    border: border,
    columnWidths: columnWidths,
    defaultColumnWidth: defaultColumnWidth,
    tableWidth: tableWidth,
    headerDecoration: headerDecoration,
    headerCellDecoration: headerCellDecoration,
    rowDecoration: rowDecoration,
    oddRowDecoration: oddRowDecoration,
  );

  @override
  bool get canSpan => true;

  @override
  bool get hasMoreWidgets => _context.lastLine < children.length;

  /// The rows of the table.
  final List<TableRow> children;

  final TableBorder? border;

  final TableCellVerticalAlignment defaultVerticalAlignment;

  final TableWidth tableWidth;

  final List<double> _widths = <double>[];
  final List<double> _minWidths = <double>[];
  final List<double> _flex = <double>[];

  /// Height and distance from the table top of every laid out row
  final List<double> _rowHeights = <double>[];
  final List<double> _rowTops = <double>[];

  /// Indexes of the rows on the current page, repeated headers first
  final List<int> _rows = <int>[];

  /// Whether the last row placed overflows and must be clipped
  bool _clip = false;

  /// The cells starting in each row
  List<List<_Cell>>? _grid;

  /// For each row, the end of the group of rows that row spans tie together
  List<int>? _blockEnds;

  /// The cells of the previous page whose row span goes on in this one
  final List<_Cell> _continuedCells = <_Cell>[];

  /// The height of the group of rows that didn't fit on the page
  double _overflowHeight = 0;

  int _columnCount = 0;

  /// The maximal width the column widths were computed for
  double? _layoutWidth;

  bool _hasSpans = false;

  final TableContext _context = TableContext();

  final TableColumnWidth defaultColumnWidth;
  final Map<int, TableColumnWidth>? columnWidths;

  @override
  WidgetContext saveContext() {
    return _context;
  }

  @override
  void restoreContext(TableContext context) {
    _context.apply(context);
    _context._continued = true;
    _context.firstLine = _context.lastLine;
  }

  /// Places every cell in the grid, skipping the positions covered by the
  /// spans of the rows above.
  void _resolveCells() {
    if (_grid != null) {
      return;
    }

    final grid = <List<_Cell>>[];
    // For each column, the first row no longer covered by a span
    final coveredUntil = <int>[];
    _columnCount = 0;
    _hasSpans = false;

    for (var row = 0; row < children.length; row++) {
      final cells = <_Cell>[];
      var column = 0;
      for (final child in children[row].children) {
        while (column < coveredUntil.length && coveredUntil[column] > row) {
          column++;
        }
        final colSpan = child is TableCell ? child.colSpan : 1;
        final rowSpan = child is TableCell
            ? math.min(child.rowSpan, children.length - row)
            : 1;
        if (colSpan > 1 || rowSpan > 1) {
          _hasSpans = true;
        }
        cells.add(_Cell(child, row, column, colSpan, rowSpan));
        for (var n = column; n < column + colSpan; n++) {
          if (n < coveredUntil.length) {
            // Overlapping spans overlap, like in HTML, but a span is never
            // cut short by another
            coveredUntil[n] = math.max(coveredUntil[n], row + rowSpan);
          } else {
            coveredUntil.add(row + rowSpan);
          }
        }
        column += colSpan;
      }
      _columnCount = math.max(_columnCount, column);
      grid.add(cells);
    }

    final blockEnds = List<int>.filled(children.length, 0);
    var blockStart = 0;
    var blockEnd = 0;
    for (var row = 0; row < children.length; row++) {
      blockEnd = math.max(blockEnd, row + 1);
      for (final cell in grid[row]) {
        blockEnd = math.max(blockEnd, cell.rowEnd);
      }
      if (blockEnd == row + 1) {
        blockEnds.fillRange(blockStart, blockEnd, blockEnd);
        blockStart = blockEnd;
      }
    }

    _grid = grid;
    _blockEnds = blockEnds;
  }

  TableColumnWidth _columnWidth(int column) =>
      columnWidths?[column] ?? defaultColumnWidth;

  /// Measures the natural and minimal width and the flex of every column.
  void _measureColumns(Context context, BoxConstraints constraints) {
    _widths
      ..clear()
      ..addAll(List<double>.filled(_columnCount, 0));
    _minWidths
      ..clear()
      ..addAll(List<double>.filled(_columnCount, 0));
    _flex
      ..clear()
      ..addAll(List<double>.filled(_columnCount, 0));

    void measure(int column, Widget child) {
      final layout = _columnWidth(column).layout(child, context, constraints);
      _flex[column] = math.max(_flex[column], layout.flex);
      _widths[column] = math.max(_widths[column], layout.width);
      _minWidths[column] = math.max(_minWidths[column], layout.minWidth);
    }

    final measured = List<bool>.filled(_columnCount, false);
    final spanning = <_Cell>[];
    for (final cells in _grid!) {
      for (final cell in cells) {
        if (cell.colSpan > 1) {
          spanning.add(cell);
        } else {
          measure(cell.column, cell.widget);
          measured[cell.column] = true;
        }
      }
    }

    // A column only reached by spans still gets the width it is configured with
    for (var column = 0; column < _columnCount; column++) {
      if (!measured[column]) {
        measure(column, SizedBox.shrink());
      }
    }

    // Spread the extra width spanning cells need over their columns, the
    // narrowest spans first as they constrain the columns the most.
    spanning.sort((a, b) => a.colSpan.compareTo(b.colSpan));
    for (final cell in spanning) {
      _grow(
        _minWidths,
        cell.column,
        cell.columnEnd,
        cell.widget.getMinIntrinsicWidth(context),
      );
      var flexible = false;
      for (var column = cell.column; column < cell.columnEnd; column++) {
        flexible |= _flex[column] > 0;
      }
      if (!flexible) {
        cell.widget.layout(context, const BoxConstraints());
        final width = cell.widget.box!.width;
        if (width.isFinite) {
          _grow(_widths, cell.column, cell.columnEnd, width);
        }
      }
    }

    for (var column = 0; column < _columnCount; column++) {
      _widths[column] = math.max(_widths[column], _minWidths[column]);
    }
  }

  /// Grows `values[start..end]` to sum to at least [total], proportionally to
  /// their current values.
  static void _grow(List<double> values, int start, int end, double total) {
    var current = 0.0;
    for (var n = start; n < end; n++) {
      current += values[n];
    }
    if (total <= current) {
      return;
    }
    final excess = total - current;
    for (var n = start; n < end; n++) {
      values[n] += current > 0
          ? excess * values[n] / current
          : excess / (end - start);
    }
  }

  /// Fits the columns into [maxWidth]. Columns shrink towards their minimal
  /// width in proportion to how much they can give, so that words are only
  /// broken when even the minimal widths don't fit.
  void _fitColumns(double maxWidth) {
    final totalFlex = _flex.fold(0.0, (sum, flex) => sum + flex);

    var naturalWidth = 0.0;
    var minimalWidth = 0.0;
    var flexMinimalWidth = 0.0;
    for (var n = 0; n < _columnCount; n++) {
      if (_flex[n] > 0) {
        flexMinimalWidth += _minWidths[n];
      } else {
        naturalWidth += _widths[n];
        minimalWidth += _minWidths[n];
      }
    }

    if (minimalWidth + flexMinimalWidth > maxWidth) {
      // Not even the longest words fit, they will have to break
      final scale = maxWidth / (minimalWidth + flexMinimalWidth);
      for (var n = 0; n < _columnCount; n++) {
        _widths[n] = _minWidths[n] * scale;
      }
      return;
    }

    final target = tableWidth == TableWidth.max && totalFlex == 0
        ? maxWidth
        : math.min(naturalWidth, maxWidth - flexMinimalWidth);

    if (target >= naturalWidth) {
      final count = _flex.where((flex) => flex == 0).length;
      for (var n = 0; n < _columnCount; n++) {
        if (_flex[n] == 0 && target > naturalWidth) {
          _widths[n] = naturalWidth > 0
              ? _widths[n] * target / naturalWidth
              : target / count;
        }
      }
    } else {
      // Between the natural and the minimal widths: every column gives up
      // the same share of the room it has above its minimum
      final ratio = (target - minimalWidth) / (naturalWidth - minimalWidth);
      for (var n = 0; n < _columnCount; n++) {
        if (_flex[n] == 0) {
          _widths[n] = _minWidths[n] + (_widths[n] - _minWidths[n]) * ratio;
        }
      }
    }

    if (totalFlex == 0) {
      return;
    }

    var space = maxWidth;
    for (var n = 0; n < _columnCount; n++) {
      if (_flex[n] == 0) {
        space -= _widths[n];
      }
    }

    // Share the space left by flex, but never below a column's minimal
    // width: those columns are frozen at their minimum and the rest
    // shared again among the others.
    final flexible = <int>[
      for (var n = 0; n < _columnCount; n++)
        if (_flex[n] > 0) n,
    ];
    var frozen = true;
    while (frozen && flexible.isNotEmpty) {
      frozen = false;
      final flex = flexible.fold(0.0, (sum, n) => sum + _flex[n]);
      final spacePerFlex = space / flex;
      for (final n in flexible.toList()) {
        if (spacePerFlex * _flex[n] < _minWidths[n]) {
          _widths[n] = _minWidths[n];
          space -= _minWidths[n];
          flexible.remove(n);
          frozen = true;
        }
      }
      if (!frozen) {
        for (final n in flexible) {
          _widths[n] = spacePerFlex * _flex[n];
        }
      }
    }
  }

  double _spanWidth(_Cell cell) {
    var width = 0.0;
    for (var n = cell.column; n < cell.columnEnd; n++) {
      width += _widths[n];
    }
    return width;
  }

  double _spanHeight(_Cell cell) {
    var height = 0.0;
    for (var n = cell.row; n < cell.rowEnd; n++) {
      height += _rowHeights[n];
    }
    return height;
  }

  TableCellVerticalAlignment _alignment(_Cell cell) {
    final widget = cell.widget;
    return (widget is TableCell ? widget.verticalAlignment : null) ??
        children[(cell.origin ?? cell).row].verticalAlignment ??
        defaultVerticalAlignment;
  }

  /// The cells starting in [row], with the cells continued from the
  /// previous page on its first row
  List<_Cell> _cellsIn(int row) =>
      row == _context.firstLine && _continuedCells.isNotEmpty
      ? [..._continuedCells, ..._grid![row]]
      : _grid![row];

  /// Whether the rows `start..end` are headers: rows to [TableRow.repeat]
  /// that introduce more rows.
  bool _isHeader(int start, int end) {
    for (var row = start; row < children.length; row++) {
      if (!children[row].repeat) {
        return row >= end;
      }
    }
    return false;
  }

  /// Lays out the cells starting in rows `start..end`, a whole group of rows
  /// tied by spans, and returns its height.
  double _layoutRows(Context context, int start, int end) {
    final spanning = <_Cell>[];
    for (var row = start; row < end; row++) {
      _rowHeights[row] = 0;
      for (final cell in _cellsIn(row)) {
        cell.widget.layout(
          context,
          BoxConstraints.tightFor(width: _spanWidth(cell)),
        );
        assert(cell.widget.box != null);
        if (cell.origin != null) {
          // Its content was already shown, it only fills its rows
          continue;
        }
        if (cell.rowSpan > 1) {
          spanning.add(cell);
        } else {
          _rowHeights[row] = math.max(
            _rowHeights[row],
            cell.widget.box!.height,
          );
        }
      }
    }

    // Rows grow evenly when a cell spanning them needs more height
    spanning.sort((a, b) => a.rowSpan.compareTo(b.rowSpan));
    for (final cell in spanning) {
      final excess = cell.widget.box!.height - _spanHeight(cell);
      if (excess > 0) {
        for (var row = cell.row; row < cell.rowEnd; row++) {
          _rowHeights[row] += excess / cell.rowSpan;
        }
      }
    }

    // Compute the layout again to give the full height to these cells
    for (var row = start; row < end; row++) {
      for (final cell in _cellsIn(row)) {
        if (_alignment(cell) == TableCellVerticalAlignment.full) {
          cell.widget.layout(
            context,
            BoxConstraints.tightFor(
              width: _spanWidth(cell),
              height: _spanHeight(cell),
            ),
          );
        }
      }
    }

    var height = 0.0;
    for (var row = start; row < end; row++) {
      height += _rowHeights[row];
    }
    return height;
  }

  /// Fills [_rows] with the rows that fit in [maxHeight] from
  /// [TableContext.firstLine], after the header rows of the previous pages
  /// if [repeatHeaders], and returns their height.
  ///
  /// Headers are not left alone at the bottom of a page: they move to the
  /// next one with the rows they introduce. Without [repeatHeaders] the
  /// page must make progress, so rows that don't fit are placed anyway and
  /// clipped.
  double _placeRows(
    Context context,
    double maxHeight, {
    required bool repeatHeaders,
  }) {
    final blockEnds = _blockEnds!;
    final firstLine = _context.firstLine;
    final split = !repeatHeaders;
    _rows.clear();
    _clip = false;
    _overflowHeight = 0;
    var totalHeight = 0.0;

    if (repeatHeaders) {
      for (var start = 0; start < firstLine; start = blockEnds[start]) {
        final end = blockEnds[start];
        if (end <= firstLine && _isHeader(start, end)) {
          totalHeight += _layoutRows(context, start, end);
          _rows.addAll([for (var row = start; row < end; row++) row]);
        }
      }
    }

    // Where the page stands after its last row that isn't a header
    var lastLine = firstLine;
    var bodyLine = firstLine;
    var bodyRows = 0;
    var bodyHeight = 0.0;

    for (var start = firstLine; start < children.length; start = lastLine) {
      final end = blockEnds[start];
      final height = _layoutRows(context, start, end);

      if (totalHeight + height > maxHeight) {
        _overflowHeight = height;
        if (split && bodyRows == 0) {
          // Only headers precede this group. Drop them if they leave no
          // room for its first row: the next pages repeat them. Then place
          // as many rows of the group as fit, at least one.
          if (totalHeight + _rowHeights[start] > maxHeight) {
            _rows.clear();
            totalHeight = 0;
          }
          var row = start;
          do {
            totalHeight += _rowHeights[row];
            _rows.add(row++);
          } while (row < end && totalHeight + _rowHeights[row] <= maxHeight);
          // The spans cut here only cover the rows shown on this page
          _rowHeights.fillRange(row, end, 0);
          lastLine = bodyLine = row;
          bodyRows = _rows.length;
          bodyHeight = totalHeight;
          _clip = true;
        }
        break;
      }

      totalHeight += height;
      _rows.addAll([for (var row = start; row < end; row++) row]);
      lastLine = end;

      if (!_isHeader(start, end)) {
        bodyLine = lastLine;
        bodyRows = _rows.length;
        bodyHeight = totalHeight;
      }
    }

    if (lastLine < children.length) {
      _rows.length = bodyRows;
      lastLine = bodyLine;
      totalHeight = bodyHeight;
    }
    _context.lastLine = lastLine;
    return totalHeight;
  }

  @override
  void layout(
    Context context,
    BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    _resolveCells();
    _rows.clear();
    _clip = false;

    if (_columnCount == 0) {
      _context.lastLine = children.length;
      box = PdfRect.fromPoints(PdfPoint.zero, constraints.smallest);
      return;
    }

    // Column widths don't depend on the rows on the page, so they are only
    // computed once for all the pages
    if (_layoutWidth != constraints.maxWidth) {
      _measureColumns(context, constraints);
      if (constraints.hasBoundedWidth) {
        _fitColumns(constraints.maxWidth);
      }
      _layoutWidth = constraints.maxWidth;
    }
    final totalWidth = _widths.fold(0.0, (sum, width) => sum + width);

    _rowHeights
      ..clear()
      ..addAll(List<double>.filled(children.length, 0));
    _rowTops
      ..clear()
      ..addAll(List<double>.filled(children.length, 0));

    // A page break cut the row spans of these cells: they go on over the
    // rows left on this page
    final firstLine = _context.firstLine;
    _continuedCells.clear();
    if (firstLine < children.length) {
      final blockEnd = _blockEnds![firstLine];
      for (
        var row = firstLine - 1;
        row >= 0 && _blockEnds![row] == blockEnd;
        row--
      ) {
        for (final cell in _grid![row]) {
          if (cell.rowEnd > firstLine) {
            _continuedCells.add(_Cell.continued(cell, firstLine));
          }
        }
      }
    }

    final maxHeight = constraints.maxHeight + 0.00001;
    var totalHeight = _placeRows(context, maxHeight, repeatHeaders: true);
    if (_rows.isEmpty &&
        firstLine < children.length &&
        (_context._continued ||
            _overflowHeight > context.page.pageFormat.height)) {
      // Even a fresh page can't fit the headers and the rows that follow:
      // drop the headers, and split the rows if they still don't fit.
      totalHeight = _placeRows(context, maxHeight, repeatHeaders: false);
    }

    final height = _clip
        ? math.min(totalHeight, constraints.maxHeight)
        : totalHeight;

    // Compute final positions
    var top = 0.0;
    for (final row in _rows) {
      _rowTops[row] = top;
      top += _rowHeights[row];
    }

    final columnLefts = List<double>.filled(_columnCount, 0);
    for (var n = 1; n < _columnCount; n++) {
      columnLefts[n] = columnLefts[n - 1] + _widths[n - 1];
    }

    for (final row in _rows) {
      for (final cell in _cellsIn(row)) {
        final slotHeight = _spanHeight(cell);
        cell.slot = PdfRect(
          columnLefts[cell.column],
          height - _rowTops[row] - slotHeight,
          _spanWidth(cell),
          slotHeight,
        );

        final child = cell.widget.box!;
        final double y;
        switch (_alignment(cell)) {
          case TableCellVerticalAlignment.bottom:
            y = cell.slot.bottom;
            break;
          case TableCellVerticalAlignment.middle:
            y = cell.slot.bottom + (slotHeight - child.height) / 2;
            break;
          case TableCellVerticalAlignment.top:
          case TableCellVerticalAlignment.full:
            y = cell.slot.top - child.height;
            break;
        }

        cell.widget.box = PdfRect(cell.slot.left, y, child.width, child.height);
      }
    }

    box = PdfRect(0, 0, totalWidth, height);
  }

  @override
  void paint(Context context) {
    super.paint(context);

    if (_rows.isEmpty) {
      return;
    }

    final mat = Matrix4.identity();
    mat.translateByDouble(box!.left, box!.bottom, 0, 1);
    context.canvas
      ..saveContext()
      ..setTransform(mat);

    if (_clip) {
      context.canvas
        ..drawRect(0, 0, box!.width, box!.height)
        ..clipPath();
    }

    PdfRect rowRect(int row) => PdfRect(
      0,
      box!.height - _rowTops[row] - _rowHeights[row],
      box!.width,
      _rowHeights[row],
    );

    for (final row in _rows) {
      children[row].decoration?.paint(
        context,
        rowRect(row),
        PaintPhase.background,
      );
    }

    for (final row in _rows) {
      for (final cell in _cellsIn(row)) {
        // A cell is cut to its slot when a page break shortens its row span
        final child = cell.widget;
        final bottom = math.max(child.box!.bottom, cell.slot.bottom);
        final top = math.min(child.box!.top, cell.slot.top);
        context.canvas
          ..saveContext()
          ..drawRect(
            child.box!.left,
            bottom,
            child.box!.width,
            math.max(0, top - bottom),
          )
          ..clipPath();
        child.paint(context);
        context.canvas.restoreContext();
      }
    }

    for (final row in _rows) {
      children[row].decoration?.paint(
        context,
        rowRect(row),
        PaintPhase.foreground,
      );
    }

    context.canvas.restoreContext();

    if (border != null) {
      if (_hasSpans) {
        border!.paintCells(context, box!, <PdfRect>[
          for (final row in _rows)
            for (final cell in _cellsIn(row)) cell.slot,
        ]);
      } else {
        border!.paintTable(context, box!, _widths, [
          for (final row in _rows) _rowHeights[row],
        ]);
      }
    }
  }

  @override
  double getMinIntrinsicWidth(Context context) {
    _resolveCells();
    _measureColumns(context, const BoxConstraints());
    _layoutWidth = null;
    return _minWidths.fold(0.0, (sum, width) => sum + width);
  }
}
