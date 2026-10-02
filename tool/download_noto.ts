import { createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dir, '..');
const regression = process.argv.includes('--regression');
const destination = resolve(root, `pdf_harfbuzz/fonts/${regression ? 'regression' : 'noto'}`);
const languages = await Bun.file(resolve(root, `pdf_harfbuzz/test/data/${regression ? 'regression' : 'india'}_languages.json`)).json();
const families = [...new Set<string>(languages.map((l: { folder: string }) => l.folder))];
const base = 'https://raw.githubusercontent.com/google/fonts/main/ofl';
const sha256 = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
mkdirSync(destination, { recursive: true });
const records = [];
async function download(url: string) {
  const response = await fetch(url, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`${response.status}: ${url}`);
  return new Uint8Array(await response.arrayBuffer());
}
for (const folder of families) {
  const target = resolve(destination, folder);
  mkdirSync(target, { recursive: true });
  const metadata = await download(`${base}/${folder}/METADATA.pb`);
  const filename = new TextDecoder().decode(metadata).match(/filename: "([^"/]+\.ttf)"/)?.[1];
  if (!filename) throw new Error(`No TrueType font listed for ${folder}`);
  const fontUrl = `${base}/${folder}/${encodeURIComponent(filename)}`;
  const [font, license] = await Promise.all([download(fontUrl), download(`${base}/${folder}/OFL.txt`)]);
  if (new DataView(font.buffer, font.byteOffset, font.byteLength).getUint32(0) !== 0x10000) {
    throw new Error(`Expected TrueType outlines for ${filename}`);
  }
  await Bun.write(resolve(target, filename), font);
  await Bun.write(resolve(target, 'OFL.txt'), license);
  await Bun.write(resolve(target, 'METADATA.pb'), metadata);
  records.push({ family: languages.find((l: { folder: string }) => l.folder === folder).family,
    folder, filename, source: fontUrl, sha256: sha256(font), bytes: font.length,
    license: 'SIL Open Font License 1.1', licenseSha256: sha256(license),
    languages: languages.filter((l: { folder: string }) => l.folder === folder).map((l: {code: string}) => l.code) });
  console.log(`${filename}: ${font.length} bytes`);
}
await Bun.write(resolve(destination, 'manifest.json'), JSON.stringify({
  downloadedAt: new Date().toISOString(), repository: 'https://github.com/google/fonts',
  ...(regression ? {} : {
    ranking: 'https://censusindia.gov.in/nada/index.php/catalog/42458/download/46089/C-16_25062018.pdf',
    rankingBasis: '2011 Census mother-tongue speakers; first ten scheduled languages',
  }),
  fonts: records,
}, null, 2) + '\n');
console.log(`Downloaded ${records.length} Noto families for ${languages.length} languages to ${destination}`);
