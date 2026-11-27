import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pepper = process.env.MARVIN_LICENSE_PEPPER || '';
const registryPath = resolve(process.env.MARVIN_LICENSES_FILE || resolve(root, '.marvin-data', 'licenses.json'));

function fail(message) {
  console.error(message);
  process.exit(1);
}
function digest(key) {
  return createHmac('sha256', pepper).update(key, 'utf8').digest('hex');
}
async function loadRegistry() {
  try {
    const parsed = JSON.parse(await readFile(registryPath, 'utf8'));
    return {
      licenses: parsed.licenses && typeof parsed.licenses === 'object' ? parsed.licenses : {},
      audit: Array.isArray(parsed.audit) ? parsed.audit : []
    };
  } catch (error) {
    if (error.code === 'ENOENT') return { licenses: {}, audit: [] };
    throw error;
  }
}
async function saveRegistry(registry) {
  await mkdir(dirname(registryPath), { recursive: true, mode: 0o700 });
  const temp = registryPath + '.tmp';
  await writeFile(temp, JSON.stringify(registry, null, 2) + '\n', { encoding: 'utf8', mode: 0o600 });
  await chmod(temp, 0o600);
  await rename(temp, registryPath);
  await chmod(registryPath, 0o600);
}
function audit(registry, action, licenseId) {
  registry.audit.push({ action, licenseId, at: new Date().toISOString() });
  if (registry.audit.length > 5000) registry.audit = registry.audit.slice(-5000);
}

if (!pepper) fail('MARVIN_LICENSE_PEPPER is required. Load it from a secure secret source; never commit it.');
const [command, ...args] = process.argv.slice(2);
if (!['issue', 'revoke', 'list'].includes(command)) {
  fail('Usage: npm run license -- issue --plan vip --days 30 | revoke <licenseId> | list');
}

const registry = await loadRegistry();

if (command === 'issue') {
  const planIndex = args.indexOf('--plan');
  const daysIndex = args.indexOf('--days');
  const plan = planIndex >= 0 ? args[planIndex + 1] : 'standard';
  const days = daysIndex >= 0 ? Number(args[daysIndex + 1]) : 30;
  if (!/^[a-zA-Z0-9_-]{1,40}$/.test(plan || '')) fail('Plan must be 1–40 letters, numbers, "_" or "-".');
  if (!Number.isInteger(days) || days < 1 || days > 3650) fail('Days must be an integer from 1 to 3650.');
  const key = 'MARVIN-' + randomBytes(32).toString('base64url');
  const licenseId = randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + days * 86_400_000).toISOString();
  registry.licenses[digest(key)] = {
    licenseId,
    status: 'active',
    plan,
    createdAt: now.toISOString(),
    expiresAt
  };
  audit(registry, 'issued', licenseId);
  await saveRegistry(registry);
  console.log('LICENSE KEY (shown once; save it securely):');
  console.log(key);
  console.log('LICENSE ID: ' + licenseId);
  console.log('EXPIRES: ' + expiresAt);
} else if (command === 'revoke') {
  const licenseId = args[0];
  if (!licenseId) fail('Usage: npm run license -- revoke <licenseId>');
  const record = Object.values(registry.licenses).find(item => item.licenseId === licenseId);
  if (!record) fail('License ID not found.');
  if (record.status !== 'active') fail('License is already inactive.');
  record.status = 'revoked';
  record.revokedAt = new Date().toISOString();
  audit(registry, 'revoked', licenseId);
  await saveRegistry(registry);
  console.log('Revoked license: ' + licenseId);
} else {
  const rows = Object.values(registry.licenses).map(record => ({
    licenseId: record.licenseId,
    status: record.status,
    plan: record.plan,
    createdAt: record.createdAt,
    expiresAt: record.expiresAt || null,
    revokedAt: record.revokedAt || null
  }));
  console.log(JSON.stringify(rows, null, 2));
}
