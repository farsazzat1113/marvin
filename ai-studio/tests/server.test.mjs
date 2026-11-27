import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHmac } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

async function reservePort() {
  const probe = net.createServer();
  await new Promise((resolve, reject) => {
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', resolve);
  });
  const port = probe.address().port;
  await new Promise((resolve, reject) => probe.close(error => error ? reject(error) : resolve()));
  return port;
}

async function waitForServer(port, child) {
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`MARVIN server exited early with code ${child.exitCode}`);
    const connected = await new Promise(resolve => {
      const socket = net.createConnection({ host: '127.0.0.1', port });
      socket.once('connect', () => { socket.destroy(); resolve(true); });
      socket.once('error', () => resolve(false));
    });
    if (connected) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('Timed out waiting for MARVIN API to listen');
}

test('job queue supports create, list, update, delete, and blocks unconfigured publishing', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'marvin-api-test-'));
  const port = await reservePort();
  const child = spawn(process.execPath, ['server/server.mjs'], {
    cwd: projectDir,
    env: {
      ...process.env,
      MARVIN_HOST: '127.0.0.1',
      MARVIN_PORT: String(port),
      MARVIN_DATA_DIR: dataDir,
      MARVIN_LICENSE_PEPPER: '',
      MARVIN_LICENSES_JSON: ''
    },
    stdio: 'ignore'
  });
  const base = `http://127.0.0.1:${port}`;

  try {
    await waitForServer(port, child);

    const verifierDisabled = await fetch(`${base}/api/license/verify`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ key: 'MARVIN-TEST-KEY-0001' })
    });
    assert.equal(verifierDisabled.status, 503);

    const empty = await fetch(`${base}/api/jobs`);
    assert.equal(empty.status, 200);
    assert.deepEqual((await empty.json()).jobs, []);

    const createdResponse = await fetch(`${base}/api/jobs`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        title: 'MARVIN integration test',
        script: 'Test script',
        platforms: ['YouTube', 'invalid-platform']
      })
    });
    assert.equal(createdResponse.status, 201);
    const created = (await createdResponse.json()).job;
    assert.ok(created.id);
    assert.equal(created.status, 'draft');
    assert.deepEqual(created.platforms, ['YouTube']);

    const listed = await (await fetch(`${base}/api/jobs`)).json();
    assert.equal(listed.jobs.length, 1);
    assert.equal(listed.jobs[0].id, created.id);

    const updatedResponse = await fetch(`${base}/api/jobs/${created.id}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ status: 'scheduled', scheduledAt: '2026-12-01T12:00:00Z' })
    });
    assert.equal(updatedResponse.status, 200);
    const updated = (await updatedResponse.json()).job;
    assert.equal(updated.status, 'scheduled');
    assert.equal(updated.scheduledAt, '2026-12-01T12:00:00Z');

    const publishResponse = await fetch(`${base}/api/jobs/${created.id}/publish`, { method: 'POST' });
    assert.equal(publishResponse.status, 409);
    assert.match((await publishResponse.json()).error, /not configured/i);

    const deletedResponse = await fetch(`${base}/api/jobs/${created.id}`, { method: 'DELETE' });
    assert.equal(deletedResponse.status, 200);
    assert.deepEqual(await deletedResponse.json(), { deleted: true });

    const finalList = await (await fetch(`${base}/api/jobs`)).json();
    assert.deepEqual(finalList.jobs, []);
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => {
      if (child.exitCode !== null) return resolve();
      child.once('exit', resolve);
      setTimeout(resolve, 1500).unref();
    });
    await rm(dataDir, { recursive: true, force: true });
  }
});


test('private license verifier accepts only active, unexpired server-side hashes', async () => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'marvin-license-test-'));
  const port = await reservePort();
  const pepper = 'test-only-pepper-never-use-in-production';
  const digest = key => createHmac('sha256', pepper).update(key, 'utf8').digest('hex');
  const activeKey = 'MARVIN-PRIVATE-TEST-KEY-0001';
  const revokedKey = 'MARVIN-PRIVATE-TEST-KEY-0002';
  const expiredKey = 'MARVIN-PRIVATE-TEST-KEY-0003';
  const records = {
    [digest(activeKey)]: { status: 'active', plan: 'vip', licenseId: 'test-active', expiresAt: '2099-01-01T00:00:00.000Z' },
    [digest(revokedKey)]: { status: 'revoked', plan: 'vip', licenseId: 'test-revoked' },
    [digest(expiredKey)]: { status: 'active', plan: 'vip', licenseId: 'test-expired', expiresAt: '2000-01-01T00:00:00.000Z' }
  };
  const child = spawn(process.execPath, ['server/server.mjs'], {
    cwd: projectDir,
    env: {
      ...process.env,
      MARVIN_HOST: '127.0.0.1',
      MARVIN_PORT: String(port),
      MARVIN_DATA_DIR: dataDir,
      MARVIN_LICENSE_PEPPER: pepper,
      MARVIN_LICENSES_JSON: JSON.stringify(records)
    },
    stdio: 'ignore'
  });
  const base = `http://127.0.0.1:${port}`;
  const verify = key => fetch(`${base}/api/license/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ key })
  });

  try {
    await waitForServer(port, child);

    const accepted = await verify(activeKey);
    assert.equal(accepted.status, 200);
    const acceptedBody = await accepted.json();
    assert.equal(acceptedBody.valid, true);
    assert.equal(acceptedBody.license.id, 'test-active');
    assert.equal(acceptedBody.license.plan, 'vip');

    for (const key of [revokedKey, expiredKey, 'MARVIN-UNKNOWN-KEY-0000']) {
      const rejected = await verify(key);
      assert.equal(rejected.status, 401);
      assert.equal((await rejected.json()).valid, false);
    }

    const malformed = await verify('short');
    assert.equal(malformed.status, 400);
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => {
      if (child.exitCode !== null) return resolve();
      child.once('exit', resolve);
      setTimeout(resolve, 1500).unref();
    });
    await rm(dataDir, { recursive: true, force: true });
  }
});


test('license admin CLI stores only hashes and revocation takes effect without restarting API', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'marvin-license-admin-test-'));
  const registryPath = path.join(tempDir, 'licenses.json');
  const pepper = 'test-only-license-admin-pepper';
  const env = {
    ...process.env,
    MARVIN_LICENSE_PEPPER: pepper,
    MARVIN_LICENSES_FILE: registryPath,
    MARVIN_LICENSES_JSON: ''
  };
  const runAdmin = (...args) => spawnSync(process.execPath, ['scripts/manage-licenses.mjs', ...args], {
    cwd: projectDir,
    env,
    encoding: 'utf8'
  });

  const port = await reservePort();
  const child = spawn(process.execPath, ['server/server.mjs'], {
    cwd: projectDir,
    env: {
      ...env,
      MARVIN_HOST: '127.0.0.1',
      MARVIN_PORT: String(port),
      MARVIN_DATA_DIR: tempDir
    },
    stdio: 'ignore'
  });
  const base = `http://127.0.0.1:${port}`;
  const verify = key => fetch(`${base}/api/license/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ key })
  });

  try {
    const issued = runAdmin('issue', '--plan', 'vip', '--days', '30');
    assert.equal(issued.status, 0, issued.stderr);
    const keyMatch = issued.stdout.match(/MARVIN-[A-Za-z0-9_-]{40,}/);
    const idMatch = issued.stdout.match(/LICENSE ID: ([a-f0-9-]+)/i);
    assert.ok(keyMatch, 'issue command should print the new key once');
    assert.ok(idMatch, 'issue command should print the license ID');
    const key = keyMatch[0];
    const licenseId = idMatch[1];

    const rawRegistry = await readFile(registryPath, 'utf8');
    assert.equal(rawRegistry.includes(key), false, 'plaintext key must not be persisted');
    const registry = JSON.parse(rawRegistry);
    const expectedHash = createHmac('sha256', pepper).update(key, 'utf8').digest('hex');
    assert.ok(registry.licenses[expectedHash]);
    assert.equal(registry.licenses[expectedHash].status, 'active');

    await waitForServer(port, child);
    const accepted = await verify(key);
    assert.equal(accepted.status, 200);

    const listed = runAdmin('list');
    assert.equal(listed.status, 0, listed.stderr);
    assert.equal(listed.stdout.includes(key), false);
    assert.match(listed.stdout, new RegExp(licenseId));

    const revoked = runAdmin('revoke', licenseId);
    assert.equal(revoked.status, 0, revoked.stderr);
    const rejected = await verify(key);
    assert.equal(rejected.status, 401, 'revocation should apply on the next verification request');
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => {
      if (child.exitCode !== null) return resolve();
      child.once('exit', resolve);
      setTimeout(resolve, 1500).unref();
    });
    await rm(tempDir, { recursive: true, force: true });
  }
});
