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

import 'package:meta/meta.dart';

import 'point.dart';

@immutable
class PdfRect {
  const PdfRect(
    this.left,
    this.bottom,
    this.width,
    this.height, [
    this.minWidth,
  ]);

  @Deprecated('Use PdfRect.fromLBRT instead')
  factory PdfRect.fromLTRB(
    double left,
    double bottom,
    double right,
    double top, [
    double? minWidth,
  ]) = PdfRect.fromLBRT;

  factory PdfRect.fromLBRT(
    double left,
    double bottom,
    double right,
    double top, [
    double? minWidth,
  ]) {
    return PdfRect(left, bottom, right - left, top - bottom, minWidth);
  }

  factory PdfRect.fromPoints(
    PdfPoint offset,
    PdfPoint size, [
    double? minWidth,
  ]) {
    return PdfRect(offset.x, offset.y, size.x, size.y, minWidth);
  }

  final double left, bottom, width, height;

  /// The narrowest width the content can take without overflowing, such as
  /// the widest unbreakable word of a paragraph. Tables use it to keep columns
  /// from shrinking below their content.
  final double? minWidth;

  static const PdfRect zero = PdfRect(0, 0, 0, 0);

  @Deprecated('Use left instead')
  double get x => left;

  @Deprecated('Use bottom instead')
  double get y => bottom;

  double get right => left + width;

  double get top => bottom + height;

  @Deprecated('type => horizontalCenter')
  double get horizondalCenter => horizontalCenter;

  double get horizontalCenter => left + width / 2;

  double get verticalCenter => bottom + height / 2;

  @override
  String toString() => 'PdfRect($left, $bottom, $width, $height)';

  PdfRect operator *(double factor) {
    return PdfRect(
      left * factor,
      bottom * factor,
      width * factor,
      height * factor,
    );
  }

  PdfPoint get offset => PdfPoint(left, bottom);

  PdfPoint get size => PdfPoint(width, height);

  @Deprecated('Use leftBottom instead')
  PdfPoint get topLeft => PdfPoint(left, bottom);
  PdfPoint get leftBottom => PdfPoint(left, bottom);

  @Deprecated('Use rightBottom instead')
  PdfPoint get topRight => PdfPoint(right, bottom);
  PdfPoint get rightBottom => PdfPoint(right, bottom);

  @Deprecated('Use leftTop instead')
  PdfPoint get bottomLeft => PdfPoint(left, top);
  PdfPoint get leftTop => PdfPoint(left, top);

  @Deprecated('Use rightTop instead')
  PdfPoint get bottomRight => PdfPoint(right, top);
  PdfPoint get rightTop => PdfPoint(right, top);

  /// Returns a new rectangle with edges moved outwards by the given delta.
  PdfRect inflate(double delta, [double? minWidth]) {
    return PdfRect.fromLBRT(
      left - delta,
      bottom - delta,
      right + delta,
      top + delta,
      minWidth,
    );
  }

  /// Returns a new rectangle with edges moved inwards by the given delta.
  PdfRect deflate(double delta) => inflate(-delta);

  PdfRect copyWith({
    @Deprecated('Use left instead') double? x,
    double? left,
    @Deprecated('Use bottom instead') double? y,
    double? bottom,
    double? width,
    double? height,
    double? minWidth,
  }) {
    return PdfRect(
      left ?? x ?? this.left,
      bottom ?? y ?? this.bottom,
      width ?? this.width,
      height ?? this.height,
      minWidth ?? this.minWidth,
    );
  }
}
