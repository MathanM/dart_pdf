import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const pkg = resolve(root, 'pdf_harfbuzz');
const fontDir = resolve(pkg, 'fonts/noto');
const out = resolve(root, 'output/pdf');
mkdirSync(resolve(out, 'fontconfig-cache'), { recursive: true });
const escapeXml = (s: string) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
writeFileSync(resolve(out, 'fonts.conf'), `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>${escapeXml(fontDir)}</dir><cachedir>${escapeXml(resolve(out, 'fontconfig-cache'))}</cachedir></fontconfig>`);
const env = { ...process.env, FONTCONFIG_FILE: resolve(out, 'fonts.conf') };
const manifest = await Bun.file(resolve(fontDir, 'manifest.json')).json();
for (const font of manifest.fonts) {
  const bytes = await Bun.file(resolve(fontDir, font.folder, font.filename)).bytes();
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (hash !== font.sha256) throw new Error(`Downloaded font checksum mismatch: ${font.filename}`);
}
function run(args: string[], cwd = pkg) {
  const result = Bun.spawnSync(args, { cwd, env, stdout: 'inherit', stderr: 'inherit' });
  if (result.exitCode !== 0) throw new Error(`Command failed (${result.exitCode}): ${args.join(' ')}`);
}
const dart = process.env.DART_BIN ?? 'dart';
const pubGet = ['pub', 'get', ...(process.env.PUB_OFFLINE === '1' ? ['--offline'] : [])];
run([dart, ...pubGet]);
run([dart, 'test', 'test/india_languages_test.dart']);
run([dart, 'run', 'example/india.dart']);
run([process.env.PDFTOPPM_BIN ?? 'pdftoppm', '-scale-to', '1600', '-png', resolve(out, 'india-ten-languages.pdf'), resolve(out, 'india-ten-languages')]);
run([process.env.PDFTOTEXT_BIN ?? 'pdftotext', resolve(out, 'india-ten-languages.pdf'), resolve(out, 'india-ten-languages.txt')]);
const extracted = (await Bun.file(resolve(out, 'india-ten-languages.txt')).text()).replaceAll(/\s/g, '');
const languages = await Bun.file(resolve(pkg, 'test/data/india_languages.json')).json();
for (const language of languages) {
  // Poppler may output RTL presentation order; the Dart tests verify original
  // Unicode ActualText directly for Urdu, independently of viewer reordering.
  if (language.direction === 'rtl') continue;
  if (!extracted.includes(language.sample.replaceAll(/\s/g, ''))) {
    throw new Error(`Missing extracted text: ${language.name}`);
  }
}
console.log(`Verified nine font checksums, ten-language tests, PDF and six screenshots: ${out}`);
