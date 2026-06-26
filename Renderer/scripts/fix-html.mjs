import { readdirSync, readFileSync, writeFileSync } from 'node:fs';

const rendererRoot = new URL('../../App/Resources/Renderer/', import.meta.url);
const rendererHtml = new URL('index.html', rendererRoot);
const rendererScript = new URL('assets/index.js', rendererRoot);
const rendererAssets = new URL('assets/', rendererRoot);
let html = readFileSync(rendererHtml, 'utf8');

html = html
  .replace(/<script type="module" crossorigin src="([^"]+)"><\/script>/, '<script defer src="$1"></script>')
  .replace(/<script type="module" src="([^"]+)"><\/script>/, '<script defer src="$1"></script>')
  .replace(/<link rel="stylesheet" crossorigin href="([^"]+)">/, '<link rel="stylesheet" href="$1">');

writeFileSync(rendererHtml, html);

let script = readFileSync(rendererScript, 'utf8');
script = script
  .replaceAll('import.meta.resolve', 'undefined')
  .replaceAll(
    'import.meta.url',
    '(document.currentScript && document.currentScript.src || document.baseURI)'
  );
if (script.includes('import.meta')) {
  throw new Error('Renderer bundle still contains import.meta, which cannot run as a classic script.');
}
writeFileSync(rendererScript, script);

trimTrailingWhitespace(rendererRoot);
trimTrailingWhitespace(rendererAssets);

function trimTrailingWhitespace(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isFile() || !/\.(html|css|js)$/i.test(entry.name)) {
      continue;
    }
    const file = new URL(entry.name, directory);
    const content = readFileSync(file, 'utf8');
    writeFileSync(file, content.replace(/[ \t]+$/gm, ''));
  }
}
