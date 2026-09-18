import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import { createRelay, deepLTranslate } from './server.mjs';

const token = 'test-only-token-that-is-not-a-production-secret';
const example = { text: '안녕하세요', targetLanguage: 'ja' };
async function fixture(t, options = {}) {
  const calls = [];
  const server = createRelay({ clientToken: token, translate: async (body, signal) => {
    calls.push({ body, signal });
    return { translatedText: 'こんにちは', detectedSourceLanguage: 'ko', provider: 'Test' };
  }, ...options });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const url = `http://127.0.0.1:${server.address().port}/v1/translate`;
  const post = (body = example, bearer = token) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` }, body: JSON.stringify(body) });
  return { calls, url, post };
}

test('authorized translation forwards only expected fields and disables caching', async t => {
  const { post, calls } = await fixture(t);
  const result = await post();
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await result.json(), { translatedText: 'こんにちは', detectedSourceLanguage: 'ko', provider: 'Test' });
  assert.deepEqual(calls[0].body, example);
});
test('unauthorized requests never reach provider', async t => {
  const { post, calls } = await fixture(t);
  assert.equal((await post(example, 'bad')).status, 401);
  assert.equal(calls.length, 0);
});
test('empty, whitespace, unsupported language, extra keys and oversized input are rejected', async t => {
  const { post, calls } = await fixture(t);
  for (const body of [{ ...example, text: '' }, { ...example, text: '  \n ' }, { ...example, text: 'a'.repeat(501) },
    { ...example, targetLanguage: 'xx' }, { ...example, sourceLanguage: 'xx' }, { ...example, key: 'secret' }, null]) {
    assert.equal((await post(body)).status, 400);
  }
  assert.equal(calls.length, 0);
});
test('Korean, English, Japanese, emoji and combining text survive transport', async t => {
  const { post, calls } = await fixture(t);
  for (const text of ['안녕하세요', 'hello', 'こんにちは', '👨‍👩‍👧‍👦 e\u0301', '𠮷']) {
    assert.equal((await post({ ...example, text })).status, 200);
    assert.equal(calls.at(-1).body.text, text);
  }
});
test('rate and daily limits prevent extra provider calls', async t => {
  for (const options of [{ ratePerMinute: 1 }, { dailyLimit: 1 }]) {
    const { post, calls } = await fixture(t, options);
    assert.equal((await post()).status, 200);
    assert.equal((await post()).status, 429);
    assert.equal(calls.length, 1);
  }
});
test('provider exceptions cannot leak original text or credentials', async t => {
  const { post } = await fixture(t, { translate: async () => { throw new Error('SECRET_TOKEN 안녕하세요'); } });
  const response = await post();
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: 'provider_unavailable' });
});
test('timeout cancels provider work', async t => {
  let cancelled = false;
  const { post } = await fixture(t, { timeoutMs: 30, translate: (_, signal) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => { cancelled = true; reject(new Error('aborted')); }, { once: true });
  }) });
  assert.equal((await post()).status, 504);
  assert.equal(cancelled, true);
});
test('client disconnect cancels upstream request', async t => {
  let started;
  const start = new Promise(resolve => { started = resolve; });
  let aborted;
  const abort = new Promise(resolve => { aborted = resolve; });
  const { url } = await fixture(t, { translate: (_, signal) => new Promise((_, reject) => {
    started();
    signal.addEventListener('abort', () => { aborted(); reject(new Error('aborted')); }, { once: true });
  }) });
  const request = http.request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` } });
  request.on('error', () => {});
  request.end(JSON.stringify(example));
  await start;
  request.destroy();
  await abort;
});
test('DeepL uses server credentials, auto-detection, approved URL and cancellation', async () => {
  const controller = new AbortController();
  const result = await deepLTranslate(example, { apiKey: 'test-provider-key', signal: controller.signal, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api-free.deepl.com/v2/translate');
    assert.equal(options.headers.Authorization, 'DeepL-Auth-Key test-provider-key');
    assert.equal(options.signal, controller.signal);
    assert.equal(options.redirect, 'error');
    assert.deepEqual(JSON.parse(options.body), { text: ['안녕하세요'], target_lang: 'JA' });
    return Response.json({ translations: [{ text: 'こんにちは', detected_source_language: 'KO' }] });
  } });
  assert.deepEqual(result, { translatedText: 'こんにちは', detectedSourceLanguage: 'ko', provider: 'DeepL' });
});
test('malformed and quota provider responses become safe errors', async () => {
  for (const response of [Response.json({ translations: [] }), new Response('private provider details', { status: 429 }), new Response('invalid json')]) {
    await assert.rejects(deepLTranslate(example, { apiKey: 'test', fetchImpl: async () => response }), error =>
      ['provider_unavailable', 'invalid_provider_response'].includes(error.code));
  }
});
test('wrong content type, invalid JSON and unknown routes cannot reach provider', async t => {
  const { url, calls } = await fixture(t);
  const headers = { Authorization: `Bearer ${token}` };
  assert.equal((await fetch(url, { method: 'POST', headers, body: 'private text' })).status, 415);
  assert.equal((await fetch(url, { method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, body: '{broken' })).status, 400);
  assert.equal((await fetch(url)).status, 404);
  assert.equal(calls.length, 0);
});
test('minute window resets while daily limit persists', async t => {
  let time = 100;
  const { post } = await fixture(t, { ratePerMinute: 1, dailyLimit: 2, now: () => time });
  assert.equal((await post()).status, 200);
  assert.equal((await post()).status, 429);
  time += 60001;
  assert.equal((await post()).status, 200);
  time += 60001;
  assert.equal((await post()).status, 429);
  time += 86400001;
  assert.equal((await post()).status, 200);
});
test('provider response size is bounded', async () => {
  await assert.rejects(deepLTranslate(example, { apiKey: 'test', fetchImpl: async () => new Response('x'.repeat(65537)) }),
    error => error.code === 'invalid_provider_response');
});
test('explicit source and English target map to DeepL parameters', async () => {
  await deepLTranslate({ text: 'こんにちは', sourceLanguage: 'ja', targetLanguage: 'en' }, {
    apiKey: 'test', plan: 'pro', fetchImpl: async (url, options) => {
      assert.equal(url, 'https://api.deepl.com/v2/translate');
      assert.deepEqual(JSON.parse(options.body), { text: ['こんにちは'], source_lang: 'JA', target_lang: 'EN-US' });
      return Response.json({ translations: [{ text: 'Hello', detected_source_language: 'JA' }] });
    }
  });
});
