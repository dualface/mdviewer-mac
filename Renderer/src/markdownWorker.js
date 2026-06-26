import MarkdownIt from 'markdown-it';
import anchor from 'markdown-it-anchor';
import deflist from 'markdown-it-deflist';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import katexPlugin from '@vscode/markdown-it-katex';
import hljs from 'highlight.js/lib/common';
import katex from 'katex';

const markdownItKatex = katexPlugin.default ?? katexPlugin;

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: false,
  breaks: true,
  highlight(code, language) {
    const lang = language && hljs.getLanguage(language) ? language : '';
    if (lang) {
      try {
        return `<pre><code class="hljs language-${escapeAttr(lang)}">${hljs.highlight(code, { language: lang }).value}</code></pre>`;
      } catch {
        return `<pre><code class="hljs">${escapeHtml(code)}</code></pre>`;
      }
    }
    return `<pre><code class="hljs">${escapeHtml(code)}</code></pre>`;
  },
})
  .use(anchor, { permalink: anchor.permalink.headerLink() })
  .use(deflist)
  .use(footnote)
  .use(taskLists, { enabled: true, label: true, labelAfter: true })
  .use(markdownItKatex, {
    katex,
    throwOnError: false,
    errorColor: '#b42318',
    macros: {
      '\\label': { tokens: [], numArgs: 1 },
    },
  });

const defaultFence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  const info = token.info ? token.info.trim().split(/\s+/)[0].toLowerCase() : '';
  if (info === 'mermaid') {
    return `<pre class="mermaid-source"><code>${escapeHtml(token.content)}</code></pre>`;
  }
  return defaultFence(tokens, idx, options, env, self);
};

const defaultImage = md.renderer.rules.image;
md.renderer.rules.image = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  const srcIndex = token.attrIndex('src');
  if (srcIndex >= 0) {
    const src = token.attrs[srcIndex][1];
    token.attrs[srcIndex][1] = resolveAssetURL(src, env.filePath);
  }
  return defaultImage(tokens, idx, options, env, self);
};

const defaultLinkOpen = md.renderer.rules.link_open || ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  const hrefIndex = token.attrIndex('href');
  if (hrefIndex >= 0) {
    token.attrSet('data-mdviewer-link', token.attrs[hrefIndex][1]);
  }
  return defaultLinkOpen(tokens, idx, options, env, self);
};

self.addEventListener('message', (event) => {
  const { type, renderID, payload } = event.data || {};
  if (type !== 'renderMarkdown') {
    return;
  }

  try {
    const html = md.render(payload?.markdown || '', { filePath: payload?.filePath || '' });
    self.postMessage({ type: 'renderedMarkdown', renderID, html });
  } catch (error) {
    self.postMessage({
      type: 'renderError',
      renderID,
      message: error?.message || String(error || 'Markdown worker failed.'),
    });
  }
});

function resolveAssetURL(src, filePath) {
  if (!src) {
    return src;
  }
  if (/^(https?:|data:|blob:)/i.test(src)) {
    return src;
  }
  const path = resolvePath(src, filePath);
  const url = new URL('mdv-file://asset');
  url.searchParams.set('path', path);
  return url.toString();
}

function resolvePath(src, filePath) {
  const cleanSrc = decodeURIComponent(src.split('#')[0].split('?')[0]);
  if (cleanSrc.startsWith('/')) {
    return normalizePath(cleanSrc);
  }
  const base = filePath.split('/').slice(0, -1).join('/') || '/';
  return normalizePath(`${base}/${cleanSrc}`);
}

function normalizePath(path) {
  const parts = [];
  for (const part of path.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') {
      parts.pop();
      continue;
    }
    parts.push(part);
  }
  return `/${parts.join('/')}`;
}

function escapeHtml(text) {
  return String(text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function escapeAttr(text) {
  return escapeHtml(text).replaceAll('"', '&quot;');
}
