import DOMPurify from 'dompurify';
import mermaid from 'mermaid';
import hljs from 'highlight.js/lib/common';
import MarkdownWorker from './markdownWorker.js?worker&inline';
import 'highlight.js/styles/github.css';
import 'katex/dist/katex.min.css';
import './styles.css';

const preview = document.getElementById('preview');
let currentPayload = null;
let activeRenderToken = null;
let activeMarkdownWorker = null;

class RenderCancelledError extends Error {
  constructor(renderID) {
    super(`Render ${renderID ?? ''} was cancelled.`);
    this.name = 'RenderCancelledError';
  }
}

function createRenderToken(renderID) {
  return {
    renderID,
    isCancelled: false,
  };
}

function cancelActiveRender(renderID) {
  if (!activeRenderToken) {
    return false;
  }
  if (renderID !== undefined && activeRenderToken.renderID !== renderID) {
    return false;
  }
  activeRenderToken.isCancelled = true;
  cancelMarkdownWorker(activeRenderToken);
  return true;
}

function assertRenderActive(token) {
  if (!token || token.isCancelled || activeRenderToken !== token) {
    throw new RenderCancelledError(token?.renderID);
  }
}

function isRenderCancelled(error) {
  return error instanceof RenderCancelledError;
}

function shouldAbortRender(error, token) {
  return isRenderCancelled(error) || token?.isCancelled || activeRenderToken !== token;
}

window.addEventListener('error', (event) => {
  if (isRenderCancelled(event.error)) {
    return;
  }
  if (activeRenderToken) {
    return;
  }
  postRenderError(event.message || 'Renderer JavaScript error');
});

window.addEventListener('unhandledrejection', (event) => {
  if (isRenderCancelled(event.reason)) {
    return;
  }
  if (activeRenderToken) {
    return;
  }
  const reason = event.reason?.message || String(event.reason || 'Unhandled renderer rejection');
  postRenderError(reason);
});

window.MDViewer = {
  lastStartedRenderID: 0,
  lastCompletedRenderID: 0,

  get isRendering() {
    return Boolean(activeRenderToken);
  },

  cancelRender(renderID) {
    return cancelActiveRender(renderID);
  },

  async render(payload, renderID) {
    cancelActiveRender();
    const token = createRenderToken(renderID);
    activeRenderToken = token;
    this.lastStartedRenderID = renderID;
    this.lastCompletedRenderID = 0;
    currentPayload = payload;
    try {
      assertRenderActive(token);
      applySettings(payload);
      if (payload.kind === 'markdown') {
        await renderMarkdown(payload, token);
      } else if (payload.kind === 'image') {
        renderImage(payload, token);
      } else if (payload.kind === 'text') {
        renderText(payload, token);
      } else {
        renderUnsupported(payload, token);
      }
    } catch (error) {
      if (shouldAbortRender(error, token)) {
        return;
      }
      postRenderError(error.message, token);
      preview.innerHTML = `<div class="error">Render error: ${escapeHtml(error.message)}</div>`;
    } finally {
      if (!token.isCancelled && activeRenderToken === token) {
        this.lastCompletedRenderID = Math.max(this.lastCompletedRenderID, renderID);
        await waitForPaint(token);
        if (!token.isCancelled && activeRenderToken === token) {
          postMessage('renderComplete', { renderID });
        }
      }
      if (activeRenderToken === token) {
        activeRenderToken = null;
      }
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

async function renderMarkdown(payload, token) {
  try {
    assertRenderActive(token);
    const html = await renderMarkdownInWorker(payload, token);
    assertRenderActive(token);
    const sanitized = DOMPurify.sanitize(html, {
      ADD_ATTR: ['target', 'rel', 'data-mdviewer-link'],
    });
    assertRenderActive(token);
    preview.innerHTML = sanitized;
    bindLinks(payload.filePath);
    await renderMermaidBlocks(token);
  } catch (error) {
    if (shouldAbortRender(error, token)) {
      throw error;
    }
    postRenderError(error.message, token);
    preview.innerHTML = `<div class="error">Markdown render error: ${escapeHtml(error.message)}</div>`;
  }
}

function renderMarkdownInWorker(payload, token) {
  return new Promise((resolve, reject) => {
    assertRenderActive(token);
    if (typeof Worker === 'undefined') {
      reject(new Error('Markdown worker is unavailable.'));
      return;
    }

    const worker = new MarkdownWorker();
    const session = {
      token,
      worker,
      reject,
      isFinished: false,
    };
    activeMarkdownWorker = session;

    worker.onmessage = (event) => {
      const data = event.data || {};
      if (data.renderID !== token.renderID) {
        return;
      }
      if (token.isCancelled || activeRenderToken !== token) {
        finishMarkdownWorker(session, () => reject(new RenderCancelledError(token.renderID)));
        return;
      }
      if (data.type === 'renderedMarkdown') {
        finishMarkdownWorker(session, () => resolve(data.html || ''));
        return;
      }
      finishMarkdownWorker(session, () => reject(new Error(data.message || 'Markdown worker failed.')));
    };

    worker.onerror = (event) => {
      finishMarkdownWorker(session, () => reject(new Error(event.message || 'Markdown worker failed.')));
    };

    worker.postMessage({
      type: 'renderMarkdown',
      renderID: token.renderID,
      payload: {
        markdown: payload.markdown || '',
        filePath: payload.filePath || '',
      },
    });
  });
}

function cancelMarkdownWorker(token) {
  const session = activeMarkdownWorker;
  if (!session || session.token !== token) {
    return false;
  }
  finishMarkdownWorker(session, () => session.reject(new RenderCancelledError(token.renderID)));
  return true;
}

function finishMarkdownWorker(session, complete) {
  if (session.isFinished) {
    return;
  }
  session.isFinished = true;
  if (activeMarkdownWorker === session) {
    activeMarkdownWorker = null;
  }
  session.worker.onmessage = null;
  session.worker.onerror = null;
  session.worker.terminate();
  complete();
}

function renderImage(payload, token) {
  assertRenderActive(token);
  const src = payload.mediaURL || resolveAssetURL(payload.filePath, payload.filePath);
  preview.innerHTML = `
    <div class="media-preview">
      <img src="${escapeAttr(src)}" alt="${escapeAttr(payload.name)}">
      <div class="file-caption">${escapeHtml(payload.name)} (${formatSize(payload.size)})</div>
    </div>`;
}

function renderText(payload, token) {
  assertRenderActive(token);
  const language = payload.language && hljs.getLanguage(payload.language) ? payload.language : '';
  const highlighted = language
    ? hljs.highlight(payload.content || '', { language }).value
    : escapeHtml(payload.content || '');
  preview.innerHTML = `
    <div class="code-viewer">
      <pre><code class="hljs${language ? ` language-${escapeAttr(language)}` : ''}">${highlighted}</code></pre>
    </div>`;
}

function renderUnsupported(payload, token) {
  assertRenderActive(token);
  preview.innerHTML = `
    <div class="unsupported">
      <div class="unsupported-title">Unsupported file type</div>
      <div>${escapeHtml(payload.name)} (${formatSize(payload.size)})</div>
    </div>`;
}

async function renderMermaidBlocks(token) {
  const blocks = [...preview.querySelectorAll('.mermaid-source')];
  for (const block of blocks) {
    assertRenderActive(token);
    const code = (block.textContent || '').trim();
    try {
      const id = `mermaid-${crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2)}`;
      const { svg } = await mermaid.render(id, code);
      assertRenderActive(token);
      const wrapper = document.createElement('div');
      wrapper.className = 'mermaid';
      wrapper.innerHTML = svg;
      block.replaceWith(wrapper);
    } catch (error) {
      if (shouldAbortRender(error, token)) {
        throw error;
      }
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

function postRenderError(message, token = activeRenderToken) {
  const body = { message: String(message || 'Renderer JavaScript error') };
  if (token?.renderID !== undefined) {
    body.renderID = token.renderID;
  }
  postMessage('renderError', body);
}

function waitForPaint(token) {
  return new Promise((resolve) => {
    if (token?.isCancelled) {
      resolve();
      return;
    }

    let isResolved = false;
    const finish = () => {
      if (!isResolved) {
        isResolved = true;
        resolve();
      }
    };

    setTimeout(finish, 250);
    requestAnimationFrame(() => requestAnimationFrame(finish));
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
