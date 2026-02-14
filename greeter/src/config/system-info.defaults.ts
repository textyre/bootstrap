import type { SystemInfo } from '../types/global.d';

export const DEFAULT_SYSTEM_INFO: SystemInfo = {
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
  os_name: '',
};
