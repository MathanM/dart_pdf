import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve, relative } from 'node:path';

const root = resolve(import.meta.dir, '..');
const pkg = resolve(root, 'pdf_harfbuzz');
const output = resolve(root, 'output/language-coverage');
mkdirSync(output, { recursive: true });
const readJson = (file: string) => JSON.parse(readFileSync(file, 'utf8'));
const languages = ['india_languages', 'regression_languages', 'cjk_languages']
  .flatMap((name) => readJson(resolve(pkg, `test/data/${name}.json`)));
const cases = readJson(resolve(pkg, 'test/data/language_coverage.json'));
const eventsFile = resolve(output, 'tests.jsonl');
const lcovFile = resolve(output, 'shaper.lcov');
for (const file of [eventsFile, lcovFile]) rmSync(file, { force: true });
const testFiles = ['test/india_languages_test.dart', 'test/arabic_regression_test.dart', 'test/all_languages_test.dart'];
if (process.env.INDIC_FONT_DIR) testFiles.push('test/indic_test.dart');
const coverageArgs = process.env.LANGUAGE_LINE_COVERAGE === '1'
  ? [`--coverage-path=${lcovFile}`, '--coverage-package=^pdf_harfbuzz$']
  : [];
const result = Bun.spawnSync([
  process.env.DART_BIN ?? 'dart', 'test', ...testFiles,
  '--concurrency=1',
  '--reporter=expanded', `--file-reporter=json:${eventsFile}`,
  ...coverageArgs,
], { cwd: pkg, env: process.env, stdout: 'pipe', stderr: 'pipe' });
writeFileSync(resolve(output, 'test-output.log'), Buffer.concat([result.stdout, result.stderr]));

const tests = new Map<number, { name: string; result?: string; skipped?: boolean; hidden?: boolean }>();
for (const line of existsSync(eventsFile) ? readFileSync(eventsFile, 'utf8').split('\n') : []) {
  if (!line.trim()) continue;
  const event = JSON.parse(line);
  if (event.type === 'testStart') tests.set(event.test.id, { name: event.test.name });
  if (event.type === 'testDone') {
    const test = tests.get(event.testID);
    if (test) Object.assign(test, { result: event.result, skipped: event.skipped, hidden: event.hidden });
  }
}
const completed = [...tests.values()].filter((t) => !t.hidden && t.result);
const status = (name: string) => {
  const matches = completed.filter((t) => t.name === name);
  if (matches.length !== 1) return 'missing';
  return matches[0].skipped ? 'skipped' : matches[0].result === 'success' ? 'pass' : 'fail';
};
const rows = languages.map((language) => {
  const entry = cases.find((c) => c.code === language.code);
  const prefix = `Coverage ${language.code} ${language.name}`;
  const screenshot = entry ? resolve(root, 'output/pdf', entry.screenshot) : null;
  return {
    language: language.name, code: language.code, font: language.family,
    shaping: status(`${prefix} shaping`), subsetting: status(`${prefix} subsetting`),
    wrappingAndUnicode: status(`${prefix} wrapping and Unicode`),
    fallback: entry?.fallback ? status(`${prefix} fallback`) : 'not-forced-for-Latin-fixture',
    screenshot: screenshot && existsSync(screenshot) ? {
      path: relative(root, screenshot),
      sha256: createHash('sha256').update(readFileSync(screenshot)).digest('hex'),
      status: 'present; visual review performed in preceding rendering verification',
    } : null,
  };
});
const lineCoverage = [];
if (existsSync(lcovFile)) {
  for (const record of readFileSync(lcovFile, 'utf8').split('end_of_record')) {
    const source = record.match(/^SF:(.+)$/m)?.[1];
    if (!source) continue;
    const counts = [...record.matchAll(/^DA:(\d+),(\d+)/gm)];
    const hit = counts.filter((m) => Number(m[2]) > 0).length;
    lineCoverage.push({ source, hit, executable: counts.length,
      percent: counts.length ? Math.round(10000 * hit / counts.length) / 100 : null,
      uncovered: counts.filter((m) => Number(m[2]) === 0).map((m) => Number(m[1])),
    });
  }
}
const counts = {
  passed: completed.filter((t) => t.result === 'success' && !t.skipped).length,
  failed: completed.filter((t) => t.result !== 'success' && !t.skipped).length,
  skipped: completed.filter((t) => t.skipped).length,
};
const valid = result.exitCode === 0 &&
  status('Language coverage includes every catalog entry exactly once') === 'pass' &&
  rows.every((r) => [r.shaping, r.subsetting, r.wrappingAndUnicode].every((s) => s === 'pass') &&
    !['missing', 'skipped', 'fail'].includes(r.fallback) && r.screenshot);
const report = {
  auditedAt: new Date().toISOString(), passed: valid, addressedLanguages: rows.length,
  testCounts: counts, originalLocalFontTestsIncluded: Boolean(process.env.INDIC_FONT_DIR),
  lineCoverageScope: process.env.LANGUAGE_LINE_COVERAGE === '1'
    ? 'pdf_harfbuzz native Dart implementation, exercised by the companion suite; not the native HarfBuzz C++ library or a percentage of Unicode/languages supported'
    : 'not collected; Dart test coverage instrumentation currently fails while loading this native build-hook package. Functional language coverage is unaffected and runs normally',
  lineCoverage, languages: rows,
  limitations: [
    'Samples and probes are not exhaustive language, glyph-repertoire, or OpenType conformance coverage.',
    'Latin fixtures already fit the primary font, so forced fallback is asserted only for 17 non-Latin languages.',
    'Screenshot presence and hashes are checked here. Visual correctness was manually inspected earlier; this audit does not rerender or visually compare the images.',
    'Existing legacy rendering has a three-page pixel comparison; the new OpenType pages have no automated visual golden baseline yet.',
    'Nested bidi isolates, arbitrary style boundaries, variable axes, CFF/CFF2, color-font shaping, web, and native platforms other than macOS are outside current verified scope.',
    'Two unrelated existing image tests require an unavailable external fixture; they are not part of this companion-only audit.',
    'Source-line coverage is unavailable because the Dart test runner crashes during coverage-mode suite loading for this native build-hook package; a normal-mode test run is used for the language matrix.',
    'harfbuzz_ffi 0.5.0 compiles HarfBuzz with HB_NO_MT=1. Parallel shaping from multiple Dart isolates is unsafe until that dependency enables HarfBuzz thread synchronization; verification therefore runs companion suites with one test isolate.',
  ],
};
writeFileSync(resolve(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
const md = [
  '# Language coverage audit', '',
  `Generated ${report.auditedAt} by \`bun run tool/audit_language_coverage.ts\`.`, '',
  `**${rows.length} addressed languages. ${counts.passed} companion tests pass; ${counts.failed} fail; ${counts.skipped} skipped.**`, '',
  'Shaping checks the sample for missing glyphs and compares an explicit single-script probe with a direct HarfBuzz buffer. Subsetting checks advances and complete recursive compound outlines. Wrapping is forced and checks grapheme boundaries, logical Unicode, multiple lines, and PDF text rather than images.', '',
  '| Language | Font | Shaping | Subsetting | Wrap / Unicode | Fallback | Screenshot evidence |',
  '| --- | --- | --- | --- | --- | --- | --- |',
  ...rows.map((r) => `| ${r.language} (${r.code}) | ${r.font} | ${r.shaping} | ${r.subsetting} | ${r.wrappingAndUnicode} | ${r.fallback === 'pass' ? 'pass' : r.fallback === 'not-forced-for-Latin-fixture' ? 'not forced' : r.fallback} | ${r.screenshot ? `[prior review](../pdf/${r.screenshot.path.split('/').at(-1)})` : 'missing'} |`),
  '', '## Source line coverage', '',
  ...(lineCoverage.length
    ? lineCoverage.map((c) => `- \`${c.source}\`: ${c.hit}/${c.executable} executable lines (${c.percent}%). Uncovered lines: ${c.uncovered.join(', ') || 'none'}.`)
    : [report.lineCoverageScope + '.']),
  '', '## Additional checks already in the suite', '',
  '- Arabic: lam-alef, tatweel, marks, ZWJ/ZWNJ, numbers, mirrored brackets, mixed English order, wrapping, justification, and link bounds.',
  '- Urdu: joining, Nastaliq positioning, number order, and bypassing legacy presentation-form conversion.',
  '- Tamil/Hindi: canonical forms, conjuncts, very narrow wrapping, metrics, protection, and byte-data views. Original local-font tests additionally cover supplied Tamil/Hindi/Telugu font weights.',
  '- Emoji: bitmap fallback embedded beside CJK and Latin text; emoji are not counted as a language.',
  '', '## Limits', '', ...report.limitations.map((s) => `- ${s}`), '',
];
writeFileSync(resolve(output, 'report.md'), md.join('\n'));
console.log(`${rows.length} languages: ${valid ? 'PASS' : 'INCOMPLETE'}. ${counts.passed} tests passed. Report: ${resolve(output, 'report.md')}`);
for (const coverage of lineCoverage) console.log(`${coverage.source}: ${coverage.hit}/${coverage.executable} lines (${coverage.percent}%)`);
if (!valid) {
  console.error(readFileSync(resolve(output, 'test-output.log'), 'utf8').slice(-10000));
  process.exitCode = 1;
}
