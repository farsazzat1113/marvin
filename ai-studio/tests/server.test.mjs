import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
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
      MARVIN_DATA_DIR: dataDir
    },
    stdio: 'ignore'
  });
  const base = `http://127.0.0.1:${port}`;

  try {
    await waitForServer(port, child);

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
