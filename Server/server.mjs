import http from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const languages = new Set(['ko', 'en', 'ja', 'zh']);
const digest = value => createHash('sha256').update(value).digest();
export class RelayError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}

export async function deepLTranslate(body, { apiKey, plan = 'free', signal, fetchImpl = fetch }) {
  const endpoint = plan === 'pro' ? 'https://api.deepl.com/v2/translate' : 'https://api-free.deepl.com/v2/translate';
  const upstream = await fetchImpl(endpoint, {
    method: 'POST', redirect: 'error', signal,
    headers: { 'Authorization': `DeepL-Auth-Key ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ text: [body.text], target_lang: body.targetLanguage === 'en' ? 'EN-US' : body.targetLanguage.toUpperCase(),
      ...(body.sourceLanguage ? { source_lang: body.sourceLanguage.toUpperCase() } : {}) })
  });
  if (!upstream.ok) {
    await upstream.body?.cancel();
    throw new RelayError(upstream.status === 429 || upstream.status === 456 ? 429 : 502, 'provider_unavailable');
  }
  if (!upstream.body) throw new RelayError(502, 'invalid_provider_response');
  const chunks = [];
  let length = 0;
  for await (const chunk of upstream.body) {
    length += chunk.length;
    if (length > 65536) throw new RelayError(502, 'invalid_provider_response');
    chunks.push(Buffer.from(chunk));
  }
  let json;
  try { json = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new RelayError(502, 'invalid_provider_response'); }
  const result = json.translations?.[0];
  if (typeof result?.text !== 'string' || !result.text.trim() || [...result.text].length > 8000) {
    throw new RelayError(502, 'invalid_provider_response');
  }
  return { translatedText: result.text, detectedSourceLanguage: typeof result.detected_source_language === 'string' ? result.detected_source_language.toLowerCase() : null, provider: 'DeepL' };
}

function validate(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)
      || Object.keys(body).some(key => !['text', 'sourceLanguage', 'targetLanguage'].includes(key))
      || typeof body.text !== 'string' || !body.text.trim()
      || [...body.text].length > 2000 // Swift's 500 graphemes may use multiple scalars.
      || [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(body.text)].length > 500
      || !languages.has(body.targetLanguage)
      || (body.sourceLanguage != null && !languages.has(body.sourceLanguage))) {
    throw new RelayError(400, 'invalid_request');
  }
}

export function createRelay({ clientToken, translate, ratePerMinute = 60, dailyLimit = 1000, timeoutMs = 7000, now = Date.now }) {
  if (typeof clientToken !== 'string' || clientToken.length < 32) throw new Error('CLIENT_TOKEN must contain at least 32 characters');
  const expectedToken = digest(`Bearer ${clientToken}`);
  let minuteStart = now(), dayStart = now(), minuteCount = 0, dayCount = 0, active = 0;
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const reply = (status, body) => {
      if (!res.destroyed && !res.writableEnded) { res.writeHead(status); res.end(JSON.stringify(body)); }
    };
    if (req.url === '/health' && req.method === 'GET') { reply(200, { status: 'ok' }); return; }
    if (req.url !== '/v1/translate' || req.method !== 'POST') { reply(404, { error: 'not_found' }); req.resume(); return; }
    if (!timingSafeEqual(expectedToken, digest(req.headers.authorization ?? ''))) { reply(401, { error: 'unauthorized' }); req.resume(); return; }
    if (now() - minuteStart >= 60000) { minuteStart = now(); minuteCount = 0; }
    if (now() - dayStart >= 86400000) { dayStart = now(); dayCount = 0; }
    if (minuteCount >= ratePerMinute || dayCount >= dailyLimit || active >= 8) {
      res.setHeader('Retry-After', '60'); reply(429, { error: 'rate_limited' }); req.resume(); return;
    }
    if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] ?? '')) {
      reply(415, { error: 'json_required' }); req.resume(); return;
    }
    minuteCount++; dayCount++; active++;
    const controller = new AbortController();
    const cancel = () => controller.abort();
    res.once('close', cancel);
    const timer = setTimeout(cancel, timeoutMs);
    try {
      let length = 0;
      const chunks = [];
      // The timeout must terminate slow uploads too, not just provider requests.
      const abortUpload = () => { if (!req.complete) req.destroy(); };
      controller.signal.addEventListener('abort', abortUpload, { once: true });
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 16384) throw new RelayError(413, 'request_too_large');
        chunks.push(chunk);
      }
      controller.signal.removeEventListener('abort', abortUpload);
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { throw new RelayError(400, 'invalid_json'); }
      validate(body);
      controller.signal.throwIfAborted();
      const result = await translate(body, controller.signal);
      controller.signal.throwIfAborted();
      reply(200, result);
    } catch (error) {
      // Never serialize Error messages, provider payloads, tokens or input text.
      if (controller.signal.aborted) reply(504, { error: 'timeout_or_cancelled' });
      else if (error instanceof RelayError) reply(error.status, { error: error.code });
      else reply(502, { error: 'provider_unavailable' });
    } finally {
      clearTimeout(timer); res.off('close', cancel); active--;
    }
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  return server;
}

function positiveInteger(value, fallback) {
  const number = value == null ? fallback : Number(value);
  if (!Number.isSafeInteger(number) || number < 1) throw new Error('Invalid numeric configuration');
  return number;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    if (!process.env.DEEPL_API_KEY) throw new Error('Missing provider configuration');
    if (!['free', 'pro'].includes(process.env.DEEPL_PLAN ?? 'free')) throw new Error('Invalid provider plan');
    const server = createRelay({
      clientToken: process.env.CLIENT_TOKEN,
      ratePerMinute: positiveInteger(process.env.RATE_PER_MINUTE, 60),
      dailyLimit: positiveInteger(process.env.DAILY_REQUEST_LIMIT, 1000),
      translate: (body, signal) => deepLTranslate(body, { apiKey: process.env.DEEPL_API_KEY, plan: process.env.DEEPL_PLAN, signal })
    });
    server.listen(positiveInteger(process.env.PORT, 8787), '127.0.0.1');
    server.on('error', () => { process.stderr.write('Relay could not start. Check host configuration.\n'); process.exitCode = 1; });
  } catch { process.stderr.write('Relay configuration is missing or invalid.\n'); process.exitCode = 1; }
}
