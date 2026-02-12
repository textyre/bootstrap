import type { SystemInfo } from './types/global';

let cached: SystemInfo | null = null;

export async function loadSystemInfo(): Promise<SystemInfo> {
  if (cached) return cached;

  try {
    const resp = await fetch('./system-info.json');
    cached = await resp.json();
    return cached!;
  } catch {
    cached = {
      kernel: 'unknown',
      virtualization_type: 'unknown',
      ip_address: '0.0.0.0',
      hostname: 'unknown',
      project_version: '1.0.0',
      timezone: 'UTC',
      region_prefix: '',
      systemd_version: 'unknown',
      machine_id: '00000000000000000000000000000000',
      display_output: 'unknown',
      display_resolution: 'unknown',
      ssh_fingerprint: 'unknown',
    };
    return cached;
  }
}

export function renderSystemInfo(info: SystemInfo): void {
  const envEl = document.getElementById('env-value');
  const ipEl = document.getElementById('ip-value');
  const versionProject = document.getElementById('version-project');
  const versionKernel = document.getElementById('version-kernel');

  if (envEl) envEl.textContent = info.virtualization_type;
  if (ipEl) ipEl.textContent = info.ip_address;
  if (versionProject) versionProject.textContent = `ctos-${info.project_version}`;
  if (versionKernel) versionKernel.textContent = info.kernel;
}
