import { readFileSync, writeFileSync } from 'node:fs';

const rendererRoot = new URL('../../App/Resources/Renderer/', import.meta.url);
const rendererHtml = new URL('index.html', rendererRoot);
const rendererScript = new URL('assets/index.js', rendererRoot);
let html = readFileSync(rendererHtml, 'utf8');

html = html
  .replace(/<script type="module" crossorigin src="([^"]+)"><\/script>/, '<script defer src="$1"></script>')
  .replace(/<script type="module" src="([^"]+)"><\/script>/, '<script defer src="$1"></script>')
  .replace(/<link rel="stylesheet" crossorigin href="([^"]+)">/, '<link rel="stylesheet" href="$1">');

writeFileSync(rendererHtml, html);

let script = readFileSync(rendererScript, 'utf8');
script = script.replaceAll(
  'import.meta.url',
  '(document.currentScript && document.currentScript.src || document.baseURI)'
);
writeFileSync(rendererScript, script);
