import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi_bindings.dart' as hb;

/// Independent reference: one logical, single-script probe shaped directly by
/// HarfBuzz, bypassing package itemization, bidi conversion, and PDF rendering.
List<List<num>> referenceShape(
  ByteData bytes,
  String text, {
  required String script,
  required String language,
  required bool rtl,
}) => using((arena) {
  final data = arena<Uint8>(bytes.lengthInBytes);
  data
      .asTypedList(bytes.lengthInBytes)
      .setAll(
        0,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
  final blob = hb.hb_blob_create(
    data.cast(),
    bytes.lengthInBytes,
    hb.hb_memory_mode_t.HB_MEMORY_MODE_READONLY,
    nullptr,
    nullptr,
  );
  final face = hb.hb_face_create(blob, 0);
  final font = hb.hb_font_create(face);
  final buffer = hb.hb_buffer_create();
  try {
    hb.hb_ot_font_set_funcs(font);
    final upem = hb.hb_face_get_upem(face);
    hb.hb_font_set_scale(font, upem, upem);
    final input = arena<Uint16>(text.length)
      ..asTypedList(text.length).setAll(0, text.codeUnits);
    hb.hb_buffer_add_utf16(buffer, input, text.length, 0, text.length);
    hb.hb_buffer_set_direction(
      buffer,
      rtl
          ? hb.hb_direction_t.HB_DIRECTION_RTL
          : hb.hb_direction_t.HB_DIRECTION_LTR,
    );
    hb.hb_buffer_set_script(
      buffer,
      hb.hb_script_from_string(
        script.toNativeUtf8(allocator: arena).cast(),
        -1,
      ),
    );
    hb.hb_buffer_set_language(
      buffer,
      hb.hb_language_from_string(
        language.toNativeUtf8(allocator: arena).cast(),
        -1,
      ),
    );
    hb.hb_shape(font, buffer, nullptr, 0);
    final count = arena<UnsignedInt>();
    final infos = hb.hb_buffer_get_glyph_infos(buffer, count);
    final positions = hb.hb_buffer_get_glyph_positions(buffer, nullptr);
    return [
      for (var i = 0; i < count.value; i++)
        <num>[
          infos[i].codepoint,
          infos[i].cluster,
          positions[i].x_advance / upem,
          positions[i].y_advance / upem,
          positions[i].x_offset / upem,
          positions[i].y_offset / upem,
        ],
    ];
  } finally {
    hb.hb_buffer_destroy(buffer);
    hb.hb_font_destroy(font);
    hb.hb_face_destroy(face);
    hb.hb_blob_destroy(blob);
  }
});
