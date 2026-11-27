import { createHmac } from 'node:crypto';

const pepper = process.env.MARVIN_LICENSE_PEPPER || '';
if (!pepper) {
  console.error('Set MARVIN_LICENSE_PEPPER in the environment first.');
  process.exit(1);
}

let input = '';
for await (const chunk of process.stdin) input += chunk;
const key = input.trim();
if (key.length < 12 || key.length > 256) {
  console.error('Pipe one license key (12–256 characters) to this command.');
  process.exit(1);
}

const digest = createHmac('sha256', pepper).update(key, 'utf8').digest('hex');
process.stdout.write(digest + '\n');
