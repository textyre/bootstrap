#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import {
  chmodSync,
  existsSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { networkInterfaces, hostname, release } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

const themeDir = '/usr/share/web-greeter/themes/ctos';

function readText(filePath, fallback = 'unknown') {
  try {
    return readFileSync(filePath, 'utf8').trim() || fallback;
  } catch {
    return fallback;
  }
}

function commandOutput(command, args = [], fallback = 'unknown') {
  try {
    return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
      || fallback;
  } catch {
    return fallback;
  }
}

function readOsName() {
  const values = Object.fromEntries(
    readText('/etc/os-release', '')
      .split('\n')
      .map((line) => line.split(/=(.*)/s, 2))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, value.replace(/^"|"$/g, '')]),
  );
  return values.NAME || values.ID || 'unknown';
}

function readTimezone() {
  const configured = readText('/etc/timezone', '');
  if (configured) return configured;

  try {
    const target = realpathSync('/etc/localtime');
    return target.includes('/zoneinfo/') ? target.split('/zoneinfo/', 2)[1] : 'unknown';
  } catch {
    return 'unknown';
  }
}

function readIpAddress() {
  for (const addresses of Object.values(networkInterfaces())) {
    const address = addresses?.find((candidate) => candidate.family === 'IPv4' && !candidate.internal);
    if (address) return address.address;
  }
  return '0.0.0.0';
}

function readDisplay() {
  try {
    for (const connector of readdirSync('/sys/class/drm').filter((entry) => /^card\d+-/.test(entry)).sort()) {
      const connectorDir = path.join('/sys/class/drm', connector);
      if (readText(path.join(connectorDir, 'status'), '') !== 'connected') continue;

      return {
        output: connector.replace(/^card\d+-/, ''),
        resolution: readText(path.join(connectorDir, 'modes')).split('\n')[0],
      };
    }
  } catch {
    // A headless system has no DRM connectors.
  }
  return { output: 'unknown', resolution: 'unknown' };
}

function readSshFingerprint() {
  for (const key of [
    '/etc/ssh/ssh_host_ed25519_key.pub',
    '/etc/ssh/ssh_host_rsa_key.pub',
  ]) {
    if (!existsSync(key)) continue;
    const fields = commandOutput('ssh-keygen', ['-lf', key, '-E', 'sha256'], '').split(/\s+/);
    if (fields.length > 1) return fields[1];
  }
  return 'unknown';
}

function readSystemdVersion() {
  const fields = commandOutput('systemctl', ['--version'], 'not-used').split(/\s+/);
  return fields[0] === 'systemd' && fields.length > 1 ? fields[1] : 'not-used';
}

function readVirtualizationType() {
  const value = commandOutput('systemd-detect-virt', [], 'bare-metal');
  return value === 'none' ? 'bare-metal' : value;
}

function writeSystemInfo() {
  const display = readDisplay();
  const information = {
    kernel: release(),
    virtualization_type: readVirtualizationType(),
    ip_address: readIpAddress(),
    hostname: hostname(),
    project_version: readText(path.join(themeDir, 'version')),
    timezone: readTimezone(),
    region_prefix: '',
    systemd_version: readSystemdVersion(),
    machine_id: readText('/etc/machine-id'),
    display_output: display.output,
    display_resolution: display.resolution,
    ssh_fingerprint: readSshFingerprint(),
    os_name: readOsName(),
  };

  const destination = path.join(themeDir, 'system-info.json');
  const temporary = path.join(themeDir, `.system-info-${randomUUID()}`);
  try {
    writeFileSync(temporary, `${JSON.stringify(information, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
    chmodSync(temporary, 0o644);
    renameSync(temporary, destination);
  } finally {
    rmSync(temporary, { force: true });
  }
}

writeSystemInfo();
