import test from 'node:test';
import assert from 'node:assert/strict';
import config from '../next.config.mjs';

test('security headers cover all routes without enabling cross-origin access', async () => {
  const rules = await config.headers();
  assert.equal(rules.length, 1);
  assert.equal(rules[0].source, '/:path*');
  const headers = new Headers(rules[0].headers.map(({ key, value }) => [key, value]));
  assert.equal(headers.get('X-Content-Type-Options'), 'nosniff');
  assert.equal(headers.get('X-Frame-Options'), 'DENY');
  assert.equal(headers.get('Referrer-Policy'), 'strict-origin-when-cross-origin');
  assert.equal(headers.get('Content-Security-Policy'), "frame-ancestors 'none'; object-src 'none'; base-uri 'self'");
  assert.equal(headers.has('Access-Control-Allow-Origin'), false);
  assert.equal(config.poweredByHeader, false);
});
