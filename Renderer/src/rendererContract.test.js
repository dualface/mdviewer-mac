import assert from 'node:assert/strict';
import test from 'node:test';
import { isRemoteURL, resolveAssetURL, resolvePath } from './assetResolver.js';

test('resolves relative assets through the workspace scheme', () => {
  assert.equal(resolvePath('assets/image.png#caption', '/docs/readme.md'), '/docs/assets/image.png');
  assert.equal(resolvePath('../shared/image.png#caption', '/docs/pages/readme.md'), '/docs/shared/image.png');
  assert.equal(resolveAssetURL('assets/image.png', '/docs/readme.md'), 'mdv-file://asset?path=%2Fdocs%2Fassets%2Fimage.png');
});

test('blocks remote and embedded asset URLs', () => {
  assert.equal(resolveAssetURL('https://example.com/image.png', '/docs/readme.md'), '');
  assert.equal(resolveAssetURL('http://example.com/image.png', '/docs/readme.md'), '');
  assert.equal(resolveAssetURL('data:image/png;base64,aaaa', '/docs/readme.md'), '');
  assert.equal(resolveAssetURL('blob:https://example.com/id', '/docs/readme.md'), '');
  assert.equal(isRemoteURL('https://example.com'), true);
  assert.equal(isRemoteURL('mdv-file://asset?path=/local.png'), false);
});

test('rejects traversal instead of normalizing outside the workspace', () => {
  assert.throws(() => resolvePath('../../secret.png', '/docs/readme.md'), /escape the workspace/);
});
