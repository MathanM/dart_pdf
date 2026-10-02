# OpenType shaping for dart_pdf

This package connects HarfBuzz to the normal `pdf` font, text measurement,
wrapping, and PDF text rendering pipeline. The Google Fonts demo covers Hindi,
Bengali, Marathi, Telugu, Tamil, Gujarati, Urdu, Kannada, Odia, and Malayalam.
The original Tamil/Hindi/Telugu demo with local Noto and Anek fonts is retained.

```dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_harfbuzz/pdf_harfbuzz.dart';

final tamil = pw.Font.ttf(
  fontBytes.buffer.asByteData(),
  shaper: const HarfBuzzTextShaper(language: 'ta'),
);
final text = pw.Text('தமிழ் மொழி அழகானது.',
    style: pw.TextStyle(font: tamil, fontSize: 24));
```

For Hindi use a Devanagari font and language `hi`. For Urdu use Noto Nastaliq
Urdu, `HarfBuzzTextShaper(language: 'ur')`, and `Text(textDirection:
pw.TextDirection.rtl, ...)`. Keep the input in logical Unicode order; the widget
bypasses legacy Arabic presentation-form conversion when a shaper is present.
For Arabic use **Noto Naskh Arabic** with `language: 'ar'` and the same RTL
widget setting. The regression demo also checks Persian (`fa`) and Hebrew (`he`).

Set a shaper on **every**
regular, bold, or fallback font that needs OpenType shaping. The existing
`TextStyle.fontFallback` API selects whole graphemes and keeps adjacent text in
the same font together. Low-level `PdfTtfFont(..., shaper: ...)` and
`PdfGraphics.drawString` use the same implementation.

## Ten-language Google Fonts demo

The language selection is the first ten in the [2011 Census ranking by
mother-tongue speakers](https://censusindia.gov.in/nada/index.php/catalog/42458/download/46089/C-16_25062018.pdf).
Nine Noto families cover the ten languages because Hindi and Marathi share
Devanagari. Odia's Google Fonts family is named **Noto Sans Oriya**.

| Language | Language tag | Google Fonts family |
| --- | --- | --- |
| Hindi | hi | Noto Sans Devanagari |
| Bengali | bn | Noto Sans Bengali |
| Marathi | mr | Noto Sans Devanagari |
| Telugu | te | Noto Sans Telugu |
| Tamil | ta | Noto Sans Tamil |
| Gujarati | gu | Noto Sans Gujarati |
| Urdu | ur | Noto Nastaliq Urdu |
| Kannada | kn | Noto Sans Kannada |
| Odia | or | Noto Sans Oriya |
| Malayalam | ml | Noto Sans Malayalam |

From the repository root:

```sh
bun run tool/download_noto.ts
bun run tool/verify_india.ts
```

The downloader saves original TTF files, `METADATA.pb`, and `OFL.txt` under
`pdf_harfbuzz/fonts/noto/`. Its `manifest.json` records the source URL, download
time, SHA-256, license, and language coverage for every family. These are
variable TrueType fonts used at their default coordinates; axis selection is
not implemented. Downloaded font binaries are ignored by Git.

Verification checks the font hashes, runs 35 language and Urdu regression
tests, generates `output/pdf/india-ten-languages.pdf`, and renders all six pages
as `india-ten-languages-1.png` through `india-ten-languages-6.png`. The first page
shows all ten languages; subsequent pages exercise vowels, conjuncts, localized
letters, Nastaliq marks, numerals, and wrapping. Poppler text extraction is
checked for the nine LTR languages. Urdu's original Unicode is checked directly
in `/ActualText`; PDF viewers/extractors may reorder RTL text differently.

`DART_BIN`, `PDFTOPPM_BIN`, and `PDFTOTEXT_BIN` override executable locations.
Use `PUB_OFFLINE=1` once dependencies are cached. Font downloads require network
access; verification runs locally after downloading.

## Arabic and existing-language regression checks

```sh
bun run tool/download_noto.ts --regression
bun run tool/verify_languages.ts
```

The extra download contains Noto Naskh Arabic, Noto Sans Hebrew, and Noto Sans
(Latin, Greek, and Cyrillic), with the same license/metadata/checksum records
under `fonts/regression/`. Verification also uses the existing core test fonts
listed in the repository's `Makefile`; run its individual font targets if they
are absent. The Hacen Tunisia download URL is reachable over HTTPS.

`output/pdf/language-regression.pdf` and its three PNG screenshots cover Arabic,
Persian, Hebrew, English, French, German, Spanish, Russian, Greek, Chinese,
Japanese, bitmap emoji fallback, rich text, alignment, and wrapping. Tests check
Arabic joining and mark positions against a direct HarfBuzz buffer, including
lam-alef, tatweel, hamzas, dagger alif, ZWJ/ZWNJ, digits, and parentheses. Mixed
Arabic/English word order is checked after wrapping, with ordinary and justified
alignment; source Unicode and link bounds are checked separately.

The script runs the Indian-language tests as well. Set `INDIC_FONT_DIR` to
include the original local-font tests. It runs all local core tests; the JPEG
download and isolate tests require an external `www.nfet.net/nfet.jpg` fixture
whose host was unavailable during this verification. They are explicitly
excluded from the local run, not reported as passing.

Set `BASELINE_PDF_PACKAGE` to an isolated checkout of the original `pdf` package
with dependencies resolved to compare legacy rendering. The script copies the
same example into that checkout and checks byte-identical PNGs for all three
legacy demo pages. Results are saved in `language-regression-report.json`.

The old Hacen Tunisia fixture lacks U+0654, U+0655, and U+0670. Its original
Arabic suite already had missing-mark problems: the old subset writer sometimes
substituted an unrelated glyph for a missing mark. The new writer preserves the
font's `.notdef` glyph consistently. Noto Naskh Arabic with HarfBuzz covers and
correctly shapes the tested marks; a shaper cannot add glyphs absent from a font.

## Coverage for every addressed language

```sh
bun run tool/audit_language_coverage.ts
```

This runs the companion tests and writes `output/language-coverage/report.md`,
`report.json`, and raw test events. Set
`INDIC_FONT_DIR` to include the original local-font tests as well. It uses the
previously generated screenshots as evidence; it checks their presence and
hashes, without repeating or automating the previous visual review. Dart's test
coverage instrumentation currently crashes while loading this native build-hook
package, so the audit does not claim a source-line percentage.

The current `harfbuzz_ffi` 0.5.0 build defines `HB_NO_MT=1`. Do not shape from
multiple Dart isolates concurrently with that native library. The verification
scripts run companion tests with `--concurrency=1`. Supporting parallel isolate
shaping requires a thread-safe HarfBuzz build from the native dependency.

All **21 languages** have dedicated tests for shaping against a direct HarfBuzz
probe, glyph coverage, recursive font-subset integrity, forced wrapping,
grapheme boundaries, and logical PDF Unicode. Chinese and Japanese have separate
catalog entries and tests. Forced fallback is checked for the 17 non-Latin
languages; the four Latin-language fixtures already fit the primary font. Emoji
bitmap fallback has separate coverage and is not counted as a language.

`test/data/language_coverage.json` maps each language to its probe, script, and
screenshot. A completeness test rejects missing or duplicate catalog entries.
This is sample-based regression coverage, not exhaustive Unicode or OpenType
conformance, and there is not yet an automated visual golden for every shaped
language. The implementation/platform limits below still apply.

## Original local-font demo

From the repository root:

```sh
export INDIC_FONT_DIR=/Users/mathan.m/Personal/smart-li-flutter/assets/fonts
bun run tool/verify_indic.ts
```

Requires Dart 3.13+, Bun, a C++ compiler for the `harfbuzz_ffi` build hook, and
Poppler (`pdftoppm` / `pdftotext`). `DART_BIN`, `PDFTOPPM_BIN`, and `PDFTOTEXT_BIN`
can override executable paths. The script generates the original-renderer
baseline, runs the Indic tests, produces the corrected two-page PDF, renders
screenshots, and checks extracted Unicode. Fonts are read from the supplied
directory and are not redistributed by that demo.

Outputs are under `output/pdf/`: `indic-before.pdf`, `indic-before.png`,
`indic-after.pdf`, `indic-after-1.png`, and `indic-after-2.png`.

To run only the shaping tests:

```sh
cd pdf_harfbuzz
dart pub get
INDIC_FONT_DIR=/path/to/fonts dart test
```

## Implementation

HarfBuzz itemizes script runs with its Unicode database and applies OpenType
normalization, Indic syllable reordering, GSUB substitutions, and GPOS offsets
and advances. Measurement and painting share a bounded shaped-run cache.

The PDF contains embedded subset fonts and positioned text operators. Subsets
include glyphs produced by GSUB even when those glyphs have no Unicode cmap
entry, and include referenced compound outlines. Multi-character ToUnicode
mappings and logical `/ActualText` preserve text after visual reordering.
`protect: true` suppresses that logical text as it does for unshaped fonts.

Long words break only where Unicode grapheme and HarfBuzz cluster boundaries
agree. Both sides are reshaped, including boundaries marked unsafe to break:
that HarfBuzz flag indicates that reshaping is required. An indivisible cluster
wider than the available width overflows rather than being split into marks.

References: [Microsoft Tamil shaping](https://learn.microsoft.com/en-us/typography/script-development/tamil),
[Microsoft Devanagari shaping](https://learn.microsoft.com/en-us/typography/script-development/devanagari),
[HarfBuzz shaping output](https://harfbuzz.github.io/shaping-and-shape-plans.html),
[HarfBuzz buffer and cluster semantics](https://harfbuzz.github.io/harfbuzz-hb-buffer.html).

## Scope

- This native backend supports horizontal Indic, Arabic, Persian, Urdu, Hebrew,
  Latin, Greek, Cyrillic, and CJK text with suitable fonts. RTL scripts receive
  logical Unicode directly; HarfBuzz applies joining and mark placement. Bidi
  ordering uses index-preserving character-class representatives separately from
  shaping. Fully shaped text lines resolve word order after wrapping, including
  Latin phrases inside RTL text. Arbitrarily nested directional isolates, words
  split across different styles, and lines mixing shaped and unshaped fonts or
  inline widgets are not fully supported for mixed-direction text.
- The PDF subset writer supports OpenType fonts with TrueType `glyf`/`loca`
  outlines. CFF/CFF2 outlines, variation-axis selection, and color-font shaping
  are not implemented. An `.otf` extension alone does not identify outline type.
- The optional native package uses `harfbuzz_ffi` on native Dart/Flutter platforms;
  it has been executed here on macOS arm64. Other native platforms need their
  own build verification. Web needs an implementation of `PdfTextShaper` backed
  by WASM or another engine. The core `pdf` package stays free of native imports.
- Text split manually across differently styled spans is shaped separately.
  Keep a syllable/conjunct in a single span and provide fonts covering it fully.
- `PdfGraphics.drawString` supports shaping; direct `putText` cannot express
  glyph positioning and throws when a shaper is configured.

This is a local companion package (`publish_to: none`) using the sibling `pdf`
checkout, ready for further platform integration and upstream review.
