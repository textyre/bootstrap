import type { SystemInfo } from '../../types/global';
import { SELECTORS } from '../../config/selectors';

export function renderSystemInfo(info: SystemInfo): void {
  const envEl = document.getElementById(SELECTORS.ENV_VALUE);
  const ipEl = document.getElementById(SELECTORS.IP_VALUE);
  const versionProject = document.getElementById(SELECTORS.VERSION_PROJECT);
  const versionKernel = document.getElementById(SELECTORS.VERSION_KERNEL);

  if (envEl) envEl.textContent = info.virtualization_type;
  if (ipEl) ipEl.textContent = info.ip_address;
  if (versionProject) versionProject.textContent = `ctos-${info.project_version}`;
  if (versionKernel) versionKernel.textContent = info.kernel;
}
