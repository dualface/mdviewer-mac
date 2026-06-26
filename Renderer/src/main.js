import MarkdownIt from 'markdown-it';
import anchor from 'markdown-it-anchor';
import deflist from 'markdown-it-deflist';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import katexPlugin from '@vscode/markdown-it-katex';
import DOMPurify from 'dompurify';
import mermaid from 'mermaid';
import hljs from 'highlight.js/lib/common';
import katex from 'katex';
import 'highlight.js/styles/github.css';
import 'katex/dist/katex.min.css';
import './styles.css';

const preview = document.getElementById('preview');
let currentPayload = null;
const markdownItKatex = katexPlugin.default ?? katexPlugin;

window.addEventListener('error', (event) => {
  postMessage('renderError', event.message || 'Renderer JavaScript error');
});

window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason?.message || String(event.reason || 'Unhandled renderer rejection');
  postMessage('renderError', reason);
});

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

window.MDViewer = {
  async render(payload, renderID) {
    currentPayload = payload;
    try {
      applySettings(payload);
      if (payload.kind === 'markdown') {
        await renderMarkdown(payload);
      } else if (payload.kind === 'image') {
        renderImage(payload);
      } else if (payload.kind === 'text') {
        renderText(payload);
      } else {
        renderUnsupported(payload);
      }
    } catch (error) {
      postMessage('renderError', error.message);
      preview.innerHTML = `<div class="error">Render error: ${escapeHtml(error.message)}</div>`;
    } finally {
      await waitForPaint();
      postMessage('renderComplete', { renderID });
    }
  },
};

window.addEventListener('DOMContentLoaded', () => {
  postMessage('rendererReady', { ready: true });
});

function applySettings(payload) {
  document.documentElement.dataset.theme = payload.theme || 'light';
  preview.className = `width-${payload.previewWidth || 'medium'}`;
  preview.style.setProperty('--font-size', `${payload.fontSize || 16}px`);
  preview.style.setProperty('--content-font-family', payload.fontFamily || "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif");
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: payload.theme === 'dark' ? 'dark' : 'default',
  });
}

async function renderMarkdown(payload) {
  try {
    const html = md.render(payload.markdown || '', { filePath: payload.filePath });
    preview.innerHTML = DOMPurify.sanitize(html, {
      ADD_ATTR: ['target', 'rel', 'data-mdviewer-link'],
    });
    bindLinks(payload.filePath);
    await renderMermaidBlocks();
  } catch (error) {
    postMessage('renderError', error.message);
    preview.innerHTML = `<div class="error">Markdown render error: ${escapeHtml(error.message)}</div>`;
  }
}

function renderImage(payload) {
  const src = payload.mediaURL || resolveAssetURL(payload.filePath, payload.filePath);
  preview.innerHTML = `
    <div class="media-preview">
      <img src="${escapeAttr(src)}" alt="${escapeAttr(payload.name)}">
      <div class="file-caption">${escapeHtml(payload.name)} (${formatSize(payload.size)})</div>
    </div>`;
}

function renderText(payload) {
  const language = payload.language && hljs.getLanguage(payload.language) ? payload.language : '';
  const highlighted = language
    ? hljs.highlight(payload.content || '', { language }).value
    : escapeHtml(payload.content || '');
  preview.innerHTML = `
    <div class="code-viewer">
      <pre><code class="hljs${language ? ` language-${escapeAttr(language)}` : ''}">${highlighted}</code></pre>
    </div>`;
}

function renderUnsupported(payload) {
  preview.innerHTML = `
    <div class="unsupported">
      <div class="unsupported-title">Unsupported file type</div>
      <div>${escapeHtml(payload.name)} (${formatSize(payload.size)})</div>
    </div>`;
}

async function renderMermaidBlocks() {
  const blocks = [...preview.querySelectorAll('.mermaid-source')];
  for (const block of blocks) {
    const code = (block.textContent || '').trim();
    try {
      const id = `mermaid-${crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2)}`;
      const { svg } = await mermaid.render(id, code);
      const wrapper = document.createElement('div');
      wrapper.className = 'mermaid';
      wrapper.innerHTML = svg;
      block.replaceWith(wrapper);
    } catch (error) {
      const pre = document.createElement('pre');
      pre.className = 'diagram-error';
      pre.textContent = `Mermaid render error: ${error.message}`;
      block.replaceWith(pre);
    }
  }
}

function bindLinks(filePath) {
  preview.querySelectorAll('a[href]').forEach((link) => {
    const href = link.getAttribute('data-mdviewer-link') || link.getAttribute('href');
    link.addEventListener('click', (event) => {
      event.preventDefault();
      postMessage('openLink', { href, filePath });
    });
  });
}

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

function postMessage(name, body) {
  window.webkit?.messageHandlers?.[name]?.postMessage(body);
}

function waitForPaint() {
  return new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  });
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text ?? '';
  return div.innerHTML;
}

function escapeAttr(text) {
  return escapeHtml(text).replaceAll('"', '&quot;');
}

function formatSize(bytes = 0) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
