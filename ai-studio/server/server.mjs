import http from 'node:http';
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dataDir = process.env.MARVIN_DATA_DIR
  ? resolve(process.env.MARVIN_DATA_DIR)
  : resolve(root, '.marvin-data');
const jobsFile = resolve(dataDir, 'jobs.json');
const host = process.env.MARVIN_HOST || '127.0.0.1';
const port = Number(process.env.MARVIN_PORT || 8787);
const ollamaBase = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const allowedOrigins = new Set(['http://localhost:5173', 'http://127.0.0.1:5173', 'http://localhost:4173', 'http://127.0.0.1:4173']);
const statuses = new Set(['draft', 'review', 'approved', 'scheduled', 'rendering', 'ready', 'publishing', 'published', 'failed']);
const licensePepper = process.env.MARVIN_LICENSE_PEPPER || '';
let licenseRecords = {};
try {
  const configured = JSON.parse(process.env.MARVIN_LICENSES_JSON || '{}');
  if (configured && typeof configured === 'object' && !Array.isArray(configured)) {
    licenseRecords = Object.fromEntries(Object.entries(configured).filter(([hash, record]) =>
      /^[a-f0-9]{64}$/i.test(hash) && record && typeof record === 'object'
    ));
  }
} catch {
  licenseRecords = {};
}
const licenseAttempts = new Map();
const LICENSE_WINDOW_MS = 60_000;
const LICENSE_MAX_ATTEMPTS = 10;
let writeChain = Promise.resolve();

async function readJobs() {
  try {
    const parsed = JSON.parse(await readFile(jobsFile, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}
async function saveJobs(jobs) {
  writeChain = writeChain.then(async () => {
    await mkdir(dataDir, { recursive: true });
    const temp = jobsFile + '.tmp';
    await writeFile(temp, JSON.stringify(jobs, null, 2), 'utf8');
    const { rename } = await import('node:fs/promises');
    await rename(temp, jobsFile);
  });
  return writeChain;
}
function send(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(payload));
}
async function bodyJson(req) {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 1_000_000) throw Object.assign(new Error('Request body too large'), { status: 413 });
  }
  if (!raw) return {};
  try { return JSON.parse(raw); }
  catch { throw Object.assign(new Error('Invalid JSON body'), { status: 400 }); }
}
function licenseDigest(key) {
  return createHmac('sha256', licensePepper).update(key, 'utf8').digest();
}
function verifyLicenseKey(key) {
  if (!licensePepper || !Object.keys(licenseRecords).length) return { configured: false };
  const candidate = licenseDigest(key);
  let matchedRecord = null;
  for (const [hash, record] of Object.entries(licenseRecords)) {
    const stored = Buffer.from(hash, 'hex');
    if (stored.length === candidate.length && timingSafeEqual(stored, candidate)) matchedRecord = record;
  }
  if (!matchedRecord) return { configured: true, valid: false };
  if (matchedRecord.status !== 'active') return { configured: true, valid: false };
  if (matchedRecord.expiresAt) {
    const expiry = Date.parse(matchedRecord.expiresAt);
    if (!Number.isFinite(expiry) || expiry <= Date.now()) return { configured: true, valid: false };
  }
  return {
    configured: true,
    valid: true,
    license: {
      id: cleanText(matchedRecord.licenseId, 80) || null,
      plan: cleanText(matchedRecord.plan, 40) || 'standard',
      expiresAt: matchedRecord.expiresAt || null
    }
  };
}
function licenseRateLimit(req) {
  const ip = req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  const current = licenseAttempts.get(ip);
  if (!current || now - current.startedAt >= LICENSE_WINDOW_MS) {
    licenseAttempts.set(ip, { startedAt: now, count: 1 });
    return false;
  }
  current.count += 1;
  return current.count > LICENSE_MAX_ATTEMPTS;
}
function cleanText(value, max = 4000) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
async function ollama(path, options = {}) {
  const response = await fetch(new URL(path, ollamaBase), { ...options, signal: AbortSignal.timeout(90_000) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Ollama returned HTTP ${response.status}`);
  return data;
}

const server = http.createServer(async (req, res) => {
  const origin = req.headers.origin;
  if (origin && allowedOrigins.has(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  }
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  const url = new URL(req.url, `http://${host}:${port}`);
  try {
    if (req.method === 'GET' && url.pathname === '/api/health') {
      let engine = { connected: false, models: [], error: '' };
      try {
        const tags = await ollama('/api/tags');
        engine = { connected: true, models: (tags.models || []).map(model => ({ name: model.name, size: model.size })) };
      } catch (error) { engine.error = error.message; }
      return send(res, 200, { ok: true, service: 'marvin-local-api', version: 1, engine, timestamp: new Date().toISOString() });
    }
    if (req.method === 'GET' && url.pathname === '/api/models') {
      const tags = await ollama('/api/tags');
      return send(res, 200, { models: (tags.models || []).map(model => ({ name: model.name, size: model.size })) });
    }
    if (req.method === 'POST' && url.pathname === '/api/generate') {
      const input = await bodyJson(req);
      const model = cleanText(input.model || 'qwen2.5:3b', 100);
      const niche = cleanText(input.niche || 'محتوى متنوع يختاره الذكاء الاصطناعي', 160);
      const topic = cleanText(input.topic, 500);
      const platforms = Array.isArray(input.platforms) ? input.platforms.filter(x => typeof x === 'string').slice(0, 3) : ['YouTube Shorts', 'Instagram Reels', 'TikTok'];
      const prompt = `أنت مدير إبداعي ومنتج فيديوهات قصيرة. اختر أفكاراً جذابة وأصلية ومتنوعة، وتجنب الادعاءات الواقعية غير الموثقة. المجال: ${niche}. الموضوع الإضافي إن وجد: ${topic || 'اختر بنفسك من موضوعات مناسبة وآمنة ورائجة عالمياً'}. المنصات: ${platforms.join('، ')}. أعد JSON فقط بهذا الشكل: {"ideas":[{"title":"...","hook":"...","script":"سيناريو 30-60 ثانية مع وصف المشاهد","caption":"...","hashtags":["#..."],"cta":"...","visual_prompt":"وصف بصري لتوليد الفيديو","duration_seconds":45}]}. أعد 3 أفكار مختلفة باللغة العربية المصرية الواضحة.`;
      const result = await ollama('/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model, messages: [{ role: 'user', content: prompt }], stream: false, format: 'json', options: { temperature: 0.8 } }) });
      let parsed;
      try { parsed = JSON.parse(result.message?.content || '{}'); } catch { throw new Error('Model response was not valid JSON'); }
      const ideas = Array.isArray(parsed.ideas) ? parsed.ideas.slice(0, 5) : [];
      return send(res, 200, { model: result.model || model, ideas });
    }
    if (req.method === 'GET' && url.pathname === '/api/jobs') {
      const jobs = await readJobs();
      return send(res, 200, { jobs });
    }
    if (req.method === 'POST' && url.pathname === '/api/jobs') {
      const input = await bodyJson(req);
      const title = cleanText(input.title, 180);
      if (!title) return send(res, 400, { error: 'A title is required.' });
      const job = { id: randomUUID(), title, script: cleanText(input.script), caption: cleanText(input.caption, 2000), hashtags: Array.isArray(input.hashtags) ? input.hashtags.filter(x => typeof x === 'string').slice(0, 30) : [], visualPrompt: cleanText(input.visualPrompt, 3000), platforms: Array.isArray(input.platforms) ? input.platforms.filter(x => ['YouTube', 'Instagram', 'TikTok'].includes(x)).slice(0, 3) : [], status: 'draft', createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      const jobs = await readJobs(); jobs.unshift(job); await saveJobs(jobs);
      return send(res, 201, { job });
    }
    const jobMatch = url.pathname.match(/^\/api\/jobs\/([a-f0-9-]+)$/i);
    if (jobMatch && req.method === 'PATCH') {
      const input = await bodyJson(req); const jobs = await readJobs();
      const index = jobs.findIndex(job => job.id === jobMatch[1]);
      if (index < 0) return send(res, 404, { error: 'Job not found.' });
      const patch = {};
      if (typeof input.status === 'string' && statuses.has(input.status)) patch.status = input.status;
      if (typeof input.scheduledAt === 'string') patch.scheduledAt = cleanText(input.scheduledAt, 80);
      if (typeof input.title === 'string' && cleanText(input.title, 180)) patch.title = cleanText(input.title, 180);
      jobs[index] = { ...jobs[index], ...patch, updatedAt: new Date().toISOString() };
      await saveJobs(jobs); return send(res, 200, { job: jobs[index] });
    }
    if (jobMatch && req.method === 'DELETE') {
      const jobs = await readJobs(); const next = jobs.filter(job => job.id !== jobMatch[1]);
      if (next.length === jobs.length) return send(res, 404, { error: 'Job not found.' });
      await saveJobs(next); return send(res, 200, { deleted: true });
    }
    if (req.method === 'POST' && /^\/api\/jobs\/[a-f0-9-]+\/publish$/i.test(url.pathname)) {
      return send(res, 409, { error: 'Publishing adapters are not configured yet. Connect and authorize the target platform before publishing.' });
    }
    return send(res, 404, { error: 'Route not found.' });
  } catch (error) {
    const status = error.status || (error.name === 'TimeoutError' ? 504 : 502);
    return send(res, status, { error: error.message || 'Unexpected server error.' });
  }
});

server.listen(port, host, () => {
  console.log(`MARVIN local API listening at http://${host}:${port}`);
  console.log('Local job storage: ai-studio/.marvin-data/jobs.json');
});
