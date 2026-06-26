export function resolveAssetURL(src, filePath) {
  if (!src) {
    return src;
  }
  if (isRemoteURL(src)) {
    return '';
  }
  const path = resolvePath(src, filePath);
  const url = new URL('mdv-file://asset');
  url.searchParams.set('path', path);
  return url.toString();
}

export function isRemoteURL(value) {
  return /^(https?:|data:|blob:)/i.test(value);
}

export function resolvePath(src, filePath) {
  const cleanSrc = decodeURIComponent(src.split('#')[0].split('?')[0]);
  if (cleanSrc.startsWith('/')) {
    return normalizePath(cleanSrc);
  }
  const base = filePath.split('/').slice(0, -1).join('/') || '/';
  return normalizePath(`${base}/${cleanSrc}`);
}

export function normalizePath(path) {
  const parts = [];
  for (const part of path.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') {
      if (parts.length === 0) {
        throw new Error('Asset path cannot escape the workspace.');
      }
      parts.pop();
      continue;
    }
    parts.push(part);
  }
  return `/${parts.join('/')}`;
}
