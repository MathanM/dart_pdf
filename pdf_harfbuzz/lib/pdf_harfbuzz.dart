/// Native OpenType shaping for package:pdf.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:bidi/bidi.dart' as bidi;
import 'package:characters/characters.dart';
import 'package:ffi/ffi.dart';
import 'package:harfbuzz_ffi/harfbuzz_ffi_bindings.dart' as hb;
import 'package:pdf/pdf.dart';

/// HarfBuzz's OpenType shaper, with automatic script detection and an optional
/// BCP-47 language tag. Supports horizontal text, including Indic, Arabic,
/// Persian, Urdu, and Hebrew scripts.
///
/// Pass to `pw.Font.ttf(bytes, shaper: HarfBuzzTextShaper(language: 'ta'))`.
/// Native resources are released on every call; the PDF font caches shaped runs.
class HarfBuzzTextShaper extends PdfTextShaper {
  const HarfBuzzTextShaper({this.language});

  final String? language;

  @override
  PdfGlyphRun shape(ByteData font, String text) {
    if (text.isEmpty) return PdfGlyphRun(glyphs: [], breaks: []);
    if (text.runes.any(
      (r) => const [
        bidi.CharacterType.al,
        bidi.CharacterType.rtl,
      ].contains(bidi.getCharacterType(r)),
    )) {
      return _shapeBidi(font, text);
    }
    // HarfBuzz expects one script per buffer. Use its Unicode script database,
    // retaining common/inherited characters with the surrounding script.
    final unicode = hb.hb_unicode_funcs_get_default();
    var script = hb.hb_script_t.HB_SCRIPT_COMMON;
    var start = 0;
    var offset = 0;
    final segments = <(int, int, hb.hb_script_t)>[];
    for (final cluster in text.characters) {
      var next = hb.hb_script_t.HB_SCRIPT_COMMON;
      for (final rune in cluster.runes) {
        final type = bidi.getCharacterType(rune);
        if (type == bidi.CharacterType.en || type == bidi.CharacterType.an) {
          next = hb.hb_script_t.HB_SCRIPT_LATIN;
          break;
        }
        final value = hb.hb_unicode_script(unicode, rune);
        if (value != hb.hb_script_t.HB_SCRIPT_COMMON &&
            value != hb.hb_script_t.HB_SCRIPT_INHERITED &&
            value != hb.hb_script_t.HB_SCRIPT_UNKNOWN) {
          next = value;
          break;
        }
      }
      if (next != hb.hb_script_t.HB_SCRIPT_COMMON && next != script) {
        if (script != hb.hb_script_t.HB_SCRIPT_COMMON) {
          segments.add((start, offset, script));
          start = offset;
        }
        script = next;
      }
      offset += cluster.length;
    }
    segments.add((start, text.length, script));
    final glyphs = <PdfShapedGlyph>[];
    final breaks = <int>[];
    for (final (start, end, script) in segments) {
      final run = _shapeRun(font, text.substring(start, end), script);
      glyphs.addAll(
        run.glyphs.map(
          (g) => PdfShapedGlyph(
            glyphId: g.glyphId,
            cluster: g.cluster + start,
            xAdvance: g.xAdvance,
            yAdvance: g.yAdvance,
            xOffset: g.xOffset,
            yOffset: g.yOffset,
          ),
        ),
      );
      breaks.addAll(run.breaks.map((b) => b + start));
    }
    return PdfGlyphRun(glyphs: glyphs, breaks: breaks);
  }

  /// Use the existing Unicode bidi engine only for source-index ordering.
  /// Its presentation-form characters are never sent to HarfBuzz.
  PdfGlyphRun _shapeBidi(ByteData font, String text) {
    final ranks = <int, int>{};
    final visualCharacters = <int, int>{};
    var base = 0;
    var rank = 0;
    final indexText = PdfTextShaper.bidiIndexText(text);
    for (final paragraph in bidi.BidiString.fromLogical(indexText).paragraphs) {
      final visual = paragraph.bidiText;
      for (var i = 0; i < paragraph.indices.length; i++) {
        final index = base + paragraph.indices[i];
        ranks.putIfAbsent(index, () => rank);
        visualCharacters[index] = visual[i];
        rank++;
      }
      base += paragraph.text.length + 1;
    }
    final unicode = hb.hb_unicode_funcs_get_default();
    final segments = <(int, int, hb.hb_script_t, bool)>[];
    final clusters = text.characters.toList();
    final scripts = clusters.map((cluster) {
      for (final rune in cluster.runes) {
        final script = hb.hb_unicode_script(unicode, rune);
        if (script != hb.hb_script_t.HB_SCRIPT_COMMON &&
            script != hb.hb_script_t.HB_SCRIPT_INHERITED &&
            script != hb.hb_script_t.HB_SCRIPT_UNKNOWN) {
          return script;
        }
      }
      return hb.hb_script_t.HB_SCRIPT_COMMON;
    }).toList();
    // Tatweel has Script=Common but joins the surrounding Arabic letters.
    // Resolve Common/Inherited scripts before itemizing, so an elongation or
    // joining control does not introduce an artificial shaping boundary.
    hb.hb_script_t? surrounding;
    for (var i = 0; i < scripts.length; i++) {
      if (scripts[i] != hb.hb_script_t.HB_SCRIPT_COMMON) {
        surrounding = scripts[i];
      } else if (surrounding != null) {
        scripts[i] = surrounding;
      }
    }
    surrounding = null;
    for (var i = scripts.length - 1; i >= 0; i--) {
      if (scripts[i] != hb.hb_script_t.HB_SCRIPT_COMMON) {
        surrounding = scripts[i];
      } else if (surrounding != null) {
        scripts[i] = surrounding;
      }
    }
    var start = 0;
    var end = 0;
    hb.hb_script_t? previous;
    bool? previousRtl;
    for (final (index, cluster) in clusters.indexed) {
      final rune = cluster.runes.first;
      final type = bidi.getCharacterType(rune);
      final rtl =
          type == bidi.CharacterType.al || type == bidi.CharacterType.rtl;
      final number =
          type == bidi.CharacterType.en || type == bidi.CharacterType.an;
      final neutral = !rtl && !number && type != bidi.CharacterType.ltr;
      final script = number ? hb.hb_script_t.HB_SCRIPT_LATIN : scripts[index];
      final direction = neutral
          ? visualCharacters[end] != indexText.codeUnitAt(end)
          : rtl;
      // Keep neutrals separate: a space or bracket can resolve to a different
      // direction than either adjacent script, especially around numbers.
      if (previous != null &&
          (neutral || previous != script || previousRtl != direction)) {
        segments.add((start, end, previous, previousRtl!));
        start = end;
      }
      previous = script;
      previousRtl = direction;
      end += cluster.length;
      if (neutral) {
        segments.add((start, end, script, direction));
        start = end;
        previous = null;
      }
    }
    if (previous != null) segments.add((start, end, previous, previousRtl!));
    int visualRank((int, int, hb.hb_script_t, bool) segment) {
      var result = text.length * 2;
      for (var i = segment.$1; i < segment.$2; i++) {
        if (ranks[i] != null && ranks[i]! < result) result = ranks[i]!;
      }
      return result;
    }

    segments.sort((a, b) => visualRank(a).compareTo(visualRank(b)));
    final glyphs = <PdfShapedGlyph>[];
    final breaks = <int>{};
    for (final (start, end, script, rtl) in segments) {
      final run = _shapeRun(font, text.substring(start, end), script, rtl: rtl);
      glyphs.addAll(
        run.glyphs.map(
          (g) => PdfShapedGlyph(
            glyphId: g.glyphId,
            cluster: start + g.cluster,
            xAdvance: g.xAdvance,
            yAdvance: g.yAdvance,
            xOffset: g.xOffset,
            yOffset: g.yOffset,
          ),
        ),
      );
      breaks.addAll(run.breaks.map((b) => start + b));
    }
    return PdfGlyphRun(glyphs: glyphs, breaks: breaks.toList()..sort());
  }

  PdfGlyphRun _shapeRun(
    ByteData font,
    String text,
    hb.hb_script_t script, {
    bool? rtl,
  }) {
    return using((arena) {
      final bytes = arena<Uint8>(font.lengthInBytes);
      bytes
          .asTypedList(font.lengthInBytes)
          .setAll(
            0,
            font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
          );
      final blob = hb.hb_blob_create(
        bytes.cast(),
        font.lengthInBytes,
        hb.hb_memory_mode_t.HB_MEMORY_MODE_READONLY,
        nullptr,
        nullptr,
      );
      final face = hb.hb_face_create(blob, 0);
      final nativeFont = hb.hb_font_create(face);
      final buffer = hb.hb_buffer_create();
      try {
        final upem = hb.hb_face_get_upem(face);
        if (upem == 0 || hb.hb_face_get_glyph_count(face) == 0) {
          throw FormatException('Invalid OpenType font');
        }
        hb.hb_ot_font_set_funcs(nativeFont);
        hb.hb_font_set_scale(nativeFont, upem, upem);
        final input = arena<Uint16>(text.length);
        input.asTypedList(text.length).setAll(0, text.codeUnits);
        hb.hb_buffer_add_utf16(buffer, input, text.length, 0, text.length);
        hb.hb_buffer_set_cluster_level(
          buffer,
          hb
              .hb_buffer_cluster_level_t
              .HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES,
        );
        hb.hb_buffer_set_script(buffer, script);
        if (rtl != null) {
          hb.hb_buffer_set_direction(
            buffer,
            rtl
                ? hb.hb_direction_t.HB_DIRECTION_RTL
                : hb.hb_direction_t.HB_DIRECTION_LTR,
          );
        }
        if (language != null) {
          final tag = language!.toNativeUtf8(allocator: arena);
          hb.hb_buffer_set_language(
            buffer,
            hb.hb_language_from_string(tag.cast(), -1),
          );
        }
        hb.hb_buffer_guess_segment_properties(buffer);
        // Default script feature ordering includes Indic reordering, GSUB
        // substitutions and GPOS mark attachment. Never manually reorder Unicode.
        hb.hb_shape(nativeFont, buffer, nullptr, 0);
        if (hb.hb_buffer_allocation_successful(buffer) == 0) {
          throw StateError('HarfBuzz could not allocate a shaping buffer');
        }
        final count = arena<UnsignedInt>();
        final infos = hb.hb_buffer_get_glyph_infos(buffer, count);
        final positions = hb.hb_buffer_get_glyph_positions(buffer, nullptr);
        final glyphs = <PdfShapedGlyph>[];
        final clusters = <int>{text.length};
        for (var i = 0; i < count.value; i++) {
          final info = infos[i];
          final pos = positions[i];
          clusters.add(info.cluster);
          glyphs.add(
            PdfShapedGlyph(
              glyphId: info.codepoint,
              cluster: info.cluster,
              xAdvance: pos.x_advance / upem,
              yAdvance: pos.y_advance / upem,
              xOffset: pos.x_offset / upem,
              yOffset: pos.y_offset / upem,
            ),
          );
        }
        // UNSAFE_TO_BREAK means reshaping is required, not that a line break
        // is prohibited. RichText reshapes both pieces; intersect Unicode
        // grapheme and HarfBuzz cluster boundaries to keep syllables intact.
        var end = 0;
        final breaks = <int>[];
        for (final grapheme in text.characters) {
          end += grapheme.length;
          if (clusters.contains(end)) breaks.add(end);
        }
        return PdfGlyphRun(glyphs: glyphs, breaks: breaks);
      } finally {
        hb.hb_buffer_destroy(buffer);
        hb.hb_font_destroy(nativeFont);
        hb.hb_face_destroy(face);
        hb.hb_blob_destroy(blob);
      }
    });
  }
}
