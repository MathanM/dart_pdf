import 'package:pdf/src/pdf/font/bidi_utils.dart';
import 'package:test/test.dart';

void main() {
  test('mixed RTL word slots keep Latin phrases in visual LTR order', () {
    expect(visualWordOrder(['ترتيب', 'Right', 'Order', 'العربي'], rtl: true), [
      0,
      2,
      1,
      3,
    ]);
    expect(visualWordOrder(['Right', 'Order'], rtl: true), [1, 0]);
    expect(visualWordOrder(['السعر', '123', 'ريال'], rtl: true), [0, 1, 2]);
  });
  test('LTR paragraphs keep embedded Arabic phrases in RTL order', () {
    expect(
      visualWordOrder(['Hello', 'اللغة', 'العربية', 'world'], rtl: false),
      [0, 2, 1, 3],
    );
  });
  test('combining marks and surrogate pairs retain source word identities', () {
    expect(
      visualWordOrder([
        'ترتيب',
        'cafe\u0301',
        '😀',
        'Order',
        'العربي',
      ], rtl: true),
      [0, 3, 2, 1, 4],
    );
    expect(visualWordOrder(['தமிழ்', 'हिन्दी', 'English'], rtl: false), [
      0,
      1,
      2,
    ]);
    expect(visualWordOrder(['العربي', 'résumé', 'café', 'العربي'], rtl: true), [
      0,
      2,
      1,
      3,
    ]);
    expect(visualWordOrder(['العربي', 'Γειά', 'σου', 'العربي'], rtl: true), [
      0,
      2,
      1,
      3,
    ]);
  });
}
