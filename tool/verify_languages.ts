import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const out = resolve(root, 'output/pdf');
const pkg = resolve(root, 'pdf_harfbuzz');
const dart = process.env.DART_BIN ?? 'dart';
const render = process.env.PDFTOPPM_BIN ?? 'pdftoppm';
mkdirSync(resolve(out, 'fontconfig-cache'), { recursive: true });
const xml = (s: string) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
writeFileSync(resolve(out, 'language-fonts.conf'), `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>${xml(resolve(pkg, 'fonts'))}</dir><cachedir>${xml(resolve(out, 'fontconfig-cache'))}</cachedir></fontconfig>`);
const env = { ...process.env, LANGUAGE_REPO_ROOT: root, FONTCONFIG_FILE: resolve(out, 'language-fonts.conf') };
function run(args: string[], cwd = pkg) {
  const result = Bun.spawnSync(args, { cwd, env, stdout: 'inherit', stderr: 'inherit' });
  if (result.exitCode !== 0) throw new Error(`Failed (${result.exitCode}): ${args.join(' ')}`);
}
for (const directory of ['noto', 'regression']) {
  const manifest = await Bun.file(resolve(pkg, 'fonts', directory, 'manifest.json')).json();
  for (const font of manifest.fonts) {
    const bytes = await Bun.file(resolve(pkg, 'fonts', directory, font.folder, font.filename)).bytes();
    if (createHash('sha256').update(bytes).digest('hex') !== font.sha256) throw new Error(`Font checksum mismatch: ${font.filename}`);
  }
}
// harfbuzz_ffi 0.5.0 is compiled with HB_NO_MT=1. Separate Dart test suites
// run in concurrent isolates by default and can race inside that native build.
run([dart, 'test', '--concurrency=1', ...(process.env.INDIC_FONT_DIR ? [] : ['test/india_languages_test.dart', 'test/arabic_regression_test.dart', 'test/all_languages_test.dart'])]);
// The two excluded tests require www.nfet.net/nfet.jpg. The host was unavailable
// during verification; all local core tests (including Arabic) run below.
const excluded = ['jpeg_test.dart', 'isolate_test.dart'];
const coreTests = readdirSync(resolve(root, 'pdf/test')).filter((f) => f.endsWith('_test.dart') && !excluded.includes(f)).map((f) => `test/${f}`);
run([dart, 'test', ...coreTests], resolve(root, 'pdf'));
run([dart, 'analyze'], pkg);
run([dart, 'analyze', 'lib', 'example', 'test/bidi_word_order_test.dart', 'test/font_regression_test.dart'], resolve(root, 'pdf'));
run([dart, 'run', 'example/languages.dart']);
run([dart, 'run', 'example/language_regression.dart'], resolve(root, 'pdf'));

// Optional pixel comparison against an isolated checkout of the original pdf
// package. The same example, fonts, and Poppler settings are used on both sides.
const baseline = process.env.BASELINE_PDF_PACKAGE;
if (baseline) {
  copyFileSync(resolve(root, 'pdf/example/language_regression.dart'), resolve(baseline, 'example/language_regression.dart'));
  run([dart, 'run', 'example/language_regression.dart', resolve(out, 'languages-legacy-baseline.pdf')], baseline);
}
for (const name of ['language-regression', 'languages-legacy-current', ...(baseline ? ['languages-legacy-baseline'] : [])]) {
  run([render, '-scale-to', '1600', '-png', resolve(out, `${name}.pdf`), resolve(out, name)]);
}
const comparisons = [];
if (baseline) {
  for (let page = 1; page <= 3; page++) {
    const before = await Bun.file(resolve(out, `languages-legacy-baseline-${page}.png`)).bytes();
    const after = await Bun.file(resolve(out, `languages-legacy-current-${page}.png`)).bytes();
    const identical = Buffer.from(before).equals(Buffer.from(after));
    comparisons.push({ page, identical });
    if (!identical) throw new Error(`Legacy page ${page} changed; inspect its screenshots.`);
  }
}
run([process.env.PDFTOTEXT_BIN ?? 'pdftotext', resolve(out, 'language-regression.pdf'), resolve(out, 'language-regression.txt')]);
const extracted = (await Bun.file(resolve(out, 'language-regression.txt')).text()).replaceAll(/\s/g, '');
const languages = await Bun.file(resolve(pkg, 'test/data/regression_languages.json')).json();
for (const language of languages.filter((l: { direction: string }) => l.direction === 'ltr')) {
  if (!extracted.includes(language.sample.replaceAll(/\s/g, ''))) throw new Error(`Missing PDF text: ${language.name}`);
}
for (const sample of ['你好，世界！中文文字測試。', 'こんにちは世界。日本語の文字。', 'Right Order']) {
  if (!extracted.includes(sample.replaceAll(/\s/g, ''))) throw new Error(`Missing PDF text: ${sample}`);
}
writeFileSync(resolve(out, 'language-regression-report.json'), JSON.stringify({ verifiedAt: new Date().toISOString(), localCoreTestFiles: coreTests.length, unavailableExternalImageTests: excluded, legacyPixelComparison: comparisons, pdf: 'language-regression.pdf', pages: 3 }, null, 2) + '\n');
console.log(`Verified Arabic, existing language samples, local core tests and screenshots. Legacy pages identical: ${comparisons.length}.`);
