import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const fonts = process.env.INDIC_FONT_DIR;
if (!fonts) throw new Error('Set INDIC_FONT_DIR to the directory containing ta/, hi/, te/ fonts.');
const dart = process.env.DART_BIN ?? 'dart';
const pubGet = ['pub', 'get', ...(process.env.PUB_OFFLINE === '1' ? ['--offline'] : [])];
const raster = process.env.PDFTOPPM_BIN ?? 'pdftoppm';
const extract = process.env.PDFTOTEXT_BIN ?? 'pdftotext';
const out = resolve(root, 'output/pdf');
mkdirSync(resolve(out, 'fontconfig-cache'), { recursive: true });
const escapeXml = (s: string) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
writeFileSync(resolve(out, 'fonts.conf'), `<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>${escapeXml(fonts)}</dir><cachedir>${escapeXml(resolve(out, 'fontconfig-cache'))}</cachedir></fontconfig>`);
const env = { ...process.env, FONTCONFIG_FILE: resolve(out, 'fonts.conf') };
function run(args: string[], cwd = root) {
  const result = Bun.spawnSync(args, { cwd, env, stdout: 'inherit', stderr: 'inherit' });
  if (result.exitCode !== 0) throw new Error(`Command failed (${result.exitCode}): ${args.join(' ')}`);
}
run([dart, ...pubGet], resolve(root, 'pdf'));
run([dart, 'run', 'example/indic.dart', fonts], resolve(root, 'pdf'));
run([dart, ...pubGet], resolve(root, 'pdf_harfbuzz'));
run([dart, 'test'], resolve(root, 'pdf_harfbuzz'));
run([dart, 'run', 'example/indic.dart', fonts], resolve(root, 'pdf_harfbuzz'));
run([raster, '-scale-to', '1800', '-png', '-singlefile', resolve(out, 'indic-before.pdf'), resolve(out, 'indic-before')]);
run([raster, '-scale-to', '1800', '-png', resolve(out, 'indic-after.pdf'), resolve(out, 'indic-after')]);
run([extract, resolve(out, 'indic-after.pdf'), resolve(out, 'indic-after.txt')]);
const text = await Bun.file(resolve(out, 'indic-after.txt')).text();
for (const sample of ['தமிழ் மொழி மிகவும் அழகானது.', 'हिन्दी भाषा बहुत सुंदर है। नमस्ते भारत!', 'प्रार्थना राष्ट्र विद्यालय शक्ति दृष्टि संस्कृति', 'తెలుగు భాష అందమైనది.']) {
  if (!text.includes(sample)) throw new Error(`Extracted Unicode is missing: ${sample}`);
}
console.log(`PDFs, screenshots, and verified Unicode: ${out}`);
